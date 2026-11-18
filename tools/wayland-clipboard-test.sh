#!/bin/sh
# Authenticated native client lifecycle regression. All text and descriptors are synthetic.
set -eu
cd "$(dirname "$0")/.."
mkdir -p target
if test "${1:-}" != --no-build; then
 .toolchain/lkjscript build src/wayland_clipboard_peer.lkj -o target/wayland-clipboard-peer
 .toolchain/lkjscript build src/wayland_clipboard_probe.lkj -o target/wayland-clipboard-probe
fi
session=$(mktemp -d "$PWD/target/clipboard-peer.XXXXXXXX")
peer_pid=
cleanup() {
 if test -n "$peer_pid"; then kill "$peer_pid" 2>/dev/null || true; wait "$peer_pid" 2>/dev/null || true; fi
}
trap cleanup EXIT
trap 'exit 130' HUP INT TERM
timeout 20 target/wayland-clipboard-peer >"$session/peer.log" 2>"$session/peer.err" &
peer_pid=$!
attempt=0
while ! test -s "$session/peer.log"; do
 if ! kill -0 "$peer_pid" 2>/dev/null; then cat "$session/peer.err" >&2; exit 1; fi
 attempt=$((attempt+1))
 if test "$attempt" -ge 50; then cat "$session/peer.err" >&2; exit 1; fi
 sleep 0.03
done
port=$(sed -n '1p' "$session/peer.log")
# The peer checks this exact fixture preamble before offering any framed capability.
printf '%s' '0123456789abcdef0123456789abcdef' |
 timeout 15 target/wayland-clipboard-probe "$port" >"$session/probe.log" 2>"$session/probe.err" || {
  cat "$session/probe.log" "$session/probe.err" "$session/peer.err" >&2; exit 1;
 }
wait "$peer_pid"
peer_pid=
cat "$session/probe.log"
sed -n '2p' "$session/peer.log"
printf '%s\n' "$session" >target/latest-clipboard-peer
