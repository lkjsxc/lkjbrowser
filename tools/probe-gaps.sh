#!/bin/sh
set -eu
cd "$(dirname "$0")/.."
mkdir -p target/probes
for name in unix-socket send-descriptor writable-mapping destination-authority connect-deadline array-to-vec empty-slice string-strip-prefix tls-library html-loop-view owner-replacement; do
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
printf 'Accepted the two documented loop-view rewrites.\n'
