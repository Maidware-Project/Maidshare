#!/usr/bin/env bash
# Backend: KDE Connect. Files + URLs. Needs paired phone on same network.
# Provides: backend_available, backend_send. Uses popup()/sorry() from dispatcher.
backend_available() { command -v kdeconnect-cli >/dev/null 2>&1; }

backend_send() {
  local file="$1" id="${MAID_DEVICE:-}" label
  if [ -z "$id" ] && [ -f "${XDG_CONFIG_HOME:-$HOME/.config}/kdeconnect-share-target" ]; then
    id="$(head -n1 "${XDG_CONFIG_HOME:-$HOME/.config}/kdeconnect-share-target" 2>/dev/null || true)"
  fi
  if [ -z "$id" ]; then
    id="$(kdeconnect-cli -a --id-only 2>/dev/null | head -n 1 || true)"
  fi
  if [ -z "$id" ]; then
    sorry "No reachable phone. Pair it in KDE Connect first (same Wi-Fi, accept pairing)."
    return 1
  fi
  label="$(kdeconnect-cli -l 2>/dev/null | grep -F -- "$id" | head -n1 | sed -e 's/^- //' -e 's/: .*//')"
  label="${label:-phone}"
  if kdeconnect-cli -d "$id" --share "$file" >/dev/null 2>&1; then
    popup "Sent $(basename "$file") to $label (KDE Connect)"
  else
    sorry "Failed to send to $label.\nIs the phone reachable? (kdeconnect-cli -l)"
    return 1
  fi
}
