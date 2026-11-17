#!/bin/bash
# Continuous compositor capture. Requires an explicitly approved browser SHA.
set -euo pipefail
cd "$(dirname "$0")/../.."
root=$PWD
expected=${1:?usage: bash review/motion/capture-integrated.sh APPROVED_BROWSER_SHA256}
test "${#expected}" = 64
actual=$(sha256sum target/lkjbrowser | cut -d' ' -f1)
if test "$actual" != "$expected"; then echo "Browser binary changed; obtain the approved rebuilt hash first." >&2; exit 1; fi
LC_ALL=C grep -aF 'Live script requires milliseconds and action' target/lkjbrowser >/dev/null
command -v node >/dev/null
run=$(mktemp -d "$root/target/independent-review-motion-capture-XXXXXX")
label=$(basename "$run")
out="$root/review/motion/captures/$label"
mkdir -p "$out/frames"
printf '%s\n' "$out" >"$root/review/motion/latest-capture-path.txt"
printf '%s\n' "$run" >"$out/runtime-path.txt"
exec 3>"$out/commands.log"
BASH_XTRACEFD=3
set -x
date -u +%Y-%m-%dT%H:%M:%SZ >"$out/started-utc.txt"
cp target/lkjbrowser "$run/lkjbrowser"
test "$(sha256sum "$run/lkjbrowser" | cut -d' ' -f1)" = "$expected"
cp target/byte-descriptor-bridge "$run/byte-descriptor-bridge"
cp target/fixture-server "$run/fixture-server"
cp -a fixtures "$run/fixtures"
cp review/motion/integrated-events.script "$out/events.script"
cp toolchain.lock "$out/toolchain.lock"
sha256sum target/lkjbrowser target/byte-descriptor-bridge target/fixture-server .toolchain/lkjscript-x86_64-linux >"$out/binaries.sha256"
sha256sum "$run/lkjbrowser" "$run/byte-descriptor-bridge" "$run/fixture-server" >"$out/frozen-binaries.sha256"
sha256sum src/*.lkj program.lkj toolchain.lock bridge/byte_descriptor_bridge.c fixtures/*.html fixtures/*.png >"$out/source-fixtures.sha256"
sha256sum .deps/root/usr/bin/weston .deps/root/usr/bin/weston-screenshooter >"$out/compositor-binaries.sha256"
font_dir=/usr/share/fonts/truetype/liberation
if ! test -f "$font_dir/LiberationSans-Regular.ttf"; then font_dir=/usr/share/fonts/truetype/liberation2; fi
sha256sum "$font_dir"/LiberationSans-*.ttf >"$out/fonts.sha256"
mkdir -m 700 "$run/r"
export XDG_RUNTIME_DIR="$run/r"
export WAYLAND_DISPLAY=wl
export LD_LIBRARY_PATH="$root/.deps/root/usr/lib/x86_64-linux-gnu:$root/.deps/root/usr/lib/x86_64-linux-gnu/weston"
export WESTON_MODULE_MAP="headless-backend.so=$root/.deps/root/usr/lib/x86_64-linux-gnu/libweston-13/headless-backend.so;kiosk-shell.so=$root/.deps/root/usr/lib/x86_64-linux-gnu/weston/kiosk-shell.so"
weston_pid= server_pid= bridge_pid= client_pid=
cleanup() {
    set +e
    for owned_pid in "$client_pid" "$bridge_pid" "$server_pid" "$weston_pid"; do
        if test -n "$owned_pid"; then kill "$owned_pid" 2>/dev/null; wait "$owned_pid" 2>/dev/null; fi
    done
    date -u +%Y-%m-%dT%H:%M:%SZ >"$out/finished-utc.txt"
}
trap cleanup EXIT
trap 'exit 130' HUP INT TERM
"$root/.deps/root/usr/bin/weston" --version >"$out/weston-version.txt"
"$root/.deps/root/usr/bin/weston" --backend=headless --renderer=pixman --width=1000 --height=760 --shell="$root/.deps/root/usr/lib/x86_64-linux-gnu/weston/kiosk-shell.so" --socket="$WAYLAND_DISPLAY" --idle-time=0 --no-config --debug --log="$out/weston.log" >"$out/weston-stdio.log" 2>&1 &
weston_pid=$!
for ((attempt=0;attempt<100;attempt++)); do
    test -S "$run/r/$WAYLAND_DISPLAY" && break
    kill -0 "$weston_pid";sleep 0.05
done
test -S "$run/r/$WAYLAND_DISPLAY"
"$run/fixture-server" "$run/fixtures" "$run/http-port" >"$out/http-server.log" 2>&1 &
server_pid=$!
for ((attempt=0;attempt<100;attempt++)); do
    test -s "$run/http-port" && break
    kill -0 "$server_pid";sleep 0.05
done
port=$(cat "$run/http-port")
printf '%s\n' "$port" >"$out/http-port.txt"
truncate -s 6082304 "$run/frame.bgra"
"$run/byte-descriptor-bridge" "$run/r/$WAYLAND_DISPLAY" "$run/frame.bgra" >"$run/bridge-port" 2>"$out/bridge.log" &
bridge_pid=$!
for ((attempt=0;attempt<100;attempt++)); do
    test -s "$run/bridge-port" && break
    kill -0 "$bridge_pid";sleep 0.05
done
bridge_port=$(cat "$run/bridge-port")
browser_started_ns=$(date +%s%N)
"$run/lkjbrowser" --wayland "$bridge_port" --frame-file "$run/frame.bgra" --font-dir "$font_dir" --live-script "$out/events.script" --layout "$out/final.layout" --max-ms 15000 "http://127.0.0.1:$port/article.html" >"$out/browser.log" 2>"$out/browser.err" &
client_pid=$!
printf '%s\n' "$client_pid" >"$out/browser.pid"
sleep 0.25
capture_started_ns=$(date +%s%N)
for ((index=0;index<55;index++)); do
    deadline_ns=$((capture_started_ns+index*200000000))
    now_ns=$(date +%s%N)
    if test "$now_ns" -lt "$deadline_ns"; then
        remaining=$((deadline_ns-now_ns))
        printf -v delay '%d.%09d' $((remaining/1000000000)) $((remaining%1000000000))
        sleep "$delay"
    fi
    kill -0 "$client_pid"
    printf -v number '%04d' "$index"
    frame_dir="$run/capture-$number"
    mkdir "$frame_dir"
    (cd "$frame_dir"; timeout 2 "$root/.deps/root/usr/bin/weston-screenshooter") >"$out/frames/$number.log" 2>"$out/frames/$number.err"
    captured_ns=$(date +%s%N)
    captures=("$frame_dir"/wayland-screenshot-*.png)
    test "${#captures[@]}" = 1
    cp "${captures[0]}" "$out/frames/$number.png"
    printf '%s\tframes/%s.png\n' "$(((captured_ns-browser_started_ns)/1000000))" "$number" >>"$out/frames.tsv"
done
wait "$client_pid"
client_pid=
wait "$bridge_pid"
bridge_pid=
grep -Fx "URL http://127.0.0.1:$port/simple.html" "$out/final.layout"
grep -Fx "VIEW 1000 760 SCROLL 0" "$out/final.layout"
grep -Fx "Script 6200ms: click 130 120" "$out/browser.log"
test "$(grep -c '^Script ' "$out/browser.log")" = 10
test ! -s "$out/browser.err"
"$run/lkjbrowser" --headless --font-dir "$font_dir" "http://127.0.0.1:$port/shutdown" >"$out/http-shutdown.log" 2>&1
wait "$server_pid"
server_pid=
kill "$weston_pid"
wait "$weston_pid" || true
weston_pid=
node "$root/review/motion/encode-apng.mjs" "$out/frames.tsv" "$out/scroll-and-link.png" >"$out/encoding.log"
sha256sum "$out"/frames/*.png "$out/scroll-and-link.png" >"$out/capture.sha256"
sha256sum src/*.lkj program.lkj toolchain.lock bridge/byte_descriptor_bridge.c fixtures/*.html fixtures/*.png >"$out/source-fixtures-after.sha256"
if cmp -s "$out/source-fixtures.sha256" "$out/source-fixtures-after.sha256"; then
    printf 'Sources and fixtures stayed unchanged during capture.\n' >"$out/source-stability.txt"
else
    printf 'Shared sources or fixtures changed during capture. Frozen binaries and fixtures were used.\n' >"$out/source-stability.txt"
fi
printf 'PASS: one browser process, ten timed ordinary-handler events, 55 actual compositor frames.\n'
printf 'Capture: %s\n' "$out"
