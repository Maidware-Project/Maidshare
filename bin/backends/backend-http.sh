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
  local lan dir base url enc server_pid f urls=""
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
    urls="$urls
http://$lan:$PORT/$sub/$enc"
  done
  url="http://$lan:$PORT/$sub/$(python3 -c "import urllib.parse,sys; print(urllib.parse.quote(sys.argv[1]))" "$(basename "$1")")"
  firewall_hint "$PORT" &
  cd "$dir" || return 1
  python3 -m http.server "$PORT" >/dev/null 2>&1 &
  server_pid=$!
  cd - >/dev/null 2>&1 || true
  trap 'kill "$server_pid" 2>/dev/null; rm -rf "$dir"' EXIT INT TERM
  if command -v qrencode >/dev/null 2>&1; then
    qrencode -t ANSIUTF8 "$url" 2>/dev/null || true
  fi
  popup "On your phone open (valid ${SERVE_MIN} min):$urls"
  echo "MaidShare serving $# file(s) for ${SERVE_MIN} min (Ctrl-C stops early):$urls"
  sleep $((SERVE_MIN * 60))
  kill "$server_pid" 2>/dev/null || true
  rm -rf "$dir"
}
