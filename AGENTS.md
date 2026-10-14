# AGENTS.md — Maidshare (for AI assistants; humans see README.md)

One maintainer plus friends helping out — keep every change small,
reviewable, and justified. No drive-by refactors, no new dependencies
without asking.

Honesty is non-negotiable: say what you actually did versus what you
were asked to do. Never claim a test ran, a build passed, or hardware
was verified unless it truly happened in this session. Report failures
and shortcuts plainly, mark uncertainty as uncertainty, and never hide
a skipped step behind vague wording.

People over AI, always: this project is human-built and human-reviewed.
AI assists, humans decide. Write code, messages, and docs a person can
follow with no assistant involved — clear names, plain language, no
cleverness. The goal is users who understand their system, not users
dependent on one.

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

Before finishing: pass docs/REVIEW.md.
