# Implemented TLS 1.3 protocol profile

This document describes the code in src/crypto/record.lkj, handshake.lkj,
transport.lkj and tls.lkj. These modules have no browser dependency. Cryptographic
arithmetic, DER and certificate policy are sibling source modules. The transport
adapter uses the pinned language's File, Readiness, Clock and Entropy capabilities;
it does not execute another TLS implementation.

This is a restricted, authenticated TLS 1.3 client profile. It is not a claim of
complete mandatory-to-implement coverage: P-256 ECDH is absent even though P-256
ECDSA verification is implemented. The current specification is
[RFC 9846](https://www.rfc-editor.org/info/rfc9846/), published July 2026;
[RFC 8448](https://www.rfc-editor.org/rfc/rfc8448.html) supplies the historical
known-answer handshake trace.

## Exact advertised choices

| Property | Implemented browser offer |
| --- | --- |
| Protocol | TLS 1.3 only; no older-version fallback |
| Record suite | TLS_AES_128_GCM_SHA256 (0x1301) |
| Key exchange | X25519 (group 29), a fresh ephemeral share per connection |
| CertificateVerify | ECDSA P-256/SHA-256 (0x0403), ECDSA P-384/SHA-384 (0x0503), RSA-PSS-rsae/SHA-256 (0x0804), RSA-PSS-rsae/SHA-384 (0x0805) |
| Certificate-signature offer | Those four schemes, plus RSA PKCS#1/SHA-256 and RSA PKCS#1/SHA-384 |
| Application protocol | HTTP/1.1 only through ALPN |
| Server identity | Original DNS host through SNI and certificate SAN; numeric IPv4 uses an IP SAN and no DNS SNI |
| Trust | Explicit caller-supplied root bundle; browser default /etc/ssl/certs/ca-certificates.crt |

The signature library can also verify SHA-512 certificate signatures, but the
current TLS offer and CertificateVerify parser do not advertise that additional
scheme. A server that omits ALPN may still carry HTTP/1.1; an ALPN selection other
than the exact offered HTTP/1.1 value is rejected.

PSK resumption, 0-RTT, exporters, client certificates, P-256 ECDH, ChaCha20-Poly1305,
AES-256-GCM, HTTP/2 and QUIC are not implemented in this connection. Public
known-answer tests of a resumption/exporter derivation do not make that feature
available in the browser.

## Authentication and state transitions

The connection sends ClientHello, requires a matching TLS 1.3 ServerHello and
X25519 share, then installs separate handshake read/write keys. It parses
EncryptedExtensions and the server certificate message, validates the chain,
host and time, verifies CertificateVerify over the exact encoded transcript,
and verifies the server Finished before sending its own Finished.

Only after these checks and the client Finished send succeed does the constructor
mark the connection authenticated and install application keys. HTTP request
bytes are not sent beforehand, and plaintext received before authentication is
not released to the browser. A failure returns an error and attempts a fatal alert.

Transcript bytes are retained exactly as encoded. The connection validates
message order, duplicate extensions, offered algorithms and session-identifier
echo. A single cookie-only HelloRetryRequest is supported: the first ClientHello
is replaced by its synthetic message_hash, the retry is included, and the second
ClientHello preserves its random, session and already-sent X25519 share while
adding the cookie. A request for an already-sent or unsupported group, an empty
cookie, or a second retry is rejected. This is not general multi-group retry
support.

Handshake messages may be coalesced or fragmented across protected records.
Buffered handshake bytes must end at ServerHello, Finished and KeyUpdate key
boundaries. Application data cannot interrupt an incomplete handshake message.
Client-certificate requests produce an explicit unsupported-authentication error.

Certificate-policy detail is in [tls-x509-profile.md](tls-x509-profile.md).
In particular, a peer-provided self-signed certificate is not a trust anchor,
unknown critical extensions and unsupported constraints fail closed, and no
verification-skipping switch exists.

## Records, updates and close

Each direction has a separate sequence number and traffic epoch. The record
nonce XORs the epoch IV with the padded 64-bit sequence number. Sequence numbers
reset only with newly derived keys. The implementation stops an epoch at
8,388,608 records rather than risking sequence wrap or unlimited GCM key use.

The encrypted record body is bounded at 16,640 bytes. After successful AEAD
authentication, the **entire** TLSInnerPlaintext, including the content-type byte
and all padding, must fit 16,385 bytes. The check precedes removal of zero padding.
A padded oversized record cannot evade the content limit by stripping down to a
short message. Content then has a 16,384-byte limit; empty application records
are allowed, while empty handshake/alert content and missing/invalid content
types are rejected. The native trace gate includes exact-boundary and
authenticated-oversized-padding regressions.

AES-GCM verifies the tag before exposing plaintext. Record headers are included
as authenticated additional data. Changed ciphertext, tag, nonce or header
therefore cannot silently become page text. An integrity failure terminates the
connection with the corresponding error.

The post-handshake loop supports KeyUpdate, derives the next read secret and
resets its record sequence. A requested reciprocal update is sent with the
current write keys before switching to the next write epoch. The connection
allows at most 64 received updates.

NewSessionTicket messages are framed and bounded but silently ignored because
resumption is not implemented. user_canceled alerts do not authorize data or
complete a connection; the reader continues waiting for further records,
including close_notify, under the existing deadline. These choices follow the
current specification's handling of non-resuming clients and cancellation.

The client sends warning-level close_notify on an ordinary completed response
or when closing an authenticated connection. Received close_notify ends the
read stream and receives a reciprocal close. A raw socket EOF inside a required
TLS record is an incomplete-message error. For HTTP bodies already completed by
Content-Length or chunk framing, the browser can finish without waiting for an
extra peer close alert.

## Resource and timing boundaries

| Boundary | Current policy |
| --- | --- |
| One handshake message | 1 MiB |
| Pending handshake buffer | 1 MiB + 16,388 bytes |
| Extensions per parsed extension block | 128 |
| Retry cookie | 4,096 bytes |
| Peer certificates | 12 |
| Compatibility ChangeCipherSpec records | At most 8, before authentication |
| Received KeyUpdate messages | 64 |
| Socket read/write work | Six-second absolute deadline after connect succeeds |
| Browser response headers/body | 64 KiB / 16 MiB |
| Redirects | At most 5 |

The six-second timer is shared by that stream's TLS handshake and HTTP exchange.
It is **not** a DNS or TCP establishment deadline: Connector.connect remains
blocking in the pinned runtime. Main-document navigation and image fetches
remain synchronous, and the UI cannot process an interactive cancellation while
blocked in those paths.

External stylesheet fetches now run in owned children of the same browser
executable. One three-second absolute deadline is shared across at most four
distinct stylesheet fetches; the parent can terminate and reap a child even when
it is blocked in DNS or TCP establishment. Each stylesheet response body is
limited to 1 MiB, and the accumulated inline and external stylesheet text is
limited to 4 MiB. Successful cached sheets are applied at each DOM source
position. A failed or timed-out sheet is omitted so document rendering can
continue. The parent waits synchronously for these bounded stylesheet jobs;
this does not make navigation asynchronous or bound the main-document and image
connect paths. These remaining limits are not fixed by a capture-script
watchdog.

The log field handshake_us starts after DNS, root-bundle loading and TCP connect;
it covers TLS construction/authentication, not total navigation. The PAINT marker
starts with navigation and ends at headless completion or Wayland presentation
submission. Actual compositor comparison and replay input are separate evidence.

For example, the recorded native local run
target/browser-tls-local.j0yZksmi measured 23,712 microseconds for the ordinary
independent peer handshake, 37,940 for fragmented records and 34,045 for the
KeyUpdate peer. Corresponding headless navigation-to-paint values were 139,463,
153,170 and 173,248 microseconds. These are observations on the shared host,
not public-network predictions, physical-input timings or steady-state promises.

## HTTP and browser boundary

The browser reauthenticates every new HTTPS connection, including redirects and
subresources. Bare host input selects HTTPS. HTTP-to-HTTPS redirects work; after
a redirect chain reaches HTTPS, an insecure downgrade is refused. HTTPS pages
do not load insecure image or stylesheet subresources. The local-file origin
policy remains in effect.

HTTP framing stays above TLS: Content-Length, chunked bodies/trailers and the
supported redirects use authenticated application bytes. The browser requests
identity encoding and refuses unexpected compressed content. It sends GET
requests for public pages/resources; forms, cookies and logins are absent.

## Established proof and its limits

The reproducible combined offline command is:

~~~sh
sh tools/https-test.sh
~~~

It combines existing browser tests, the original 14 public primitive answers,
additional primitive/signature cases, the recorded RFC trace, protocol-parser
refusals, certificate decisions and independent local TLS peers.

The RFC trace proves key schedule, transcript, signature/Finished and exact
record calculations for public fixed inputs. Its historical 1024-bit RSA key is
used only in transcript/signature tests; the production X.509 policy still
requires at least 2048 bits. Cookie-only retry is covered by parser/transcript
tests, not by a claimed live public-server retry.

The native local browser run has accepted RSA, P-256 and P-384 server identities,
HTTP upgrade, HTTPS redirects, chunked bodies and a PNG subresource. It produced
the intended error pages for expired, wrong-host, self-signed and unknown-root
certificates, tampered record, bad Finished, bad CertificateVerify and insecure
downgrade. The independent peer also established native 37-byte handshake
fragmentation and KeyUpdate interoperability. No foreign TLS helper was used by
the browser; Node/OpenSSL acted solely as external test peers.

Public-network and real-window evidence stays separate. The badssl endpoints
for expiry, wrong host and self-signing rejected this TLS 1.3 profile before
sending certificates; those online results establish negotiation refusal,
not the corresponding certificate-validation checks. Local TLS 1.3 fixtures
establish those checks. The public-candidate ledger separately records TLS 1.3
expiry endpoints and the selected pages; it must not be mistaken for native
rendering evidence.

Known-answer success and a finite interoperability matrix are not certification.
The emitted code has not been proved constant-time, and reliable secret erasure
has not been established. AES uses a secret-indexed S-box. The source-level
full-byte comparison helpers do not establish machine-code timing guarantees.
Revocation, OCSP/CRL policy and Certificate Transparency are absent as documented
in the certificate profile.

## References

- [RFC 9846, current TLS 1.3 specification](https://www.rfc-editor.org/info/rfc9846/)
- [RFC 8448, public handshake traces](https://www.rfc-editor.org/rfc/rfc8448.html)
- [Source primitive and trace evidence](../tests/tls/crypto-primitives.md)
- [Certificate profile and decisions](tls-x509-profile.md)
- [Independent adversarial peer and native proof](tls-adversarial-peer.md)
- [Actual Weston capture workflow](HTTPS-capture.md)
- [Public reconnaissance, distinct from native proof](tls/public-candidates.md)
