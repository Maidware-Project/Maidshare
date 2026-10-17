#!/usr/bin/env bash
# Backend: throwaway LAN HTTPS server + QR code. Files only.
# Zero phone-side requirements: scan the code (or open the URL) in any
# browser/camera. Needs: python3 + openssl CLI (qrencode optional, for
# terminal QR). TLS uses a throwaway per-run cert (TOFU: the fingerprint
# is printed for comparison with the browser warning).
# Serves a copy from a temp dir for SERVE_MIN minutes, then cleans up.
# No directory listings - only exact file paths under the secret subdir.
# Provides: backend_available, backend_send. Uses popup()/sorry() from dispatcher.
SERVE_MIN="${SERVE_MIN:-10}"
# sleep's arithmetic needs a number; anything else falls back to the default
[[ "${SERVE_MIN:-10}" =~ ^[0-9]+$ ]] || SERVE_MIN=10
PORT="${MAID_HTTP_PORT:-8077}"

backend_available() { command -v python3 >/dev/null 2>&1 && command -v openssl >/dev/null 2>&1; }

backend_send() {
  # $@ = files. Served together from one throwaway server (fixed port).
  local lan dir sub base url enc fp server_pid f urls="" first_url=""
  lan=$(ip route get 1.1.1.1 2>/dev/null | grep -oP "src \K[0-9.]+" | head -n 1)
  if [ -z "$lan" ]; then sorry "No LAN address found. Are you offline?"; return 1; fi
  dir=$(mktemp -d -t maidshare-XXXXXX) || return 1
  # shellcheck disable=SC1090
  . "$BINDIR/maid-cert.sh"
  # cert lives OUTSIDE the served root: the handler serves every file
  # under $dir, so key.pem/cert.pem must never be under it.
  certdir=$(mktemp -d -t maidshare-cert-XXXXXX) || { rm -rf "$dir"; return 1; }
  fp=$(maid_cert "$certdir") || { rm -rf "$dir" "$certdir"; sorry "Need the openssl CLI for the encrypted link."; return 1; }
  sub=$(python3 -c "import secrets; print(secrets.token_urlsafe(16))")
  mkdir -p "$dir/$sub" || { rm -rf "$dir"; return 1; }
  for f in "$@"; do
    case "$f" in
      http://*|https://*) sorry "HTTP backend sends files only, not URLs.\nUse --via kdeconnect for links."; rm -rf "$dir" "$certdir"; return 1 ;;
    esac
    base=$(basename "$f")
    cp -a "$f" "$dir/$sub/$base" || { rm -rf "$dir" "$certdir"; return 1; }
    enc=$(python3 -c "import urllib.parse,sys; print(urllib.parse.quote(sys.argv[1]))" "$base")
    url="https://$lan:$PORT/$sub/$enc"
    urls="$urls
$url"
    [ -z "$first_url" ] && first_url="$url"
  done
  firewall_hint "$PORT" &

  # Custom server: 404 on / and any directory. Only exact file paths are served.
  python3 - "$PORT" "$dir" "$certdir/cert.pem" "$certdir/key.pem" <<'PY' >/dev/null 2>&1 &
import os
import ssl
import sys
from http.server import ThreadingHTTPServer, SimpleHTTPRequestHandler

PORT = int(sys.argv[1])
ROOT = sys.argv[2]
CERT = sys.argv[3]
KEY = sys.argv[4]

class NoIndexHandler(SimpleHTTPRequestHandler):
    def __init__(self, *a, **k):
        super().__init__(*a, directory=ROOT, **k)

    def list_directory(self, path):
        self.send_error(404, "Not found")
        return None

    def do_GET(self):
        path = self.translate_path(self.path)
        if os.path.isdir(path):
            self.send_error(404, "Not found")
            return
        return super().do_GET()

    def log_message(self, fmt, *args):
        pass

srv = ThreadingHTTPServer(("0.0.0.0", PORT), NoIndexHandler)
ctx = ssl.SSLContext(ssl.PROTOCOL_TLS_SERVER)
ctx.load_cert_chain(CERT, KEY)
srv.socket = ctx.wrap_socket(srv.socket, server_side=True)
srv.serve_forever()
PY
  server_pid=$!
  trap 'kill "$server_pid" 2>/dev/null; rm -rf "$dir" "$certdir"' EXIT INT TERM

  if command -v qrencode >/dev/null 2>&1; then
    qrencode -t ANSIUTF8 "$first_url" 2>/dev/null || true
  fi
  popup "On your phone open (valid ${SERVE_MIN} min):$urls"
  echo "MaidShare serving $# file(s) for ${SERVE_MIN} min (Ctrl-C stops early):$urls"
  echo "cert fingerprint (compare with the browser warning): $fp"
  sleep $((SERVE_MIN * 60))
  kill "$server_pid" 2>/dev/null || true
  rm -rf "$dir" "$certdir"
}