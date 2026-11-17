# Public, synthetic certificate fixtures

Every `.key` in this directory was generated solely for local tests. These are
public test keys, not credentials for a real person, service or public CA. They
are committed so the offline TLS peer and certificate tests can be reproduced.
Never install `root.pem` in a system/browser trust store. The browser must receive
it explicitly through its test trust-file option.

`localhost.pem` and `localhost.key` are a P-256 server identity under the RSA-2048
`root.pem`. They cover DNS `localhost`, IP `127.0.0.1` and `*.example.test`.
`rsa.pem`/`rsa.key` and `p384.pem`/`p384.key` provide alternate server key types.
`chain.pem` is a P-256 leaf under a P-384 intermediate and that RSA root.
`pss.pem` has an RSA-PSS/SHA-256 certificate signature.

The remaining certificates deliberately exercise expired/future validity,
unrelated trust, wrong names, self-signing, missing SAN, invalid usages, CA
constraints, excessive path length and unsupported critical/name/policy
constraints. They are not expected to authenticate successfully.

The native test validator uses Unix second 1800000000 for ordinary cases, plus
explicit boundary instants. Leaf validity is mostly 2020–2040; the generated root
is valid from its 2026-11-17 UTC creation through 2046. The TLS test server uses
the actual host clock, not the test validator's fixed time.

Normal reproducible gate:

```sh
sh tools/test-x509.sh
```

Deliberate regeneration, using OpenSSL only as a test fixture generator:

```sh
sh tools/x509-make-fixtures.sh
sh tools/test-x509.sh
```

Regeneration changes keys and certificate bytes. Do not run it while a local TLS
peer is using the previous fixture files. Certificates are not downloaded and no
port, background server or system installation is created by this generator.
