# Maidshare - send files and links from linux to android

send files or links to Android and receive files back from your phone. `maidshare` runs as an interactive **TUI** by default (arrow keys + number, send/receive/update/uninstall); CLI args still work for scripting (`maidshare file`, `--receive`, `--via`). **Maidshare GUI** (`maidshare-gui`, optional, needs `python3-pyqt6`) does both directions in a window. picks KDE Connect first, then USB/ADB, then a temporary wifi page. no phone app needed.

```
bin/maidshare         dispatcher: picker, backend select, multi-file fan-out
bin/backends/backend-kdeconnect.sh   paired phone on LAN (files + URLs)
bin/backends/backend-adb.sh          ADB push to /sdcard/Download (files)
bin/backends/backend-http.sh         throwaway LAN server + QR (files, zero setup)
bin/maidshare-receive.py  phone -> PC browser upload (token URL, auto-expires)
bin/maidshare-gui      window launcher (Qt around the same CLI, optional)
src/maidshare_gui/     the window itself (send list + receive QR)
desktop/              launcher icon (pin to task manager)
servicemenu/          Dolphin/Nemo right-click entries (send / send-via-QR)
install.sh            installer (copies, never symlinks)
```

## quick start

```sh
# one line, straight from GitHub:
bash <(curl -fsSL https://raw.githubusercontent.com/Maidware-Project/Maidshare/main/install.sh)

bash install.sh            # copy + icon, reports which backends work
maidshare file.pdf         # picks KDE Connect, ADB, or wifi page for you
maidshare --receive        # phone uploads to your PC via QR + browser
maidshare-gui              # the window: drag files in, or scan the receive QR
```

## why not just KDE Connect / LocalSend / Snapdrop?

KDE Connect alone is the best backend and Maidshare uses it first - but
it needs the app installed, paired, same wifi. Maidshare covers the
rest: USB/ADB with no network at all, and a QR wifi page with zero phone
setup. vs Snapdrop/LocalSend: no third app, no account, files land
straight in `~/Downloads/MaidShare`, and the receive side is token +
https + expiry by default.

tested daily on openSUSE Tumbleweed → Android; backends auto-detect
(kdeconnect / adb / python3+openssl). suite green in CI.

## what you need

backends are optional and auto-detected - install any of them:

| need | arch | debian/ubuntu | fedora | opensuse |
|---|---|---|---|---|
| kdeconnect backend | kdeconnect | kdeconnect | kdeconnect | kdeconnect-kde |
| adb backend | android-tools | adb | android-tools | android-tools |
| http backend | python + openssl + qrencode (opt) | python3 + openssl + qrencode | python3 + openssl + qrencode | python3 + openssl + qrencode |
| gui window (opt) | pyqt6 | python3-pyqt6 | python3-pyqt6 | python313-PyQt6 |
| picker/popups | kdialog or zenity | kdialog or zenity | kdialog or zenity | kdialog or zenity |

no services here - everything runs on demand when you click it or scan a
code, so init doesn't matter.

## installation

```sh
bash install.sh            # copy + icon + servicemenu, reports backend status
bash install.sh --check    # dry run
```

existing files are backed up to `*.bak-<timestamp>`. `install.sh`
downloads nothing - every dependency comes from your distro repos. then:
launcher → **MaidShare GUI** (pin to task manager for one click).

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

send several files at once - each goes out on its own, and you get told
per file if one fails. filenames with spaces, quotes, or `|` are sent
intact.

setup shortcuts: pin one phone with
`echo '<id>' > ~/.config/kdeconnect-share-target`
(`kdeconnect-cli -l` lists ids). USB target: `--adb` or `$MAID_ADB`.

## the window

`maidshare-gui` wraps the same CLI (same backends, same files land in the
same place). the **send** tab keeps a list (drag files or links in),
picks a backend or forces one, and streams output as it runs. the
**receive** tab starts the listen, draws the QR, shows the token URL
with a copy button and the cert fingerprint to compare against the
browser warning; stopping the listen (or closing the window) stops the
server. it follows the suite's Maid Scroll palettes from
`~/.config/maid-scroll/`.

right-click any file(s) in Dolphin → **Send to phone (MaidShare)** (or
Send via QR). the other direction needs no phone setup: `maidshare
--receive` shows a QR code, scan it, upload from the phone browser -
files land in `~/Downloads/MaidShare`.

## safety & limits

both browser directions run over https with a throwaway per-run cert
(1-day validity, deleted after). first visit shows a certificate warning
- expected: compare the fingerprint in your terminal with the one the
browser shows, then proceed. token + expiry still apply.

uploads are streamed straight to disk (low memory). caps: `MAID_MAX_MB`
per request (default 500), `MAID_MAX_FILE_MB` per file (default: the
request cap), four uploads at once (extra ones get 503), and the server
refuses an upload up front when free disk space is too tight. rejected
or interrupted uploads leave no partial file behind.

## if it doesn't work

phone can't reach the page? that's your firewall - the script prints the
exact command to open it (firewalld/ufw). KDE Connect needs the phone
paired and on the same wifi; USB needs an authorized device (`adb pair`
/ `adb connect`). prefer KDE Connect when you can. only use the
wifi-page method on networks you trust, and stop it (Ctrl-C) when done -
anyone on the network with the link can download while it's up.

## Linux Mint / Cinnamon

same `apt` path as Ubuntu. Nemo gets its own right-click action
alongside the Dolphin one; PulseAudio systems use the same `pactl`
fallbacks, nothing to configure.

## related projects

- [OpenDrop](https://github.com/seemoo-lab/opendrop) - open AirDrop
  implementation (send files/links to **Apple** receivers over AWDL).
  not a MaidShare backend: it targets iPhones/Macs, not Android, and
  needs AWDL radio support most linux laptops lack.

## uninstall

```sh
bash install.sh --uninstall            # everything out, asks about settings + received files
bash install.sh --uninstall --purge    # everything out including those, no questions
```

## works with the Maid suite

Maidshare stands alone. it works well with [Maid Suite](https://github.com/Maidware-Project/Maid-Suite),
the canonical Maidware front end (TUI/GUI) which embeds the Helper and
AU updater cores and can install/update Maidshare and the rest of the
suite. the standalone Maid Helper and Maid AU repos are archived; their
cores live in Maid Suite. your KDE Connect pairing is shared with Maid
BT phone features - pair once, both work.

## License

GPL-3.0-or-later — forkable and open source. See `LICENSE`.
Third-party notices and credits: `THIRD-PARTY-NOTICES.md` (names what
Maidshare references or depends on; third-party components keep their
own licenses). Part of the Maidware Project.
