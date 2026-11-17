#!/bin/sh
# Regeneration only. Synthetic private keys below are public test fixtures, never identities.
set -eu
cd "$(dirname "$0")/.."
work=$(mktemp -d "$PWD/target/x509-fixtures.XXXXXXXX")
trap 'rm -rf "$work"' EXIT
mkdir -p tests/x509 "$work/newcerts"
: > "$work/index"
printf '0100\n' > "$work/serial"
openssl genpkey -algorithm RSA -pkeyopt rsa_keygen_bits:2048 -out tests/x509/root.key 2>"$work/key.log"
openssl req -x509 -new -sha256 -key tests/x509/root.key -days 7300 -subj '/CN=lkjbrowser untrusted test root' -out tests/x509/root.pem -addext 'basicConstraints=critical,CA:true,pathlen:3' -addext 'keyUsage=critical,keyCertSign,cRLSign'
cat > "$work/ca.cnf" <<CONFIG
[ca]
default_ca=CA
[CA]
database=$work/index
new_certs_dir=$work/newcerts
certificate=$PWD/tests/x509/root.pem
private_key=$PWD/tests/x509/root.key
serial=$work/serial
default_md=sha256
default_days=3650
policy=policy
unique_subject=no
[policy]
commonName=supplied
[server]
basicConstraints=critical,CA:false
keyUsage=critical,digitalSignature
extendedKeyUsage=serverAuth
subjectAltName=DNS:localhost,IP:127.0.0.1,DNS:*.example.test
[wronghost]
basicConstraints=critical,CA:false
keyUsage=critical,digitalSignature
extendedKeyUsage=serverAuth
subjectAltName=DNS:elsewhere.test
[clientonly]
basicConstraints=critical,CA:false
keyUsage=critical,digitalSignature
extendedKeyUsage=clientAuth
subjectAltName=DNS:localhost
[badusage]
basicConstraints=critical,CA:false
keyUsage=critical,keyEncipherment
extendedKeyUsage=serverAuth
subjectAltName=DNS:localhost
[ca_server]
basicConstraints=critical,CA:true,pathlen:0
keyUsage=critical,keyCertSign,cRLSign,digitalSignature
subjectAltName=DNS:localhost
[intermediate]
basicConstraints=critical,CA:true,pathlen:0
keyUsage=critical,keyCertSign,cRLSign
[not_ca]
basicConstraints=critical,CA:false
keyUsage=critical,digitalSignature
[unknown_critical]
basicConstraints=critical,CA:false
keyUsage=critical,digitalSignature
extendedKeyUsage=serverAuth
subjectAltName=DNS:localhost
1.2.3.4=critical,DER:05:00
[name_constraints]
basicConstraints=critical,CA:true,pathlen:0
keyUsage=critical,keyCertSign,cRLSign
nameConstraints=critical,permitted;DNS:.example.test
[policy_constraints]
basicConstraints=critical,CA:true,pathlen:0
keyUsage=critical,keyCertSign,cRLSign
policyConstraints=requireExplicitPolicy:0
CONFIG
openssl genpkey -algorithm EC -pkeyopt ec_paramgen_curve:P-256 -out tests/x509/localhost.key 2>"$work/key.log"
openssl req -new -key tests/x509/localhost.key -subj '/CN=localhost test leaf' -out "$work/leaf.csr"
for item in localhost:server wronghost:wronghost expired:server future:server clientonly:clientonly badusage:badusage ca-leaf:ca_server unknown-critical:unknown_critical; do
 name=${item%:*}; ext=${item#*:}; from=20200101000000Z; until=20401231235959Z
 if [ "$name" = expired ]; then until=20240101000000Z; fi
 if [ "$name" = future ]; then from=20350101000000Z; fi
 openssl ca -batch -notext -config "$work/ca.cnf" -extensions "$ext" -in "$work/leaf.csr" -out "tests/x509/$name.pem" -startdate "$from" -enddate "$until" >"$work/ca.log" 2>&1
 done
openssl req -x509 -new -sha256 -key tests/x509/localhost.key -days 7300 -subj '/CN=localhost selfsigned test leaf' -out tests/x509/selfsigned.pem -addext 'basicConstraints=critical,CA:false' -addext 'keyUsage=critical,digitalSignature' -addext 'subjectAltName=DNS:localhost,IP:127.0.0.1'
openssl genpkey -algorithm RSA -pkeyopt rsa_keygen_bits:2048 -out tests/x509/rsa.key 2>"$work/key.log"
openssl req -new -key tests/x509/rsa.key -subj '/CN=localhost RSA test leaf' -out "$work/rsa.csr"
openssl ca -batch -notext -config "$work/ca.cnf" -extensions server -in "$work/rsa.csr" -out tests/x509/rsa.pem -startdate 20200101000000Z -enddate 20401231235959Z >"$work/ca.log" 2>&1
openssl genpkey -algorithm EC -pkeyopt ec_paramgen_curve:P-384 -out tests/x509/p384.key 2>"$work/key.log"
openssl req -new -key tests/x509/p384.key -subj '/CN=lkjbrowser test intermediate' -out "$work/intermediate.csr"
for item in intermediate:intermediate not-ca:not_ca name-constraints:name_constraints policy-constraints:policy_constraints; do
 name=${item%:*}; ext=${item#*:}
 openssl ca -batch -notext -config "$work/ca.cnf" -extensions "$ext" -in "$work/intermediate.csr" -out "tests/x509/$name.pem" -startdate 20200101000000Z -enddate 20401231235959Z >"$work/ca.log" 2>&1
 done
openssl req -new -key tests/x509/localhost.key -subj '/CN=localhost intermediate test leaf' -out "$work/inter-leaf.csr"
openssl ca -batch -notext -config "$work/ca.cnf" -cert tests/x509/intermediate.pem -keyfile tests/x509/p384.key -md sha384 -extensions server -in "$work/inter-leaf.csr" -out tests/x509/intermediate-leaf.pem -startdate 20200101000000Z -enddate 20401231235959Z >"$work/ca.log" 2>&1
openssl req -new -key tests/x509/p384.key -subj '/CN=localhost P384 test leaf' -out "$work/p384.csr"
openssl ca -batch -notext -config "$work/ca.cnf" -extensions server -in "$work/p384.csr" -out tests/x509/p384.pem -startdate 20200101000000Z -enddate 20401231235959Z >"$work/ca.log" 2>&1
openssl req -x509 -new -sha256 -key tests/x509/rsa.key -days 7300 -subj '/CN=unrelated test root' -out tests/x509/unrelated-root.pem -addext 'basicConstraints=critical,CA:true' -addext 'keyUsage=critical,keyCertSign,cRLSign'
cat tests/x509/intermediate-leaf.pem tests/x509/intermediate.pem > tests/x509/chain.pem
cat tests/x509/intermediate-leaf.pem tests/x509/not-ca.pem > tests/x509/not-ca-chain.pem
cat tests/x509/intermediate-leaf.pem tests/x509/name-constraints.pem > tests/x509/name-constraints-chain.pem
cat tests/x509/intermediate-leaf.pem tests/x509/policy-constraints.pem > tests/x509/policy-constraints-chain.pem
openssl verify -CAfile tests/x509/root.pem -verify_hostname localhost tests/x509/localhost.pem tests/x509/rsa.pem tests/x509/p384.pem
openssl verify -CAfile tests/x509/root.pem -untrusted tests/x509/intermediate.pem -verify_hostname localhost tests/x509/intermediate-leaf.pem
# Additional path-policy and RSA-PSS certificate-signature witnesses.
openssl req -new -key tests/x509/localhost.key -subj '/CN=localhost' -out "$work/extras-leaf.csr"
cat > "$work/extras.cnf" <<'CONFIG'
[server]
basicConstraints=critical,CA:false
keyUsage=critical,digitalSignature
extendedKeyUsage=serverAuth
subjectAltName=DNS:localhost,IP:127.0.0.1
[nosan]
basicConstraints=critical,CA:false
keyUsage=critical,digitalSignature
extendedKeyUsage=serverAuth
[intermediate]
basicConstraints=critical,CA:true,pathlen:0
keyUsage=critical,keyCertSign,cRLSign
CONFIG
openssl x509 -req -in "$work/extras-leaf.csr" -CA tests/x509/root.pem -CAkey tests/x509/root.key -set_serial 2001 -days 7300 -sha256 -sigopt rsa_padding_mode:pss -sigopt rsa_pss_saltlen:digest -extfile "$work/extras.cnf" -extensions server -out tests/x509/pss.pem 2>"$work/sign.log"
openssl x509 -req -in "$work/extras-leaf.csr" -CA tests/x509/root.pem -CAkey tests/x509/root.key -set_serial 2002 -days 7300 -sha256 -extfile "$work/extras.cnf" -extensions nosan -out tests/x509/no-san.pem 2>"$work/sign.log"
openssl req -new -key tests/x509/rsa.key -subj '/CN=lkjbrowser sub intermediate' -out "$work/subca.csr"
openssl x509 -req -in "$work/subca.csr" -CA tests/x509/intermediate.pem -CAkey tests/x509/p384.key -set_serial 2003 -days 7300 -sha384 -extfile "$work/extras.cnf" -extensions intermediate -out tests/x509/subca.pem 2>"$work/sign.log"
openssl x509 -req -in "$work/extras-leaf.csr" -CA tests/x509/subca.pem -CAkey tests/x509/rsa.key -set_serial 2004 -days 7300 -sha256 -extfile "$work/extras.cnf" -extensions server -out tests/x509/subca-leaf.pem 2>"$work/sign.log"
cat tests/x509/subca-leaf.pem tests/x509/subca.pem tests/x509/intermediate.pem > tests/x509/path-length.pem
