#!/bin/sh
set -eu
cd "$(dirname "$0")/.."
mkdir -p target
# Concurrent launchers keep using a complete old image until this one is validated.
bridge_build=$(mktemp "$PWD/target/byte-descriptor-bridge.XXXXXXXX")
trap 'rm -f "$bridge_build"' EXIT
trap 'exit 130' HUP INT TERM
gcc -O2 -std=c11 -nostdlib -static -fno-builtin -ffreestanding -fno-stack-protector -fno-pie -no-pie -Wl,--build-id=none -Wall -Wextra bridge/byte_descriptor_bridge.c -o "$bridge_build"
readelf -h "$bridge_build" >/dev/null
if readelf -l "$bridge_build" | rg -q 'INTERP'; then
  echo 'bridge unexpectedly needs a dynamic loader' >&2
  exit 1
fi
chmod 755 "$bridge_build"
mv -f "$bridge_build" target/byte-descriptor-bridge
