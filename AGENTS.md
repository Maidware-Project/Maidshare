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

## What you can't do here

- The whole point is moving files between two machines. CI runs the suite;
  it cannot reach a real phone, so a green run is not a real transfer.
- The receive path is a real http server, tested through stubs. A second
  device on a real network is the only thing that proves it end to end.
- kdeconnect and adb need actual devices and a live desktop session. When
  you could not run a backend by hand, say that.

## Layout

- `bin/maidshare` dispatcher, `bin/backends/backend-*.sh`,
  `bin/maidshare-receive.py` (phone→PC browser upload, token URL)
- `desktop/` launcher, `servicemenu/` Dolphin entries, `install.sh`

## Rules

- No personal data in repo. Installer copies, never symlinks, backs up.
- CODE_OF_CONDUCT.md applies to code, comments, and docs:
  technical scope, no politics, stay neutral.
- Commits: short lowercase summaries with a prefix (`fix:`, `feat:`, `docs:`,
  `tests:`, `chore:`), one logical change each. Sign off every commit -
  the trailer is exactly `Signed-off-by: visa`, no email. Bug fixes cite
  `Fixes: #N`.
- Security-sensitive paths (receive upload): token-gated, auto-expire,
  traversal-tested. Keep the traversal tests green.
- HTTP serving is throwaway by design; never background it.

## Principles

Keep it simple ([KISS](https://en.wikipedia.org/wiki/KISS_principle)) and
boring. In practice:

- The smallest change that solves the problem; nothing added "for later"
  (YAGNI).
- One place owns each fact; no repeated logic (DRY).
- Each tool does one thing well and composes (unix philosophy, rule of
  least power).
- Readable beats clever; less is more (worse is better).
- Delete what nothing needs instead of keeping it around.

## Never

- Never push. The maintainer pushes; commits stay local until asked.
- Never leave the receive server running behind the script, or in a test
  that can outlive it.
- Never echo, log or commit the upload token, and never weaken the token,
  expiry, traversal or size-cap checks to make something pass.
- Never report a transfer, a device or a test you did not actually run.

## Boundaries (do not touch)

- The backend order (kdeconnect → adb → http) and the auto-pick rules.
- The receive-side guards: token, expiry, traversal, size cap.
- The installer contract: copies, never symlinks, backs up; `--uninstall`
  keeps settings and received files (asks), `--purge` removes everything.

## Verify

- `bash tests/run.sh` - includes upload, traversal, dupe, size-cap tests
- `bash install.sh --check` - dry run
- Uninstaller contract: `--uninstall` keeps settings/received files
  (asks), `--purge` removes everything. Test with a fake HOME only.

## Making a change

1. `git status -sb` first. A commit or a sync can land while you work,
   and amending something already pushed leaves duplicate commits.
2. Make the smallest diff that solves the stated problem.
3. Run `bash tests/run.sh` and `bash install.sh --check`.
4. If a backend or the receive path changed, exercise it as far as the
   machine allows, and say what you could not.
5. Pass `docs/REVIEW.md`, then commit with a sign-off. Do not push.

## References

- `README.md` - what it does, backends, phone setup
- `docs/REVIEW.md` - the checklist to pass before a change ships
- `CONTRIBUTING.md` - how to take part
- `CODE_OF_CONDUCT.md` - scope, and what stays out of the repo
- `CHANGELOG.md` - what changed, release by release
- `SECURITY.md` - how to report a security problem
