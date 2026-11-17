# Certificate authentication profile

The reusable implementation is `src/crypto/der.lkj` and `src/crypto/x509.lkj`.
It depends only on sibling signature arithmetic and the source language library;
there is no browser, socket, file, clock or foreign-runtime dependency. The caller
supplies the peer's DER chain, an explicit PEM root bundle, the original URL host,
and wall-clock Unix seconds. Successful validation returns the parsed leaf key.
`verify_handshake` separately verifies TLS CertificateVerify with that leaf key.
Neither an issuer name nor successful key agreement establishes trust.

## Implemented policy

- Trust originates exclusively in the caller-supplied root bundle. Root subjects
  are compared with issuer names as a candidate-selection step; each path edge
  then requires a valid cryptographic signature. A self-signed certificate sent
  by the peer is not automatically trusted. A root's self-signature is not a path
  edge and need not use a currently accepted signature algorithm.
- RSA encryption SPKI keys are 2048–4096 bits with odd exponents of at most
  32 bits. Named P-256/P-384 EC keys use uncompressed points; the signature
  verifier checks that the point is on the selected curve. RSA-PSS SPKI keys,
  explicit EC parameters, DSA, EdDSA and other curves are not supported.
- Certificate signatures include RSA PKCS#1 v1.5 or RSA-PSS with SHA-256,
  SHA-384 or SHA-512, and ECDSA with those hashes. PSS requires MGF1 with the
  same digest, salt length equal to the digest length, and the standard trailer.
  Both certificate AlgorithmIdentifiers must have exactly matching DER.
- TLS CertificateVerify accepts ECDSA P-256/SHA-256, ECDSA P-384/SHA-384 and
  RSA-PSS-rsae with SHA-256/384/512. The TLS caller must advertise only the
  schemes that its state machine accepts. PKCS#1 v1.5 is certificate-signature
  support; it is not accepted for TLS 1.3 CertificateVerify.
- Every certificate on the selected path, including the explicitly configured
  anchor, is checked against the supplied wall clock. UTCTime and
  GeneralizedTime accept second precision and `Z`, validate calendar fields,
  and use inclusive validity endpoints. There is no build-date fallback.
- DNS identity uses only subjectAltName. Comparison is ASCII case-insensitive.
  A wildcard must occupy the whole first label, match exactly one label, and
  have at least two literal suffix labels. Numeric IPv4 identities require
  an iPAddress SAN; Common Name is never a fallback. The caller's original host
  is used, not the numeric DNS answer. A final dot in the reference DNS name is
  removed before comparison. Unicode hostnames need explicit A-label input.
- The leaf must not be a CA. When present, leaf KeyUsage must allow
  digitalSignature and ExtendedKeyUsage must allow serverAuth or anyEKU.
  Intermediates must be CAs with critical BasicConstraints, obey pathLen, and
  allow keyCertSign/serverAuth when the corresponding restrictions are present.
  Self-issued intermediate certificates do not consume a pathLen position.
- Duplicate extensions, unsupported critical extensions, malformed DER lengths,
  noncanonical positive integers, inconsistent signature algorithms and trailing
  top-level DER are rejected. No unknown critical extension is silently ignored.
- NameConstraints, PolicyMappings, PolicyConstraints and InhibitAnyPolicy are
  rejected, whether critical or noncritical, because their semantics are not yet
  implemented. A critical CertificatePolicies extension is also refused. Ordinary
  noncritical policy assertions do not select a policy or add trust.

## Deliberate conservative boundaries

Issuer/subject names must match byte-for-byte DER. Full distinguished-name
normalization is not implemented, so a valid path with different equivalent
name encodings may be refused. The path builder tries alternative supplied
intermediates and matching configured roots, detects repeated intermediate
positions, and caps signature attempts at 64. It accepts no more than twelve
peer certificates, ten intermediate positions, 64 extensions per certificate,
one MiB per certificate, 1024 alternative names, or 1024 PEM roots in 16 MiB.
These are explicit source-library resource policies, not language limits.

The peer must supply the necessary intermediates. AIA fetching, revocation,
OCSP stapling policy, CRL processing, Certificate Transparency and browser-vendor
root policy are not implemented. Passing this profile establishes the implemented
chain/signature/name/time checks, not parity with a mainstream browser's trust
policy. An unsupported constraint fails closed; no bypass switch exists.

The generated code has not been reviewed for constant-time execution or secret
zeroization. Certificate/signature validation principally processes public data;
this statement does not extend a constant-time claim to other TLS primitives.

## Reproduce the evidence

```sh
sh tools/test-x509.sh
```

This deterministic offline gate builds the pinned native validator, runs eleven
module unit tests, and checks 31 decisions using committed synthetic certificates.
The cases include RSA/P-256/P-384 leaves, a P-384 intermediate, a PSS-signed
certificate, DNS/IP/wildcard identities, exact date boundaries, expired/future
certificates, wrong host, self-signed/unknown-root certificates, a tampered
signature, absent SAN with matching CN, invalid CA/KU/EKU/pathLen, unknown critical
extensions and unsupported name/policy constraints. It also rejects every one
of the 671 truncated prefixes of the fixture leaf and a trailing-DER mutation.
Expected refusals match their error category in the returned text.

OpenSSL 3.0.13 generated the fixtures and independently verified the valid chains.
It is a test oracle only; the validator and browser do not execute it. Fixture
regeneration is separate from the gate, changes keys and certificates, and is
never required for an ordinary offline test. See `tests/x509/README.md`.

## Primary specifications

- [RFC 5280, certificate profile and path validation](https://www.rfc-editor.org/rfc/rfc5280.html)
- [RFC 9525, TLS service identity](https://www.rfc-editor.org/rfc/rfc9525.html)
- [RFC 4055, RSA algorithm identifiers and PSS parameters](https://www.rfc-editor.org/rfc/rfc4055.html)
- [RFC 7468, PEM textual encodings](https://www.rfc-editor.org/rfc/rfc7468.html)

These references describe the standards. The finite implemented subset and the
explicit refusal policy above describe what this source has established.
