# review checklist

run through these before a change ships.

1. plain words. could a non-technical friend follow the README diff with
   no help? errors should say what to do, not just what broke.
2. safe by default. the auto backend order never exposes anything
   surprising; serving stays throwaway, token-gated, expiring.
3. proven, not claimed. `bash tests/run.sh` green (upload, traversal,
   dupes, caps).
4. docs match code. README updated with behavior and firewall notes. no
   personal data anywhere.
5. uninstall story intact. `--uninstall` asks about settings and received
   files, `--purge` removes everything. tested with a fake HOME, never
   live.
