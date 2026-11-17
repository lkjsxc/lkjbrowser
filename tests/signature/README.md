# Public signature verification evidence

Run `sh tools/signature-test.sh` offline with the pinned compiler. The gate has 75
native tests. The implementation is in `src/crypto/bigint.lkj`,
`sha512.lkj` and `signature.lkj`; no foreign crypto is called at runtime.

## Supported primitive profile

- RSA PKCS#1 v1.5 with exact DER DigestInfo for SHA-256/384/512.
- RSA-PSS with SHA-256/384/512, the same hash for MGF1, hash-sized salt,
  and trailer field 0xbc. Certificate parameter validation is the X.509 caller's job.
- RSA unsigned canonical modulus of 1024–4096 bits and odd exponent 3 through
  2^32-1. The 1024-bit floor allows RFC 8448's public recorded trace; the
  X.509 layer requires at least 2048 bits for actual authentication.
- ECDSA P-256/P-384 with SHA-256/384/512, correct digest truncation, exact
  uncompressed points, on-curve/range validation and minimal DER signatures.
- General 32-bit-limb Montgomery multiplication and exponentiation in u64;
  SHA-384 and SHA-512 one-shot hashing. Curve field and scalar modulus are distinct.

These are public verification operations. Emitted-code timing and memory erasure
were not examined. This module does not implement signing or secret scalar multiplication.

## Independent known answers

`vectors.json` records public inputs and expected results only.

1. All twelve P-256/P-384 × SHA-256/384/512 × sample/test cases from
   [RFC 6979 A.2.5–A.2.6](https://www.rfc-editor.org/rfc/rfc6979.html).
2. RSA-PSS SHA-384 signature from
   [RFC 9474 A.1](https://www.rfc-editor.org/rfc/rfc9474.html#appendix-A.1),
   independently accepted by OpenSSL before the lkjscript test.
3. Eighteen independent Node/OpenSSL-generated public RSA vectors:
   2048/3072/4096 × SHA-256/384/512 × v1.5/PSS. Temporary private keys existed
   only in the one fixture-generation process; none were saved. The gate reads
   only the static public vectors and runs no Node or OpenSSL.
4. FIPS/RFC SHA-384/512 empty, abc and multi-block known answers; eighteen
   independent OpenSSL digest cases at 111, 112, 127, 128, 129 and 1024 bytes.
5. Twenty-one deterministic JavaScript BigInt multiplication/exponentiation
   references across 1–512-byte odd moduli, including partial high words;
   native one- and two-limb carry/reduction boundary cases.
6. Negative modified-message, modified-signature, signature-at-modulus and
   off-curve-point cases accompany the accepted vectors.

Algorithm references: [RFC 8017](https://www.rfc-editor.org/rfc/rfc8017.html),
[RFC 6234](https://www.rfc-editor.org/rfc/rfc6234.html),
[FIPS 186-5](https://csrc.nist.gov/pubs/fips/186-5/final).
This is finite implementation evidence, not CAVP certification or an exhaustive audit.

## Native timings

`src/crypto/signature_bench.lkj` repeats each public verification ten times using
the native monotonic clock. On this shared host on 2026-11-17 UTC:

| Operation | Mean |
| --- | ---: |
| RSA 2048 PSS SHA-256 | 4.13 ms |
| RSA 3072 PSS SHA-256 | 8.38 ms |
| RSA 4096 PSS SHA-256 | 10.49 ms |
| ECDSA P-256 SHA-256 | 8.22 ms |
| ECDSA P-384 SHA-384 | 21.40 ms |

These include per-call modulus setup and are observations, not latency guarantees.
The recorded primitive timings are small enough that a multi-second TLS handshake
must be investigated in the complete protocol/network/browser path.
