#!/usr/bin/env bash
set -euo pipefail
underline_review_dir="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
underline_root="$(cd -- "$underline_review_dir/../.." && pwd)"
underline_source_dir="${1:-$underline_root/src}"
underline_source_dir="$(cd -- "$underline_source_dir" && pwd)"
underline_run_dir="$(mktemp -d "$underline_root/target/independent-review-underline-run-XXXXXXXX")"
for underline_module in html css font paint layout; do
    cp -- "$underline_source_dir/$underline_module.lkj" "$underline_run_dir/$underline_module.lkj"
done
cp -- "$underline_review_dir/underline_probe.lkj" "$underline_run_dir/underline_probe.lkj"
cd -- "$underline_run_dir"
sha256sum html.lkj css.lkj font.lkj paint.lkj layout.lkj underline_probe.lkj > source.sha256
printf 'Underline review artifacts: %s\n' "$underline_run_dir"
underline_status=0
timeout --signal=TERM --kill-after=2s 40s "$underline_root/.toolchain/lkjscript" test underline_probe.lkj --engine native --jobs 1 > results.log 2>&1 || underline_status=$?
cat results.log
exit "$underline_status"
