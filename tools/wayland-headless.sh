#!/bin/sh
set -eu
cd "$(dirname "$0")/.."
if ! test -x .deps/root/usr/bin/weston; then sh tools/wayland-deps.sh; fi
mkdir -p .deps/runtime target
chmod 700 .deps/runtime
export XDG_RUNTIME_DIR="$PWD/.deps/runtime"
export LD_LIBRARY_PATH="$PWD/.deps/root/usr/lib/x86_64-linux-gnu:$PWD/.deps/root/usr/lib/x86_64-linux-gnu/weston"
export WESTON_MODULE_MAP="headless-backend.so=$PWD/.deps/root/usr/lib/x86_64-linux-gnu/libweston-13/headless-backend.so;kiosk-shell.so=$PWD/.deps/root/usr/lib/x86_64-linux-gnu/weston/kiosk-shell.so"
# Debug is confined to the mode-0700 runtime directory and permits test capture.
exec .deps/root/usr/bin/weston --backend=headless --renderer=pixman --width=1000 --height=760 --shell="$PWD/.deps/root/usr/lib/x86_64-linux-gnu/weston/kiosk-shell.so" --socket="${1:-browser-test}" --idle-time=0 --no-config --debug --log="$PWD/target/weston.log"
