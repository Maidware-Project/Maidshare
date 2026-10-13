# MaidShare — send files and links from linux to your android phone

no phone app needed for most of it. backends auto-picked in order
(kdeconnect → adb → http), override with `--via`. no personal data inside.

## layout

```
bin/maidshare         dispatcher: picker, backend select, multi-file fan-out
bin/backends/backend-kdeconnect.sh   paired phone on LAN (files + URLs)
bin/backends/backend-adb.sh          ADB push to /sdcard/Download (files)
bin/backends/backend-http.sh         throwaway LAN server + QR (files, zero setup)
bin/maidshare-receive.py  phone -> PC browser upload (token URL, auto-expires)
desktop/              launcher icon (pin to task manager)
servicemenu/          dolphin right-click entries (send / send-via-QR)
install.sh            installer (copies, never symlinks)
```

## requirements per distro

backends are optional and auto-detected — install any of them:

| need | arch | debian/ubuntu | fedora | opensuse |
|---|---|---|---|---|
| kdeconnect backend | kdeconnect | kdeconnect | kdeconnect | kdeconnect-kde |
| adb backend | android-tools | adb | android-tools | android-tools |
| http backend | python + qrencode (opt) | python3 + qrencode | python3 + qrencode | python3 + qrencode |
| picker/popups | kdialog or zenity | kdialog or zenity | kdialog or zenity | kdialog or zenity |

## installation

```sh
bash install.sh            # copy + icon + servicemenu, reports backend status
bash install.sh --check    # dry run
```

existing files are backed up to `*.bak-<timestamp>`. then: launcher →
**MaidShare** (pin to task manager for one click).

## usage

```sh
maidshare [FILE|URL]...            # picker when empty, auto backend, multi-file ok
maidshare --via adb FILE
maidshare --via http FILE1 FILE2   # one server, one URL per file
maidshare --via kdeconnect https://example.com
maidshare --device <kdeconnect-id> FILE
maidshare --adb <host:port> FILE
maidshare --receive [--time MIN]   # phone -> PC: browser upload, QR shown
```

multiple files go out concurrently (one job each, failures tracked per
file); HTTP files share a single throwaway server since the port is
fixed for firewall sanity.

pin one KDE Connect phone: `echo '<id>' > ~/.config/kdeconnect-share-target`
(`kdeconnect-cli -l` lists ids). ADB target: `--adb` or `$MAID_ADB`.
HTTP server: port `$MAID_HTTP_PORT` (default 8077), valid `$SERVE_MIN`
minutes (default 10).

right-click any file(s) in dolphin → **Send to phone (MaidShare)**
(or Send via QR). other direction, zero phone setup: `maidshare --receive`
shows a QR; scan it and upload from the phone browser into
`~/Downloads/MaidShare`. per-run token URL, auto-expires.

## notes

if the phone can't reach the http/receive URL it's the firewall, not the
script — it prints the exact open command (firewalld/ufw) instead of
failing silently. kdeconnect backend needs pair + same network. adb
backend needs an authorized device (`adb pair` / `adb connect`).

## related projects

- [OpenDrop](https://github.com/seemoo-lab/opendrop) — open AirDrop
  implementation (send files/links to **Apple** receivers over AWDL).
  not a MaidShare backend on purpose: it targets iPhones/Macs, not
  android, and needs AWDL radio support most linux laptops lack — but
  if someone you share with is on apple hardware, that's the tool you would want to use. 

## uninstall

```sh
rm ~/.local/bin/maidshare; rm -rf ~/.local/bin/backends
rm ~/.local/bin/maidshare-receive.py
rm ~/.local/share/applications/maidshare.desktop
rm ~/.local/share/kio/servicemenus/maidshare.desktop
```

## License

MIT — see LICENSE.
