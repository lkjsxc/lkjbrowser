#!/bin/sh
set -eu
cd "$(dirname "$0")/.."
mkdir -p target/probes
for name in unix-socket send-descriptor writable-mapping destination-authority connect-deadline array-to-vec empty-slice string-strip-prefix tls-library tls-split-ascii-whitespace function-item-map-err html-loop-view owner-replacement image-view-array image-owned-array-iteration string-match-loop-compare pages-net-late-type pages-net-collection-type pages-net-string-parse; do
  source="probes/$name.lkj"
  if .toolchain/lkjscript check "$source" >"target/probes/$name.log" 2>&1; then
    printf 'Unexpectedly accepted: %s\n' "$source"
    exit 1
  fi
  printf '%s: ' "$name"
  head -1 "target/probes/$name.log"
done
if .toolchain/lkjscript test probes/html-cfg-test.lkj --engine native --jobs 1 >target/probes/html-cfg-test.log 2>&1; then
  echo "Unexpectedly accepted cfg(test) helper"
  exit 1
fi
printf 'html-cfg-test: '
head -1 target/probes/html-cfg-test.log
.toolchain/lkjscript check probes/html-loop-view-workaround.lkj
.toolchain/lkjscript check probes/loop-view.lkj
.toolchain/lkjscript check probes/function-item-map-err-workaround.lkj
printf 'Accepted the loop-view rewrites and function-item callback workaround.\n'

.toolchain/lkjscript check probes/image-owned-vec-workaround.lkj
.toolchain/lkjscript check probes/string-match-loop-compare-workaround.lkj
.toolchain/lkjscript check probes/pages-net-accepted.lkj
printf 'Accepted the image, CSS comparison and stylesheet inference rewrites.\n'
