# lkjbrowser

A native Wayland browser written in generation-two lkjscript. It fetches documents,
builds an HTML tree, computes a small CSS subset, wraps text using runtime TrueType
metrics, rasterizes outlines, paints pixels, and speaks the Wayland wire protocol itself.

The same executable opens **authenticated HTTPS, plain HTTP and local files**, displays
text and PNG, JPEG and GIF images, follows links, scrolls and goes back. TLS 1.3, cryptography,
certificate parsing and validation are lkjscript source in `src/crypto/`.
JavaScript is not implemented.

[The ten-page comparison](docs/pages/verification.md) records real Weston before/after
captures of documentation, an encyclopedia article, a standards page, project sites,
a blog, a news index and a mailing-list archive. The page engine handles intrinsic
image sizes, list numbering, table spans, bounded stylesheet imports and compressed
HTTP. Code examples use real monospace typefaces.

[The completed HTTPS proof](docs/tls/verification.md) records five authenticated public
pages, Enter-to-first-frame timings, unchanged offline goldens and the current real
Weston address/scroll/link recording.

## Run

Linux x86-64, a Wayland compositor, GCC for the temporary transport bridge, a system
PEM trust bundle, and Liberation Sans or DejaVu Sans TrueType fonts are required.
Font discovery includes the distribution font directories used by Debian and Arch Linux.

~~~sh
sh tools/build.sh
sh tools/wayland-run.sh 'https://www.rfc-editor.org/rfc/rfc5869.html'
~~~

The launcher runs `target/lkjbrowser` on the desktop selected by `XDG_RUNTIME_DIR`
and `WAYLAND_DISPLAY`. It creates an owned frame file, starts the byte/descriptor
bridge on a fresh loopback port, and cleans up that bridge. The launcher authenticates the browser's private bridge
connection using a fresh 32-byte credential passed through inherited stdin handles;
the credential is never a command-line argument, environment value or log entry.

The address line accepts `https://`, `http://`, `file://` and bare hostnames.
Bare hostnames select HTTPS. A local document can be opened with:

~~~sh
sh tools/wayland-run.sh "file://$PWD/fixtures/article.html"
~~~

Without a compositor, the same executable writes its own image and layout:

~~~sh
target/lkjbrowser --headless --screenshot shots/page-local.png \
  --layout target/page.layout 'https://www.kernel.org/'
~~~

`--screenshot` writes PNG when the name ends in `.png`, otherwise PPM.
`--width`, `--height` and `--scroll` select the viewport.
`--font-dir DIR` selects four LiberationSans files; `--dns IPv4` selects an IPv4 DNS
resolver for TCP queries. `--trust-file FILE` selects an explicit PEM root bundle
for HTTPS connections, including subresources. Without this option, the browser
uses the system roots in `/etc/ssl/certs/ca-certificates.crt` or the regular PEM file
at `/etc/ca-certificates/extracted/tls-ca-bundle.pem` on Arch Linux.
Local TLS tests supply their test root through this option.

### Controls

| Action | Input |
| --- | --- |
| Edit the address | Click the address field, Ctrl+L, Alt+D or F6; Enter navigates |
| Follow a link | Left click |
| Scroll | Wheel, drag the scrollbar, Up/Down, Page Up/Page Down, Space |
| Beginning / end | Home / End |
| Back / forward | Toolbar arrows or Alt+Left / Alt+Right, including while editing |
| Reload | The reload button, or Ctrl+R |
| Restore / leave address editing | Escape restores changed text and selects it; Escape again leaves editing |
| Close | The cross, compositor close, Ctrl+Q or Ctrl+W |
| Move the window | Drag empty toolbar |

The address editor moves by UTF-8 scalar or Unicode word boundaries, supports
anchored Shift selection, Home/End, Backspace/Delete and their Ctrl word variants.
Typing replaces the selection. Click places the caret, double-click selects a word,
triple-click selects all, and dragging selects text with horizontal scrolling.
The caret is steady; long edited text is clipped and scrolled without an ellipsis.
Clicking outside discards the edit and restores the page address.

Ctrl+C, Ctrl+X and Ctrl+V use the compositor's plain-text clipboard through
`wl_data_device`. Cut removes text only after compositor ownership is confirmed.
Paste removes line breaks, turns tabs into spaces, and trims surrounding whitespace.
Unavailable clipboard authority leaves text unchanged; there is no internal clipboard
substitute. Clipboard payloads are limited to one MiB. Paste has a five-second total
deadline; bridge descriptor transfers have a five-second inactivity deadline.
Invalid UTF-8, failed, incomplete or stale transfers do not insert partial text.
[The interaction and visual contract](docs/address-editing.md) records the exact behavior.
[Verification, acceptance images and reproduction](docs/address-editing-verification.md)
record the exact local candidate and its final offline and compositor proofs.

Keyboard text still uses the US physical-key layout; both left/right Shift, Ctrl
and Alt are tracked across focus changes. XKB layout parsing, IME, grapheme-cluster
movement and key-repeat scheduling are not implemented. The window advertises a
fixed size selected at launch.

The toolbar is the only permanent chrome. The address field shows a lock for verified
HTTPS, a "Not secure" chip for plain HTTP and a document for local files; the host or
file name is in strong ink and the rest is quiet. A hovered link's destination appears
in a small bubble at the bottom, the scrollbar overlays the page, and a progress line
is painted before a fetch blocks the event loop. `sh tools/chrome-shots.sh` regenerates
the review pictures in `shots/chrome/` (it needs the public network).

## HTTPS and authentication

This is a **restricted TLS 1.3 profile**, with these complete advertised choices:

| Layer | Implemented profile |
| --- | --- |
| Protocol and records | TLS 1.3 only, TLS_AES_128_GCM_SHA256 |
| Key agreement | Fresh X25519 share for each connection |
| Handshake signatures | ECDSA P-256/SHA-256, ECDSA P-384/SHA-384, RSA-PSS-rsae/SHA-256 and SHA-384 |
| Certificate-signature offer | The above schemes plus RSA PKCS#1/SHA-256 and SHA-384 |
| Public certificate keys | RSA 2048–4096, P-256 and P-384 |
| Identity and time | SAN DNS names or IPv4 addresses, restricted single-label wildcards, validity against the system Clock |
| Trust | A chain to an explicitly trusted root in the system or user-supplied PEM bundle |
| Application protocol | HTTP/1.1; no HTTP/2 |

The constructor verifies the chain, hostname, validity, CertificateVerify and Finished
before releasing application bytes. A peer's self-signed certificate never becomes
trusted merely because the peer sent it. Unsupported constraints or critical extensions
fail closed. There is no verification-skipping switch, “continue anyway” path or
older-protocol fallback. Authentication failures become ordinary error pages retaining
the requested address.

The connection handles handshake fragmentation, a cookie-only HelloRetryRequest,
authenticated records, KeyUpdate, alerts and close_notify. It ignores session tickets
because resumption is absent. P-256 **signature verification** is implemented; P-256
**key agreement** is not. This is not a complete mandatory-to-implement TLS profile.

Use this browser for **reading public pages**. Forms, cookies and logins are absent.
Emitted-code timing has not been established as constant-time; AES uses secret-indexed
S-box tables. Reliable secret erasure has not been established. Revocation, OCSP/CRLs,
Certificate Transparency, resumption, 0-RTT and client certificates are not implemented.
Successful chain/name/time verification does not claim a mainstream browser's complete
trust policy.

See [the exact protocol profile](docs/tls-protocol-profile.md),
[the certificate profile](docs/tls-x509-profile.md) and
[remaining TLS work](docs/next-tls.md).

## Documents, resources and pixels

| Layer | Implementation |
| --- | --- |
| Wayland | Registry, wl_compositor, wl_shm, xdg-shell, pointer/keyboard input, cursor and two release-tracked buffers |
| Networking | IPv4 TCP, DNS A queries over TCP, HTTP/1.1 framing, chunks/trailers, redirects, bounded gzip and zlib-wrapped deflate |
| Documents | Owned HTML tree, selected optional table/paragraph closes, entities, UTF-8/UTF-16/windows-1252 decoding, native details disclosure and raw style/title/script handling |
| CSS | Indexed static selectors/cascade, percentage boxes, root-relative lengths, font/list hints, visibility, observed clipping/clearance and screen-width media; documented finite flex/float fallback |
| Layout | Wrapped inline runs, intrinsic image sizes, visible list markers, anchors and hit tests; table row/column spans and intrinsic widths; nonoverlapping readable fallback for crowded flex rows |
| Fonts | Runtime TrueType outlines and cached coverage masks; four Sans and four Mono faces share measurement and painting metrics |
| Images | Native PNG, baseline/progressive JPEG and GIF first-frame decoders; SVG metadata reserves dimensions for an explicit alt placeholder |
| UI | Address line, history, scrolling, links and ordinary error pages |

Linked and imported stylesheets use the same HTTP/HTTPS authentication rules. The browser
accepts at most four distinct stylesheet URLs across the whole batch, one MiB per sheet
and four MiB of expanded CSS. Legal leading `@import` statements resolve against the
owning sheet's final URL after redirects, preserve source order and obey supported media
conditions. Cached repeats replay in source order; cycles stop and expansion work is
bounded to 1,024 occurrences. Remote sheets cannot acquire local-file authority through
a local parent document.

A same-executable lkjscript child fetches each optional sheet into anonymous storage.
The parent enforces **one shared three-second budget for the entire batch**, including
imports, and kills/reaps an unfinished child. Missing sheets leave the document readable
with the remaining styles. No curl or foreign TLS helper is used by the browser.

Media queries cover screen/all, min/max-width in px/em/rem, comma alternatives and
bounded nesting. Unsupported conditions and print styles are skipped. Imported layers,
`supports()`, escaped URL tokens and downloadable fonts remain unsupported.
Tables retain a 64-column policy and readable narrow fallback; row spans, column spans,
legacy spacing/padding, group boundaries and footer placement now work. Complete CSS
table sizing, collapsed borders and CSS `vertical-align` are not implemented.

Visible raster images are decoded before the corresponding paint. Their intrinsic sizes
then reflow the page using the cached document and computed styles, avoiding another
whole-page selector pass. Image-driven reflow keeps the first visible text fragment at
its screen position, including when the same image source also occurs above the
viewport; initial navigation stays at scroll zero. Off-screen resources remain deferred. GIFs show their first
composited frame; CMYK JPEG, SVG painting, non-8-bit/Adam7 PNG, orientation metadata and
color-profile management are outside the implemented image subset.

This deadline isolation applies to **stylesheets only**. Main-document and image fetches
remain synchronous. Their six-second I/O deadline begins after TCP connect; the pinned
`Connector.connect()` itself remains blocking. A slow connection can still delay
navigation and input. [GAPS.md](GAPS.md) keeps that runtime gap first.

Every HTTPS connection is authenticated again, including redirects and subresources.
HTTP-to-HTTPS redirects work. An HTTPS redirect chain cannot downgrade to HTTP, and
HTTPS pages do not load insecure image or stylesheet resources. Web-origin links,
redirects and subresources cannot enter `file://`. Explicit user navigation and
local-origin links may open local files through `Directory.open_regular`, which
refuses FIFOs, devices, directories and final symlinks before reading their contents.
A separate trusted-configuration reader handles OS-owned configuration paths.

Unsupported content is not delegated to another browser. There is no JavaScript,
complete HTML5 recovery, complete CSS/flex/grid/table/SVG layout, forms, cookies,
Brotli, every legacy character encoding, IPv6 or Unicode-to-IDNA conversion. Text has no
shaping, bidi, per-glyph fallback-font selection or kerning. CFF outlines and non-8-bit/Adam7 PNGs are absent.
The precise subsets and resource policies are in [HTML/CSS](docs/html.md),
[fonts](docs/font.md), [typefaces](docs/typefaces.md), [images](docs/images.md),
[content decoding](docs/content-decoding.md), [tables](docs/tables.md) and [Wayland](docs/wayland.md).

## Reproducible verification

The combined deterministic offline gate is:

~~~sh
sh tools/pages-test.sh
~~~

This includes the existing `sh tools/https-test.sh` gate plus the image, compressed-content
and stylesheet-import cases. Public-network captures remain separate.

After the pinned toolchain is present, this requires no public network. It includes
the original browser fixtures and visual goldens, exact language probes, the public
primitive known answers, additional signature/hash tests, the recorded RFC handshake
trace, certificate decisions and independent local TLS peers.

Local peers prove successful authenticated pages and ordinary error pages for expired,
wrong-host, self-signed and unknown-root certificates, tampered records, bad Finished
and bad CertificateVerify. Fragmented handshakes, KeyUpdate, redirects, chunked bodies
and PNG resources are included. The peers use Node/OpenSSL solely as independent test
servers; the browser never executes them.

The browser's existing narrower gate remains available as `sh tools/test.sh`.
Its layout/pixel comparisons cover file/HTTP framing, PNG, scroll/link/back/address
events, malformed responses, and local-file origin/special-file policies. The five
visual goldens use fixed Sans/Mono font hashes in `tests/fonts.sha256`. The pages slice
preserved all five complete fixture PNGs byte for byte; only the new monospace flag was
added to their layout metadata.
Set `LKJBROWSER_FONT_DIR` if the recorded Liberation Sans files live elsewhere.
To deliberately accept reviewed visual changes, run
`sh tools/test.sh --update-goldens`, then `sh tools/test.sh`; do not refresh
goldens to conceal a failed comparison.

Public-network proof is a separate, explicit command:

~~~sh
sh tools/https-online-test.sh
~~~

[The five-page manifest](docs/tls/public-pages.tsv) selects Example Domain, RFC 5869,
Kernel.org, NPR's text edition and Debian's about page. It covers ECDSA and RSA
server identities across different operators. The command records actual native
authentication and paint logs; [candidate reconnaissance](docs/tls/public-candidates.md)
is separate OpenSSL evidence and must not be substituted for that native run.

The public SSL.com expired RSA/ECC endpoints reach certificate-expiry errors.
The three badssl endpoints for expiry, wrong host and self-signing currently refuse
this TLS 1.3 profile **before certificates**. Their online results are negotiation
errors, not evidence of those certificate checks. The offline TLS 1.3 cases establish
wrong-host and self-signed rejection.

## Actual Wayland proof

~~~sh
bash tools/capture-https.sh --enter --round r2
~~~

This starts an owned Weston compositor using the locally unpacked dependencies, opens
the five pages in the actual native browser, takes compositor screenshots and compares
every pixel with the browser's own image. Outputs use
`shots/https-NAME-ROUND.png` and `docs/tls/wayland-ROUND.log`.
Repeated inspect/fix/capture rounds assess readability separately from the pixel match.
See [the capture workflow](docs/HTTPS-capture.md).

The continuous demonstration types an HTTPS address through application-event replay,
waits for the page, scrolls and clicks a link to a second HTTPS page. The current
recording is [shots/scroll-and-link.apng](shots/scroll-and-link.apng), also written as
`shots/https-first.apng`. The workflow records the exact replay, compositor frames
and timings. This is application-event replay, not physical keyboard or mouse input.

A `handshake_us` log measures TLS construction after DNS/root loading/TCP connect.
The `PAINT` marker covers navigation through headless completion or Wayland presentation
submission. Neither is a claim about physical display scanout. Capture watchdogs do not
repair the browser's remaining blocking connect operation.

The original fixture window proof remains reproducible with
`sh tools/capture-wayland.sh`; `sh tools/wayland-test.sh` independently checks
protocol/input traffic against a native lkjscript peer. Compositor packages remain
under `.deps`; no system package installation or persistent service is created.
All processes started by the capture/test scripts are owned and reaped.

## Pin, modules and the temporary bridge

`toolchain.lock` fixes:

- Tag: `2026.11.17-e6d13590b`
- Commit: `e6d13590b7bb2d665d668727f1a8d1ee4f76c33d`
- SHA-256: `60149069984ecfe491e322eba406238555c13acc90375c5468e5d5d4954a83ca`

`tools/fetch-toolchain.sh` verifies the release checksum and executable against
the lock. Pin changes require a deliberate commit; the language checkout is read-only.
Builds and tests are local operations. Public-repository synchronization, releases
and deployments are separate from these commands.

| Module | Responsibility |
| --- | --- |
| `src/main.lkj` | Application state, origin policy, input, navigation and page painting |
| `src/chrome.lkj` | Toolbar, address field, link bubble and overlay scrollbar: painting and hit testing |
| `src/address.lkj`, `address_words.lkj` | UTF-8 editor state, measured caret/selection scrolling and Unicode word boundaries |
| `src/net.lkj` | URLs, regular files, DNS, HTTP framing and TLS adaptation |
| `src/resources.lkj` | Same-executable stylesheet fetch worker and parent deadline/cleanup |
| `src/crypto/` | HKDF, X25519, AES-GCM, bigint/signatures, SHA-384/512, DER/X.509, TLS records/handshake/transport |
| `src/html.lkj`, `css.lkj`, `layout.lkj` | Tree, supported styles, boxes and inline runs |
| `src/font.lkj`, `typefaces.lkj`, `paint.lkj` | TrueType parsing, Sans/Mono faces, glyph masks, pixel canvas and anti-aliased shapes |
| `src/png.lkj`, `jpeg.lkj`, `gif.lkj`, `images.lkj` | Native image decoding, SVG dimension metadata and PNG output |
| `src/net/content.lkj`, `src/layout/table.lkj` | Bounded HTTP/text decoding and table-grid geometry |
| `src/wayland.lkj` | Wayland object state, wire messages, buffers and input |

The crypto directory has no browser dependency and is organized for later reuse.
Its presence does not add `std::tls` to the pinned language's standard library.
`program.lkj` declares the reviewed World entry; `.toolchain/lkjscript authority .`
reports its authority and reachable effects.

`bridge/byte_descriptor_bridge.c` is the existing small freestanding, syscall-only
transport, compiled without libc or a dynamic loader. It connects the explicit Unix
socket, forwards opaque bytes, attaches the supplied frame-file descriptor, and
transfers bytes through descriptor-owned pipes. Clipboard protocol, selection
ownership and MIME choices remain in lkjscript; the bridge has no Wayland interpretation,
cryptography, certificate validation, HTTP, parsing, layout, text or pixels. [The clipboard transport](docs/clipboard-transport.md)
documents ownership checks, descriptor lifetime and failure handling.

The pin lacks Unix-path stream connection and descriptor send/receive operations;
those capabilities remove the bridge. Writable mapping is optional because ordinary
file writes already work. The browser still closes unused keymap descriptors and uses
its documented physical-key subset. [GAPS.md](GAPS.md) separates runtime capabilities,
source forms and source libraries, with exact probes and supported workarounds.
