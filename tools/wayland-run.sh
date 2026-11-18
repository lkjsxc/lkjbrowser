#!/bin/sh
# Same native browser binary on a real Wayland desktop.
set -eu
cd "$(dirname "$0")/.."
. ./tools/wayland-auth.sh
if ! test -x target/lkjbrowser; then sh tools/build.sh; fi
# Rebuild the tiny transport so an old executable cannot retain obsolete authority rules.
sh tools/wayland-build-bridge.sh
case "${WAYLAND_DISPLAY:-wayland-0}" in
 /*) socket="${WAYLAND_DISPLAY}" ;;
 *) socket="${XDG_RUNTIME_DIR:?XDG_RUNTIME_DIR is required}/${WAYLAND_DISPLAY:-wayland-0}" ;;
esac
if ! test -S "$socket"; then echo "No Wayland socket: $socket" >&2; exit 1; fi
run_directory=$(mktemp -d "$PWD/target/browser-run.XXXXXXXX")
bridge_pid= browser_pid=
cleanup() {
 wayland_auth_close
 for pid in "$browser_pid" "$bridge_pid"; do
  if test -n "$pid"; then kill "$pid" 2>/dev/null || true; wait "$pid" 2>/dev/null || true; fi
 done
 rm -rf "$run_directory"
}
trap cleanup EXIT
trap 'exit 130' HUP INT TERM
frame="$run_directory/frame.bgra"
truncate -s 6082304 "$frame"
wayland_auth_prepare
target/byte-descriptor-bridge "$socket" "$frame" >"$run_directory/port" 2>"$run_directory/bridge.log" <&8 8<&- 9<&- &
bridge_pid=$!
exec 8<&-
attempt=0
while ! test -s "$run_directory/port"; do
 if ! kill -0 "$bridge_pid" 2>/dev/null; then cat "$run_directory/bridge.log" 8<&- 9<&- >&2; exit 1; fi
 attempt=$((attempt + 1))
 if test "$attempt" -ge 50; then echo "Transport bridge startup timed out" >&2; exit 1; fi
 sleep 0.1 8<&- 9<&-
done
port=$(cat "$run_directory/port" 8<&- 9<&-)
if test "$#" -eq 0; then set -- "file://$PWD/fixtures/article.html"; fi
target/lkjbrowser --wayland "$port" --frame-file "$frame" "$@" <&9 8<&- 9<&- &
browser_pid=$!
wayland_auth_close
wait "$browser_pid"
browser_pid=
