#!/usr/bin/env python3
# MaidShare receive end: browser upload form behind a per-run token URL.
# Usage: maidshare-receive.py PORT OUTDIR TOKEN MINUTES
# Prints "SAVED <name>" per upload. Ctrl-C or timeout stops it. Stdlib only.
import os
import sys
import time
from email.parser import BytesParser
from email.policy import HTTP
from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer

PORT = int(sys.argv[1])
OUTDIR = sys.argv[2]
TOKEN = sys.argv[3]
MINUTES = int(sys.argv[4])
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

    def do_GET(self):  # noqa: N802
        if self.path.rstrip("/") == f"/{TOKEN}":
            self._ok("text/html", FORM)
        else:
            self._deny()

    def do_POST(self):  # noqa: N802
        if self.path.rstrip("/") != f"/{TOKEN}/upload":
            self._deny()
            return
        try:
            length = int(self.headers.get("Content-Length", 0))
        except ValueError:
            length = 0
        if length <= 0 or length > 500 * 1024 * 1024:
            self._deny()
            return
        ctype = self.headers.get("Content-Type", "")
        body = self.rfile.read(length)
        try:
            msg = BytesParser(policy=HTTP).parsebytes(
                b"Content-Type: " + ctype.encode() + b"\r\n\r\n" + body)
        except Exception:  # noqa: BLE001 - malformed upload, reject it
            self._deny()
            return
        saved = []
        for part in msg.iter_parts():
            if part.get_content_disposition() != "form-data":
                continue
            name = os.path.basename(part.get_filename() or "")
            if not name:
                continue
            dest = os.path.join(OUTDIR, name)
            base, ext = os.path.splitext(dest)
            n = 1
            while os.path.exists(dest):
                n += 1
                dest = f"{base}-{n}{ext}"
            with open(dest, "wb") as f:
                f.write(part.get_payload(decode=True) or b"")
            saved.append(os.path.basename(dest))
            print(f"SAVED {os.path.basename(dest)}", flush=True)
        self._ok("text/plain", ("saved: " + ", ".join(saved) + "\n").encode())


srv = ThreadingHTTPServer(("0.0.0.0", PORT), Handler)
srv.timeout = 1
print(f"[recv] http://<lan>:{PORT}/{TOKEN} -> {OUTDIR} ({MINUTES} min)", flush=True)
while time.time() < STOP_AT:
    srv.handle_request()
print("[recv] done", flush=True)
