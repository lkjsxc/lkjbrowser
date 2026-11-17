#!/bin/sh
# Full browser on an owned headless Weston, serving pages on a fresh loopback port.
set -eu
cd "$(dirname "$0")/.."
sh tools/build.sh
sh tools/wayland-build-bridge.sh
if ! test -x .deps/root/usr/bin/weston; then sh tools/wayland-deps.sh; fi
.toolchain/lkjscript build src/fixture_server.lkj -o target/fixture-server
.toolchain/lkjscript build src/pixel_compare.lkj -o target/pixel-compare
.toolchain/lkjscript build src/animate.lkj -o target/animate
run=$(mktemp -d "$PWD/target/browser-capture.XXXXXXXX")
comp_pid= server_pid= bridge_pid= browser_pid=
cleanup() {
 for pid in "$browser_pid" "$bridge_pid" "$server_pid" "$comp_pid"; do
  if test -n "$pid"; then kill "$pid" 2>/dev/null || true; wait "$pid" 2>/dev/null || true; fi
 done
}
trap cleanup EXIT
trap 'exit 130' HUP INT TERM
export XDG_RUNTIME_DIR="$PWD/.deps/runtime"
export WAYLAND_DISPLAY="browser-capture-$$"
mkdir -p "$XDG_RUNTIME_DIR"
chmod 700 "$XDG_RUNTIME_DIR"
sh tools/wayland-headless.sh "$WAYLAND_DISPLAY" >"$run/compositor.log" 2>&1 &
comp_pid=$!
target/fixture-server "$PWD/fixtures" "$run/port" >"$run/server.log" 2>&1 &
server_pid=$!
attempt=0
while ! test -S "$XDG_RUNTIME_DIR/$WAYLAND_DISPLAY" || ! test -s "$run/port"; do
 if ! kill -0 "$comp_pid" 2>/dev/null || ! kill -0 "$server_pid" 2>/dev/null; then cat "$run/compositor.log" "$run/server.log"; exit 1; fi
 attempt=$((attempt+1)); if test "$attempt" -gt 100; then echo "Capture setup timed out" >&2; exit 1; fi
 sleep 0.05
done
port=$(cat "$run/port")
closed=$(cat "$run/port.closed")
printf 'Real Weston 13 pixman screenshots; browser source pin:\n' >docs/wayland-final-proof.log
cat toolchain.lock >>docs/wayland-final-proof.log
capture() {
 name=$1; url=$2
 mkdir -p "$run/$name"
 frame="$run/$name/frame.bgra"
 truncate -s 6082304 "$frame"
 target/byte-descriptor-bridge "$XDG_RUNTIME_DIR/$WAYLAND_DISPLAY" "$frame" >"$run/$name/bridge-port" 2>"$run/$name/bridge.log" &
 bridge_pid=$!
 attempt=0
 while ! test -s "$run/$name/bridge-port"; do
  attempt=$((attempt+1)); if test "$attempt" -gt 100; then echo "Bridge timed out" >&2; exit 1; fi
  sleep 0.03
 done
 bridge_port=$(cat "$run/$name/bridge-port")
 target/lkjbrowser --wayland "$bridge_port" --frame-file "$frame" --max-ms 2000 \
  --screenshot "$run/$name/program.png" --layout "shots/$name.layout" "$url" >"$run/$name/browser.log" 2>&1 &
 browser_pid=$!
 attempt=0
 while ! test -s "$run/$name/program.png"; do
  if ! kill -0 "$browser_pid" 2>/dev/null; then cat "$run/$name/browser.log"; exit 1; fi
  attempt=$((attempt+1)); if test "$attempt" -gt 100; then echo "Browser timed out" >&2; exit 1; fi
  sleep 0.03
 done
 sleep 0.3
 root=$PWD
 (cd "$run/$name"; LD_LIBRARY_PATH="$root/.deps/root/usr/lib/x86_64-linux-gnu:$root/.deps/root/usr/lib/x86_64-linux-gnu/weston" "$root/.deps/root/usr/bin/weston-screenshooter")
 set -- "$run/$name"/wayland-screenshot-*.png
 test "$#" -eq 1
 test -s "$1"
 mv "$1" "shots/$name.png"
 wait "$browser_pid"; browser_pid=
 wait "$bridge_pid"; bridge_pid=
 printf '\n%s %s\n' "$name" "$url" >>docs/wayland-final-proof.log
 cat "$run/$name/browser.log" >>docs/wayland-final-proof.log
 target/pixel-compare "shots/$name.png" "$run/$name/program.png" >>docs/wayland-final-proof.log
}
capture article "http://127.0.0.1:$port/article.html"
capture simple "http://127.0.0.1:$port/simple.html"
capture error "http://127.0.0.1:$closed/unreachable"
capture_motion() {
 mkdir -p "$run/motion"
 frame="$run/motion/frame.bgra"
 truncate -s 6082304 "$frame"
 target/byte-descriptor-bridge "$XDG_RUNTIME_DIR/$WAYLAND_DISPLAY" "$frame" >"$run/motion/bridge-port" 2>"$run/motion/bridge.log" &
 bridge_pid=$!
 attempt=0
 while ! test -s "$run/motion/bridge-port"; do
  attempt=$((attempt+1)); if test "$attempt" -gt 100; then echo "Motion bridge timed out" >&2; exit 1; fi
  sleep 0.03
 done
 bridge_port=$(cat "$run/motion/bridge-port")
 target/lkjbrowser --wayland "$bridge_port" --frame-file "$frame" --max-ms 15000 \
  --live-script tests/demo.live --screenshot "$run/motion/initial.png" --layout "$run/motion/final.layout" \
  "http://127.0.0.1:$port/article.html" >"$run/motion/browser.log" 2>&1 &
 browser_pid=$!
 attempt=0
 while ! test -s "$run/motion/initial.png"; do
  if ! kill -0 "$browser_pid" 2>/dev/null; then cat "$run/motion/browser.log"; exit 1; fi
  attempt=$((attempt+1)); if test "$attempt" -gt 100; then echo "Motion browser timed out" >&2; exit 1; fi
  sleep 0.03
 done
 sleep 0.1
 root=$PWD
 i=0
 while test "$i" -lt 16; do
  if ! kill -0 "$browser_pid" 2>/dev/null; then cat "$run/motion/browser.log"; echo "Motion browser exited before capture completed" >&2; exit 1; fi
  label=$(printf '%03d' "$i")
  frame_dir="$run/motion/capture-$label"
  mkdir -p "$frame_dir"
  (cd "$frame_dir"; LD_LIBRARY_PATH="$root/.deps/root/usr/lib/x86_64-linux-gnu:$root/.deps/root/usr/lib/x86_64-linux-gnu/weston" "$root/.deps/root/usr/bin/weston-screenshooter")
  set -- "$frame_dir"/wayland-screenshot-*.png
  test "$#" -eq 1
  test -s "$1"
  mv "$1" "$run/motion/frame-$label.png"
  i=$((i+1))
  if test "$i" -lt 16; then sleep 0.35; fi
 done
 wait "$browser_pid"; browser_pid=
 wait "$bridge_pid"; bridge_pid=
 set --
 relative_run=$(basename "$run")
 for frame in "$run/motion"/frame-*.png; do
  set -- "$@" "target/$relative_run/motion/$(basename "$frame")"
 done
 printf 'Actual Weston screenshots of one continuously running native browser.\nInput is timed application event replay, not physical hardware input.\nFrames retain exact PNG pixels; animation uses a nominal 400 ms frame delay.\n' >docs/motion-proof.log
 target/animate shots/scroll-and-link.apng 400 "$@" >>docs/motion-proof.log
 cat "$run/motion/browser.log" >>docs/motion-proof.log
 grep -F "Script 3400ms: click 130 120" "$run/motion/browser.log" >/dev/null
 grep -F "Script 5200ms: click 75 35" "$run/motion/browser.log" >/dev/null
 grep -Fx "URL http://127.0.0.1:$port/article.html" "$run/motion/final.layout" >/dev/null
}
capture_motion
target/lkjbrowser --headless "http://127.0.0.1:$port/shutdown" >"$run/shutdown.log"
wait "$server_pid"; server_pid=
kill "$comp_pid"
wait "$comp_pid" || true
comp_pid=
printf '\nAll capture-owned processes stopped. No system installation or service.\n' >>docs/wayland-final-proof.log
cat docs/wayland-final-proof.log
printf '%s\n' "$run" >target/latest-capture-run
