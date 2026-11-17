#!/bin/sh
# Deterministic offline public known answers and RFC 8448 complete simple trace.
set -eu
cd "$(dirname "$0")/.."
.toolchain/lkjscript test src/crypto/primitive_tests.lkj --engine native --jobs 1
.toolchain/lkjscript test src/crypto/trace_tests.lkj --engine native --jobs 1
