#!/bin/sh
# One deterministic offline gate. Public-site tests and captures are separate.
set -eu
cd "$(dirname "$0")/.."
sh tools/test.sh
sh tools/crypto-primitives-test.sh
sh tools/signature-test.sh
sh tools/test-x509.sh
.toolchain/lkjscript test src/crypto/protocol_tests.lkj --engine native --jobs 1
.toolchain/lkjscript test src/crypto/protocol_trace_tests.lkj --engine native --jobs 1
.toolchain/lkjscript build probes/owned-resource-child.lkj -o target/browser-owned-resource-child
target/browser-owned-resource-child
sh tools/tls-local-test.sh --no-build
printf 'PASS all offline browser and authenticated HTTPS gates\n'
