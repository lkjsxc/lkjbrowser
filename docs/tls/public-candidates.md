# Public HTTPS candidates and certificate reconnaissance

Observed 2026-11-17 18:08–18:12 UTC (2026-11-18 JST), using the host's OpenSSL
3.0.13 as an independent inspection tool. This document selects inputs for the
native browser proof; **it is not evidence that lkjscript rendered the pages**.

All five selected URLs returned HTTP 200 with certificate verification enabled,
forced TLS 1.3, X25519 and TLS_AES_128_GCM_SHA256. Each page received one
reconnaissance GET. Certificate inspection used one additional handshake without
an HTTP request. No older protocol, verification bypass, proxy, credential or
browser runtime helper was used.

## Selected five pages

| URL | Operator | Leaf public key / CertificateVerify | Observed certificate chain signatures |
| --- | --- | --- | --- |
| [Example Domain](https://example.com/) | IANA | P-256 / ECDSA SHA-256 | ECDSA SHA-256 leaf; ECDSA SHA-384 intermediates; optional cross-sign RSA SHA-256 |
| [RFC 5869: HKDF](https://www.rfc-editor.org/rfc/rfc5869.html) | RFC Editor | P-256 / ECDSA SHA-256 | ECDSA SHA-256 leaf; ECDSA SHA-384 intermediate; cross-sign RSA SHA-256 |
| [Linux Kernel Archives](https://www.kernel.org/) | Kernel.org | RSA 2048 / RSA-PSS SHA-256 | RSA PKCS#1 SHA-256 leaf; RSA PKCS#1 SHA-384 intermediates |
| [NPR text edition](https://text.npr.org/) | NPR | RSA 2048 / RSA-PSS SHA-256 | RSA PKCS#1 SHA-256 throughout the supplied chain |
| [About Debian](https://www.debian.org/intro/about.en.html) | Debian | RSA 4096 / RSA-PSS SHA-256 | RSA PKCS#1 SHA-256 throughout the supplied chain |

RFC 5869's response was 33,045 bytes including HTTP framing. The initially
inspected RFC 9110 HTML response was about 1.18 MiB; the shorter complete RFC
provides a more practical readable-page demonstration. GNU's GPL page was also
considered, but both its initial attempt and an explicit IPv4 retry timed out
before a TLS handshake. No GNU HTTP response was received.

## Exact observed server chains

These are the certificates the servers sent, including cross-certificates where
present. OpenSSL verified each connection against the system store; this list
does not claim that every supplied cross-certificate was required by the chosen
validation path.

- **example.com:** example.com (P-256) → Cloudflare TLS Issuing ECC CA 3
  (P-256) → SSL.com TLS Transit ECC CA R2 (P-384) → SSL.com TLS ECC Root CA
  2022 cross-certificate (P-384), issued by AAA Certificate Services.
- **www.rfc-editor.org:** rfc-editor.org (P-256) → WE1 (P-256) → GTS Root R4
  cross-certificate (P-384), issued by GlobalSign Root CA.
- **www.kernel.org:** cdn.kernel.org (RSA 2048) → GlobalSign Atlas R46 DV
  TLS CA 2026 Q3 (RSA 4096) → GlobalSign Root R46 cross-certificate
  (RSA 4096), issued by GlobalSign Root CA - R3.
- **text.npr.org:** www.npr.org (RSA 2048) → Let's Encrypt YR1 (RSA 2048)
  → Root YR cross-certificate (RSA 4096), issued by ISRG Root X1.
- **www.debian.org:** www.debian.org (RSA 4096) → Let's Encrypt YR1
  (RSA 2048) → Root YR cross-certificate (RSA 4096), issued by ISRG Root X1.

The server chains contained no Name Constraints, Policy Mappings,
Policy Constraints or Inhibit Any Policy extension. This was a metadata check;
the native X.509 implementation must still make every validation decision.

| Host | Leaf SHA-256 |
| --- | --- |
| example.com | `85ca6ab068e9bcce88b6c4aa3c47f7d17228134a457f870d3800e6223a0df07a` |
| www.rfc-editor.org | `a7c16707e33afdf4e4f70f62c140bcdf61c6c501ef5d0b5d5f0a78d4cc140dbf` |
| www.kernel.org | `8c5aa80763b45fbd972e1f43bcc20e8fa6a6c5fccff2cd4d91e58439cc29ee73` |
| text.npr.org | `ee3dd3388520c02876cdd5556960131026bcf553ade1db61d85906df3bb8d0db` |
| www.debian.org | `ad0e405a6f7a9cba54da56cc165fa9b4a1fb819091d85baa086b99dc87db9eef` |

Trust bundle: `/etc/ssl/certs/ca-certificates.crt`, SHA-256
`ecd9dc38bc3efb7dbd6431f57e29d2f8d6a0f0d211e1464b3fef2cbfe266fcd2`.

## Public negative endpoints

| Endpoint | Forced TLS 1.3 observation | What this establishes |
| --- | --- | --- |
| https://expired.badssl.com/ | Server handshake_failure alert 40, before a certificate | Protocol refusal only; not evidence of expiry validation |
| https://wrong.host.badssl.com/ | Server handshake_failure alert 40, before a certificate | Protocol refusal only; not evidence of hostname validation |
| https://self-signed.badssl.com/ | Server handshake_failure alert 40, before a certificate | Protocol refusal only; not evidence of trust-anchor validation |
| https://expired-rsa-dv.ssl.com/ | Certificate verification error 10; expired 2016-08-02 20:48:30 UTC | A real TLS 1.3 peer reaches expired-certificate rejection |
| https://expired-ecc-dv.ssl.com/ | Certificate verification error 10; expired 2019-08-16 15:20:44 UTC | A second real TLS 1.3 expiry case |

SSL.com explicitly publishes the last two endpoints in its
[valid, revoked and expired test-certificate list](https://www.ssl.com/sample-valid-revoked-and-expired-ssl-tls-certificates/).
That list does not provide wrong-host or self-signed endpoints. The bounded
reconnaissance found no replacement for those two public cases. Keep the
offline TLS 1.3 wrong-host and self-signed rejection proof, and label badssl's
online failures as negotiation errors. Do not retry using TLS 1.2.

## Reproduction profile

The reconnaissance used these options, with `HOST` replaced by the exact host:

```sh
openssl s_client -4 -connect HOST:443 -servername HOST \
  -tls1_3 -groups X25519 -ciphersuites TLS_AES_128_GCM_SHA256 \
  -sigalgs 'ecdsa_secp256r1_sha256:ecdsa_secp384r1_sha384:rsa_pss_rsae_sha256:rsa_pss_rsae_sha384:rsa_pkcs1_sha256:rsa_pkcs1_sha384' \
  -verify_hostname HOST -verify_return_error \
  -CAfile /etc/ssl/certs/ca-certificates.crt -brief -no_ticket
```

The combined OpenSSL signature list permits the browser's supported certificate
signature algorithms; TLS 1.3 itself restricts CertificateVerify to valid TLS 1.3
signature schemes. The native browser uses its separate handshake and certificate
signature lists. Responses requested identity encoding and connection close.

Public certificate PEMs, OpenSSL summaries and structured certificate metadata
from this reconnaissance are in the ignored `target/public-candidates/`
directory. No TLS key log, private key or session-secret artifact was created.
