#!/usr/bin/env bash
set -euo pipefail
parser_review_dir="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
parser_root="$(cd -- "$parser_review_dir/../.." && pwd)"
parser_source_dir="${1:-$parser_root/src}"
parser_source_dir="$(cd -- "$parser_source_dir" && pwd)"
parser_run_dir="$(mktemp -d "$parser_root/target/independent-review-parsers-run-XXXXXXXX")"
parser_compiler="$parser_root/.toolchain/lkjscript"
cp -- "$parser_source_dir/html.lkj" "$parser_run_dir/html.lkj"
cp -- "$parser_source_dir/css.lkj" "$parser_run_dir/css.lkj"
cp -- "$parser_review_dir/parser_probe.lkj" "$parser_run_dir/parser_probe.lkj"
cd -- "$parser_run_dir"
sha256sum html.lkj css.lkj parser_probe.lkj "$parser_compiler" > source.sha256
printf 'Parser review artifacts: %s\n' "$parser_run_dir"
parser_failed=0
parser_test_status=0
timeout --signal=TERM --kill-after=2s 30s "$parser_compiler" test parser_probe.lkj --engine native --jobs 1 > unit-tests.log 2>&1 || parser_test_status=$?
cat unit-tests.log
if test "$parser_test_status" -ne 0; then parser_failed=1; fi
parser_build_status=0
timeout --signal=TERM --kill-after=2s 30s "$parser_compiler" build parser_probe.lkj -o parser-probe.elf > build.log 2>&1 || parser_build_status=$?
if test "$parser_build_status" -ne 0; then cat build.log; exit "$parser_build_status"; fi
printf 'case\texit\n' > results.tsv
for parser_case in unicode numeric depth font-boundary font-overflow font-em-overflow font-small-policy specificity-boundary specificity-overflow specificity-order; do
    parser_status=0
    timeout --signal=TERM --kill-after=2s 10s ./parser-probe.elf "$parser_case" > "$parser_case.log" 2>&1 || parser_status=$?
    printf '%s\t%s\n' "$parser_case" "$parser_status" >> results.tsv
    cat "$parser_case.log"
    if test "$parser_status" -ne 0; then parser_failed=1; fi
done
cat results.tsv
printf 'Unit test exit: %s\n' "$parser_test_status"
sha256sum parser-probe.elf results.tsv > result.sha256
exit "$parser_failed"
