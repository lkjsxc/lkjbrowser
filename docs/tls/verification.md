# Authenticated HTTPS verification — 2026-11-18 JST

**Result: DONE for the documented restricted profile.** The native lkjscript executable
authenticates and displays all five selected public pages. It refuses failed authentication,
and the same real Weston window supports typed HTTPS navigation, scrolling and a clicked
link to a second HTTPS page.

Implementation commit: `696a60b`. Final captures completed on 2026-11-17 UTC
(2026-11-18 in Japan). Browser SHA-256:

`a1fe4079115998427a6abe0b041adcde654a3698068948c722f1b6bc2aa50f16`

## Five public pages and Enter timing

The final round starts each fresh process at about:welcome, replaces the address through
the application's editor, and invokes its ordinary Enter handler in the already-open
Wayland window. The source timer starts inside navigation and ends when the first target
frame is submitted to Wayland. It includes DNS, TCP, TLS, HTTP, optional resources,
layout, painting and capture-file work. It does not measure physical keyboard latency
or display scanout. Each figure is one observation on the shared host.

The TLS column measures only the main document connection after DNS, root loading and
TCP establishment. Additional stylesheet and image connections authenticate separately.

| Page/operator | Server identity | Main TLS handshake | Enter to first Wayland submission | Actual window |
| --- | --- | ---: | ---: | --- |
| [Example Domain](https://example.com/) | ECDSA P-256 | 189.580 ms | 0.664880 s | [PNG](../../shots/https-example-r2.png) |
| [RFC Editor — RFC 5869](https://www.rfc-editor.org/rfc/rfc5869.html) | ECDSA P-256 | 167.536 ms | 1.003743 s | [PNG](../../shots/https-rfc5869-r2.png) |
| [Kernel.org](https://www.kernel.org/) | RSA-2048 / PSS | 50.837 ms | 0.320669 s | [PNG](../../shots/https-kernel-r2.png) |
| [NPR text edition](https://text.npr.org/) | RSA-2048 / PSS | 80.279 ms | 1.419293 s | [PNG](../../shots/https-npr-r2.png) |
| [Debian — About](https://www.debian.org/intro/about.en.html) | RSA-4096 / PSS | 193.742 ms | 5.166359 s | [PNG](../../shots/https-debian-r2.png) |

[The complete final proof log](wayland-r2.log) retains exact microsecond values, URLs,
replay scripts, source/compiler/browser/trust-store hashes and cleanup. All five compositor
screenshots matched the native program pixels exactly: **zero differing pixels**.
The [earlier direct-CLI round](wayland-r1.log) is preserved and is explicitly distinct
from this Enter-driven round.

Debian remains slower overall at 5.166359 seconds; its main TLS authentication took
193.742 ms. The remaining phases were not individually timed, so this evidence does not
assign the residual delay to one particular network or rendering operation.
No measured main TLS handshake took a second.

The certificate-key descriptions come from the bounded, dated
[candidate reconnaissance](public-candidates.md), while successful native authentication
and presentation are established by the final browser logs. The selected operators
include both ECDSA and RSA identities and cross-signed/intermediate chains.

## Continuous real-window recording

- [Current HTTPS APNG](../../shots/https-first.apng)
- [Owner's existing recording path](../../shots/scroll-and-link.apng)
- [Exact raw-key replay](../../tests/https-demo.live)
- [Compositor frames, timestamps and browser log](../../shots/https-motion-demo-r2/)
- [Motion proof](wayland-demo-r2.log)

One native browser process types `https://www.kernel.org/` using ordinary key/modifier
events, presses Enter, scrolls twice through the release table, returns Home, clicks
About at a verified coordinate, and scrolls the destination's body into view.
There is no direct-address/open/follow shortcut in this motion replay.

The APNG contains **30 actual compositor captures**, 1000×760 pixels, with a nominal
400 ms frame delay (12 seconds total), and is 1,281,445 bytes. The browser submitted
22 frames during the run; some capture frames therefore show an unchanged state.
The final compositor frame matched the native frame exactly, and the APNG assembler
verified its first-frame pixels. Actual capture times are retained in frames.tsv.

The ordinary Enter-to-submit observation for the typed Kernel page was 331,042 us;
the clicked About page took 354,354 us. The edited-address, scrolled-table and final
linked-body keyframes were opened and inspected. This is application-event replay,
not physical keyboard or mouse input.

APNG SHA-256: `df0e8a0dcdedaa56bca74cb5ce1c638e62026f52095fe500d56f014fb9ce72b2`.

## Deterministic offline gate

```sh
sh tools/https-test.sh
```

[The retained final gate log](offline-final.log) ends with
`PASS all offline browser and authenticated HTTPS gates`.
After adding the tracked positive callback workaround, the unchanged gap script was
also rerun successfully; [its final output](gap-final.log) is retained. No expected
layout/pixel golden was refreshed during this HTTPS slice.

| Verification group | Result |
| --- | --- |
| Native browser unit suite | 72 tests and the declared program path case passed |
| Primitive known answers | 18 tests passed, including the original 14 public vector transcriptions and additional boundaries |
| Primitive RFC trace calculations | 11 tests passed |
| Big integers, SHA-384/512, RSA and ECDSA | 75 tests passed |
| DER/X.509 module checks | 11 tests passed |
| Certificate policy fixtures | 31 decisions plus every truncated leaf prefix and malformed trailing data passed |
| Basic protocol parser/record checks | 4 tests passed |
| Complete recorded-handshake checks | 16 tests passed, including every split of the 657-byte flight and bytewise assembly |
| Existing browser behavior | Five unchanged layout/pixel goldens; HTTP framing, PNG, input/history, file authority and native Wayland peer passed |
| Native local TLS/browser flows | 28 page invocations cover accepted pages, resources and eight refusal paths |
| Owned resource worker | Same-image 128 KiB transfer; deadline kill/reap and drop/reap passed |

These groups overlap in source coverage and must not be added up as a count of
independent security guarantees. The public fixed inputs establish computations,
and the independent peers establish the listed interoperability cases.

The local peers exercise RSA, P-256 and P-384 server identities, 37-byte handshake
fragmentation, KeyUpdate, chunked responses, redirects, HTTPS PNG resources and
HTTP-to-HTTPS navigation. Refusals become error pages for expiry, wrong host,
self-signing, unknown root, a changed protected record, bad Finished, bad
CertificateVerify and HTTPS downgrade. Accepted page text is absent from those
error-page outputs.

Stylesheet regressions establish source order, replay of a cached URL after the
four-distinct-fetch cap, ignored print media, exact 1000px screen-width matching,
mixed-content refusal and visible-only image loading. Two CSS URLs that each stall
for five seconds share one three-second budget; the final native test painted the
body in **3,161,783 us**. A timeout kills/reaps the owned child.

Node/OpenSSL act only as independent test peers. The browser performs its own TLS
and certificate verification; the optional resource child executes the exact same
native executable and uses anonymous files.

## Separate public refusal evidence

[The public negative log](negative-online.log) and
[endpoint manifest](public-negative.tsv) record the actual outcomes:

| Public endpoint | Observed native refusal |
| --- | --- |
| expired-rsa-dv.ssl.com | Certificate expiry |
| expired-ecc-dv.ssl.com | Certificate expiry |
| expired.badssl.com | TLS 1.3 algorithm negotiation failed before certificates |
| wrong.host.badssl.com | TLS 1.3 algorithm negotiation failed before certificates |
| self-signed.badssl.com | TLS 1.3 algorithm negotiation failed before certificates |

All five ended on an error page; the PNGs are `shots/https-error-NAME.png`.
The badssl results do **not** establish public wrong-host/self-signed certificate
checks because those peers did not send certificates for this offered profile.
The deterministic local TLS 1.3 fixtures establish those checks. No downgrade or
verification exception was used to make a public endpoint load.

## Look, fix, and inspect again

1. Initial native public-page renders exposed missing viewport/font shorthand,
   both Kernel desktop/mobile headers, inline-collapsed tables and unnecessary
   off-screen image fetches. The renderer gained vh/vw, supported font shorthand,
   linked sheets and screen-width media, readable table rows/columns, and stable
   visible-image loading.
2. Cached real HTML/CSS was rendered again without extra network requests. The
   release table still wrapped dates/link brackets and the bold linux-next value.
   Crowded columns now reduce gaps first, and intrinsic widths use descendant
   text styles. The corrected table, Example paragraph spacing and single Kernel
   header were inspected again. [Detailed evidence](../../tests/layout-public-review.md)
   records the exact sources, hashes and focused tests.
3. All five actual r1 Weston screenshots were opened. Final r2 document layouts
   are identical; the final Kernel/Debian screens and motion keyframes were also
   opened. The start page's margin was reduced so its text fits without a
   redundant desktop scrollbar.
4. The first motion attempt captured a black compositor frame immediately after
   submission. The capture harness now waits 200 ms for the initial repaint before
   sampling. The continuous recording was repeated, and its first frame now shows
   the start page; its final linked-page frame was inspected again. Native browser
   code and the five-page timing round were unchanged.

Remaining visible compromises include Debian's logo placeholder and long stacked
navigation, the shared fallback font family, and the intentionally limited table/CSS
model. No site-specific hiding rules or invented page content were introduced.

## Established scope and remaining work

The profile is TLS 1.3, X25519, AES-128-GCM/SHA-256 and the documented RSA/P-256/P-384
authentication schemes, with system-root chain, SAN identity, validity,
CertificateVerify and Finished checks. The crypto directory has no browser
dependency. See [protocol](../tls-protocol-profile.md) and
[certificate](../tls-x509-profile.md) details.

Emitted constant-time behavior and reliable secret erasure have not been established.
AES uses a secret-indexed S-box. This browser reads public pages and has no forms,
cookies or logins. Revocation, CT, AIA fetching, resumption, 0-RTT, client
certificates, P-256 ECDH and HTTP/2 remain outside the delivered profile.
Unsupported required certificate semantics fail closed.

The parent deadline bounds optional stylesheets only. Main documents and images
still use synchronous fetches, and the pin's TCP connect can block before the
six-second I/O timer starts. That remains the first ranked runtime gap.

The pin and existing byte/descriptor bridge are unchanged from 798c6b7.
The repository has no remote. No release, deployment, system installation or
persistent service was created. Capture/test-owned processes were stopped and
reaped; each private compositor runtime was removed.

## Local implementation history

- `e0a278a`: verified primitive calculations and public RFC trace.
- `e0d0735`: RSA/ECDSA signatures, DER/X.509 and certificate policy.
- `696a60b`: authenticated TLS/HTTP integration, bounded resources, public-page layout and proof tooling.

The following documentation/proof commit contains the retained screenshots,
recording and final logs without changing the captured native code.
