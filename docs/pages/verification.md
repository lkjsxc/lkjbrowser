# Ten real pages: reading verification

**RESULT: DONE for the documented page subset.** Ten additional real HTTPS pages
were compared against frozen baseline ecac370. The final native browser presents
readable article/list content in the inspected views; remaining mainstream
differences are recorded for every page below.

## Scope and evidence

The slice changes HTML/CSS, text and table layout, native image decoding,
stylesheet resources, and compressed HTTP bodies. Runtime implementation is
lkjscript throughout. The existing byte/descriptor bridge and browser chrome
are unchanged. The 52 px toolbar was already present at baseline
ecac370125e52fbdaa271300c96d8ec5f18e7150.

Implementation commits are **2d37da5** (JPEG/GIF), **a907ef8** (HTTP content/imports),
and **d14bec3** (layout, typefaces, cached styles and stable image reflow).
The compiler remains **2026.11.17-e6d13590b**. No exact new published pin/probe
handoff arrived from the lead before completion; no compiler source or installed
runtime was modified.

The final ten URLs are in [pages.tsv](pages.tsv). Actual Weston captures are in
[before](../../shots/pages/before/) and [after](../../shots/pages/after/), with
adjacent layout and authentication/timing logs. Each uses a **1000×760** window
and a **1000×708** document viewport. All ten final compositor images have
**zero differing pixels** against their native framebuffer images; this
establishes real presentation, not Chromium pixel equivalence.

The [paired contact sheet](../../shots/pages/contact-after.png) is **2000×2030**,
within the requested width. Every [full-size pair](../../shots/pages/pairs-after/)
is 2000×792 including its label. Final proof is [wayland-after.log](wayland-after.log);
the frozen baseline proof is [wayland-before.log](wayland-before.log).

Mainstream witnesses are [reference screenshots and geometry](../../shots/pages/reference/):
Chromium 153.0.8010.12, JavaScript disabled, light scheme, and the same 1000×708
document viewport. They were used for comparison only. Public news/list content
can change between requests, and typography is intentionally compared rather than
claimed identical.

Openwall and GNU archive candidates failed the supported TLS 1.3 negotiation
profile; independent probes found TLS 1.2 service on those archive endpoints.
Openwall's retained error evidence does not count as one of the ten successful
pages. It was replaced by the authenticated pgsql-hackers Mail Archive.
No TLS downgrade or certificate exception was added. A separate GNU main-site
connection timed out and is not classified as a certificate failure.

## Repairs ranked by observed corpus impact

Counts are conservative, overlapping sets of pages whose observed content or
layout required the repair. They are not counts of every stylesheet mentioning a
property, nor an assertion of complete support for that feature.

| Rank | Missing capability and count | Audited pages and evidence |
| --- | --- | --- |
| 1 | Readable navigation, columns and document flow — 7/10 | Python, SQLite, Wikipedia, curl, Git, Mail Archive, FreeBSD. Before captures show stacked navigation/side panels or header flow displacing the article. Repairs combine finite float/flex flow, percentages, static hiding/selectors, root-relative sizes and inherited visibility. Mail Archive's recorded header becomes 119 px rather than 158 px, and its right-hand archive link moves from x=0 to x=757. |
| 2 | Meaningful JPEG/GIF content and intrinsic geometry — 4/10 | Wikipedia portrait JPEG; W3C's seven source GIF diagrams; Paul Graham's four source GIFs, including the title/navigation artwork; FreeBSD's daemon GIF. Hacker News also references two GIF spacers, but these are not counted as a fifth missing content image. |
| 3= | Live table geometry and legacy hints — 3/10 | Wikipedia: 20 table elements, 3 rowspan and 37 colspan attributes. Hacker News: 4 tables, 31 colspan and 4 cellpadding attributes. Paul Graham: 3 tables and 3 cellpadding attributes. Nested ownership, spans, intrinsic widths, percentage/legacy hints and centered table boxes matter. W3C has zero live table elements: its examples are escaped source and diagrams, so it does not inflate this count. |
| 3= | Real monospace code metrics — 3/10 | Python: 42 pre and 77 code elements; W3C: 51 pre elements; curl: 22 pre and 174 code elements. Dedicated Mono faces now supply both measurement and painting. These element counts overlap, so they are not counts of distinct code examples. |
| 5 | Leading stylesheet imports — 1/10 | Python's classic.css imports basic.css. The imported declarations must precede the owning sheet and count against the same fetch/deadline budget. |

The HTML counts come from an HTMLParser audit of the cached actual documents,
excluding escaped markup in examples. The CSS source map is
target/browser-pages/corpus/assets/map.tsv; the Mail Archive source was added
after that map and its flow evidence comes from the authenticated page layouts.

Character-set decoding, bounded gzip/zlib deflate, redirects and TLS refusals
have independent deterministic tests. This report does not invent corpus failure
counts for them or claim that a larger TLS profile was necessary for these ten.

## Per-page comparison with Chromium

The before→after column describes the final inspected evidence. Differences below
are remaining limits or visible styling differences, not claims of mainstream
pixel fidelity.

| Page | Before → after / integrated repair | One-line remaining mainstream difference |
| --- | --- | --- |
| [Python tutorial](https://docs.python.org/3/tutorial/introduction.html) | Closed mobile navigation and a large SVG placeholder buried the chapter; the article returns to a readable first view and code uses real Mono metrics. | Search/theme controls and SVG artwork are absent or simplified; form controls and script-driven interaction are outside the subset. |
| [SQLite About](https://www.sqlite.org/about.html) | Tall stacked menu and full-width summary displaced prose; compact navigation and a bounded right-hand summary leave readable article text. | The SVG logo/background artwork is absent, and native text metrics/spacing are larger than Chromium's. |
| [Tim Berners-Lee](https://en.wikipedia.org/wiki/Tim_Berners-Lee) | Unopened menus and accessibility text appeared before the article; static hiding, readable columns, table sizing and native JPEG decoding restore article access. | The SVG wordmark is absent and Vector navigation/grid is simplified; final tabs remain two vertical groups rather than Chromium's horizontal strip. |
| [W3C HTML 4 tables](https://www.w3.org/TR/html401/struct/tables.html) | The contents list was already readable; real Mono improves the source examples, and the deep capture displays the actual 301×140 GIF diagram. | The vertical black recommendation banner is absent and table/example border and font treatment is simplified. |
| [curl FAQ](https://curl.se/docs/faq.html) | Related links occupied the main flow; a right-hand related panel leaves the numbered contents readable. A focused regression also keeps two-digit labels inside a marginless viewport. | The SVG mark and shadow decoration are absent; text is larger and less dense. |
| [Git book](https://git-scm.com/book/en/v2/Getting-Started-About-Version-Control) | Stacked navigation and the language list pushed the article down; a side column leaves the chapter readable. | The serif/web-font chapter title uses native Sans, with simpler panel and navigation decoration. |
| [Hacker News](https://news.ycombinator.com/) | Wide sparse rows and inherited center alignment disrupted the news list; cell widths, cellpadding and table alignment restore distinct ranks, titles and subtext. | CSS-background upvote triangles are absent and row spacing is larger. |
| [How to Do Great Work](https://paulgraham.com/greatwork.html) | Placeholder artwork and weak table sizing lost the authored rail/article proportions; 69 px rail, 26 px spacer and 435 px article geometry plus GIF title artwork are retained. | GIF navigation image-map links are unsupported, and native Sans differs from Chromium's typography. |
| [pgsql-hackers archive](https://www.mail-archive.com/pgsql-hackers@postgresql.org/) | Header content stacked; the archive link now occupies its right-hand position above the thread list. | The search form is not implemented and native thread text is larger than Chromium's denser list. |
| [About FreeBSD](https://www.freebsd.org/about/) | Navigation/header flow consumed excessive vertical space; finite columns keep the article alongside its navigation. | The SVG header mark is absent and responsive navigation is simplified. |

## Images below the first viewport

The three extra before/after views use the same URLs and scroll positions from
[deep.tsv](deep.tsv), and retain [full-size pairs](../../shots/pages/pairs-deep/).
All six are actual compositor captures with zero differing pixels against their
native frames. See [before-deep](wayland-before-deep.log) and
[after-deep](wayland-after-deep.log).

| View | Scroll | Actual final image evidence |
| --- | ---: | --- |
| W3C table illustration | 2700 | mergedcells.gif decoded at 301×140 and visible beside the source example. The page's illustrated table is a GIF, not a live HTML table. |
| Git local version control | 800 | local.png decoded at 1008×861 and displayed at the available article width with its aspect ratio; centralized.png also decoded at 1182×822. |
| FreeBSD daemon | 850 | dae_up3.gif decoded at 72×81 and visible beside the “FreeBSD is free” paragraph. The unsupported SVG header remains a placeholder. |

I opened these compositor images, the final ten-pair sheet, individual final
Python/Wikipedia views, and the motion keyframes. The observations concern the
retained views; this is not an exhaustive screenshot audit of every scroll
position or a general CSS conformance claim.

## Verification and image evidence

The final completed command sh tools/pages-test.sh passed in 40.6 s. Its retained
docs/pages/offline-final.log starts with **ok 116 tests** and ends with
**PASS all offline real-page foundation gates**. The earlier completed integration
gate had 113 native tests; the final total includes the three reading-position
anchor regressions. The HTML/CSS source subset still contains 6 HTML and 28 CSS
tests. The full gate also runs authenticated HTTPS, Wayland peer/input, local
HTTP, resource authority, image, compressed-content and stylesheet-import checks.

The following groups remain separate because imported module tests overlap:

| Gate | Recorded result |
| --- | --- |
| Main browser | 116 native tests, plus the program case |
| HTML/CSS subset | 6 HTML + 28 CSS tests, included in the main suite |
| Capability probes | 20 expected rejections plus accepted source workarounds |
| Wayland peer/input | Input checks passed; 32 protocol requests |
| Fonts and visual goldens | 8 face hashes and 5 layout/pixel goldens |
| Crypto native suites | 18 primitive, 11 trace, 75 signature/hash, 11 X.509, 4 protocol, 16 full-trace tests |
| Certificate decisions | 31 decisions, 671 prefix truncations, trailing-data rejection |
| Local authenticated pages | 15 successful page cases and 8 expected error-page cases |
| Raster codecs | 3,246 decisions; 17 independent JPEG and 6 independent GIF references |
| HTTP content | 38 module tests; 30 independent cases, 23 loopback requests |
| CSS imports | 73 module tests; 11 independent HTTP/HTTPS scenarios |

Expected compiler diagnostics and NAV_ERROR lines belong to deliberate refusal
tests. Every test-owned peer was stopped. No public network is needed for this
gate once the pinned compiler and recorded fonts are present.

Image reflow now anchors the first visible text node and rendered byte position,
preserving its signed screen offset after intrinsic dimensions change. Three new
regressions cover the same source appearing above/current viewport, a partly
clipped Unicode fragment changing its wrap, and initial navigation staying at
scroll zero. With no visible text, ordinary scroll clamping remains. Only image
reflow uses the new anchor path.

The five original before/after fixture PNG files are byte-for-byte identical,
verified by direct byte comparison and SHA-256, not merely equal file sizes.
Paths are target/browser-pages/goldens-before/ and goldens-after/.

| Fixture | Identical PNG SHA-256 |
| --- | --- |
| simple | 7b51fb93da991883ffdcd58d9332aeee7723285f001d9117045bb10581fcc64c |
| article | 2864020c6c19d5a2f6046d14a45222b9e0dc99fc6116c216f6c9156dfc45c197 |
| scrolled | 961cd0c32dd1278443676d90fb357e46096c71e9a5ca3b9adc6c99f85bf05b0d |
| narrow | dbd7efb42799715089b64a0ca59239bd2a0c557792d0c11ea48d734e8c4813b8 |
| error-fixture | 446a9f3e6c616bd616e91002a4faf44710c1858e23894a1e76dc5f56e29550ba |

Native image tests record 3,246 decisions. Stored independent RGB witnesses cover
baseline/progressive JPEG and GIF; no independent codec is needed to rerun the
offline gate. The actual Wikipedia 250×187 portrait differs from the independent
decoder by at most 4/255 per channel, mean 0.255736. Four retrieved source GIFs
(W3C merged cells, W3C rowspan, Paul Graham title, FreeBSD daemon) have exact
composited RGB and alpha agreement. See docs/images-corpus.tsv,
docs/images-verification.log and docs/images.md. Codec validation is separate
from proving an image was scrolled into the live page viewport.

A frozen Wikipedia CSS comparison of this slice's extended matcher before and
after rule indexing used 10,767 nodes and 1,949 rules. Computed-style
time fell from 17,466,694 us to 1,774,554 us including the rule index, about 9.84×
faster. The frozen command count, height and encoded PNG byte count were equal;
this is not a pixel-hash or end-to-end latency claim, nor a measurement of the
older ecac370 matcher. Cached DOM/styles also avoid repeating selector matching
during intrinsic-image reflow; the isolated cached reflow was about 21 ms.
Details are in [render-performance.md](../render-performance.md).

## Final navigation timings

The values below are CLI-navigation-to-Wayland-submit elapsed seconds from the
actual before/after logs. They include public-network work, authentication,
resources and rendering. They measure submission, not scanout, and are single
observations rather than benchmark distributions. Python, SQLite and Hacker News
were slower in the final sample, so no universal latency improvement is claimed.
The final native executable SHA-256 is
b6b9ea6f957c16b5838e051c31e8b50e8b5185e439add47426e6c69ab2b75eba.

| Page | Before | Final after |
| --- | ---: | ---: |
| Python | 0.908 | 0.967 |
| SQLite | 3.037 | 3.384 |
| Wikipedia | 12.438 | 5.597 |
| W3C | 2.330 | 2.126 |
| curl | 0.794 | 0.715 |
| Git | 2.354 | 1.976 |
| Hacker News | 2.585 | 3.158 |
| Paul Graham | 3.254 | 1.953 |
| Mail Archive | 1.724 | 1.420 |
| FreeBSD | 1.411 | 1.225 |

Exact integer microseconds and URLs are retained in [timings.json](timings.json).
The isolated CSS timing above answers a different question and is not substituted
for these complete navigation observations.

## Continuous input, scroll and link proof

The current [scroll-and-link.apng](../../shots/scroll-and-link.apng), also saved as
[https-first.apng](../../shots/https-first.apng), contains **30 real compositor
frames**, nominal **400 ms** each, at **1000×760**. One native process starts at the
welcome page, receives Ctrl+L and typed key events for https://www.kernel.org/,
navigates on Enter, scrolls through and below the release table, returns Home,
clicks About, and scrolls the destination body.

The final layout put About at x286..334 and document y156..176. With the unchanged
52 px toolbar, the replay click is **(310, 218)**. I inspected the welcome,
scrolled-page and linked-destination frames. The final compositor/native
comparison has zero differing pixels. This is application-event replay, not a
claim of physical hardware input.

[wayland-pages-final.log](../tls/wayland-pages-final.log) retains the exact input,
frame timing, authentication and pixel proof. The replay and all 30 frames are in
[https-motion-pages-final](../../shots/https-motion-pages-final/). Both current
APNG aliases contain 1,678,704 bytes and have SHA-256
09bc16ef8764b2ad8b645b11beccb650ed47410774f01f945331ebe66f343c3b.
Capture-owned browser, bridge, compositor and screenshooter processes were reaped.

## Exact remaining limits

- **HTML/CSS/layout:** selected optional closes and static selectors, not the full
  HTML5 builder or CSS cascade. No JavaScript, forms, custom properties,
  grid, generated text, full inline-block, positioning or flex algorithm. Complex
  functional-selector arguments and interactive pseudo-states are unsupported.
  Widths/margins/padding resolve percentages; ex is an approximate half-font-size.
  The flex readability fallback clamps negative horizontal item margins to zero,
  preserves minimum boxes and stacks crowded rows. Outside lists reserve only
  the extra viewport gutter needed by their marker. Tables are capped at 64
  columns; CSS collapsed borders and CSS vertical-align remain absent, while
  legacy HTML valign works. General SVG/background artwork and clipping are absent.
- **Stylesheets and network content:** four distinct external sheets across links
  and imports, one MiB per sheet, four MiB expanded CSS, 1,024 expansion attempts,
  one shared three-second child-process deadline. Imports preserve source order
  and final redirected base URLs. Print/unsupported media, imported layers,
  supports(), escaped URL tokens and downloaded fonts are unsupported. Gzip and
  zlib-wrapped deflate are bounded; Brotli and HTTP/2 are absent. UTF-8, UTF-16 and
  windows-1252 do not imply arbitrary legacy-encoding coverage.
- **Fonts:** four Sans and four Mono faces share measurement/paint metrics, with
  optional system/override Mono selection and explicit Sans fallback. No separate
  serif family, web fonts, shaping, bidi, kerning or per-glyph fallback. This
  remains a Latin-focused reading corpus.
- **Images:** supported PNG is non-interlaced 8-bit; JPEG is 8-bit Huffman DCT
  baseline/extended sequential/progressive in grayscale/RGB/YCbCr. CMYK/YCCK,
  arithmetic/lossless/12-bit JPEG, EXIF orientation and ICC management are absent.
  GIF displays only its first composited frame. SVG provides bounded root-header
  dimensions and an alt placeholder, not rasterized pixels. Standalone JPEG/GIF inputs are
  bounded to 32 MiB, 4096 px per axis and 8,388,608 pixels; network bodies retain
  their stricter 16 MiB cap, with further codec work
  and storage caps documented in docs/images.md.
- **TLS/runtime:** unchanged restricted TLS 1.3, AES-128-GCM/SHA-256 and X25519
  agreement; ECDSA P-256/P-384 and RSA-PSS SHA-256/SHA-384 handshake signatures,
  supported RSA 2048–4096/P-256/P-384 certificates, explicit root trust and
  chain/name/time checks. Unsupported profiles fail closed. No TLS 1.2, HTTP/2,
  resumption, 0-RTT, client certificates, revocation/CT policy or constant-time
  implementation claim. P-256 signature verification is not P-256 key agreement.
  TCP connect still lacks a runtime deadline; optional stylesheets have child
  isolation, but main-document/image connects can stall before response deadlines.
  Native Unix sockets/descriptor transfer still require the documented transport
  bridge. GAPS.md preserves rejecting probes and accepted source rewrites.

The HTML/CSS, table, typeface, image and TLS profile documents carry the detailed
contracts. General CSS fidelity, runtime socket/deadline barriers and shaping
remain separate from the improvements demonstrated by these ten pages.

## Review cycles and reproducibility

The early r1 pass exposed thin-column regressions. Intrinsic line/image/padding
measurement and float clearance repaired them before r2. Independent review then
found double application of percentage widths, overlapping padded flex items,
negative flex margins touching adjacent labels, and image growth moving the
reading position. Focused regressions accompany those corrections. The final
capture follows the completed 116-test gate.

The baseline source and executable were frozen from ecac370 before edits.
The pre-existing target binary was stale relative to that source and was not
used as the baseline. An initial multi-page Weston process crashed late in the
baseline round; the retained proof records that attempt and the successful
resume. The final harness uses one fresh owned compositor per page.

Reproduce with the pinned compiler and the existing locally unpacked Weston tools:

~~~sh
sh tools/pages-test.sh
bash tools/capture-pages.sh --round after
bash tools/capture-pages.sh --manifest docs/pages/deep.tsv --count 3 --round after-deep
node tools/pages-contact.cjs after
bash tools/capture-https.sh --motion tests/https-demo.live about:welcome \
  --round pages-final --frames 30 --delay-ms 400
~~~

The contact-sheet assembler needs Sharp as a proof-only dependency; set
LKJBROWSER_SHARP to an existing module path if it is not installed at the
documented fallback location. The native browser never executes that tool.
The capture harness can use the frozen baseline via --binary and --source-root.
Source hashes include every lkjscript submodule and the compiler pin.

The factual welcome phrase changed from “PNG pictures” to “pictures” after the
proposal to the lead; its style and all chrome remain unchanged. The run adds
no site-specific hiding rules, foreign runtime codecs, deployment or system
installation. Work is committed locally; the lead owns publication of main.
