#!/bin/sh
set -eu
cd "$(dirname "$0")/.."
mkdir -p target
gcc -O2 -std=c11 -nostdlib -static -fno-builtin -ffreestanding -fno-stack-protector -fno-pie -no-pie -Wl,--build-id=none -Wall -Wextra bridge/byte_descriptor_bridge.c -o target/byte-descriptor-bridge
if readelf -l target/byte-descriptor-bridge | rg -q 'INTERP'; then
  echo 'bridge unexpectedly needs a dynamic loader' >&2
  exit 1
fi
