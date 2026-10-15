# MaidShare — send files and links from linux to your android phone

no phone app needed. it picks the best way automatically (KDE Connect
first, then USB/ADB, then a throwaway wifi page) and tells you which
one it used — check the popup before walking away. override anytime
with `--via`.

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
| http backend | python + openssl + qrencode (opt) | python3 + openssl + qrencode | python3 + openssl + qrencode | python3 + openssl + qrencode |
| picker/popups | kdialog or zenity | kdialog or zenity | kdialog or zenity | kdialog or zenity |

no services here — everything runs on demand when you click it or scan
a code, so init doesn't matter. fork it for whatever setup you run.

## installation

```sh
bash install.sh            # copy + icon + servicemenu, reports backend status
bash install.sh --check    # dry run
```

existing files are backed up to `*.bak-<timestamp>`. install.sh downloads
nothing — every dependency comes from your distro repos. then: launcher →
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

send several files at once — each goes out on its own, and you
get told per file if one fails. filenames with spaces, quotes, or
even `|` are sent intact.

setup shortcuts: pin one phone with
`echo '<id>' > ~/.config/kdeconnect-share-target`
(`kdeconnect-cli -l` lists ids). USB target: `--adb` or `$MAID_ADB`.

two ways to use it: right-click any file(s) in dolphin →
**Send to phone (MaidShare)** (or Send via QR). other direction needs
no phone setup at all: `maidshare --receive` shows a QR code, scan it,
upload from the phone browser — files land in `~/Downloads/MaidShare`.
the link is token-protected and expires on its own.

both browser directions run over https with a throwaway per-run cert
(1-day validity, deleted after). first visit shows a certificate
warning — that's expected: compare the fingerprint in your terminal
with the one the browser shows, then proceed. token + expiry still
apply on top.

## if it doesn't work

phone can't reach the page? that's your firewall, not the script — it
prints the exact command to open it (firewalld/ufw). otherwise: KDE
Connect needs the phone paired and on the same wifi; USB needs an
authorized device (`adb pair` / `adb connect`). prefer KDE Connect
when you can. only use the wifi-page method on networks you trust,
and stop it (Ctrl-C) when done — anyone on the network with the link
can download while it's up.

## related projects

- [OpenDrop](https://github.com/seemoo-lab/opendrop) — open AirDrop
  implementation (send files/links to **Apple** receivers over AWDL).
  not a MaidShare backend on purpose: it targets iPhones/Macs, not
  android, and needs AWDL radio support most linux laptops lack — but
  if someone you share with is on apple hardware, that's the tool you would want to use. 

## uninstall

```sh
bash install.sh --uninstall            # everything out, asks about settings + received files
bash install.sh --uninstall --purge    # everything out including those, no questions
```

## License

MIT — see LICENSE.

## works with the Maid suite

Stands alone, plays nice: [Maid AU](https://github.com/Maidware-Project/Maid-AU) pulls
Maidshare updates (`MAID_SUITE`, deploy with `UPDATE_MAID_DEPLOY=1`),
and your KDE Connect pairing is shared with Maid BT phone features —
pair once, both work.

## Linux Mint / Cinnamon

Same `apt` path as Ubuntu. Nemo gets its own right-click action alongside the Dolphin one; PulseAudio systems use the same `pactl` fallbacks, nothing to configure.
