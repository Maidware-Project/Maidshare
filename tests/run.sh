#!/usr/bin/env bash
# MaidShare test suite. No deps beyond bash/python3/curl/openssl. Safe: localhost
# only, temp dirs, no phone/network touched. Exit nonzero on first failure.
set -u
PKGDIR="$(cd "$(dirname "$0")/.." && pwd)"
PASS=0
ok()   { PASS=$((PASS+1)); echo "ok $PASS - $1"; }
fail() { echo "NOT OK - $1"; exit 1; }

echo "== syntax =="
for f in "$PKGDIR"/bin/maidshare "$PKGDIR"/bin/maid-cert.sh "$PKGDIR"/bin/backends/*.sh "$PKGDIR"/install.sh; do
  bash -n "$f" || fail "bash -n $f"
done
python3 -m py_compile "$PKGDIR/bin/maidshare-receive.py" || fail "py_compile receive"
command -v shellcheck >/dev/null 2>&1 && shellcheck -S error "$PKGDIR"/bin/maidshare "$PKGDIR"/bin/maid-cert.sh "$PKGDIR"/bin/backends/*.sh "$PKGDIR"/install.sh || true
ok "syntax"

echo "== personal data =="
if grep -rni -E "90:BF|SmartAction|soundcore|Liberty|Mothership|10\.0\.0|/home/visa" \
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

echo "== https backend: multi-file serve =="
# our servers run as `python3 - 8077 ...` (no "http.server" in argv),
# plus the dispatcher parent holding the sleep: clear both.
for pat in "python3 - 807[78]( |$)" "bin/maidshare --via http"; do
  for p in $(pgrep -f "$pat"); do
    [ "$p" != "$$" ] && [ "$p" != "$PPID" ] && kill "$p" 2>/dev/null || true
  done
done
sleep 1
echo one > /tmp/ms-t1.txt; echo two > /tmp/ms-t2.txt
SERVE_MIN=1 bash "$PKGDIR/bin/maidshare" --via http /tmp/ms-t1.txt /tmp/ms-t2.txt >/tmp/ms-out.txt 2>&1 &
sleep 4
U1=$(grep -oE "https://[0-9.]+:[0-9]+/[^ ]+/ms-t1.txt" /tmp/ms-out.txt | head -n 1)
U2=$(grep -oE "https://[0-9.]+:[0-9]+/[^ ]+/ms-t2.txt" /tmp/ms-out.txt | head -n 1)
[ -n "$U1" ] && [ -n "$U2" ] || fail "no https URLs printed"
grep -qE "fingerprint.*([0-9A-F]{2}:){31}[0-9A-F]{2}" /tmp/ms-out.txt || fail "no cert fingerprint shown"
[ "$(curl -sk "$U1")" = "one" ] || fail "https fetch file 1"
[ "$(curl -sk "$U2")" = "two" ] || fail "https fetch file 2"
P1=$(echo "$U1" | sed 's|^https://|http://|')
[ -z "$(curl -s --max-time 10 "$P1" 2>/dev/null)" ] || fail "plaintext answered on TLS port"
BASE=$(dirname "$U1")
ROOT=$(echo "$U1" | grep -oE "https://[0-9.]+:[0-9]+")
# key material lives outside the web root: direct requests must 404
[ "$(curl -sk -o /dev/null -w "%{http_code}" "$ROOT/key.pem")" = "404" ] || fail "key.pem served!"
[ "$(curl -sk -o /dev/null -w "%{http_code}" "$ROOT/cert.pem")" = "404" ] || fail "cert.pem served!"
[ "$(curl -sk -o /dev/null -w "%{http_code}" "$ROOT/../key.pem")" = "404" ] || fail "traversal served!"
[ "$(curl -sk "$ROOT/" | grep -c "ms-t")" = "0" ] || fail "filenames exposed at root"
ok "https multi-file serve (token-gated)"

echo "== receive: upload + traversal + dupes =="
rm -rf /tmp/ms-dl && mkdir -p /tmp/ms-dl
rm -rf /tmp/ms-dl && mkdir -p /tmp/ms-dl
XDG_DOWNLOAD_DIR=/tmp/ms-dl bash "$PKGDIR/bin/maidshare" --receive --time 1 >/tmp/ms-recv.txt 2>&1 &
sleep 4
RU=$(grep -oE "https://[0-9.]+:[0-9]+/[A-Za-z0-9_-]+" /tmp/ms-recv.txt | head -n 1)
[ -n "$RU" ] || fail "receive URL printed"
grep -qE "fingerprint.*([0-9A-F]{2}:){31}[0-9A-F]{2}" /tmp/ms-recv.txt || fail "no cert fingerprint shown"
[ "$(curl -sk -o /dev/null -w "%{http_code}" "$RU/wrongtoken")" = "403" ] || fail "bad token not rejected"
[ "$(curl -sk -F "f=@/tmp/ms-t1.txt" "$RU/upload")" = "saved: ms-t1.txt" ] || fail "upload"
printf evil > /tmp/evil.txt
[ "$(curl -sk -F "f=@/tmp/evil.txt;filename=../../etc/pwned" "$RU/upload")" = "saved: pwned" ] || fail "traversal not contained"
[ -e /tmp/etc/pwned ] && fail "traversal escaped!"
[ -f /tmp/ms-dl/MaidShare/pwned ] || fail "traversal file misplaced"
echo "victim-data" > /tmp/victim.txt
ln -sf /tmp/victim.txt /tmp/ms-dl/MaidShare/linkevil
printf newdata > /tmp/linkevil
[ "$(curl -sk -F "f=@/tmp/linkevil" "$RU/upload")" = "saved: linkevil-2" ] || fail "planted symlink not dodged"
[ "$(cat /tmp/victim.txt)" = "victim-data" ] || fail "symlink target clobbered!"
rm -f /tmp/linkevil /tmp/victim.txt
[ "$(curl -sk -F "f=@/tmp/ms-t1.txt" "$RU/upload")" = "saved: ms-t1-2.txt" ] || fail "dup rename"
[ "$(cat /tmp/ms-dl/MaidShare/ms-t1.txt)" = "one" ] || fail "upload content"
# concurrency: 6 parallel uploads must all succeed (slots recycle, no deadlock)
# (wait only the curl pids — never the background server itself)
rm -f /tmp/ms-par-*.txt
parpids=""
for i in 1 2 3 4 5 6; do
  curl -sk -F "f=@/tmp/ms-t1.txt" "$RU/upload" > /tmp/ms-par-$i.txt 2>/dev/null &
  parpids="$parpids $!"
done
for p in $parpids; do wait "$p" || fail "parallel upload job failed"; done
for i in 1 2 3 4 5 6; do
  grep -q "^saved: ms-t1" /tmp/ms-par-$i.txt || fail "parallel upload $i failed"
done
rm -f /tmp/ms-par-*.txt
ok "receive concurrent uploads"
# oversize rejected by header check before any body is read
[ "$(timeout 15 curl -sk -o /dev/null -w "%{http_code}" -X POST -H "Content-Length: 600000000" -H "Content-Type: multipart/form-data; boundary=x" --data-binary "" "$RU/upload")" = "403" ] || fail "oversize not rejected"
ok "receive upload, traversal, dupes, size cap"

echo "== receive: configurable size cap =="
rm -rf /tmp/ms-dl2 && mkdir -p /tmp/ms-dl2
head -c 2000000 /dev/urandom > /tmp/ms-big.bin
MAID_HTTP_PORT=8079 MAID_MAX_MB=1 XDG_DOWNLOAD_DIR=/tmp/ms-dl2 bash "$PKGDIR/bin/maidshare" --receive --time 1 >/tmp/ms-cap.txt 2>&1 &
sleep 4
RCAP=$(grep -oE "https://[0-9.]+:[0-9]+/[A-Za-z0-9_-]+" /tmp/ms-cap.txt | head -n 1)
[ -n "$RCAP" ] || fail "capped server URL missing"
[ "$(curl -sk -o /dev/null -w "%{http_code}" -F "f=@/tmp/ms-big.bin" "$RCAP/upload")" = "403" ] || fail "2MB over 1MB cap not rejected"
[ "$(curl -sk -F "f=@/tmp/ms-t1.txt" "$RCAP/upload")" = "saved: ms-t1.txt" ] || fail "small upload under cap failed"
for p in $(pgrep -f "maidshare-receive.py"); do
  [ "$p" != "$$" ] && [ "$p" != "$PPID" ] && kill "$p" 2>/dev/null || true
done
rm -rf /tmp/ms-dl2 /tmp/ms-big.bin /tmp/ms-cap.txt
ok "receive size cap configurable"

echo "== cleanup =="
for p in $(pgrep -f "maidshare-receive.py"); do
  [ "$p" != "$$" ] && [ "$p" != "$PPID" ] && kill "$p" 2>/dev/null || true
done
for pat in "python3 - 807[78]( |$)" "bin/maidshare --via http"; do
  for p in $(pgrep -f "$pat"); do
    [ "$p" != "$$" ] && [ "$p" != "$PPID" ] && kill "$p" 2>/dev/null || true
  done
done
rm -rf /tmp/ms-t1.txt /tmp/ms-t2.txt /tmp/evil.txt /tmp/ms-out.txt /tmp/ms-recv.txt /tmp/ms-dl /tmp/maidshare-test-home /tmp/etc
ok "cleanup"
echo "ALL $PASS PASSED"
