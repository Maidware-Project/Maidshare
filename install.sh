#!/usr/bin/env bash
# Installer: copies files (no symlinks), desktop icon with home path fixed.
# Backends are optional and auto-detected at runtime - install any of:
#   KDE Connect (kdeconnect-cli) / ADB (android-tools) / python3 + qrencode.
# Usage: ./install.sh [--check] [--uninstall [--purge]]
#          [--prefix=DIR] [--no-packages] [--no-config]
# --prefix installs program files elsewhere (packaging: DESTDIR supported);
# user setup is skipped for non-default prefixes and with --no-config.
set -u
PKGDIR="$(cd "$(dirname "$0")" && pwd)"
BACKUP_TS="$(date +%Y%m%d-%H%M%S)"
CHECK=0; UNINST=0; PURGE=0; NOCONFIG=0; PREFIX=""
for a in "$@"; do
  case "$a" in
    --check) CHECK=1 ;;
    --uninstall) UNINST=1 ;;
    --purge) PURGE=1 ;;
    --no-config) NOCONFIG=1 ;;
    --no-packages) ;; # accepted for packaging/consistency: Maidshare installs no packages
    --prefix=*) PREFIX="${a#--prefix=}" ;;
    *) echo "unknown option: $a (see header)" >&2; exit 2 ;;
  esac
done
if [ -z "$PREFIX" ]; then PREFIX="$HOME/.local"; fi
if [ "$PREFIX" = "$HOME/.local" ]; then
  BINDIR="$HOME/.local/bin"; SHAREDIR="$HOME/.local/share"; REWRITE=1
else
  BINDIR="${DESTDIR:-}$PREFIX/bin"; SHAREDIR="${DESTDIR:-}$PREFIX/share"; REWRITE=2
  NOCONFIG=1
fi

say()  { echo "==> $*"; }

if [ "$UNINST" = "1" ]; then
  # program files come out of the same dirs the install used, so
  # --prefix/DESTDIR installs uninstall cleanly too.
  rm -f "$BINDIR"/maidshare "$BINDIR"/maidshare-receive.py \
    "$BINDIR"/maid-cert.sh
  rm -rf "$BINDIR"/backends
  rm -f "$SHAREDIR"/applications/maidshare.desktop \
    "$SHAREDIR"/kio/servicemenus/maidshare.desktop
  rm -rf "$SHAREDIR"/maidshare
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
    sed -e "s|@HOME@|${HOME//&/\\&}|g" "$src" > "$dest"
  elif [ "$rewrite" = "2" ]; then
    # system package: bare command names, resolved via PATH
    sed -e "s|@HOME@||g" -e "s|/.local/bin/||g" "$src" > "$dest"
  else
    cp -a "$src" "$dest"
  fi
  echo "installed $dest"
}

copy_one "$PKGDIR/bin/maidshare" "$BINDIR/maidshare"
[ "$CHECK" = "1" ] || mkdir -p "$BINDIR/backends"
for f in "$PKGDIR"/bin/backends/*.sh; do
  [ -f "$f" ] || continue
  copy_one "$f" "$BINDIR/backends/$(basename "$f")"
done
[ "$CHECK" = "0" ] && chmod +x "$BINDIR/maidshare" 2>/dev/null || true
copy_one "$PKGDIR/bin/maidshare-receive.py" "$BINDIR/maidshare-receive.py"
copy_one "$PKGDIR/bin/maid-cert.sh" "$BINDIR/maid-cert.sh"
copy_one "$PKGDIR/desktop/maidshare.desktop" \
  "$SHAREDIR/applications/maidshare.desktop" "$REWRITE"
copy_one "$PKGDIR/servicemenu/maidshare.desktop" \
  "$SHAREDIR/kio/servicemenus/maidshare.desktop"

# the kdeconnect early-login fix (kernel 7.2.11 / Plasma 6.8) travels
# with the suite: ~/.local/share/maidshare/patches/kdeconnect-26.08.2/
for f in "$PKGDIR"/patches/kdeconnect-26.08.2/*; do
  [ -f "$f" ] || continue
  copy_one "$f" "$SHAREDIR/maidshare/patches/kdeconnect-26.08.2/$(basename "$f")"
done

if [ "$CHECK" = "1" ]; then say "(check only, nothing changed)"; exit 0; fi
if [ "$NOCONFIG" = "0" ]; then
  command -v kbuildsycoca6 >/dev/null 2>&1 && kbuildsycoca6 --noincremental >/dev/null 2>&1 || true
  command -v update-desktop-database >/dev/null 2>&1 && update-desktop-database "$SHAREDIR/applications" >/dev/null 2>&1 || true
fi

say "backend status on this machine:"
command -v kdeconnect-cli >/dev/null 2>&1 && say "  kdeconnect: yes" || say "  kdeconnect: MISSING (best backend - install your distro's kdeconnect package)"
command -v adb >/dev/null 2>&1 && say "  adb: yes" || say "  adb: missing (optional; android-tools for the ADB backend)"
command -v python3 >/dev/null 2>&1 && say "  python3: yes (http backend)" || say "  python3: MISSING"
command -v openssl >/dev/null 2>&1 && say "  openssl: yes (https for http backend)" || say "  openssl: MISSING (http backend stays off without it)"
command -v qrencode >/dev/null 2>&1 && say "  qrencode: yes (terminal QR)" || say "  qrencode: missing (optional; URL still works)"
say "done. Pin it: launcher -> MaidShare -> Pin to Task Manager."