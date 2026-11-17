#!/bin/sh
# Actual native browser against independent local TLS peers; no public network.
set -eu
cd "$(dirname "$0")/.."
if [ "${1:-}" != --no-build ]; then sh tools/build.sh; fi
run=$(mktemp -d "$PWD/target/browser-tls-local.XXXXXXXX")
peer= adversary=
cleanup(){
 for pid in "$adversary" "$peer"; do
  if [ -n "$pid" ]; then kill "$pid" 2>/dev/null || true; wait "$pid" 2>/dev/null || true; fi
 done
}
trap cleanup EXIT
trap 'exit 130' HUP INT TERM
UV_THREADPOOL_SIZE=1 node --single-threaded --v8-pool-size=1 tools/tls-local-peer.cjs "$run/ports.json" >"$run/peer.log" 2>&1 &
peer=$!
await_file(){
 file=$1;pid=$2;attempt=0
 while ! test -s "$file"; do
  kill -0 "$pid" 2>/dev/null || { cat "$run/"*.log; exit 1; }
  attempt=$((attempt+1));if [ "$attempt" -gt 100 ]; then echo "TLS peer failed to publish its port"; exit 1; fi
  sleep 0.03
 done
}
await_file "$run/ports.json" "$peer"
port(){ sed -n 's/.*"'"$1"'":\([0-9]*\).*/\1/p' "$run/ports.json"; }
render(){
 name=$1;url=$2;trust=${3:-root}
 timeout 15 target/lkjbrowser --headless --width 1000 --trust-file "$PWD/tests/x509/$trust.pem" \
  --layout "$run/$name.layout" --screenshot "$run/$name.png" "$url" >"$run/$name.log" 2>&1
}
accepted(){
 name=$1;expected_title=$2
 grep -F "TITLE $expected_title" "$run/$name.layout" >/dev/null || { cat "$run/$name.log"; exit 1; }
 grep -F 'authenticated tls=1.3' "$run/$name.log" >/dev/null
 printf 'PASS TLS page %s\n' "$name"
}
refused(){
 name=$1;reason=$2
 grep -Fx 'TITLE Unable to open this page' "$run/$name.layout" >/dev/null || { cat "$run/$name.log"; exit 1; }
 grep -Fi "$reason" "$run/$name.log" >/dev/null || { cat "$run/$name.log"; exit 1; }
 if grep -F 'The web, one readable page' "$run/$name.layout" >/dev/null; then echo "Unauthenticated body leaked"; exit 1; fi
 printf 'PASS TLS error page %s\n' "$name"
}
title='The web, one readable page at a time'
for mode in good rsa p384; do
 render "$mode" "https://localhost:$(port "$mode")/article.html"
 accepted "$mode" "$title"
done
for endpoint in chunked redirect; do
 render "$endpoint" "https://localhost:$(port good)/$endpoint"
 accepted "$endpoint" "$title"
done
render image "https://localhost:$(port good)/simple.html"
grep -Fx 'IMAGES 1' "$run/image.layout" >/dev/null
printf 'PASS HTTPS PNG subresource\n'
render styled "https://localhost:$(port good)/styled.html"
accepted styled 'Style order'
if grep -F 'needle-not-rendered' "$run/styled.layout" >/dev/null; then echo "External CSS did not hide the fixture"; exit 1; fi
grep -F 'color=ff206040' "$run/styled.layout" >/dev/null
render style-before "https://localhost:$(port good)/style-before.html"
grep -F 'color=ff112233' "$run/style-before.layout" >/dev/null
render mixed-style "https://localhost:$(port good)/mixed-style.html"
grep -F 'needle-not-rendered' "$run/mixed-style.layout" >/dev/null
render style-repeat "https://localhost:$(port good)/style-repeat.html"
accepted style-repeat 'Repeated stylesheet'
grep -F 'color=ff112233' "$run/style-repeat.layout" >/dev/null
grep -F 'four-distinct-sheets-only' "$run/style-repeat.layout" >/dev/null
for sheet in repeat cap-a cap-b cap-c; do
 count=$(grep -Fxc "STYLE_REQUEST /$sheet.css" "$run/peer.log" || true)
 if [ "$count" -ne 1 ]; then echo "Expected one cached fetch of $sheet.css, got $count"; exit 1; fi
done
if grep -Fx 'STYLE_REQUEST /cap-denied.css' "$run/peer.log" >/dev/null; then echo "Exceeded four distinct stylesheet fetches"; exit 1; fi
render style-media "https://localhost:$(port good)/style-media.html"
accepted style-media 'Screen media'
for marker in inline-print-visible link-print-visible; do
 grep -F "$marker" "$run/style-media.layout" >/dev/null || { echo "Print-only CSS affected screen content"; exit 1; }
done
if grep -Fx 'STYLE_REQUEST /print.css' "$run/peer.log" >/dev/null; then echo "Fetched print-only stylesheet"; exit 1; fi
render style-width "https://localhost:$(port good)/style-width.html"
accepted style-width 'Exact viewport media'
for marker in inline-exact link-exact inline-query external-query inline-boundary link-boundary screen-only; do
 grep -F "$marker-visible" "$run/style-width.layout" >/dev/null || { echo "CSS media did not match the actual 1000px window: $marker"; exit 1; }
done
grep -Fx 'STYLE_REQUEST /width-exact.css' "$run/peer.log" >/dev/null
for sheet in width-below width-above; do
 if grep -Fx "STYLE_REQUEST /$sheet.css" "$run/peer.log" >/dev/null; then echo "Fetched nonmatching width stylesheet $sheet.css"; exit 1; fi
done
printf 'PASS repeated stylesheet cache order, four-fetch cap and screen media at 1000px\n'
render slow-style "https://localhost:$(port good)/slow-style.html"
accepted slow-style 'Stylesheet timeout'
grep -F 'slow-style-body-visible' "$run/slow-style.layout" >/dev/null
grep -F 'STYLES timeout' "$run/slow-style.log" >/dev/null || { cat "$run/slow-style.log"; echo "Missing shared stylesheet timeout evidence"; exit 1; }
paint_us=$(sed -n 's/^PAINT [^ ]* elapsed_us=\([0-9]*\) .*/\1/p' "$run/slow-style.log")
case "$paint_us" in ''|*[!0-9]*) echo "Missing unambiguous paint timing"; exit 1;; esac
if [ "$paint_us" -ge 5000000 ]; then cat "$run/slow-style.log"; echo "Slow styles blocked body paint for five seconds"; exit 1; fi
printf 'PASS one stylesheet deadline; body painted in %s us\n' "$paint_us"
render lazy "https://localhost:$(port good)/lazy.html"
grep -Fx 'IMAGES 1' "$run/lazy.layout" >/dev/null
timeout 15 target/lkjbrowser --headless --trust-file "$PWD/tests/x509/root.pem" --scroll 1800 \
 --layout "$run/lazy-scroll.layout" "https://localhost:$(port good)/lazy.html" >"$run/lazy-scroll.log"
grep -Fx 'IMAGES 2' "$run/lazy-scroll.layout" >/dev/null
printf 'PASS stylesheet order, mixed-style refusal and visible-image loading\n'
render upgrade "http://localhost:$(port http)/upgrade"
accepted upgrade "$title"
grep -Fx "URL https://localhost:$(port good)/article.html" "$run/upgrade.layout" >/dev/null
render bare-host "localhost:$(port good)/article.html"
accepted bare-host "$title"
render downgrade "https://localhost:$(port good)/downgrade"
refused downgrade 'redirected to an insecure'
render expired "https://localhost:$(port expired)/"
refused expired 'has expired'
render wronghost "https://localhost:$(port wronghost)/"
refused wronghost 'different host name'
render selfsigned "https://localhost:$(port selfsigned)/"
refused selfsigned 'self-signed'
render unknown-root "https://localhost:$(port good)/" unrelated-root
refused unknown-root 'trusted root'
render tampered-record "https://localhost:$(port tampered)/"
refused tampered-record 'integrity check'
for mode in good fragmented key-update bad-finished bad-signature; do
 UV_THREADPOOL_SIZE=1 node --single-threaded --v8-pool-size=1 tools/tls-bad-finished-peer.cjs "$mode" "$run/$mode-port.json" >"$run/$mode-peer.log" 2>&1 &
 adversary=$!
 await_file "$run/$mode-port.json" "$adversary"
 ap=$(sed -n 's/.*"port":\([0-9]*\).*/\1/p' "$run/$mode-port.json")
 render "peer-$mode" "https://localhost:$ap/"
 case "$mode" in
  good|fragmented|key-update) accepted "peer-$mode" 'Authenticated test peer';;
  bad-finished) refused "peer-$mode" 'Finished authentication';;
  bad-signature) refused "peer-$mode" 'signature';;
 esac
 kill "$adversary" 2>/dev/null || true; wait "$adversary" 2>/dev/null || true;adversary=
done
printf 'PASS native TLS local gate; evidence %s\n' "$run"
