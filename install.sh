#!/usr/bin/env bash
# Installer: copies files (no symlinks), desktop icon with home path fixed.
# Backends are optional and auto-detected at runtime - install any of:
#   KDE Connect (kdeconnect-cli) / ADB (android-tools) / python3 + qrencode.
# Usage: ./install.sh [--check] [--uninstall [--purge]]
set -u
PKGDIR="$(cd "$(dirname "$0")" && pwd)"
BACKUP_TS="$(date +%Y%m%d-%H%M%S)"
CHECK=0; UNINST=0; PURGE=0
for a in "$@"; do
  case "$a" in
    --check) CHECK=1 ;;
    --uninstall) UNINST=1 ;;
    --purge) PURGE=1 ;;
    *) echo "unknown option: $a (see: --check --uninstall [--purge])" >&2; exit 2 ;;
  esac
done

say()  { echo "==> $*"; }

if [ "$UNINST" = "1" ]; then
  rm -f "$HOME"/.local/bin/maidshare "$HOME"/.local/bin/maidshare-receive.py \
    "$HOME"/.local/bin/maid-cert.sh
  rm -rf "$HOME"/.local/bin/backends
  rm -f "$HOME"/.local/share/applications/maidshare.desktop \
    "$HOME"/.local/share/kio/servicemenus/maidshare.desktop
  if [ "$PURGE" = "1" ]; then
    rm -f "$HOME"/.config/kdeconnect-share-target
    rm -rf "$HOME/Downloads/MaidShare"
    say "uninstalled, settings and received files removed (--purge)"
  elif [ -t 0 ]; then
    printf 'Remove settings and received files too (share target, ~/Downloads/MaidShare)? [y/N]: '
    read -r _ans
    case "$_ans" in [Yy]*)
      rm -f "$HOME"/.config/kdeconnect-share-target
      rm -rf "$HOME/Downloads/MaidShare"
      say "uninstalled, settings and received files removed" ;;
    *) say "uninstalled, settings and received files kept" ;;
    esac
  else
    say "uninstalled (kept: share target, ~/Downloads/MaidShare; rerun with --purge to remove)"
  fi
  exit 0
fi

copy_one() {
  local src="$1" dest="$2" rewrite="${3:-0}"
  if [ "$CHECK" = "1" ]; then echo "COPY $dest"; return 0; fi
  mkdir -p "$(dirname "$dest")"
  if [ -e "$dest" ] && ! cmp -s "$src" "$dest"; then
    cp -a "$dest" "${dest}.bak-${BACKUP_TS}"
    say "backed up $dest"
  fi
  if [ "$rewrite" = "1" ]; then
    # escape & (sed replacement metachar) in $HOME
    sed -e "s|/home/EXAMPLEUSER/|${HOME//&/\\&}|g" "$src" > "$dest"
  else
    cp -a "$src" "$dest"
  fi
  echo "installed $dest"
}

copy_one "$PKGDIR/bin/maidshare" "$HOME/.local/bin/maidshare"
[ "$CHECK" = "1" ] || mkdir -p "$HOME/.local/bin/backends"
for f in "$PKGDIR"/bin/backends/*.sh; do
  [ -f "$f" ] || continue
  copy_one "$f" "$HOME/.local/bin/backends/$(basename "$f")"
done
[ "$CHECK" = "0" ] && chmod +x "$HOME/.local/bin/maidshare" 2>/dev/null || true
copy_one "$PKGDIR/bin/maidshare-receive.py" "$HOME/.local/bin/maidshare-receive.py"
copy_one "$PKGDIR/bin/maid-cert.sh" "$HOME/.local/bin/maid-cert.sh"
copy_one "$PKGDIR/desktop/maidshare.desktop" \
  "$HOME/.local/share/applications/maidshare.desktop" 1
copy_one "$PKGDIR/servicemenu/maidshare.desktop" \
  "$HOME/.local/share/kio/servicemenus/maidshare.desktop"

if [ "$CHECK" = "1" ]; then say "(check only, nothing changed)"; exit 0; fi
command -v kbuildsycoca6 >/dev/null 2>&1 && kbuildsycoca6 --noincremental >/dev/null 2>&1 || true
command -v update-desktop-database >/dev/null 2>&1 && update-desktop-database "$HOME/.local/share/applications" >/dev/null 2>&1 || true

say "backend status on this machine:"
command -v kdeconnect-cli >/dev/null 2>&1 && say "  kdeconnect: yes" || say "  kdeconnect: MISSING (best backend - install your distro's kdeconnect package)"
command -v adb >/dev/null 2>&1 && say "  adb: yes" || say "  adb: missing (optional; android-tools for the ADB backend)"
command -v python3 >/dev/null 2>&1 && say "  python3: yes (http backend)" || say "  python3: MISSING"
command -v openssl >/dev/null 2>&1 && say "  openssl: yes (https for http backend)" || say "  openssl: MISSING (http backend stays off without it)"
command -v qrencode >/dev/null 2>&1 && say "  qrencode: yes (terminal QR)" || say "  qrencode: missing (optional; URL still works)"
say "done. Pin it: launcher -> MaidShare -> Pin to Task Manager."