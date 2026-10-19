#!/usr/bin/env bash
# Backend: ADB push to /sdcard/Download. Files only. No KDE Connect needed.
# Needs: adb + device visible (USB, or TCP after `adb pair` / `adb connect`).
# Target: --adb HOST:PORT, $MAID_ADB, or first `adb devices` entry.
# Provides: backend_available, backend_send. Uses popup()/sorry() from dispatcher.
backend_available() { command -v adb >/dev/null 2>&1; }

_adb_target() {
  if [ -n "${MAID_ADB:-}" ]; then echo "$MAID_ADB"; return 0; fi
  adb devices 2>/dev/null | awk '$2=="device" {print $1; exit}'
}

backend_send() {
  local file="$1" target
  case "$file" in
    http://*|https://*) sorry "ADB backend sends files only, not URLs.\nUse --via kdeconnect or --via http for links."; return 1 ;;
  esac
  target="$(_adb_target)"
  if [ -z "$target" ]; then
    sorry "No ADB device. Connect USB or run:\nadb pair <ip:port>  then  adb connect <ip:port>"
    return 1
  fi
  if adb -s "$target" push "$file" "/sdcard/Download/$(basename "$file")" >/dev/null 2>&1; then
    popup "Pushed $(basename "$file") to Downloads (ADB: $target)"
  else
    sorry "ADB push failed ($target).\nRe-check authorization on the phone."
    return 1
  fi
}
