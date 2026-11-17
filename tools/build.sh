#!/bin/sh
set -eu
cd "$(dirname "$0")/.."
sh tools/fetch-toolchain.sh
mkdir -p target
exec .toolchain/lkjscript build . -o target/lkjbrowser "$@"
