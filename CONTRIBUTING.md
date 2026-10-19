# contributing

small, reviewable changes only - one logical change per pull request. if
your description is turning into a story, it's probably two patches. read
README.md first; it covers what the project is and how it
builds. maintained by Maidware Project.

## commits

- short lowercase summaries with a prefix: `fix:`, `feat:`, `docs:`,
  `tests:`, `chore:` - e.g. `fix: keep the receive page up until the
  upload finishes`
- sign off every commit (`git commit -s` appends it):
  `Signed-off-by: Your Name <you@example.com>` - the developer's
  certificate of origin, your word that you may contribute it
- bug fixes name what they fix: `Fixes: #123` or `Closes: #123` (the
  issue number, or the symptom if no issue exists)

## before opening anything

- `bash tests/run.sh` green on your machine, and the output pasted in the
  pull request. it runs on localhost only - a throwaway server here, no
  phone, no real network - and covers the upload path, name clashes,
  directory traversal, the size cap and the TLS/key handling.
- `bash install.sh --check` writes nothing
- CI must be green before review - a green run on your machine is the
  start, not the finish
- touched the receive side? say what you actually exercised: a real phone,
  `curl`, or the suite alone
- no personal data anywhere (MACs, names, IPs, home paths). the suite
  greps for it and CI fails on a hit

## know your patch

understand every line you send. if you can't
say what a line does, drop it - "i didn't write it" is not an
answer.

you need basic linux: the terminal, file permissions, what sudo does,
where configs live (~/.config). this repo moves files over a network, so
guessing isn't contributing.

reviewers here are people, not bots: expect to answer questions about your
patch, and don't open one you can't back up. unattended drive-by or bot
PRs get closed.

## issues

use the bug report template, paste the diagnostics it asks for, trim
personal data before posting publicly. "it doesn't work" with nothing
attached will be closed with a pointer back here.
