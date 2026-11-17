#!/bin/sh
# Explicit opt-in public-site verification; never included in the offline gate.
set -eu
cd "$(dirname "$0")/.."
run=$(mktemp -d "$PWD/target/browser-https-online.XXXXXXXX")
printf 'UTC %s\n' "$(date -u +%Y-%m-%dT%H:%M:%SZ)" >"$run/proof.log"
sha256sum target/lkjbrowser /etc/ssl/certs/ca-certificates.crt >>"$run/proof.log"
while IFS="$(printf '\t')" read -r name url; do
 timeout 30 target/lkjbrowser --headless --layout "$run/$name.layout" "$url" >"$run/$name.log" 2>&1
 if grep -Fxq 'TITLE Unable to open this page' "$run/$name.layout"; then cat "$run/$name.log"; exit 1; fi
 grep -F 'authenticated tls=1.3' "$run/$name.log" >/dev/null
 cat "$run/$name.log" >>"$run/proof.log"
 printf 'PASS public HTTPS %s\n' "$url"
done <docs/tls/public-pages.tsv
while IFS="$(printf '\t')" read -r name url; do
 timeout 20 target/lkjbrowser --headless --layout "$run/$name.layout" "$url" >"$run/$name.log" 2>&1
 grep -Fx 'TITLE Unable to open this page' "$run/$name.layout" >/dev/null
 case "$name" in
  expired-rsa|expired-ecc) grep -F 'has expired' "$run/$name.log" >/dev/null ;;
  badssl-*) grep -F 'could not negotiate' "$run/$name.log" >/dev/null ;;
 esac
 cat "$run/$name.log" >>"$run/proof.log"
 printf 'PASS public refusal %s\n' "$name"
done <docs/tls/public-negative.tsv
printf 'Public proof: %s\n' "$run/proof.log"
printf 'Badssl hosts currently refuse this TLS 1.3 profile before certificates; these are negotiation errors.\n'
