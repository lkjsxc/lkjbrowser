#!/bin/sh
# Independent Node/zlib HTTP peer; native decoding and fetch code under test.
set -eu
cd "$(dirname "$0")/.."
mkdir -p target/browser-pages-network
.toolchain/lkjscript build src/content_probe.lkj -o target/browser-pages-network/content-probe
.toolchain/lkjscript test src/content_probe.lkj --engine native --jobs 1
UV_THREADPOOL_SIZE=1 node --single-threaded --v8-pool-size=1 tools/content-test.cjs \
  target/browser-pages-network/content-probe target/browser-pages-network/content-run
