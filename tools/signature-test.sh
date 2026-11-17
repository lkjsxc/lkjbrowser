#!/bin/sh
# Deterministic offline public signature/math/hash known answers.
set -eu
cd "$(dirname "$0")/.."
exec .toolchain/lkjscript test src/crypto/signature_test.lkj --engine native --jobs 1
