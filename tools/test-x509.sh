#!/bin/sh
# Deterministic, offline certificate decisions. Fixtures are public synthetic data.
set -eu
cd "$(dirname "$0")/.."
mkdir -p target/x509-results
.toolchain/lkjscript test src/crypto/x509_test.lkj --engine native --jobs 1
.toolchain/lkjscript build src/crypto/x509_test.lkj -o target/x509-test
accept() {
 name=$1; chain=$2; host=$3
 target/x509-test tests/x509/root.pem "tests/x509/$chain.pem" "$host" > "target/x509-results/$name.log"
 grep -F 'ACCEPT ' "target/x509-results/$name.log" >/dev/null
 printf 'PASS %s\n' "$name"
}
refuse() {
 name=$1; root=$2; chain=$3; host=$4; reason=$5; shift 5
 if target/x509-test "tests/x509/$root.pem" "tests/x509/$chain.pem" "$host" "$@" > "target/x509-results/$name.log"; then
  cat "target/x509-results/$name.log"; printf 'Expected refusal: %s\n' "$name" >&2; exit 1
 fi
 grep -F "$reason" "target/x509-results/$name.log" >/dev/null
 printf 'PASS %s\n' "$name"
}
accept trusted-p256 localhost localhost
accept certificate-rsa-pss pss localhost
accept trusted-rsa rsa localhost
accept trusted-p384 p384 localhost
accept intermediate-p384 chain localhost
accept numeric-ip localhost 127.0.0.1
accept wildcard localhost www.example.test
accept case-fold localhost LOCALHOST
accept trailing-dot localhost localhost.
refuse expired root expired localhost 'has expired'
refuse not-yet-valid root future localhost 'not valid yet'
refuse wrong-host root wronghost localhost 'different host name'
refuse self-signed root selfsigned localhost 'self-signed certificate'
refuse unknown-root unrelated-root localhost localhost 'trusted root'
refuse tampered-certificate root localhost localhost 'invalid signature' tamper
refuse wildcard-depth root localhost a.b.example.test 'different host name'
refuse wildcard-bare root localhost example.test 'different host name'
refuse incorrect-ip root localhost 127.0.0.2 'different host name'
refuse server-eku root clientonly localhost 'not allowed to authenticate'
refuse leaf-key-usage root badusage localhost 'not allowed to sign'
refuse leaf-ca root ca-leaf localhost 'CA certificate as its server certificate'
refuse issuer-not-ca root not-ca-chain localhost 'not authorized as a certificate authority'
refuse no-common-name-fallback root no-san localhost 'different host name'
refuse path-length root path-length localhost 'permitted path length'
refuse unknown-critical root unknown-critical localhost 'critical extension'
refuse name-constraint root name-constraints-chain localhost 'name or policy constraint'
refuse policy-constraint root policy-constraints-chain localhost 'name or policy constraint'
target/x509-test tests/x509/root.pem tests/x509/localhost.pem localhost parser
target/x509-test tests/x509/root.pem tests/x509/future.pem localhost 2051222400
refuse before-validity root future localhost 'not valid yet' 2051222399
target/x509-test tests/x509/root.pem tests/x509/localhost.pem localhost 2240611199
refuse after-validity root localhost localhost 'has expired' 2240611200
printf 'PASS 31 certificate decisions plus every truncated leaf prefix\n'
