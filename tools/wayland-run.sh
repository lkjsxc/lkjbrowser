#!/bin/sh
# Same native browser binary on a real Wayland desktop.
set -eu
cd "$(dirname "$0")/.."
if ! test -x target/lkjbrowser; then sh tools/build.sh; fi
if ! test -x target/byte-descriptor-bridge; then sh tools/wayland-build-bridge.sh; fi
case "${WAYLAND_DISPLAY:-wayland-0}" in
 /*) socket="${WAYLAND_DISPLAY}" ;;
 *) socket="${XDG_RUNTIME_DIR:?XDG_RUNTIME_DIR is required}/${WAYLAND_DISPLAY:-wayland-0}" ;;
esac
if ! test -S "$socket"; then echo "No Wayland socket: $socket" >&2; exit 1; fi
run_directory=$(mktemp -d "$PWD/target/browser-run.XXXXXXXX")
bridge_pid= browser_pid=
cleanup() {
 for pid in "$browser_pid" "$bridge_pid"; do
  if test -n "$pid"; then kill "$pid" 2>/dev/null || true; wait "$pid" 2>/dev/null || true; fi
 done
 rm -rf "$run_directory"
}
trap cleanup EXIT
trap 'exit 130' HUP INT TERM
frame="$run_directory/frame.bgra"
truncate -s 6082304 "$frame"
target/byte-descriptor-bridge "$socket" "$frame" >"$run_directory/port" 2>"$run_directory/bridge.log" &
bridge_pid=$!
attempt=0
while ! test -s "$run_directory/port"; do
 if ! kill -0 "$bridge_pid" 2>/dev/null; then cat "$run_directory/bridge.log" >&2; exit 1; fi
 attempt=$((attempt + 1))
 if test "$attempt" -ge 50; then echo "Transport bridge startup timed out" >&2; exit 1; fi
 sleep 0.1
done
port=$(cat "$run_directory/port")
if test "$#" -eq 0; then set -- "file://$PWD/fixtures/article.html"; fi
target/lkjbrowser --wayland "$port" --frame-file "$frame" "$@" &
browser_pid=$!
wait "$browser_pid"
browser_pid=
