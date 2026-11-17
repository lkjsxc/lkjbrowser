# Source cryptographic primitives and recorded TLS trace

These modules are ordinary lkjscript source with no browser, transport, OS, or
foreign-library dependency:

- src/crypto/hkdf.lkj: SHA-256 HKDF Extract/Expand and TLS 1.3 labels.
- src/crypto/x25519.lkj: RFC 7748 X25519, including scalar clamping, decoding
  noncanonical public inputs, canonical output, and refusal of all-zero results.
- src/crypto/aesgcm.lkj: AES-128, 96-bit nonce GCM, full 128-bit tags. seal
  returns ciphertext followed by the tag; open checks the tag before running
  CTR decryption. It never returns tentative plaintext.

## Reproduce

Run from the repository root:

~~~sh
sh tools/crypto-primitives-test.sh
~~~

The command is offline and uses the pinned native compiler, one test job. It runs
18 primitive tests and 11 RFC 8448 trace tests. The first group includes the 14
unchanged public-vector cases in review/tls/vectors/public_known_answers.json,
SHA-256/HMAC witnesses, the RFC 7748 one- and 1,000-iteration checkpoints, and
refusals for changed ciphertext/tag/AAD/nonce, truncated tag, wrong key length,
low-order X25519 input and invalid HKDF lengths.

The 14 original cases are three RFC 5869 SHA-256 cases, six RFC 7748
scalar/public/shared-secret cases, FIPS 197 appendix B, and four NIST AES-GCM
examples. Original JSON SHA-256:

0904e65c17fce6a5b94c97e98cb370297c593398322779b5eb08fd76ba59afaa

That source JSON's original “transcription only” metadata is preserved; the native
execution evidence belongs to the new tests, not to the earlier review.

## Recorded handshake

tests/tls/rfc8448-simple.json records all 38 operations with byte-bearing fields
from RFC 8448 section 3. Every field was extracted with the RFC's declared byte
length enforced. Each operation has peer, operation and fields, where field
values are lowercase hex. The source RFC file SHA-256 is recorded in the JSON.

Convenience hex files hold ClientHello, ServerHello, the 657-byte server handshake
flight, and its complete 679-byte encrypted TLS record. The flight contains
EncryptedExtensions, Certificate, CertificateVerify and Finished. The JSON also
contains client Finished, NewSessionTicket, both application records and both
close-notify records.

The 11 native trace tests establish:

- X25519 ephemeral public keys and shared secret;
- early, handshake and master extracts, plus every published expansion and TLS
  label in this simple trace, including exporter/resumption label calculations;
- transcript hashes through ServerHello, server Finished and client Finished;
- both Finished verify-data values;
- exact encryption and authenticated decryption of seven TLS records, with
  handshake/application key epochs and the published sequence-number nonces.

The trace is public test material. Its fixed keys must never be used on live
connections. Its RSA certificate is a 1024-bit historical fixture; these primitive
tests do not establish a trusted certificate path or permission to weaken the
production certificate policy. Testing exporter/resumption derivations does not
mean the browser offers those protocol features.

## Arithmetic and timing boundaries

The field representation has sixteen radix-2^16 limbs, with a 15-bit top limb.
Inputs to multiplication are normalized. Each convolution cell is below
16*(65535^2); folding high cells using 2^256 = 38 mod (2^255-19) stays below
2^42. Carry normalization uses four fixed passes. No u128, host big integer or
foreign curve implementation is used.

AES-GCM accepts only 16-byte keys and 12-byte nonces and enforces GCM's
2^36-32-byte per-message plaintext bound, plus the 64-bit AAD bit-length bound.
The TLS layer must independently enforce its much smaller record/key-usage
limits and unique nonces. This module cannot enforce uniqueness across callers.

Timing and reliable secret erasure have **not** been established from emitted
code. AES intentionally uses a secret-indexed S-box, so this implementation must
not be described as constant-time. Full-byte tag comparison in the source is
also not an emitted-code timing guarantee.

## Measured source performance

src/crypto/primitive_bench.lkj uses only explicitly public fixed test data:

~~~sh
.toolchain/lkjscript build src/crypto/primitive_bench.lkj -o target/crypto-primitive-bench
target/crypto-primitive-bench
~~~

On the shared native host on 2026-11-17 UTC:

| Operation | Measurement |
| --- | ---: |
| X25519, 100 operations | 699,439 microseconds total; 6,994 microseconds per operation |
| AES-128-GCM seal and open, 1 MiB each | 597,232 microseconds combined |

These are observations on a shared host, not performance promises or first-paint
times. Before the S-box source change, the same GCM workload took 3,024,108
microseconds. A sampled build attributed 78.4% self time to the AES block
function; immediate constants/address formation dominated emitted instructions.
Binding let sbox=SBOX once per block/schedule, instead of using SBOX[index]
inside the byte loop, removed repeated table construction and reduced this
workload by approximately five times. The complete RFC trace still passed after
that change. The repeated-constant-table behavior is a compiler performance
opportunity with a simple source workaround, not missing crypto authority.

## Primary specifications

- https://www.rfc-editor.org/rfc/rfc5869
- https://www.rfc-editor.org/rfc/rfc7748
- https://www.rfc-editor.org/rfc/rfc4231
- https://www.rfc-editor.org/rfc/rfc8448
- https://nvlpubs.nist.gov/nistpubs/FIPS/NIST.FIPS.197-upd1.pdf
- https://csrc.nist.gov/CSRC/media/Projects/Cryptographic-Standards-and-Guidelines/documents/examples/AES_GCM.pdf
- https://nvlpubs.nist.gov/nistpubs/Legacy/SP/nistspecialpublication800-38d.pdf
