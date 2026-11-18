#!/bin/sh
# Native same-executable stylesheet workers against independent local peers.
set -eu
cd "$(dirname "$0")/.."
mkdir -p target/browser-pages-network
.toolchain/lkjscript build src/styles_probe.lkj -o target/browser-pages-network/styles-probe
.toolchain/lkjscript test src/styles_probe.lkj --engine native --jobs 1
UV_THREADPOOL_SIZE=1 node --single-threaded --v8-pool-size=1 tools/styles-test.cjs \
  target/browser-pages-network/styles-probe target/browser-pages-network/styles-run
