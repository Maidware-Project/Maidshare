# AGENTS.md — Maidshare (for AI assistants; humans see README.md)

One maintainer plus friends helping out — keep every change small,
reviewable, and justified. No drive-by refactors, no new dependencies
without asking.

Phone↔PC file sharing. Backends auto-picked kdeconnect → adb → http.

## Layout

- `bin/maidshare` dispatcher, `bin/backends/backend-*.sh`,
  `bin/maidshare-receive.py` (phone→PC browser upload, token URL)
- `desktop/` launcher, `servicemenu/` Dolphin entries, `install.sh`

## Rules

- No personal data in repo. Installer copies, never symlinks, backs up.
- Security-sensitive paths (receive upload): token-gated, auto-expire,
  traversal-tested. Keep the traversal tests green.
- HTTP serving is throwaway by design; never background it.

## Verify

- `bash tests/run.sh` — includes upload, traversal, dupe, size-cap tests
- `bash install.sh --check` — dry run
- Uninstaller contract: `--uninstall` keeps settings/received files
  (asks), `--purge` removes everything. Test with a fake HOME only.
