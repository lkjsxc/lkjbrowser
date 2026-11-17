# Next milestone: authenticated HTTPS in lkjscript

HTTPS is not implemented. The browser must continue to show that explicitly for an `https://` URL. This milestone is complete only when ordinary HTTP requests run over an authenticated, encrypted TLS 1.3 connection implemented in lkjscript.

As checked on 2026-11-17 UTC, [RFC 9846](https://www.rfc-editor.org/info/rfc9846/) is the current TLS 1.3 specification (July 2026), replacing RFC 8446. The implementation should use its current errata too.

## Work required

1. **Crypto foundations.** Reuse the language's SHA-256/HMAC as reviewed source components; add HKDF and TLS labels, ephemeral key agreement, AEAD and signature verification. The baseline includes AES-128-GCM and P-256; X25519 is a practical additional group. ChaCha20-Poly1305 can follow. Use `Entropy` for ephemeral secrets. Verify vectors and secret-dependent control flow in emitted native code; successful handshakes alone do not establish crypto correctness.
2. **Record and handshake state machines.** Handle fragmented/coalesced records and handshake messages, ClientHello/SNI, selected extensions, key shares, HelloRetryRequest, transcript hashing, the key schedule, CertificateVerify and Finished, encrypted application records, alerts, close_notify and KeyUpdate. Sequence-number/nonce reuse, unsupported negotiation and malformed messages must fail closed. Begin without 0-RTT or resumption.
3. **Certificate authentication.** Implement bounded DER parsing, certificate-chain signature checks and path building to explicitly trusted roots. Validate validity periods with `Clock.unix_seconds()`, BasicConstraints/path length, key usage/EKU, name constraints, critical extensions and algorithm policy. A received self-signed certificate is not a trust anchor. Choose and document trust-root loading/update and revocation policy.
4. **Service identity.** Match the original URL host against certificate subjectAltName using DNS-ID or IP-ID rules, including restricted wildcards and an explicit IDNA policy. DNS resolution, redirects and SNI do not replace hostname verification. Do not fall back to Common Name matching.
5. **Browser integration and proof.** Keep HTTP framing above TLS, advertise only HTTP/1.1 through ALPN, retain request deadlines/size limits and reauthenticate every new HTTPS origin. Test known-answer vectors, fragmented records, bad MAC/Finished/signatures, expired/untrusted/wrong-host certificates and then multiple real sites. Compare against an independent implementation used only as a test peer.

No C/Rust TLS helper, curl subprocess, external terminator or certificate-verification bypass belongs in the browser. Public root certificates are data; a foreign process implementing TLS would hide the central missing library.

OPINION: The existing TCP, entropy, clock and file capabilities are sufficient to start this milestone. Most missing work is reusable cryptographic, TLS and X.509 source code. Constant-time guarantees and secret erasure need an explicit compiler/runtime review; they should not be claimed from ordinary source syntax alone.

## Primary references

- [RFC 9846, TLS 1.3](https://www.rfc-editor.org/info/rfc9846/)
- [RFC 7748, X25519](https://www.rfc-editor.org/info/rfc7748/)
- [RFC 5869, HKDF](https://www.rfc-editor.org/info/rfc5869/)
- [RFC 8439, ChaCha20-Poly1305](https://www.rfc-editor.org/info/rfc8439/)
- [RFC 5280, X.509 path validation and its updates](https://www.rfc-editor.org/info/rfc5280/)
- [RFC 9525, service identity](https://www.rfc-editor.org/info/rfc9525/)
