#!/bin/sh
# Reproducible native fixture, event, layout and pixel tests. No public network.
set -eu
cd "$(dirname "$0")/.."
export LC_ALL=C
mode=check
case "${1:-}" in
 --update-goldens) mode=update ;;
 "") ;;
 *) echo "usage: sh tools/test.sh [--update-goldens]" >&2; exit 2 ;;
esac
sh tools/build.sh
.toolchain/lkjscript test . --engine native --jobs 1
sh tools/probe-gaps.sh
sh tools/wayland-test.sh
.toolchain/lkjscript build src/fixture_server.lkj -o target/fixture-server
font_dir=${LKJBROWSER_FONT_DIR:-/usr/share/fonts/truetype/liberation}
if ! test -f "$font_dir/LiberationSans-Regular.ttf"; then font_dir=/usr/share/fonts/truetype/liberation2; fi
if ! test -f "$font_dir/LiberationSans-Regular.ttf"; then echo "Pixel tests require Liberation Sans; set LKJBROWSER_FONT_DIR." >&2; exit 1; fi
root=$PWD
if test -f tests/fonts.sha256; then
 (cd "$font_dir"; sha256sum -c "$root/tests/fonts.sha256")
fi
run=$(mktemp -d "$PWD/target/browser-tests.XXXXXXXX")
server_pid=
cleanup() {
 if test -n "$server_pid"; then kill "$server_pid" 2>/dev/null || true; wait "$server_pid" 2>/dev/null || true; fi
}
trap cleanup EXIT
trap 'exit 130' HUP INT TERM
target/fixture-server "$PWD/fixtures" "$run/port" >"$run/server.log" 2>&1 &
server_pid=$!
attempt=0
while ! test -s "$run/port"; do
 if ! kill -0 "$server_pid" 2>/dev/null; then cat "$run/server.log"; exit 1; fi
 attempt=$((attempt+1))
 if test "$attempt" -gt 100; then echo "Fixture server did not start" >&2; exit 1; fi
 sleep 0.03
done
port=$(cat "$run/port")
closed=$(cat "$run/port.closed")
base="http://127.0.0.1:$port"
mkdir -p tests/golden
render() {
 name=$1; width=$2; url=$3; shift 3
 target/lkjbrowser --headless --font-dir "$font_dir" --width "$width" --height 760 \
  --screenshot "$run/$name.ppm" --layout "$run/$name.full-layout" "$@" "$url"
 # Only the first URL line varies with checkout directory / ephemeral HTTP port.
 tail -n +2 "$run/$name.full-layout" >"$run/$name.layout"
 # Exact document viewport pixels below the 52 px toolbar (the overlay scrollbar thumb is part of them).
 tail -c "$((width*760*3))" "$run/$name.ppm" |
  dd bs="$((width*3))" skip=52 count=708 iflag=fullblock status=none |
  sha256sum | cut -d' ' -f1 >"$run/$name.pixels.sha256"
}
golden() {
 name=$1
 for suffix in layout pixels.sha256; do
  if test "$mode" = update; then cp "$run/$name.$suffix" "tests/golden/$name.$suffix"
  else cmp "tests/golden/$name.$suffix" "$run/$name.$suffix"
  fi
 done
}
same() {
 cmp "$run/$1.layout" "$run/$2.layout"
 cmp "$run/$1.pixels.sha256" "$run/$2.pixels.sha256"
}
render article 1000 "file://$PWD/fixtures/article.html"
render scrolled 1000 "file://$PWD/fixtures/article.html" --scroll 600
render simple 1000 "file://$PWD/fixtures/simple.html"
render narrow 620 "file://$PWD/fixtures/article.html"
render error-fixture 1000 "file://$PWD/fixtures/error.html"
for name in article scrolled simple narrow error-fixture; do golden "$name"; done
render http 1000 "$base/article.html"
render chunked 1000 "$base/chunked"
render redirect 1000 "$base/redirect"
same article http
same article chunked
same article redirect
render http-image 1000 "$base/simple.html"
same simple http-image
render scroll-event 1000 "file://$PWD/fixtures/article.html" --script tests/scroll.script
same scrolled scroll-event
render click 1000 "file://$PWD/fixtures/article.html" --script tests/click.script
same simple click
grep -F "URL file://$PWD/fixtures/simple.html" "$run/click.full-layout" >/dev/null
render history 1000 "file://$PWD/fixtures/article.html" --script tests/history.script
same article history
render typed-address 1000 "file://$PWD/fixtures/article.html" --script tests/typed-address.script
grep -Fx "URL about:welcome" "$run/typed-address.full-layout" >/dev/null
for endpoint in truncated ambiguous invalid-status large-header; do
 render "$endpoint" 1000 "$base/$endpoint"
 grep -Fx "TITLE Unable to open this page" "$run/$endpoint.full-layout" >/dev/null
done
render unreachable 1000 "http://127.0.0.1:$closed/unreachable"
grep -Fx "TITLE Unable to open this page" "$run/unreachable.full-layout" >/dev/null
render plain 1000 "$base/plain"
render plain-case 1000 "$base/plain-case"
same plain plain-case
sh tools/test-file-policy.sh "$base" "$run" "$font_dir"
target/lkjbrowser --headless "$base/shutdown" >"$run/shutdown.log"
wait "$server_pid"
server_pid=
cp "$run/server.log" target/test-server.log
printf '%s\n' "$run" >target/latest-test-run
printf 'PASS: native unit cases, capability probes, Wayland input peer, 5 layout/pixel goldens, HTTP framing, PNG, click, history, scroll and typed address.\n'
printf 'Evidence: %s\n' "$run"
