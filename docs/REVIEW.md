# Review checklist — pass all five before any change ships

1. **Plain words.** Could a non-technical friend follow the README
   diff with no help? Errors must say what to do, not just what broke.
2. **Safe by default.** Auto backend order never exposes anything
   surprising; serving stays throwaway, token-gated, expiring.
3. **Proven, not claimed.** `bash tests/run.sh` green (upload,
   traversal, dupes, caps).
4. **Docs match code.** README updated with behavior + firewall notes.
   No personal data anywhere.
5. **Uninstall story intact.** `--uninstall` asks about settings and
   received files, `--purge` removes everything. Tested with a fake
   HOME, never live.
