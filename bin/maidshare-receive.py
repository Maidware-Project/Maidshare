#!/usr/bin/env python3
# MaidShare receive end: browser upload form behind a per-run token URL.
# Usage: maidshare-receive.py PORT OUTDIR TOKEN MINUTES CERT KEY
# TLS is mandatory (fail closed: no cert, no server). Resource bounds:
# uploads stream to RAM in 64 KiB chunks (never one big read), capped at
# MAID_MAX_MB (default 500), at most 4 concurrent uploads (rest get 503),
# 60 s per-connection socket timeout, and the whole server auto-expires.
# Prints "SAVED <name>" per upload. Ctrl-C or timeout stops it. Stdlib only.
import hmac
import os
import ssl
import sys
import threading
import time
from email.parser import BytesParser
from email.policy import HTTP
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
CHUNK = 65536
MAX_UPLOADS = 4
os.makedirs(OUTDIR, exist_ok=True)
STOP_AT = time.time() + MINUTES * 60

FORM = """<html><head><meta name="viewport" content="width=device-width">
<title>MaidShare receive</title></head><body>
<h2>Send to PC</h2>
<form method="POST" action="upload" enctype="multipart/form-data">
<input type="file" name="f" multiple><br><br>
<input type="submit" value="Send">
</form></body></html>""".encode()


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
        ctype = self.headers.get("Content-Type", "")
        try:
            # stream in chunks: RAM stays flat no matter the declared size
            body = bytearray()
            remaining = length
            while remaining > 0:
                chunk = self.rfile.read(min(CHUNK, remaining))
                if not chunk:
                    self._deny()
                    return
                body += chunk
                remaining -= len(chunk)
            msg = BytesParser(policy=HTTP).parsebytes(
                b"Content-Type: " + ctype.encode() + b"\r\n\r\n" + bytes(body))
        except Exception:  # noqa: BLE001 - malformed upload, reject it
            self._deny()
            return
        saved = []
        try:
            for part in msg.iter_parts():
                if part.get_content_disposition() != "form-data":
                    continue
                name = os.path.basename(part.get_filename() or "")
                if not name:
                    continue
                data = part.get_payload(decode=True) or b""
                dest = self._store(name, data)
                if dest:
                    saved.append(dest)
                    print(f"SAVED {self._clean(dest)}", flush=True)
        except Exception:  # noqa: BLE001 - never leak tracebacks for uploads
            self._deny()
            return
        self._ok("text/plain", ("saved: " + ", ".join(saved) + "\n").encode())

    @staticmethod
    def _store(name, data):
        # atomic create (O_EXCL): concurrent same-name uploads can't clobber
        base, ext = os.path.splitext(os.path.join(OUTDIR, name))
        for n in range(1, 1000):
            dest = base + ext if n == 1 else f"{base}-{n}{ext}"
            try:
                fd = os.open(dest, os.O_WRONLY | os.O_CREAT | os.O_EXCL, 0o644)
            except FileExistsError:
                continue
            except OSError:
                return ""
            try:
                with os.fdopen(fd, "wb") as f:
                    f.write(data)
                return os.path.basename(dest)
            except OSError:
                return ""
        return ""


srv = ThreadingHTTPServer(("0.0.0.0", PORT), Handler)
srv.timeout = 1
ctx = ssl.SSLContext(ssl.PROTOCOL_TLS_SERVER)
ctx.load_cert_chain(CERT, KEY)
srv.socket = ctx.wrap_socket(srv.socket, server_side=True)
print(f"[recv] https://<lan>:{PORT}/{TOKEN} -> {OUTDIR} ({MINUTES} min)", flush=True)
while time.time() < STOP_AT:
    srv.handle_request()
print("[recv] done", flush=True)