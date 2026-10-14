#!/usr/bin/env bash
# Backend: throwaway LAN HTTP server + QR code. Files only.
# Zero phone-side requirements: scan the code (or open the URL) in any
# browser/camera. Needs: python3 (qrencode optional, for terminal QR).
# Serves a copy from a temp dir for SERVE_MIN minutes, then cleans up.
# Provides: backend_available, backend_send. Uses popup()/sorry() from dispatcher.
SERVE_MIN="${SERVE_MIN:-10}"
PORT="${MAID_HTTP_PORT:-8077}"

backend_available() { command -v python3 >/dev/null 2>&1; }

backend_send() {
  # $@ = files. Served together from one throwaway server (fixed port).
  local lan dir sub base url enc server_pid f urls="" first_url=""
  lan=$(ip route get 1.1.1.1 2>/dev/null | grep -oP "src \K[0-9.]+" | head -n 1)
  if [ -z "$lan" ]; then sorry "No LAN address found. Are you offline?"; return 1; fi
  dir=$(mktemp -d -t maidshare-XXXXXX) || return 1
  sub=$(python3 -c "import secrets; print(secrets.token_hex(6))")
  mkdir -p "$dir/$sub" || { rm -rf "$dir"; return 1; }
  for f in "$@"; do
    case "$f" in
      http://*|https://*) sorry "HTTP backend sends files only, not URLs.\nUse --via kdeconnect for links."; rm -rf "$dir"; return 1 ;;
    esac
    base=$(basename "$f")
    cp -a "$f" "$dir/$sub/$base" || { rm -rf "$dir"; return 1; }
    enc=$(python3 -c "import urllib.parse,sys; print(urllib.parse.quote(sys.argv[1]))" "$base")
    url="http://$lan:$PORT/$sub/$enc"
    urls="$urls
$url"
    [ -z "$first_url" ] && first_url="$url"
  done
  firewall_hint "$PORT" &

  # Custom server: no directory listing. Only exact file paths under /sub/ are served.
  python3 - "$PORT" "$dir" <<'PY' >/dev/null 2>&1 &
import os, sys
from http.server import ThreadingHTTPServer, SimpleHTTPRequestHandler

PORT = int(sys.argv[1])
ROOT = sys.argv[2]

class NoIndexHandler(SimpleHTTPRequestHandler):
    def __init__(self, *a, **k):
        super().__init__(*a, directory=ROOT, **k)
    def list_directory(self, path):
        self.send_error(404, "Not found")
        return None
    def do_GET(self