#!/usr/bin/env bash
set -euo pipefail
underline_review_dir="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
underline_root="$(cd -- "$underline_review_dir/../.." && pwd)"
cd -- "$underline_root"
printf '%s  %s\n' '5c68d356596bff6c8198690a49916cedbe726b5d20f00942b174ee4118470692' 'src/layout.lkj' | sha256sum --check
printf '%s  %s\n' '5d188a39554a2816309b8d99c8cd611602e74b5d6b847d095efad8d9cfdd2d6d' 'review/underline/link-underline.patch' | sha256sum --check
git apply --check review/underline/link-underline.patch
