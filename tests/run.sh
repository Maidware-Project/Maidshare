#!/usr/bin/env bash
# MaidShare test suite. No deps beyond bash/python3/curl. Safe: localhost
# only, temp dirs, no phone/network touched. Exit nonzero on first failure.
set -u
PKGDIR="$(cd "$(dirname "$0")/.." && pwd)"
PASS=0
ok()   { PASS=$((PASS+1)); echo "ok $PASS - $1"; }
fail() { echo "NOT OK - $1"; exit 1; }

echo "== syntax =="
for f in "$PKGDIR"/bin/maidshare "$PKGDIR"/bin/backends/*.sh "$PKGDIR"/install.sh; do
  bash -n "$f" || fail "bash -n $f"
done
python3 -m py_compile "$PKGDIR/bin/maidshare-receive.py" || fail "py_compile receive"
command -v shellcheck >/dev/null 2>&1 && shellcheck -S error "$PKGDIR"/bin/maidshare "$PKGDIR"/bin/backends/*.sh "$PKGDIR"/install.sh || true
ok "syntax"

echo "== personal data =="
if grep -rn -E "90:BF|SmartAction|soundcore|Liberty|Mothership|10\.0\.0|/home/visa" \
    "$PKGDIR/bin" "$PKGDIR/README.md" "$PKGDIR/install.sh" 2>/dev/null | grep -v "s|/home/visa|"; then
  fail "personal string leaked"
fi
ok "no personal data"

echo "== installer dry run =="
[ -d "${TMPDIR:-/tmp}/maidshare-test" ] && rm -rf "${TMPDIR:-/tmp}/maidshare-test"
mkdir -p "${TMPDIR:-/tmp}/maidshare-test-home"
HOME="${TMPDIR:-/tmp}/maidshare-test-home" bash "$PKGDIR/install.sh" --check >/dev/null 2>&1 \
  || fail "install --check"
[ -f "${TMPDIR:-/tmp}/maidshare-test-home/.local/bin/maidshare" ] && fail "dry run wrote files"
ok "installer dry run clean"

echo "== http backend: multi-file serve =="
for p in $(pgrep -f "http.server 807[78]"); do
  [ "$p" != "$$" ] && [ "$p" != "$PPID" ] && kill "$p" 2>/dev/null || true
done
sleep 1
echo one > /tmp/ms-t1.txt; echo two > /tmp/ms-t2.txt
SERVE_MIN=1 bash "$PKGDIR/bin/maidshare" --via http /tmp/ms-t1.txt /tmp/ms-t2.txt >/tmp/ms-out.txt 2>&1 &
sleep 4
U1=$(grep -oE "http://[0-9.]+:[0-9]+/[^ ]+/ms-t1.txt" /tmp/ms-out.txt | head -n 1)
U2=$(grep -oE "http://[0-9.]+:[0-9]+/[^ ]+/ms-t2.txt" /tmp/ms-out.txt | head -n 1)
[ "$(curl -s "$U1")" = "one" ] || fail "http fetch file 1"
[ "$(curl -s "$U2")" = "two" ] || fail "http fetch file 2"
BASE=$(dirname "$U1")
ROOT=$(echo "$U1" | grep -oE "http://[0-9.]+:[0-9]+")
[ "$(curl -s "$ROOT/" | grep -c "ms-t")" = "0" ] || fail "filenames exposed at root"
ok "http multi-file serve (token-gated)"

echo "== receive: upload + traversal + dupes =="
rm -rf /tmp/ms-dl && mkdir -p /tmp/ms-dl
rm -rf /tmp/ms-dl && mkdir -p /tmp/ms-dl
XDG_DOWNLOAD_DIR=/tmp/ms-dl bash "$PKGDIR/bin/maidshare" --receive --time 1 >/tmp/ms-recv.txt 2>&1 &
sleep 4
RU=$(grep -oE "http://[0-9.]+:[0-9]+/[A-Za-z0-9_-]+" /tmp/ms-recv.txt | head -n 1)
[ -n "$RU" ] || fail "receive URL printed"
[ "$(curl -s -o /dev/null -w "%{http_code}" "$RU/wrongtoken")" = "403" ] || fail "bad token not rejected"
[ "$(curl -s -F "f=@/tmp/ms-t1.txt" "$RU/upload")" = "saved: ms-t1.txt" ] || fail "upload"
printf evil > /tmp/evil.txt
[ "$(curl -s -F "f=@/tmp/evil.txt;filename=../../etc/pwned" "$RU/upload")" = "saved: pwned" ] || fail "traversal not contained"
[ -e /tmp/etc/pwned ] && fail "traversal escaped!"
[ -f /tmp/ms-dl/MaidShare/pwned ] || fail "traversal file misplaced"
echo "victim-data" > /tmp/victim.txt
ln -sf /tmp/victim.txt /tmp/ms-dl/MaidShare/linkevil
printf newdata > /tmp/linkevil
[ "$(curl -s -F "f=@/tmp/linkevil" "$RU/upload")" = "saved: linkevil-2" ] || fail "planted symlink not dodged"
[ "$(cat /tmp/victim.txt)" = "victim-data" ] || fail "symlink target clobbered!"
rm -f /tmp/linkevil /tmp/victim.txt
[ "$(curl -s -F "f=@/tmp/ms-t1.txt" "$RU/upload")" = "saved: ms-t1-2.txt" ] || fail "dup rename"
[ "$(cat /tmp/ms-dl/MaidShare/ms-t1.txt)" = "one" ] || fail "upload content"
# oversize rejected by header check before any body is read
[ "$(timeout 15 curl -s -o /dev/null -w "%{http_code}" -X POST -H "Content-Length: 600000000" -H "Content-Type: multipart/form-data; boundary=x" --data-binary "" "$RU/upload")" = "403" ] || fail "oversize not rejected"
ok "receive upload, traversal, dupes, size cap"

echo "== cleanup =="
for p in $(pgrep -f "maidshare-receive.py"); do
  [ "$p" != "$$" ] && [ "$p" != "$PPID" ] && kill "$p" 2>/dev/null || true
done
for p in $(pgrep -f "http.server 807[78]"); do
  [ "$p" != "$$" ] && [ "$p" != "$PPID" ] && kill "$p" 2>/dev/null || true
done
rm -rf /tmp/ms-t1.txt /tmp/ms-t2.txt /tmp/evil.txt /tmp/ms-out.txt /tmp/ms-recv.txt /tmp/ms-dl /tmp/maidshare-test-home /tmp/etc
ok "cleanup"
echo "ALL $PASS PASSED"
