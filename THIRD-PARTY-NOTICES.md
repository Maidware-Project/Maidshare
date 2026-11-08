# third-party and credits

Maidshare is Maidware work under the **GPL-3.0-or-later** license in `LICENSE`. It does not bundle third-party libraries; it shells out to tools your system provides.

## Called at runtime, not bundled
Provided by your system/distribution (availability varies by backend):
- **bash** and core userland.
- **Python 3** (PSF License): used for helper components (e.g. the receive/web flow where applicable).
- **KDE Connect** / `kdeconnect-cli`, `kdeconnectd` (GPL): file/URL sharing backend when available.
- **Android platform-tools / adb** (Apache-2.0 components): USB/wireless device file push backend when available.
- **python3 + openssl** (and related tooling): used for local receive/QR web-share flows as implemented (cert/serving helpers); exact tools depend on your environment.
- **qrencode** or equivalent (if used by the receive/QR flow on your system) — optional, provided by the distro.
- **A web browser** (on the phone/receiving device) for the QR receive flow — not bundled.

## Desktop / integration (referenced, not bundled)
- **XDG** desktop/menu conventions for launchers/integration; no XDG code bundled.

Everything else in this repository is original Maidware work. Corrections welcome.
