# changelog

## kdeconnectd early-login fix moved to Maid Helper

- the version-specific patch no longer travels in this repo. Maid
  Helper's `kdeconnect` doctor installs a user-level platform-fallback
  wrapper that works across KDE Connect versions and survives package
  updates: `maid-helper --only kdeconnect --fix`.
- the upstream-style source patch is shipped by Maid Helper under its
  `patches/kdeconnect-26.08.2/` and attached to its releases.

## stronger send-side token

- the http send backend's secret path now uses the same 128-bit
  url-safe token as receive (`secrets.token_urlsafe(16)`), replacing
  six random bytes (48 bits). same flow and expiry, just harder to
  guess on a busy lan.

## receive: uploads go straight to disk

- the receive server no longer collects the request body in memory:
  multipart parts are written to their final file as they arrive in
  bounded chunks, so a huge upload costs kilobytes of RAM, not
  gigabytes. the declared size is checked against free disk space
  first, a new `MAID_MAX_FILE_MB` cap bounds each single file
  (default: the request cap), and a rejected or broken upload leaves
  no partial file behind.

## receive resource bounds

- uploads stream in 64 KiB chunks straight to disk (RAM stays flat), capped at
  `MAID_MAX_MB` (default keeps the old 500), at most 4 concurrent
  uploads (rest get 503), 60 s per-connection socket timeout, and
  the server still auto-expires. plaintext answers nothing.

## encrypted browser directions (https + TOFU)

- send (http backend) and receive now serve https only, with a
  throwaway per-run cert (openssl, 1-day validity, deleted after).
  the terminal prints the sha256 fingerprint - compare it with the
  browser's certificate warning before proceeding (trust on first
  use). token gate + auto-expiry still apply on top.
- plaintext answers nothing on those ports anymore (tested).
- needs the openssl CLI now; without it the http backend stays off
  with a plain error instead of falling back to http.

## dispatcher fix

- parallel sends no longer join backend and filename with `|`; filenames
  containing a literal pipe now send to the right backend intact.

## receive hardening + concurrency

- uploads save atomically (O_EXCL, concurrent same-name uploads can't
  clobber), hostile filenames get basename-stripped, control chars
  stripped from logs, oversize rejected by header before reading a byte,
  planted symlinks dodged, tracebacks never leak.
- http send dir is token-gated like receive (no open listing).
- multi-file sends run concurrently (one job each); http files share one
  server since the port is fixed for firewall sanity.
- firewall hint suggests runtime-only rules and runs backgrounded so a
  slow firewalld never blocks a send.
- tests/: full localhost suite (serve, upload, traversal, symlink plant,
  dupes, size cap) + CI. installer downloads nothing.
