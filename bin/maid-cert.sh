#!/usr/bin/env bash
# MaidShare per-run TLS cert. Sourced, not executed.
# maid_cert DIR: writes DIR/cert.pem + DIR/key.pem (throwaway, 1-day
# validity) and echoes the SHA256 fingerprint in AA:BB:... form, the
# same form phone browsers show on the certificate-warning screen, so
# the user can compare them (TOFU). Needs the openssl CLI. Callers
# delete DIR when done (cert dies with the server).
# Returns nonzero when openssl is missing or generation fails.

maid_cert() {
  local dir="$1" fp
  [ -n "$dir" ] || return 1
  command -v openssl >/dev/null 2>&1 || return 1
  openssl req -x509 -newkey rsa:2048 -keyout "$dir/key.pem" \
    -out "$dir/cert.pem" -days 1 -nodes -subj "/CN=MaidShare" \
    2>/dev/null || return 1
  chmod 600 "$dir/key.pem" 2>/dev/null || true
  fp=$(openssl x509 -noout -fingerprint -sha256 \
    -in "$dir/cert.pem" 2>/dev/null) || return 1
  echo "${fp##*=}"
}
