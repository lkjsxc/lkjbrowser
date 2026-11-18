#!/bin/sh
set -eu
cd "$(dirname "$0")/.."
sh tools/wayland-build-bridge.sh
gcc -O2 -std=c11 -Wall -Wextra -Werror tools/descriptor-bridge-test.c -o target/descriptor-bridge-test
timeout 25 target/descriptor-bridge-test "$PWD/target/byte-descriptor-bridge"
