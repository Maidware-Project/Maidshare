# contributing

small, reviewable changes only - one logical change per pull request. if
your description is turning into a story, it's probably two patches. read
AGENTS.md first; it applies to humans and AI assistants alike. maintained
by Maidware Project.

## commits

- short lowercase summaries with a prefix: `fix:`, `feat:`, `docs:`,
  `tests:`, `chore:` - e.g. `fix: keep the receive page up until the
  upload finishes`
- sign off every commit (`git commit -s` appends it):
  `Signed-off-by: Your Name <you@example.com>` - the developer's
  certificate of origin, your word that you may contribute it
- AI-assisted work gets an `Assisted-by:` trailer naming the tool, e.g.
  `Assisted-by: opencode (muse-spark)`. the kernel requires it; so do we.
  never claim a test ran that didn't.
- bug fixes name what they fix: `Fixes: #123` or `Closes: #123` (the
  issue number, or the symptom if no issue exists)

## before opening anything

- `bash tests/run.sh` green on your machine, and the output pasted in the
  pull request. it runs on localhost only - a throwaway server here, no
  phone, no real network - and covers the upload path, name clashes,
  directory traversal, the size cap and the TLS/key handling.
- `bash install.sh --check` writes nothing
- touched the receive side? say what you actually exercised: a real phone,
  `curl`, or the suite alone
- no personal data anywhere (MACs, names, IPs, home paths). the suite
  greps for it and CI fails on a hit

## know your patch

understand every line you send, assistant-written parts included. if you
can't say what a line does, drop it - "the assistant wrote it" is not an
answer.

you need basic linux: the terminal, file permissions, what sudo does,
where configs live (~/.config). this repo moves files over a network, so
guessing isn't contributing.

## issues

use the bug report template, paste the diagnostics it asks for, trim
personal data before posting publicly. "it doesn't work" with nothing
attached will be closed with a pointer back here.
