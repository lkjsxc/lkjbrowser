#!/bin/sh
# Offline JPEG/GIF references and bounded malformed inputs; no external image codec.
set -eu
cd "$(dirname "$0")/.."
sha256sum -c tests/images/SHA256SUMS > /dev/null
mkdir -p target/browser-pages-images
.toolchain/lkjscript build src/image_test.lkj -o target/browser-pages-images/image-test
exec target/browser-pages-images/image-test "$PWD"
