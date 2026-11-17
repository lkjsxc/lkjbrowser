#!/bin/sh
set -eu
cd "$(dirname "$0")/.."
.toolchain/lkjscript build src/wayland_peer.lkj -o target/wayland-peer
.toolchain/lkjscript build src/wayland_input_probe.lkj -o target/wayland-input-probe
session=$(mktemp -d "$PWD/target/browser-peer.XXXXXXXX")
peer_pid=
cleanup() {
 if test -n "$peer_pid"; then kill "$peer_pid" 2>/dev/null || true; wait "$peer_pid" 2>/dev/null || true; fi
 rm -rf "$session"
}
trap cleanup EXIT HUP INT TERM
timeout 15 target/wayland-peer >"$session/peer.log" 2>"$session/peer.err" &
peer_pid=$!
attempt=0
while ! test -s "$session/peer.log"; do
 attempt=$((attempt + 1))
 if test "$attempt" -ge 50; then cat "$session/peer.err" >&2; exit 1; fi
 sleep 0.1
done
port=$(sed -n '1p' "$session/peer.log")
timeout 10 target/wayland-input-probe "$port" >"$session/probe.log"
wait "$peer_pid"
cat "$session/probe.log"
sed -n '2p' "$session/peer.log"
cat "$session/probe.log" >docs/wayland-input-proof.log
sed -n '2p' "$session/peer.log" >>docs/wayland-input-proof.log
