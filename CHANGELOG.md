# changelog

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
