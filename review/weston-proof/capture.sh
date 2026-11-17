#!/bin/bash
# Independent review: copy existing binaries, use a private compositor, capture its output.
set -euo pipefail
cd "$(dirname "$0")/../.."
root=$PWD
proof="$root/review/weston-proof"
mkdir -p "$proof"
run=$(mktemp -d "$root/target/independent-review-weston-XXXXXX")
printf '%s\n' "$run" >"$proof/runtime-path.txt"
exec 3>"$proof/commands.log"
BASH_XTRACEFD=3
set -x
date -u +%Y-%m-%dT%H:%M:%SZ >"$proof/started-utc.txt"
cp target/lkjbrowser "$run/lkjbrowser"
cp target/byte-descriptor-bridge "$run/byte-descriptor-bridge"
cp target/fixture-server "$run/fixture-server"
cp toolchain.lock "$proof/toolchain.lock"
sha256sum target/lkjbrowser target/byte-descriptor-bridge target/fixture-server .toolchain/lkjscript-x86_64-linux >"$proof/binaries.sha256"
sha256sum src/*.lkj program.lkj toolchain.lock bridge/byte_descriptor_bridge.c fixtures/article.html fixtures/simple.html fixtures/workshop.png >"$proof/source-fixtures.sha256"
sha256sum "$run/lkjbrowser" "$run/byte-descriptor-bridge" "$run/fixture-server" >"$proof/frozen-binaries.sha256"
sha256sum .deps/root/usr/bin/weston .deps/root/usr/bin/weston-screenshooter >"$proof/compositor-binaries.sha256"
font_dir=/usr/share/fonts/truetype/liberation
if ! test -f "$font_dir/LiberationSans-Regular.ttf"; then font_dir=/usr/share/fonts/truetype/liberation2; fi
sha256sum "$font_dir"/LiberationSans-*.ttf >"$proof/fonts.sha256"
mkdir -m 700 "$run/runtime"
export XDG_RUNTIME_DIR="$run/runtime"
export WAYLAND_DISPLAY=review-wl
export LD_LIBRARY_PATH="$root/.deps/root/usr/lib/x86_64-linux-gnu:$root/.deps/root/usr/lib/x86_64-linux-gnu/weston"
export WESTON_MODULE_MAP="headless-backend.so=$root/.deps/root/usr/lib/x86_64-linux-gnu/libweston-13/headless-backend.so;kiosk-shell.so=$root/.deps/root/usr/lib/x86_64-linux-gnu/weston/kiosk-shell.so"
weston_pid= server_pid= bridge_pid= client_pid=
cleanup() {
    set +e
    for owned_pid in "$client_pid" "$bridge_pid" "$server_pid" "$weston_pid"; do
        if test -n "$owned_pid"; then
            kill "$owned_pid" 2>/dev/null
            wait "$owned_pid" 2>/dev/null
        fi
    done
    date -u +%Y-%m-%dT%H:%M:%SZ >"$proof/finished-utc.txt"
}
trap cleanup EXIT
trap 'exit 130' HUP INT TERM
"$root/.deps/root/usr/bin/weston" --version >"$proof/weston-version.txt"
"$root/.deps/root/usr/bin/weston" --backend=headless --renderer=pixman --width=1000 --height=760 --shell="$root/.deps/root/usr/lib/x86_64-linux-gnu/weston/kiosk-shell.so" --socket="$WAYLAND_DISPLAY" --idle-time=0 --no-config --debug --log="$proof/weston.log" >"$proof/weston-stdio.log" 2>&1 &
weston_pid=$!
for ((attempt=0; attempt<100; attempt++)); do
    test -S "$run/runtime/$WAYLAND_DISPLAY" && break
    kill -0 "$weston_pid"
    sleep 0.05
done
test -S "$run/runtime/$WAYLAND_DISPLAY"
"$run/fixture-server" "$root/fixtures" "$run/http-port" >"$proof/http-server.log" 2>&1 &
server_pid=$!
for ((attempt=0; attempt<100; attempt++)); do
    test -s "$run/http-port" && break
    kill -0 "$server_pid"
    sleep 0.05
done
port=$(cat "$run/http-port")
closed_port=$(cat "$run/http-port.closed")
printf '%s\n' "$port" >"$proof/http-port.txt"
printf '%s\n' "$closed_port" >"$proof/unreachable-port.txt"
capture() {
    local name=$1 url=$2
    local page="$run/$name"
    mkdir -p "$page" "$proof/$name"
    truncate -s 6082304 "$page/frame.bgra"
    "$run/byte-descriptor-bridge" "$run/runtime/$WAYLAND_DISPLAY" "$page/frame.bgra" >"$page/bridge-port" 2>"$proof/$name/bridge.log" &
    bridge_pid=$!
    for ((attempt=0; attempt<100; attempt++)); do
        test -s "$page/bridge-port" && break
        kill -0 "$bridge_pid"
        sleep 0.05
    done
    local bridge_port
    bridge_port=$(cat "$page/bridge-port")
    printf '%s\n' "$url" >"$proof/$name/url.txt"
    "$run/lkjbrowser" --wayland "$bridge_port" --frame-file "$page/frame.bgra" --font-dir "$font_dir" --max-ms 6500 "$url" >"$proof/$name/browser.log" 2>"$proof/$name/browser.err" &
    client_pid=$!
    sleep 2
    kill -0 "$client_pid"
    (cd "$proof/$name"; timeout 10 "$root/.deps/root/usr/bin/weston-screenshooter") >"$proof/$name/capture.log" 2>"$proof/$name/capture.err"
    local captures=("$proof/$name"/wayland-screenshot-*.png)
    test "${#captures[@]}" = 1
    cp "${captures[0]}" "$proof/$name.png"
    wait "$client_pid"
    client_pid=
    wait "$bridge_pid"
    bridge_pid=
}
capture article "http://127.0.0.1:$port/article.html"
capture simple "http://127.0.0.1:$port/simple.html"
capture unreachable "http://127.0.0.1:$closed_port/unreachable"
"$run/lkjbrowser" --headless --font-dir "$font_dir" "http://127.0.0.1:$port/shutdown" >"$proof/http-shutdown.log" 2>&1
wait "$server_pid"
server_pid=
sha256sum "$proof/article.png" "$proof/simple.png" "$proof/unreachable.png" >"$proof/screenshots.sha256"
sha256sum src/*.lkj program.lkj toolchain.lock bridge/byte_descriptor_bridge.c fixtures/article.html fixtures/simple.html fixtures/workshop.png >"$proof/source-fixtures-after.sha256"
cmp "$proof/source-fixtures.sha256" "$proof/source-fixtures-after.sha256" && printf 'Source hashes stayed unchanged during capture.\n' >"$proof/source-stability.txt" || printf 'Source changed during capture; binaries were frozen before capture.\n' >"$proof/source-stability.txt"
printf 'PASS: three actual Weston output captures; binary copies frozen; all owned child processes cleaned up.\n'
