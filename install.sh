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
  BINDIR="$HOME/.local/bin"; LIBDIR="$HOME/.local/lib"; SHAREDIR="$HOME/.local/share"; REWRITE=1
else
  BINDIR="${DESTDIR:-}$PREFIX/bin"; LIBDIR="${DESTDIR:-}$PREFIX/lib"; SHAREDIR="${DESTDIR:-}$PREFIX/share"; REWRITE=2
  NOCONFIG=1
fi

say()  { echo "==> $*"; }

# Report the KDE stack so install logs show what this machine runs.
kde_env() {
  local plasma fw qt kc
  plasma=$(plasmashell --version 2>/dev/null | awk 'NR==1{print $2}')
  [ -n "$plasma" ] || plasma=$(kwin_wayland --version 2>/dev/null | awk 'NR==1{print $2}')
  fw=$(kf6-config --version 2>/dev/null)
  [ -n "$fw" ] || fw=$(pkg-config --modversion KF6CoreAddons 2>/dev/null)
  [ -n "$fw" ] || fw=$(rpm -q --qf '%{VERSION}' kf6-kcoreaddons 2>/dev/null)
  [ -n "$fw" ] || fw=$(dpkg-query -W -f='${Version}' libkf6coreaddons6 2>/dev/null)
  [ -n "$fw" ] || fw=$(pacman -Q kf6-kcoreaddons 2>/dev/null | awk '{print $2}')
  qt=$(qmake6 -query QT_VERSION 2>/dev/null)
  [ -n "$qt" ] || qt=$(qtpaths6 --qt-version 2>/dev/null)
  [ -n "$qt" ] || qt=$(pkg-config --modversion Qt6Core 2>/dev/null)
  kc=$(kdeconnectd --version 2>/dev/null | awk 'NR==1{print $NF}')
  [ -n "$kc" ] || kc=$(kdeconnect-cli --version 2>/dev/null | awk 'NR==1{print $NF}')
  KDE_PLASMA="$plasma"
  KDE_FRAMEWORKS="$fw"
  KDE_QT="$qt"
  KDE_CONNECT="$kc"
}
kde_env_line() {
  if [ -z "${KDE_PLASMA:-}${KDE_FRAMEWORKS:-}${KDE_QT:-}${KDE_CONNECT:-}" ]; then
    echo "KDE: not detected (non-KDE session or tools missing)"
  else
    echo "KDE: Plasma ${KDE_PLASMA:-?} | Frameworks ${KDE_FRAMEWORKS:-?} | Qt ${KDE_QT:-?} | KDE Connect ${KDE_CONNECT:-not installed}"
  fi
}
kde_env
say "$(kde_env_line)"

if [ "$UNINST" = "1" ]; then
  # program files come out of the same dirs the install used, so
  # --prefix/DESTDIR installs uninstall cleanly too.
  rm -f "$BINDIR"/maidshare "$BINDIR"/maidshare-receive.py \
    "$BINDIR"/maid-cert.sh "$BINDIR"/maidshare-gui
  rm -rf "$BINDIR"/backends "$LIBDIR"/maidshare-gui
  rm -f "$SHAREDIR"/applications/maidshare.desktop \
    "$SHAREDIR"/applications/maidshare-gui.desktop \
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
# GUI: the wrapper resolves its Qt package via ../lib/maidshare-gui
copy_one "$PKGDIR/bin/maidshare-gui" "$BINDIR/maidshare-gui"
[ "$CHECK" = "1" ] || mkdir -p "$LIBDIR/maidshare-gui"
cd "$PKGDIR/src" || { say "missing src tree: $PKGDIR/src"; exit 1; }
while IFS= read -r -d '' f; do
  copy_one "$PKGDIR/src/$f" "$LIBDIR/maidshare-gui/$f"
done < <(find maidshare_gui -name "*.py" -print0)
cd "$PKGDIR"
copy_one "$PKGDIR/desktop/maidshare-gui.desktop" \
  "$SHAREDIR/applications/maidshare-gui.desktop" "$REWRITE"
copy_one "$PKGDIR/desktop/maidshare.desktop" \
  "$SHAREDIR/applications/maidshare.desktop" "$REWRITE"
copy_one "$PKGDIR/servicemenu/maidshare.desktop" \
  "$SHAREDIR/kio/servicemenus/maidshare.desktop"

# the kdeconnect early-login fix lives in Maid Helper's `kdeconnect`
# doctor (maid-helper --only kdeconnect --fix); it is not shipped here.
# clean a stale patch copy left by older installs
if [ "$CHECK" = "0" ]; then rm -rf "$SHAREDIR/maidshare/patches"; fi

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
python3 -c "import PyQt6" 2>/dev/null && say "  PyQt6: yes (GUI)" \
  || say "  PyQt6: missing (optional; the GUI window stays off, the CLI works fully)"
say "done. Pin it: launcher -> MaidShare GUI -> Pin to Task Manager."