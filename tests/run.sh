#!/usr/bin/env bash
# MaidShare test suite. No deps beyond bash/python3/curl/openssl. Safe: localhost
# only, temp dirs, no phone/network touched. Exit nonzero on first failure.
set -u
PKGDIR="$(cd "$(dirname "$0")/.." && pwd)"
PASS=0
ok()   { PASS=$((PASS+1)); echo "ok $PASS - $1"; }
fail() { echo "NOT OK - $1"; exit 1; }

echo "== syntax =="
for f in "$PKGDIR"/bin/maidshare "$PKGDIR"/bin/maid-cert.sh "$PKGDIR"/bin/backends/*.sh "$PKGDIR"/install.sh "$PKGDIR"/bin/maidshare-gui; do
  bash -n "$f" || fail "bash -n $f"
done
python3 -m py_compile "$PKGDIR/bin/maidshare-receive.py" || fail "py_compile receive"
python3 -m py_compile "$PKGDIR"/src/maidshare_gui/app.py "$PKGDIR"/src/maidshare_gui/palettes.py || fail "py_compile gui"
command -v shellcheck >/dev/null 2>&1 && shellcheck -S error "$PKGDIR"/bin/maidshare "$PKGDIR"/bin/maid-cert.sh "$PKGDIR"/bin/backends/*.sh "$PKGDIR"/install.sh || true
ok "syntax"

echo "== palette contrast =="
PYTHONPATH="$PKGDIR/src" python3 - <<'EOF' || fail "palette contrast"
from maidshare_gui.palettes import PALETTES

def lum(h):
    h = h.lstrip("#")
    c = [int(h[i:i + 2], 16) / 255 for i in (0, 2, 4)]
    c = [x / 12.92 if x <= 0.04045 else ((x + 0.055) / 1.055) ** 2.4 for x in c]
    return 0.2126 * c[0] + 0.7152 * c[1] + 0.0722 * c[2]

def ratio(a, b):
    la, lb = lum(a), lum(b)
    hi, lo = max(la, lb), min(la, lb)
    return (hi + 0.05) / (lo + 0.05)

bad = []
for name, p in PALETTES:
    for fg in ("fg", "muted", "accent"):
        for bg in ("bg", "bg_alt"):
            r = ratio(p[fg], p[bg])
            if r < 4.5:
                bad.append("%s: %s on %s = %.2f" % (name, fg, bg, r))
if bad:
    print("\n".join(bad))
    raise SystemExit(1)
print("all palette text pairs clear 4.5:1")
EOF
ok "palette contrast"

echo "== personal data =="
if grep -rn --exclude-dir=__pycache__ -iE "([0-9a-f]{2}:){5}[0-9a-f]{2}|/(home|Users)/[^/[:space:]]+|(10|192\.168|172\.(1[6-9]|2[0-9]|3[01]))\.[0-9]{1,3}\.[0-9]{1,3}" \
    "$PKGDIR/bin" "$PKGDIR/desktop" "$PKGDIR/servicemenu" "$PKGDIR/README.md" "$PKGDIR/install.sh" "$PKGDIR/src" 2>/dev/null \
    | grep -v "AA:BB:CC:DD:EE:FF"; then
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
# (wait only the curl pids - never the background server itself)
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

echo "== receive: disk streaming + per-file cap =="
rm -rf /tmp/ms-dl3 && mkdir -p /tmp/ms-dl3
MAID_HTTP_PORT=8080 MAID_RECV_CHUNK=1024 MAID_MAX_FILE_MB=1 XDG_DOWNLOAD_DIR=/tmp/ms-dl3 \
  bash "$PKGDIR/bin/maidshare" --receive --time 1 >/tmp/ms-stream.txt 2>&1 &
sleep 4
RS=$(grep -oE "https://[0-9.]+:[0-9]+/[A-Za-z0-9_-]+" /tmp/ms-stream.txt | head -n 1)
[ -n "$RS" ] || fail "streaming server URL missing"
# uploads are written to disk while the body is still arriving; sweep
# payload sizes so the closing boundary lands at every offset within a
# 1 KiB read chunk (this is what MAID_RECV_CHUNK is for)
python3 - "$RS/upload" /tmp/ms-dl3/MaidShare <<'EOF' || fail "boundary split uploads"
import http.client, ssl, sys, urllib.parse

url = urllib.parse.urlparse(sys.argv[1])
outdir = sys.argv[2]
ctx = ssl.SSLContext(ssl.PROTOCOL_TLS_CLIENT)
ctx.check_hostname = False
ctx.verify_mode = ssl.CERT_NONE
B = b"TESTB0UNDARY1234567890abc"
pattern = b"assorted bytes \r\n--TESTB0UNDARY123 fire \r\n end"
for n in range(1, 261):
    payload = (pattern * (n // len(pattern) + 1))[:n * 4]
    body = (b"--" + B + b"\r\n"
            b"Content-Disposition: form-data; name=\"f\"; filename=\"edge.bin\"\r\n"
            b"Content-Type: application/octet-stream\r\n\r\n" + payload +
            b"\r\n--" + B + b"--\r\n")
    conn = http.client.HTTPSConnection(url.hostname, url.port, context=ctx, timeout=20)
    conn.request("POST", url.path, body=body, headers={
        "Content-Type": "multipart/form-data; boundary=" + B.decode(),
        "Content-Length": str(len(body))})
    resp = conn.getresponse()
    reply = resp.read()
    conn.close()
    want = b"saved: edge.bin\n" if n == 1 else b"saved: edge-%d.bin\n" % n
    if resp.status != 200 or reply != want:
        sys.exit("upload %d: %s %r" % (n, resp.status, reply[:80]))
    with open(outdir + ("/edge.bin" if n == 1 else "/edge-%d.bin" % n), "rb") as f:
        if f.read() != payload:
            sys.exit("upload %d: stored bytes differ" % n)
print("boundary offsets ok: 260")
EOF
# per-file cap: 2 MB over a 1 MB MAID_MAX_FILE_MB is rejected, nothing partial stays
head -c 2000000 /dev/urandom > /tmp/ms-big3.bin
[ "$(curl -sk -o /dev/null -w "%{http_code}" -F "f=@/tmp/ms-big3.bin" "$RS/upload")" = "413" ] || fail "per-file cap not enforced"
[ -e /tmp/ms-dl3/MaidShare/ms-big3.bin ] && fail "partial file left after cap reject"
# two files in one request still land intact
printf 'one' > /tmp/ms-m1.txt; printf 'two' > /tmp/ms-m2.txt
[ "$(curl -sk -F "f=@/tmp/ms-m1.txt" -F "f=@/tmp/ms-m2.txt" "$RS/upload")" = "saved: ms-m1.txt, ms-m2.txt" ] || fail "multi-file single request"
[ "$(cat /tmp/ms-dl3/MaidShare/ms-m1.txt)" = "one" ] || fail "multi-file content 1"
[ "$(cat /tmp/ms-dl3/MaidShare/ms-m2.txt)" = "two" ] || fail "multi-file content 2"
for p in $(pgrep -f "maidshare-receive.py"); do
  [ "$p" != "$$" ] && [ "$p" != "$PPID" ] && kill "$p" 2>/dev/null || true
done
rm -rf /tmp/ms-dl3 /tmp/ms-stream.txt /tmp/ms-big3.bin /tmp/ms-m1.txt /tmp/ms-m2.txt
ok "receive streams to disk, per-file cap, multi-file"

echo "== gui =="
if python3 -c "import PyQt6" 2>/dev/null; then
  QT_QPA_PLATFORM=offscreen PYTHONPATH="$PKGDIR/src" python3 - "$PKGDIR" <<'EOF' || fail "gui window build"
import os, sys

from PyQt6.QtWidgets import QApplication, QTabWidget

from maidshare_gui.app import (build_window, parse_receive_output,
                               send_args)

pkg = sys.argv[1]
cli = os.path.join(pkg, "bin", "maidshare")
app = QApplication([])
win = build_window(cli)
tabs = win.findChild(QTabWidget)
assert tabs and tabs.count() == 2, "window should have send + receive tabs"
assert cli in send_args(cli, ["a.txt"], via="auto")
assert ["--via", "http"] == send_args("m", ["a"], via="http")[1:3]
text = ("MaidShare receive at https://192.0.2.7:8078/abc -> "
        "/home/demo/Downloads/MaidShare (10 min, Ctrl-C stops)\n\n"
        "cert fingerprint (compare with the browser warning): "
        "aa2f:bb33:dead:beef:1111:2222:3333:4444\n")
url, outdir, mins, fp = parse_receive_output(text)
assert url and outdir and mins == 10 and fp, parse_receive_output(text)
assert parse_receive_output("nothing here") == (None, None, None, None)
print("gui build ok")
EOF
  ok "gui window builds (send + receive tabs, argv builder, receive parser)"
  rm -rf "${TMPDIR:-/tmp}/ms-gui-shot.png"
  QT_QPA_PLATFORM=offscreen PYTHONPATH="$PKGDIR/src" \
    python3 -m maidshare_gui --screenshot "${TMPDIR:-/tmp}/ms-gui-shot.png" \
    >/dev/null 2>&1 || fail "gui screenshot run"
  [ -s "${TMPDIR:-/tmp}/ms-gui-shot.png" ] || fail "gui screenshot empty"
  file "${TMPDIR:-/tmp}/ms-gui-shot.png" | grep -qi "PNG image data" \
    || fail "gui screenshot not a PNG"
  rm -f "${TMPDIR:-/tmp}/ms-gui-shot.png"
  ok "gui --screenshot renders a PNG without a display"
else
  ok "gui tests skipped (PyQt6 not installed; the CLI still runs)"
fi

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
