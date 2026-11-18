#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")/../.."
root=$PWD
deps=/home/coder/workspace/lkjbrowser/.deps/root
if test "$#" -gt 0; then deps=$1; fi
run=$(mktemp -d "$root/target/ap-self.XXXXXX")
printf '%s\n' "$run" >"$root/target/address-proof-selftest-last"
mkdir -m 700 "$run/r"
: >"$run/r/address-proof-owned"
export XDG_RUNTIME_DIR="$run/r" WAYLAND_DISPLAY=wl
export LD_LIBRARY_PATH="$deps/usr/lib/x86_64-linux-gnu:$deps/usr/lib/x86_64-linux-gnu/weston"
export WESTON_MODULE_MAP="x11-backend.so=$deps/usr/lib/x86_64-linux-gnu/libweston-13/x11-backend.so;kiosk-shell.so=$deps/usr/lib/x86_64-linux-gnu/weston/kiosk-shell.so"
xpid= wpid= spid= qpid=
cleanup(){ set +e; for pid in "$qpid" "$spid" "$wpid" "$xpid"; do if test -n "$pid"; then kill "$pid" 2>/dev/null; wait "$pid" 2>/dev/null; fi; done; }
trap cleanup EXIT
Xvfb -displayfd 3 -screen 0 1440x760x24 -nolisten tcp -ac 3>"$run/display" >"$run/xvfb.log" 2>&1 &
xpid=$!
for ((i=0;i<100;i++));do test -s "$run/display" && break;kill -0 "$xpid";sleep 0.05;done
export DISPLAY=:$(cat "$run/display")
"$deps/usr/bin/weston" --backend=x11 --renderer=pixman --width=1440 --height=760 --shell="$deps/usr/lib/x86_64-linux-gnu/weston/kiosk-shell.so" --socket=wl --idle-time=0 --no-config --debug --log="$run/weston.log" >"$run/weston-stdio.log" 2>&1 &
wpid=$!
for ((i=0;i<100;i++));do test -S "$run/r/wl" && break;kill -0 "$wpid";sleep 0.05;done
printf '  https://example.test/\r\nalpha\tbeta \n ' >"$run/synthetic.txt"
target/address-clipboard-peer "$run/r/wl" source "$run/synthetic.txt" >"$run/source.log" 2>&1 &
spid=$!
for ((i=0;i<100;i++));do grep -q MAPPED "$run/source.log" && break;kill -0 "$spid";sleep 0.05;done
printf 'focus\nmove 700 380\ntap 57\nwait 200\n' | target/address-xinput >"$run/input.log"
grep -q SELECTION_SET "$run/source.log"
target/address-clipboard-peer "$run/r/wl" sink "$run/received.txt" >"$run/sink.log" 2>&1 &
qpid=$!
wait "$qpid";qpid=
cmp "$run/synthetic.txt" "$run/received.txt"
printf 'PASS independent XTest -> Weston keyboard serial -> data-device source -> pipe transfer -> independent sink\nEvidence: %s\n' "$run"
cat "$run/source.log" "$run/sink.log"
