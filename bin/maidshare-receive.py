#!/usr/bin/env python3
# MaidShare receive end: browser upload form behind a per-run token URL.
# Usage: maidshare-receive.py PORT OUTDIR TOKEN MINUTES CERT KEY
# TLS is mandatory (fail closed: no cert, no server). Resource bounds:
# uploads are written straight to disk off the socket in MAID_RECV_CHUNK
# chunks (default 64 KiB) - request bodies are never collected in RAM.
# Caps: MAID_MAX_MB per request (default 500), MAID_MAX_FILE_MB per file
# (default = request cap), 4 concurrent uploads (rest get 503), 60 s
# per-connection socket timeout, free-disk precheck, partial files
# removed on failure, and the whole server auto-expires. MAID_RECV_CHUNK
# is a test knob to force boundary splits; production keeps 64 KiB.
# Prints "SAVED <name>" per upload. Ctrl-C or timeout stops it. Stdlib only.
import hmac
import os
import shutil
import ssl
import sys
import threading
import time
from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer

if len(sys.argv) < 7:
    print("need CERT KEY args (TLS is mandatory)", file=sys.stderr)
    sys.exit(2)
PORT = int(sys.argv[1])
OUTDIR = sys.argv[2]
TOKEN = sys.argv[3]
MINUTES = int(sys.argv[4])
CERT = sys.argv[5]
KEY = sys.argv[6]
MAX_BYTES = int(os.environ.get("MAID_MAX_MB", "500")) * 1024 * 1024
MAX_FILE = int(os.environ.get("MAID_MAX_FILE_MB", os.environ.get("MAID_MAX_MB", "500"))) * 1024 * 1024
CHUNK = max(256, int(os.environ.get("MAID_RECV_CHUNK", "65536")))
MAX_UPLOADS = 4
FREE_MARGIN = 64 * 1024 * 1024
MAX_HEAD = 16384
os.makedirs(OUTDIR, exist_ok=True)
STOP_AT = time.time() + MINUTES * 60

FORM = """<html><head><meta name="viewport" content="width=device-width">
<title>MaidShare receive</title></head><body>
<h2>Send to PC</h2>
<form method="POST" action="upload" enctype="multipart/form-data">
<input type="file" name="f" multiple><br><br>
<input type="submit" value="Send">
</form></body></html>""".encode()


class _Body:
    """Request body reader: CHUNK-sized reads, small rolling buffer.

    stream_until() writes everything before the marker through sink(data)
    with at most one chunk plus marker-length held in memory, so a part is
    never assembled in RAM. It is careful to only flush bytes that cannot
    be the start of a marker split across two reads.
    """

    def __init__(self, rfile, length):
        self.rfile = rfile
        self.left = length
        self.buf = b""

    def refill(self):
        if self.left <= 0:
            return False
        chunk = self.rfile.read(min(CHUNK, self.left))
        if not chunk:
            self.left = 0
            return False
        self.left -= len(chunk)
        self.buf += chunk
        return True

    def ensure(self, n):
        while len(self.buf) < n and self.refill():
            pass
        return len(self.buf) >= n

    def take(self, n):
        out = self.buf[:n]
        self.buf = self.buf[n:]
        return out

    def read_until(self, marker, cap):
        """bytes before marker (marker consumed). None on EOF or over cap."""
        out = bytearray()
        while True:
            i = self.buf.find(marker)
            if i >= 0:
                out += self.buf[:i]
                self.buf = self.buf[i + len(marker):]
                return bytes(out) if len(out) <= cap else None
            if len(out) + len(self.buf) > cap:
                return None
            out += self.buf
            self.buf = b""
            if not self.refill():
                return None

    def stream_until(self, marker, sink, cap):
        """Write payload before marker through sink(data), bounded RAM.
        Returns 'ok' | 'eof' | 'over' | 'write'."""
        seen = 0
        keep = len(marker) - 1
        while True:
            i = self.buf.find(marker)
            if i >= 0:
                if i > 0:
                    seen += i
                    if seen > cap:
                        return "over"
                    if not sink(self.buf[:i]):
                        return "write"
                self.buf = self.buf[i + len(marker):]
                return "ok"
            safe = len(self.buf) - keep
            if safe > 0:
                seen += safe
                if seen > cap:
                    return "over"
                if not sink(self.buf[:safe]):
                    return "write"
                self.buf = self.buf[safe:]
            if not self.refill():
                return "eof"


def _wr(fd, data):
    try:
        os.write(fd, data)
        return True
    except OSError:
        return False


def _part_disp(head):
    for line in head.split(b"\r\n"):
        name, _, value = line.partition(b":")
        if name.strip().lower() == b"content-disposition":
            return value.strip()
    return None


def _part_filename(disp):
    if not disp or not disp.lower().startswith(b"form-data"):
        return None
    key = b"filename="
    i = disp.lower().find(key)
    if i < 0:
        return None
    v = disp[i + len(key):].lstrip()
    if v[:1] == b'"':
        raw = bytearray()
        j = 1
        while j < len(v):
            c = v[j:j + 1]
            if c == b"\\" and j + 1 < len(v):
                raw += v[j + 1:j + 2]
                j += 2
                continue
            if c == b'"':
                break
            raw += c
            j += 1
        return bytes(raw).decode("utf-8", "replace")
    return v.split(b";", 1)[0].strip().decode("utf-8", "replace")


class Handler(BaseHTTPRequestHandler):
    server_version = "maidshare-recv/1.0"
    timeout = 60
    slots = threading.Semaphore(MAX_UPLOADS)

    def log_message(self, fmt, *args):
        pass

    def _ok(self, ctype, body):
        self.send_response(200)
        self.send_header("Content-Type", ctype)
        self.send_header("Content-Length", str(len(body)))
        self.end_headers()
        self.wfile.write(body)

    def _deny(self):
        self.send_response(403)
        self.end_headers()
        self.wfile.write(b"nope")

    def _fail(self, code, msg):
        self.send_response(code)
        self.send_header("Content-Type", "text/plain")
        self.end_headers()
        self.wfile.write(msg.encode())

    def _token_from_path(self):
        # /<token> or /<token>/upload
        parts = [p for p in self.path.split("?")[0].split("/") if p]
        return parts[0] if parts else ""

    def _token_ok(self):
        got = self._token_from_path()
        return bool(TOKEN) and hmac.compare_digest(got, TOKEN)

    def do_GET(self):  # noqa: N802
        parts = [p for p in self.path.split("?")[0].rstrip("/").split("/") if p]
        if len(parts) == 1 and self._token_ok():
            self._ok("text/html", FORM)
        else:
            self._deny()

    @staticmethod
    def _clean(name):
        # strip control chars so hostile filenames can't spoof journal lines
        return "".join(c for c in name if c.isprintable())

    @staticmethod
    def _boundary(ctype):
        if not ctype.lower().startswith("multipart/form-data"):
            return None
        for part in ctype.split(";")[1:]:
            key, _, value = part.strip().partition("=")
            if key.strip().lower() == "boundary":
                value = value.strip()
                if value[:1] == '"' and value[-1:] == '"':
                    value = value[1:-1]
                return value.encode("utf-8", "replace") if value else None
        return None

    def do_POST(self):  # noqa: N802
        if not Handler.slots.acquire(blocking=False):
            self.send_response(503)
            self.end_headers()
            self.wfile.write(b"busy")
            return
        try:
            self._do_post()
        finally:
            Handler.slots.release()

    def _do_post(self):
        parts = [p for p in self.path.split("?")[0].rstrip("/").split("/") if p]
        if not (len(parts) == 2 and parts[1] == "upload" and self._token_ok()):
            self._deny()
            return
        try:
            length = int(self.headers.get("Content-Length", 0))
        except ValueError:
            length = 0
        if length <= 0 or length > MAX_BYTES:
            self._deny()
            return
        boundary = self._boundary(self.headers.get("Content-Type", ""))
        if not boundary:
            self._deny()
            return
        try:
            # refuse up front when the declared size cannot fit on disk
            if shutil.disk_usage(OUTDIR).free < length + FREE_MARGIN:
                self._fail(507, "not enough free disk space for this upload")
                return
        except OSError:
            pass
        body = _Body(self.rfile, length)
        delim = b"\r\n--" + boundary
        # leading boundary (any preamble is tolerated)
        if body.read_until(b"--" + boundary, MAX_HEAD) is None:
            self._deny()
            return
        saved = []
        try:
            while True:
                if not body.ensure(2):
                    self._deny()
                    return
                if body.buf[:2] == b"--":
                    break  # closing delimiter: no more parts
                if body.buf[:2] != b"\r\n":
                    self._deny()
                    return
                body.take(2)
                head = body.read_until(b"\r\n\r\n", MAX_HEAD)
                if head is None:
                    self._deny()
                    return
                name = _part_filename(_part_disp(head))
                store_name = os.path.basename(name) if name else ""
                if not store_name:
                    # plain field or hostile name: drain and skip the part
                    if body.stream_until(delim, lambda _c: True, MAX_FILE) != "ok":
                        self._deny()
                        return
                    continue
                fd, base = self._open_dest(store_name)
                if fd is None:
                    self._deny()
                    return
                res = body.stream_until(delim, lambda c, fd=fd: _wr(fd, c), MAX_FILE)
                try:
                    os.close(fd)
                except OSError:
                    pass
                if res != "ok":
                    # no partial files: remove what this request started
                    try:
                        os.unlink(os.path.join(OUTDIR, base))
                    except OSError:
                        pass
                    if res == "over":
                        self._fail(413, "file over MAID_MAX_FILE_MB")
                    else:
                        self._deny()
                    return
                saved.append(base)
                print(f"SAVED {self._clean(base)}", flush=True)
        except Exception:  # noqa: BLE001 - never leak tracebacks for uploads
            self._deny()
            return
        self._ok("text/plain", ("saved: " + ", ".join(saved) + "\n").encode())

    @staticmethod
    def _open_dest(name):
        # atomic create (O_EXCL): concurrent same-name uploads can't clobber
        base, ext = os.path.splitext(os.path.join(OUTDIR, name))
        for n in range(1, 1000):
            dest = base + ext if n == 1 else f"{base}-{n}{ext}"
            try:
                fd = os.open(dest, os.O_WRONLY | os.O_CREAT | os.O_EXCL, 0o644)
            except FileExistsError:
                continue
            except OSError:
                return None, ""
            return fd, os.path.basename(dest)
        return None, ""


srv = ThreadingHTTPServer(("0.0.0.0", PORT), Handler)
srv.timeout = 1
ctx = ssl.SSLContext(ssl.PROTOCOL_TLS_SERVER)
ctx.load_cert_chain(CERT, KEY)
srv.socket = ctx.wrap_socket(srv.socket, server_side=True)
print(f"[recv] https://<lan>:{PORT}/{TOKEN} -> {OUTDIR} ({MINUTES} min)", flush=True)
while time.time() < STOP_AT:
    srv.handle_request()
print("[recv] done", flush=True)
