# changelog

## receive resource bounds

- uploads stream in 64 KiB chunks (RAM stays flat), capped at
  `MAID_MAX_MB` (default keeps the old 500), at most 4 concurrent
  uploads (rest get 503), 60 s per-connection socket timeout, and
  the server still auto-expires. plaintext answers nothing.

## encrypted browser directions (https + TOFU)

- send (http backend) and receive now serve https only, with a
  throwaway per-run cert (openssl, 1-day validity, deleted after).
  the terminal prints the sha256 fingerprint — compare it with the
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
