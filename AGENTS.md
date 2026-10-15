# AGENTS.md - Maidshare (for AI assistants; humans see README.md)

One maintainer plus a friend or two. Keep changes small enough to review,
skip refactors nobody asked for, and ask before pulling in a dependency.

Say what you actually did, not what you were asked to do. The receive side
moves files between two machines, so "the tests passed" has to mean you ran
them, not that they look like they would.

The assistant helps, a person decides. Write for the next reader, not for
the tool that typed it.

Phone↔PC file sharing. Backends auto-picked kdeconnect → adb → http.
Lowercase terse voice in docs (README, messages, popups).

## Layout

- `bin/maidshare` dispatcher, `bin/backends/backend-*.sh`,
  `bin/maidshare-receive.py` (phone→PC browser upload, token URL)
- `desktop/` launcher, `servicemenu/` Dolphin entries, `install.sh`

## Rules

- No personal data in repo. Installer copies, never symlinks, backs up.
- CODE_OF_CONDUCT.md applies to code, comments, and docs:
  technical scope, no politics, stay neutral.
- Commits: short lowercase summaries with a prefix (`fix:`, `feat:`, `docs:`,
  `tests:`, `chore:`), one logical change each. Sign off every commit
  (`git commit -s`); AI-assisted work adds an `Assisted-by:` trailer
  naming the tool. Bug fixes cite `Fixes: #N`.
- Security-sensitive paths (receive upload): token-gated, auto-expire,
  traversal-tested. Keep the traversal tests green.
- HTTP serving is throwaway by design; never background it.

## Verify

- `bash tests/run.sh` - includes upload, traversal, dupe, size-cap tests
- `bash install.sh --check` - dry run
- Uninstaller contract: `--uninstall` keeps settings/received files
  (asks), `--purge` removes everything. Test with a fake HOME only.

Before finishing: pass docs/REVIEW.md.
