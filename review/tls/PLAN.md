# TLS 1.3 readiness and implementation scope

Static planning brief, reviewed 2026-11-18 JST. No cryptography was implemented,
no tests were run, and no service connections were made for this brief.
Only this review document is proposed for the repository.

## Outcome and baseline

The next browser milestone should be **authenticated HTTPS page loading in the
same lkjscript executable**, followed by evidence for a clearly stated
interoperability profile. An encrypted connection alone is insufficient.

The current specification is [RFC 9846](https://www.rfc-editor.org/info/rfc9846/),
published July 2026 and replacing RFC 8446. Use its current errata and section
numbering. The existing `docs/next-tls.md` already identifies that correctly.

The exact source inspected was lkjscript commit
`e6d13590b7bb2d665d668727f1a8d1ee4f76c33d`, matching the browser's
`2026.11.17-e6d13590b` pin and executable SHA-256
`60149069984ecfe491e322eba406238555c13acc90375c5468e5d5d4954a83ca`.
Inspection used read-only `git show`/tree enumeration, rather than assuming that
the moving language checkout describes the pin.

| Present at the pin | Consequence |
| --- | --- |
| `std::sha256::{Sha256,digest}` | Streaming SHA-256 exists; `finish` consumes its state. |
| `std::hmac::{sha256,constant_time_eq}` | HMAC-SHA256 and a source-level full-byte comparison exist. The comparison's own comment requires emitted-code review before a constant-time claim. |
| Byte vectors, slices, checked/wrapping integers through 64 bits | Implement fixed-limb arithmetic in source; do not assume u128 or an external big-integer library. |
| TCP File, Readiness, Entropy, Clock, regular-file reads | Transport, fresh randomness, deadlines, certificate time checks and public root data are available. |

No HKDF, X25519/P-256, AES-GCM/ChaCha20-Poly1305, RSA/ECDSA verifier,
DER/X.509 validator or TLS state machine appears in the pinned library inventory.

## Proposed first supported profile

Use TLS 1.3 and HTTP/1.1, server certificate authentication, no resumption,
0-RTT or client-certificate configuration. Reject unsupported negotiation with an
ordinary page error. Do not advertise algorithms that are only partially implemented.

The protocol's baseline includes AES-128-GCM/SHA-256, P-256 key exchange,
RSA-PSS/SHA-256 and ECDSA/P-256/SHA-256 verification, plus RSA PKCS#1/SHA-256
certificate signatures. X25519 is an additional recommended group.
[RFC 9846, section 9.1](https://www.rfc-editor.org/info/rfc9846/)

**Recommendation:** implement that baseline plus X25519. A smaller X25519-only,
ChaCha-only experiment could establish internal milestones, but should be labelled
a restricted experiment rather than a completed baseline client. Add SHA-384 and
P-384 certificate verification next to broaden accepted certificate chains;
this is separate from adding another TLS record cipher suite.

Offer only HTTP/1.1 through
[ALPN](https://www.rfc-editor.org/info/rfc7301/). Keep the original URL hostname
distinct from the resolved numeric address, and use DNS names for
[SNI](https://www.rfc-editor.org/info/rfc6066/). The first identity profile can
accept ASCII/A-label hostnames and numeric IPv4 while reporting Unicode-hostname
support as unfinished.

## Source modules and sequencing

These are browser-owned source modules initially; reusable parts can be proposed
to the language streams later. No changes to the language repository are assumed.

| Work unit | Smallest useful deliverable and review focus |
| --- | --- |
| HKDF | Extract/expand over existing HMAC, checked output lengths, and TLS label encoding. Keep generic HKDF distinct from protocol labels. [RFC 5869](https://www.rfc-editor.org/info/rfc5869/) |
| Field arithmetic and X25519 | Fixed-size limbs with documented carry bounds; correct scalar/input encoding and secret-independent operations. Fresh entropy for each connection; reject unusable shared results. [RFC 7748](https://www.rfc-editor.org/info/rfc7748/) |
| P-256 | ECDH plus ECDSA verification with public-point/range validation. Share arithmetic without conflating the curve field and scalar-order arithmetic. [SP 800-56A Rev. 3](https://csrc.nist.gov/pubs/sp/800/56/a/r3/final), [FIPS 186-5 and its errata](https://csrc.nist.gov/pubs/fips/186-5/final) |
| AEAD | AES-128 plus GCM/GHASH, with an API that returns authenticated plaintext or an error. Keep tentative plaintext private until tag verification. [FIPS 197](https://csrc.nist.gov/pubs/fips/197/final), [SP 800-38D](https://csrc.nist.gov/pubs/sp/800/38/d/final), [RFC 5116](https://www.rfc-editor.org/info/rfc5116/) |
| RSA verification | Public modular arithmetic, PSS parameter validation, and PKCS#1 certificate-signature verification; document supported key sizes. No RSA private-key operations are needed for this client profile. [RFC 8017](https://www.rfc-editor.org/info/rfc8017/) |
| Certificates and trust | PEM/Base64 input, DER parsing, certificate extraction, signature/path verification, identity and time policy. Keep parsing separate from deciding trust. [RFC 7468](https://www.rfc-editor.org/info/rfc7468/), [RFC 5280](https://www.rfc-editor.org/info/rfc5280/) |
| TLS state | Record codec, handshake progression, transcript snapshots, key epochs and authenticated connection owner. |
| Browser adapter | Feed existing HTTP framing from authenticated plaintext; preserve navigation cancellation, timeout and origin policy. |

ChaCha20-Poly1305 is a useful subsequent software cipher: it uses different
arithmetic from AES/GCM and has published component and AEAD examples.
It is additional source work, not a new OS capability.
[RFC 8439](https://www.rfc-editor.org/info/rfc8439/)

Start HKDF and arithmetic alongside certificate parsing. Complete primitive
verification before integrating records, then add the handshake and finally the
HTTP adapter. Avoid making an insecure partial handshake look like functioning HTTPS.

## Handshake, transcript and record boundaries

The ordinary full-handshake progression is ClientHello, ServerHello, encrypted
server parameters and certificate authentication, server Finished, then client
Finished and application traffic. Preserve the exact encoded handshake bytes
for transcript calculations; verify CertificateVerify against the leaf key and
the prescribed transcript context, and compare Finished before incorporating
that Finished message into later transcript snapshots.
[RFC 8448, full-handshake examples](https://www.rfc-editor.org/info/rfc8448/)

The authenticated-connection constructor should succeed only after chain,
identity, CertificateVerify and Finished checks. Before that, no response bytes
reach HTML parsing. Support HelloRetryRequest's transcript rules, record
fragmentation/coalescing, separate key epochs and sequence numbers, close_notify
and bounded KeyUpdate handling. Use fresh key shares; ignore NewSessionTicket
when resumption is disabled. Enforce record/key-usage limits.
[RFC 9846, sections 4–7](https://www.rfc-editor.org/info/rfc9846/)

Initially, an owned, bounded transcript byte buffer with digest recomputation is
simpler than inventing a clone operation for the consuming SHA-256 state.
Later optimize only with byte-identical transcript evidence.

Model connection phases explicitly so an error cannot leave a partially
authenticated connection reusable. Separate incomplete input from invalid input.
Length checks should produce ordinary errors, not language traps. Distinguish
protocol limits from configurable memory/deadline budgets.

## Certificate path, hostname, time and trusted roots

Build a candidate path from supplied intermediates to a configured local trust
anchor. Verify signatures, validity, BasicConstraints/path length, KeyUsage,
server-auth EKU, name constraints and applicable certificate-policy requirements.
Handle critical extensions deliberately. Issuer names and key identifiers guide
candidate selection; they do not establish trust. A received self-signed
certificate is not automatically trusted.
[RFC 5280, sections 4 and 6](https://www.rfc-editor.org/info/rfc5280/)

Record a certificate-validation profile against the updates linked from RFC
5280's official page, including the revised policy-processing work in
[RFC 9618](https://www.rfc-editor.org/info/rfc9618/).
If a constraint cannot yet be processed correctly, report the chain as
unsupported rather than ignoring it. Configure bounded path search and detect
repeated certificates. Missing intermediates can fail clearly in this first
milestone; automatic issuer retrieval need not be added.

Match DNS names through subjectAltName, with case-insensitive A-label comparison
and constrained single-label wildcards. Match a numeric IP against the
iPAddress alternative name. Do not fall back to Common Name or replace the
reference identity with the DNS answer. Re-evaluate identity after a redirect
to another origin.
[RFC 9525](https://www.rfc-editor.org/info/rfc9525/)

Use `Clock.unix_seconds()` for certificate time checks and the monotonic clock
for deadlines. If wall-clock acquisition fails, verification fails. Do not
substitute a build date or accept a certificate because the local clock looks
inconvenient.

**Proposed trust input:** one explicitly configured public PEM root bundle,
read as a regular file and snapshotted once per load. Let the lead choose the
default system-bundle path and override wording. Record its content hash in
test evidence; accept no automatically downloaded trust anchors. Root updates
should come through an explicit configuration/package change, not from the
peer under verification.

Revocation and certificate-transparency policy need separate named decisions.
If online revocation/CT are deferred, say so in the milestone report; successful
chain/name/time checks do not establish parity with a mainstream browser's
complete trust policy. Do not claim unavailable checks were performed.

## Errors and browser behavior

Return distinct internal categories for transport/deadline failures, unsupported
negotiation, record authentication, handshake authentication, certificate
validation, identity mismatch, clock failure and resource limits. The lead owns
user-facing wording; preserve the requested address and provide a retry/edit
path. Do not automatically retry HTTPS as HTTP or offer a verification bypass.

Keep verification independent of rendering and cache only authenticated content.
The same requirements apply to images and redirect targets. Mixed-content and
downgrade-redirect behavior should follow a documented browser policy rather
than being an incidental consequence of URL parsing.

Diagnostics can retain the public hostname, selected algorithms, certificate/root
fingerprints, stage and error category. They should not retain live traffic
secrets, private scalars, keys or decrypted page bodies merely to debug TLS.

## Finite evidence required before the success claim

This is a proposed verification plan, not work executed in this review.

| Gate | Fixed evidence and completion condition |
| --- | --- |
| 1. Primitive known answers | Enumerated SHA/HMAC cases, all SHA-256 HKDF appendix cases, X25519 published scalar/DH/iteration examples, and the selected AES/GCM/P-256/RSA verification vectors. Archive source URL, vector-file hash, case IDs and exact comparison results. [HMAC RFC 4231](https://www.rfc-editor.org/info/rfc4231/), [HKDF](https://www.rfc-editor.org/info/rfc5869/), [X25519](https://www.rfc-editor.org/info/rfc7748/), [NIST AES vectors](https://csrc.nist.gov/projects/cryptographic-algorithm-validation-program/block-ciphers), [GCM vectors](https://csrc.nist.gov/projects/cryptographic-algorithm-validation-program/cavp-testing-block-cipher-modes), [signature vectors](https://csrc.nist.gov/projects/cryptographic-algorithm-validation-program/digital-signatures) |
| 2. Transcript and schedule | Reproduce the published simple full-handshake and HelloRetryRequest trace checkpoints: transcript digests, derived values and record results. Public test-vector material stays test-only. Account explicitly for current-spec differences. [RFC 8448](https://www.rfc-editor.org/info/rfc8448/) |
| 3. Certificate decisions | A finite public-data fixture set covering a trusted DNS name, numeric IP, wildcard, alternative valid chain, time boundaries, untrusted issuer, identity mismatch, and unsupported constraints/algorithms. Require the expected accept/error category, not just “no crash.” |
| 4. Independent local interoperability | Two independent TLS server implementations used only as test peers, on fresh loopback ports. Cover both key-exchange groups and RSA/ECDSA server authentication, the retry path, split/coalesced delivery, KeyUpdate and orderly close. Compare the expected HTTP body hash with the lkjscript result. |
| 5. Browser integration | Reuse article/image/redirect fixture rendering over the authenticated connection. Verify ordinary certificate-error pages, navigation cancellation and prompt cleanup. |
| 6. Real-site demonstration | In the later implementation run, after gates 1–5: three ordinary public HTTPS pages from separately operated origins, with supported but varied certificate paths. Record UTC date, compiler hash, root-bundle hash, algorithms, validation outcome and rendered screenshots. No credentials or secret logs. |

Known-answer success is not certification; NIST explicitly distinguishes its
public vectors from CAVP validation. The matrix is finite: resolve failing
requirements, then stop expanding optional testing once this scope is established.
A server handshake on one site is evidence for that case, not a claim about all HTTPS.

## What belongs to language work

The first implementation does **not** require a TLS OS capability, Unix sockets,
descriptor passing, writable mappings, threads, a foreign runtime, or a helper
that performs TLS. Existing transport/entropy/time/file effects are sufficient.

Two separate language/runtime questions remain:

1. The pin's TCP connect cannot be bounded by the browser's readiness deadline.
   Keep that limitation visible until the capability stream supplies completion
   and cancellation semantics.
2. Source syntax does not establish constant-time machine code or reliable secret
   erasure. Inspect emitted secret-bearing arithmetic/comparisons and establish
   an erasure contract with the compiler stream. Do not infer either guarantee
   merely from memory safety or from passing vectors.

Use small-limb source arithmetic initially. Faster wide multiplication, reviewed
crypto intrinsics or stronger secret-memory guarantees may later improve
performance/assurance, but they must be explicit language changes, not hidden
foreign execution.

**Recommendation to the lead:** adopt the baseline-plus-X25519 source scope
and the finite evidence gates after the visual/input milestone. Treat certificate
validation as a parallel critical path. Report restricted algorithm coverage and
trust-policy limitations precisely; keep the runtime entirely in lkjscript.
