# Observed language and library gaps

Pinned compiler: **2026.11.17-e6d13590b**,
commit **e6d13590b7bb2d665d668727f1a8d1ee4f76c33d**,
SHA-256 **60149069984ecfe491e322eba406238555c13acc90375c5468e5d5d4954a83ca**.

This ledger preserves three kinds: **runtime capabilities**, **source forms** and
**reusable source libraries**. Configuration, ownership and inference are source forms;
authority restrictions belong to runtime capabilities.
Counts are integration sites encountered during this run, not a count of every missing
API or a claim that the current rewritten code still fails. Browser defects fixed during
review—CSS arithmetic, specificity, HTTP validation, origin policy and font bounds—are
not language gaps.

## Ranked observed barriers: top ten

| Rank | Kind and missing form | Sites | What it blocked | Smallest witness / current treatment |
| --- | --- | ---: | --- | --- |
| 1 | Runtime: nonblocking/deadline TCP connect | 1 direct connection boundary | Main-document/image navigation can stall before the six-second response timer starts | `connector.connect_deadline(deadline)` rejects in `probes/connect-deadline.lkj`. Read/write deadlines work after connect; an owned child now bounds optional stylesheets only. |
| 2 | Runtime: Unix stream connection by authorized path | 1 | A direct Wayland connection | `world.unix_connect(path)` rejects in `probes/unix-socket.lkj`; temporary transport bridge. |
| 3 | Runtime: descriptor send **and receive** on an owned socket | 2 boundaries | Sending the wl_shm backing file and receiving a compositor keymap | `stream.send_file(file)` rejects in `probes/send-descriptor.lkj`; bridge sends a frame descriptor and closes received descriptors. |
| 4 | Runtime authority: deriving arbitrary destinations without World | 1 | A useful restricted network grant for user-selected navigation | `connector.for_destination(address, port)` rejects in `probes/destination-authority.lkj`. The current entry explicitly uses full World authority. |
| 5 | Source form, configuration: a cfg(test) helper used by a test | 1 definition, 5 original callers | Normal organization of layout test fixtures | Complete negative `probes/html-cfg-test.lkj`; the pin intentionally excludes the helper even under test. Unconditional pure helper is the workaround. |
| 6 | Source form, ownership: nested view-returning matches across a loop continue | 1 | A natural UTF-8 replacement loop | 17-line negative `probes/html-loop-view.lkj`, E_BORROW at the continue. `html-loop-view-workaround.lkj` completes the outer match into a scoped owned bool first and is accepted. |
| 7 | Source form, ownership: temporary slice loan during owner replacement | 1 | Compacting the Wayland incoming byte buffer | `v = v[n..].to_vec()` rejects with E_BORROW in `probes/owner-replacement.lkj`. An explicit block returning the owned copy ends the view before assignment; see `docs/wayland.md`. |
| 8 | Source library forwarding: array.to_vec | 2 | Straightforward byte-array copying in HTTP/PNG tests | `b"abc".to_vec()` rejects in `probes/array-to-vec.lkj`; `b"abc"[..].to_vec()` works. |
| 9 | Source form, inference: typed empty slice argument | 2 | Empty argument arrays in protocol test messages | `fn f(_: &[u32]) {}; f(&[])` rejects in `probes/empty-slice.lkj`; `&[0u32; 0]` works. |
| 10 | Source library: str.split_ascii_whitespace | 1 linked-stylesheet rel-tokenization site | Ordinary ASCII-separated attribute words | `"alternate stylesheet".split_ascii_whitespace()` rejects in `probes/tls-split-ascii-whitespace.lkj`; the browser uses the explicit ASCII scanner in `css::words`. |

The proposed API names in rows 1–4 are illustrative smallest shapes, not existing
promises or reasons to add raw descriptor integers. The negative probes are checked against
the exact binary. Documentation and the capability inventory establish the absent facility;
a missing guessed spelling alone would not establish that.

The direct connect API remains a runtime gap. The browser now uses an existing-capability
workaround for **optional linked/imported stylesheets only**: a same-executable native child,
anonymous temporary files and a parent-enforced three-second deadline shared by the
whole batch. At most four distinct URLs are fetched, each bounded to one MiB; cached
results are applied in source order within the four-MiB aggregate CSS limit. The parent
kills and reaps an unfinished child, so a stylesheet blocked inside connect cannot
hold up text indefinitely. Main-document and image fetches remain synchronous.
Do not describe their post-connect timer as a total navigation deadline.

The positive `probes/owned-resource-child.lkj` demonstrates `World.executable()`,
`Process.spawn_file`, retained anonymous output files, bounded reads, `Child.try_wait`,
deadline termination/reaping and owned-child cleanup. An empty `Readiness.wait` supplies
the short bounded wait between polls; it needs no child-readiness API or new runtime
capability. This is a native lkjscript resource worker, not an external HTTP/TLS helper.

## Resolved browser blocker: authenticated TLS/PKI

The pinned library still rejects `use std::tls;` in `probes/tls-library.lkj`.
That exact absence remains recorded, but it no longer blocks this browser's HTTPS:
`src/crypto/` now implements reusable authenticated TLS 1.3, X25519, AES-128-GCM,
DER/X.509, system-root chain validation and RSA/P-256/P-384 signatures in lkjscript.
The browser verifies the original URL host and certificate validity against system time
before releasing application data.
No compiler change, new standard-library import or foreign TLS process produced that result.

This is a restricted public-page profile, not complete TLS/certificate-policy coverage.
P-256 key agreement, wider suites, revocation and several certificate constraints remain
unimplemented; unsupported required constraints fail closed. Emitted constant-time
behavior and reliable secret erasure have not been established. See
[the protocol profile](docs/tls-protocol-profile.md),
[certificate policy](docs/tls-x509-profile.md) and
[remaining work](docs/next-tls.md). Reusable source-library packaging is a follow-up;
it is distinct from the retired browser implementation blocker.

## Further encountered gaps and limits

| Rank | Kind / form | Sites | Consequence and supported route |
| --- | --- | ---: | --- |
| 11 | Source form: named function item as a Result callback | 1 resource-worker I/O helper | `result.map_err(io_error)` rejects with E_TYPE in `probes/function-item-map-err.lkj`; the explicit typed closure in `probes/function-item-map-err-workaround.lkj` is accepted. |
| 12 | Source library forwarding: String.strip_prefix and String.parse | 2 | Use an explicit `as_str()` view. Negatives: `probes/string-strip-prefix.lkj` and `probes/pages-net-string-parse.lkj`; the latter accepts in `pages-net-accepted.lkj`. |
| 13 | Source library: shaping, bidi and fallback fonts | 1 text pipeline | Unicode decoding and cmap lookup work, but complex scripts and missing characters need reusable layout/fallback libraries. No new OS authority is needed for those algorithms. |
| 14 | Source library and input authority: XKB/IME | 1 keyboard pipeline | Physical US-key text input is implemented. Full keyboard text needs the received keymap descriptor, a source keymap/text implementation and later IME protocol work. |
| 15 | Runtime: writable shared region | 0 required; 1 proposed optimization | `file.map_writable()` rejects in `probes/writable-mapping.lkj`. The working browser uses seek/write plus release ownership, so this is not a first-window blocker. |
| 16 | Runtime: IPv6/UDP | 1 HTTP address parser, 1 DNS design choice | The pin exposes numeric IPv4 TCP. This browser uses DNS over TCP; IPv6/UDP are not hidden in the bridge. |
| 17 | Source form policy: string views in owned arrays | 2: image fixtures and list marker strings | Static `[&str; N]` rejects with E_BORROW in `image-view-array.lkj`; an owned `Vec<String>` is explicit and accepted in `image-owned-vec-workaround.lkj`. |
| 18 | Source library: owned-array IntoIterator | 1 image fixture loop | `[String; N]` in a for loop rejects E_TRAIT in `image-owned-array-iteration.lkj`; the owned vector probe is accepted. |
| 19 | Source inference: String/view comparison after a match and loop | 1 CSS attribute matcher | The thirteen-line `string-match-loop-compare.lkj` rejects E_TYPE. Its `item.as_str() == desired` counterpart accepts. Ordinary isolated String comparisons can work; this is the precise inference context. |
| 20 | Source inference: late binding and collection element type | 2 stylesheet helpers | `pages-net-late-type.lkj` needs an explicit `String`; `pages-net-collection-type.lkj` needs `Vec<String>`. Both supported spellings are in `pages-net-accepted.lkj`. |

Runtime font parsing, PNG/DEFLATE, JPEG/GIF, gzip and text decoding, HTTP client framing,
HTML, layout and TLS/PKI were missing reusable components at the beginning of their
respective slices. They are now ordinary lkjscript modules here. They
did not require another language or compiler changes. CFF outlines, additional PNG formats,
full HTML recovery and wider CSS remain application/library work, detailed in the module docs.

## Exact distinction for the loop refusal

The earlier `probes/loop-view.lkj` is **accepted**. It omits the outer Result match and is
not negative evidence. The reduced rejecting case has an outer UTF-8 Result, a loop in the
Err arm, and another view-returning Result match whose success arm continues the loop.
No mutation of the input or live bound payload reference is needed. Both the rejecting
case and the accepted scoped rewrite are retained.

Run `sh tools/probe-gaps.sh` to reproduce the compiler refusals, the two positive
loop-view rewrites and the explicit-closure callback workaround. The separate owned-child capability witness is executable with:

```sh
.toolchain/lkjscript build probes/owned-resource-child.lkj -o target/browser-owned-resource-child
target/browser-owned-resource-child
```

The broader standard-library absence for shaping/IME is a design inventory, not a fabricated
compiler error.

## Temporary bridge and its removal

`bridge/byte_descriptor_bridge.c` is a freestanding syscall-only transport. It opens one
explicit Unix socket and the supplied frame file, binds a fresh loopback TCP port, forwards
opaque payloads, attaches that descriptor when the browser requests it and closes received
descriptors. It neither recognizes a Wayland opcode nor parses, lays out, decodes or paints
a page. It has no libc, Wayland library, font library or codec dependency.

The native lkjscript program owns Wayland IDs/state, registry binding, xdg-shell, shm buffers,
release tracking, cursor data, pointer/keyboard decoding, HTTP/DNS/TLS and certificate
authentication, HTML/CSS, layout, glyph rasterization and every pixel. The bridge is an acknowledged exception to a wholly-lkjscript
launch path.

A replacement shape is:

```rust
let mut socket = directory.unix_connector("wayland-0")?.connect()?;
socket.send_message(bytes, files)?;
let message = socket.receive_message(byte_limit, descriptor_limit)?;
```

Exact partial-send, ownership transfer, excess-descriptor rejection, close-on-failure,
readiness and deadline semantics belong in that API contract. Numeric descriptors must not
become forgeable source authority. Frame pixels can keep using existing file writes.

## Opinions for the language streams

OPINION: Add readiness-based nonblocking connect with an absolute deadline. It removes the
remaining unbounded direct network operation; do not confuse the existing response deadline
with connection establishment.

OPINION: Add a confined UnixConnector derived from a Directory/path authority and typed
send_message/receive_message operations carrying owned File capabilities. These remove the
entire temporary transport bridge, including the keymap receive gap.

OPINION: Defer writable shared mapping behind those capabilities. Current file writes and
release tracking already prove correct wl_shm presentation.

OPINION: Provide a restricted affine network authority that derives exact destinations at
runtime, so a browser can navigate without its present World entry.

OPINION: Support cfg(test) while compiling test entries, and consistently exclude test-only
bodies during ordinary builds. The small helper/test example is enough to expose the current
source-configuration restriction.

OPINION: Improve temporary-view cleanup at loop backedges and owner replacement, preserving
the inactive Err payload state. Keep the accepted lexical-block rewrite and useful fix-its;
no unsafe escape or weaker ownership rule is needed.

OPINION: Array-to-slice forwarding, typed empty-slice inference, String-to-str forwarding
and an ASCII-whitespace iterator are small high-frequency conveniences. They matter to
large source programs but did not stop this browser.

OPINION: Package the now-working TLS/PKI modules as reviewed reusable lkjscript library
work; keep their restricted profile and cryptographic assurance limits explicit. Shaping
and keymaps remain source-library work. Keep browser implementation defects in this
repository rather than presenting them as compiler defects.

## Pages slice checkpoint

The ten-page work retained the same published pin and unchanged byte/descriptor bridge.
No new runtime capability was required for JPEG/GIF, compressed HTTP, text encodings,
stylesheet imports, table spans, monospace typefaces or cached semantic layout.
The small source restrictions above have rejecting witnesses and explicit accepted
rewrites; none was hidden behind another language.

The compiler stream owns deadline connect and Unix/descriptor capabilities. The lead
said an exact published pin and probes would be handed over when ready. Until that
handoff actually arrives, the rank 1–3 witnesses remain negative at this exact pin.
A future capability's existence is not inferred from a branch or a proposed API name.
