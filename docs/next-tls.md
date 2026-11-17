# Authenticated HTTPS: delivered profile and remaining work

The browser now opens authenticated HTTPS with a native lkjscript TLS 1.3 implementation
in `src/crypto/`. The same executable parses the response, lays out text and paints the
Wayland window. HTTP framing remains above the authenticated stream. No curl subprocess,
foreign TLS implementation, external terminator or verification bypass is part of that
path. Public roots are data loaded from the system PEM bundle or an explicit
`--trust-file` replacement.

The former HTTPS implementation blocker is retired. The pinned language still has no
`std::tls` import: the working implementation is reusable source in this repository,
not a new compiler or standard-library capability.

## Delivered profile

| Area | Implemented browser behavior |
| --- | --- |
| Protocol | TLS 1.3 only, AES-128-GCM/SHA-256, fresh X25519 key agreement |
| TLS peer signatures | ECDSA P-256/SHA-256, ECDSA P-384/SHA-384, RSA-PSS-rsae/SHA-256 or SHA-384 |
| Certificate authentication | RSA 2048–4096 and named P-256/P-384 keys, chain signatures to explicit roots, SAN hostname/IP matching, system-clock validity, CA/path-length and key-use checks |
| Application gate | Chain, identity, time, CertificateVerify and Finished succeed before HTTP data is released |
| State and records | Fragmentation/coalescing, bounded cookie-only HelloRetryRequest, authenticated records, KeyUpdate, alerts and close_notify |
| Web integration | HTTP/1.1, chunked bodies, redirects, images, linked stylesheets and ordinary error pages |
| Origin rules | Every HTTPS connection is authenticated; HTTPS downgrade and insecure subresources are refused; web content cannot enter local files |

The certificate-signature offer also includes RSA PKCS#1/SHA-256 and SHA-384.
The underlying signature library supports additional SHA-512 verification; that does
not enlarge the browser's advertised TLS profile. A received self-signed certificate
does not become trusted. Unknown critical extensions and unsupported name/policy
constraints fail closed. Common Name is not a substitute for SAN matching.

The exact supported algorithms, state transitions, resource caps and conservative
refusals are maintained in [tls-protocol-profile.md](tls-protocol-profile.md) and
[tls-x509-profile.md](tls-x509-profile.md). The crypto directory has no browser dependency.

## Resource deadlines and the remaining runtime gap

Optional linked stylesheets use a same-executable native child in `src/resources.lkj`.
The parent gives the entire batch one shared three-second deadline, fetches at most
four distinct URLs, and enforces one MiB per response and four MiB aggregate CSS.
Cached repeated URLs are applied at their original document positions. Unsupported
media conditions are skipped. Anonymous temporary files carry the bounded result;
a timed-out child is killed and reaped. A slow optional sheet can therefore be omitted
while text remains readable.

This workaround applies to **stylesheets only**. Main documents and images still use
synchronous fetches. Their six-second stream deadline begins after TCP connect, so
blocking `Connector.connect()` can still stall navigation and input. The missing
readiness/deadline connect capability remains rank 1 in [GAPS.md](../GAPS.md).
An external capture watchdog is not an application connection deadline.
The positive [owned-child probe](../probes/owned-resource-child.lkj) records the
already-available capabilities used by the stylesheet workaround.

[The final verification report](tls/verification.md) links the actual five-site
screenshots, Enter-driven measurements, current APNG and accepted/refused test logs.

## Evidence and reproducibility

Run the deterministic offline gate with the pinned toolchain:

~~~sh
sh tools/https-test.sh
~~~

It combines browser fixture/visual checks, exact language probes, primitive and signature
known answers, a recorded RFC handshake trace, certificate-policy decisions and local
independent TLS peers. The local cases exercise authenticated success, fragmentation,
KeyUpdate, redirects and PNG bodies, plus expired, wrong-host, self-signed/unknown-root,
tampered-record, bad CertificateVerify and bad Finished refusals. Node/OpenSSL serve
only as independent test peers; the browser never executes them.

Public-network verification is an explicitly separate command:

~~~sh
sh tools/https-online-test.sh
bash tools/capture-https.sh --enter --round r2
~~~

[public-pages.tsv](tls/public-pages.tsv) lists the five pages: Example Domain, RFC 5869,
Kernel.org, NPR's text edition and Debian's about page. Native logs prove browser
authentication; [public-candidates.md](tls/public-candidates.md) records separate
OpenSSL reconnaissance. Actual Weston screenshots use `shots/https-NAME-ROUND.png`
and `docs/tls/wayland-ROUND.log`. Pixel agreement establishes the presentation path;
inspect/fix/capture rounds separately assess readability. See
[HTTPS-capture.md](HTTPS-capture.md) for the continuous address/scroll/link replay and
its `shots/scroll-and-link.apng` artifact.

The public SSL.com expired RSA/ECC endpoints reach actual certificate-expiry rejection.
The three badssl endpoints currently refuse this TLS 1.3 profile before sending a
certificate. Their results are negotiation failures and do not prove online wrong-host
or self-signed rejection. The deterministic local TLS 1.3 cases establish those checks.

`handshake_us` begins after DNS, root loading and TCP connect. `PAINT` measures navigation
through headless completion or Wayland submission. Neither measures physical display
scanout, and application-event replay is distinct from physical keyboard/mouse input.

## Remaining work and assurance limits

This implementation is for **reading public pages**. It has no forms, cookies or login
flow. Successful public sites establish the implemented profile, not complete TLS or
mainstream-browser trust-policy equivalence.

1. **Bound all connection establishment.** Add or adopt readiness-based deadline connect
   and a responsive document/image fetch architecture. The stylesheet worker is a scoped
   existing-capability workaround; it does not resolve the general runtime gap.
2. **Review secret handling.** Emitted constant-time behavior and reliable secret erasure
   have not been established. AES currently uses secret-indexed S-box tables. Public
   known answers prove calculations; they do not prove timing or memory-erasure properties.
3. **Expand protocol coverage deliberately.** P-256 signature verification is implemented,
   but P-256 ECDH is absent, so this is not a complete mandatory-to-implement TLS profile.
   Other suites, general multi-group retries, resumption, 0-RTT, exporters and client
   authentication are absent. Advertise an addition only when its complete path is tested.
4. **Expand certificate policy.** AIA intermediate fetching, name/policy constraint
   processing, revocation, OCSP/CRLs, Certificate Transparency and vendor root policy remain
   absent. Unsupported required semantics must continue to fail closed. The host's PEM
   bundle and system clock remain explicit trust inputs.
5. **Package reusable source libraries.** Preserve the browser-independent crypto/PKI
   boundary and deterministic vectors when moving these modules into a shared library.
   Missing `std::tls` alone is no longer evidence that the browser cannot implement HTTPS.

## Primary references

- [RFC 9846, TLS 1.3](https://www.rfc-editor.org/info/rfc9846/)
- [RFC 8448, TLS 1.3 example traces](https://www.rfc-editor.org/rfc/rfc8448.html)
- [RFC 7748, X25519](https://www.rfc-editor.org/info/rfc7748/)
- [RFC 5869, HKDF](https://www.rfc-editor.org/info/rfc5869/)
- [NIST SP 800-38D, GCM](https://csrc.nist.gov/pubs/sp/800/38/d/final)
- [RFC 5280, X.509 path validation and its updates](https://www.rfc-editor.org/info/rfc5280/)
- [RFC 9525, service identity](https://www.rfc-editor.org/info/rfc9525/)

The standards define the protocols. The implementation profiles and reproducible gates
above state the finite subset that this repository supports.
