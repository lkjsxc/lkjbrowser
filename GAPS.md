# Observed language and library gaps

Pinned compiler: **2026.11.17-e6d13590b**,
commit **e6d13590b7bb2d665d668727f1a8d1ee4f76c33d**,
SHA-256 **60149069984ecfe491e322eba406238555c13acc90375c5468e5d5d4954a83ca**.

This ledger separates runtime capabilities, source forms and reusable source libraries.
Counts are integration sites encountered during this run, not a count of every missing
API or a claim that the current rewritten code still fails. Browser defects fixed during
review—CSS arithmetic, specificity, HTTP validation, origin policy and font bounds—are
not language gaps.

## Ranked observed barriers: top ten

| Rank | Kind and missing form | Sites | What it blocked | Smallest witness / current treatment |
| --- | --- | ---: | --- | --- |
| 1 | Runtime: nonblocking/deadline TCP connect | 1 | A bounded connection handshake; synchronous navigation can stall before the six-second response timer starts | `connector.connect_deadline(deadline)` rejects in `probes/connect-deadline.lkj`. Read/write deadlines work after connect. |
| 2 | Runtime: Unix stream connection by authorized path | 1 | A direct Wayland connection | `world.unix_connect(path)` rejects in `probes/unix-socket.lkj`; temporary transport bridge. |
| 3 | Runtime: descriptor send **and receive** on an owned socket | 2 boundaries | Sending the wl_shm backing file and receiving a compositor keymap | `stream.send_file(file)` rejects in `probes/send-descriptor.lkj`; bridge sends a frame descriptor and closes received descriptors. |
| 4 | Source library: authenticated TLS/PKI | 1 navigation boundary | HTTPS pages | `use std::tls;` rejects in `probes/tls-library.lkj`. TCP/entropy/clock/files already suffice to start an implementation; this is not a demand for foreign TLS. |
| 5 | Runtime authority: deriving arbitrary destinations without World | 1 | A useful restricted network grant for user-selected navigation | `connector.for_destination(address, port)` rejects in `probes/destination-authority.lkj`. The current entry explicitly uses full World authority. |
| 6 | Source configuration: a cfg(test) helper used by a test | 1 definition, 5 original callers | Normal organization of layout test fixtures | Complete negative `probes/html-cfg-test.lkj`; the pin intentionally excludes the helper even under test. Unconditional pure helper is the workaround. |
| 7 | Source ownership: nested view-returning matches across a loop continue | 1 | A natural UTF-8 replacement loop | 17-line negative `probes/html-loop-view.lkj`, E_BORROW at the continue. `html-loop-view-workaround.lkj` completes the outer match into a scoped owned bool first and is accepted. |
| 8 | Source ownership: temporary slice loan during owner replacement | 1 | Compacting the Wayland incoming byte buffer | `v = v[n..].to_vec()` rejects with E_BORROW in `probes/owner-replacement.lkj`. An explicit block returning the owned copy ends the view before assignment; see `docs/wayland.md`. |
| 9 | Source library forwarding: array.to_vec | 2 | Straightforward byte-array copying in HTTP/PNG tests | `b"abc".to_vec()` rejects in `probes/array-to-vec.lkj`; `b"abc"[..].to_vec()` works. |
| 10 | Source inference: typed empty slice argument | 2 | Empty argument arrays in protocol test messages | `fn f(_: &[u32]) {}; f(&[])` rejects in `probes/empty-slice.lkj`; `&[0u32; 0]` works. |

The proposed API names in rows 1–3 and 5 are illustrative smallest shapes, not existing
promises or reasons to add raw descriptor integers. The negative probes are checked against
the exact binary. Documentation and the capability inventory establish the absent facility;
a missing guessed spelling alone would not establish that.

The direct connect API is a runtime gap, but an owned child process can isolate a fetch
with existing capabilities. The current UI has not yet adopted that architecture. Do not
describe its post-connect timer as a total navigation deadline.

## Further encountered gaps and limits

| Rank | Kind / form | Sites | Consequence and supported route |
| --- | --- | ---: | --- |
| 11 | Source library forwarding: String.strip_prefix | 1 | Fixture server used `value.as_str().strip_prefix(...)`; negative `probes/string-strip-prefix.lkj`. |
| 12 | Source library: shaping, bidi and fallback fonts | 1 text pipeline | Unicode decoding and cmap lookup work, but complex scripts and missing characters need reusable layout/fallback libraries. No new OS authority is needed for those algorithms. |
| 13 | Source library and input authority: XKB/IME | 1 keyboard pipeline | Physical US-key text input is implemented. Full keyboard text needs the received keymap descriptor, a source keymap/text implementation and later IME protocol work. |
| 14 | Runtime: writable shared region | 0 required; 1 proposed optimization | `file.map_writable()` rejects in `probes/writable-mapping.lkj`. The working browser uses seek/write plus release ownership, so this is not a first-window blocker. |
| 15 | Runtime: IPv6/UDP | 1 HTTP address parser, 1 DNS design choice | The pin exposes numeric IPv4 TCP. This browser uses DNS over TCP; IPv6/UDP are not hidden in the bridge. |

Runtime font parsing, PNG/DEFLATE, HTTP client framing, HTML and layout were missing reusable
components at the beginning of the run. They are now ordinary lkjscript modules here. They
did not require another language or compiler changes. CFF outlines, additional PNG formats,
full HTML recovery and wider CSS remain application/library work, detailed in the module docs.

## Exact distinction for the loop refusal

The earlier `probes/loop-view.lkj` is **accepted**. It omits the outer Result match and is
not negative evidence. The reduced rejecting case has an outer UTF-8 Result, a loop in the
Err arm, and another view-returning Result match whose success arm continues the loop.
No mutation of the input or live bound payload reference is needed. Both the rejecting
case and the accepted scoped rewrite are retained.

Run `sh tools/probe-gaps.sh` to reproduce the compiler refusals and the positive rewrites.
The broader standard-library absence for shaping/IME is a design inventory, not a fabricated
compiler error.

## Temporary bridge and its removal

`bridge/byte_descriptor_bridge.c` is a freestanding syscall-only transport. It opens one
explicit Unix socket and the supplied frame file, binds a fresh loopback TCP port, forwards
opaque payloads, attaches that descriptor when the browser requests it and closes received
descriptors. It neither recognizes a Wayland opcode nor parses, lays out, decodes or paints
a page. It has no libc, Wayland library, font library or codec dependency.

The native lkjscript program owns Wayland IDs/state, registry binding, xdg-shell, shm buffers,
release tracking, cursor data, pointer/keyboard decoding, HTTP/DNS, HTML/CSS, layout, glyph
rasterization and every pixel. The bridge is an acknowledged exception to a wholly-lkjscript
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

OPINION: Array-to-slice forwarding, typed empty-slice inference and String-to-str forwarding
are small high-frequency conveniences. They matter to large source programs but did not stop
this browser.

OPINION: Treat TLS/PKI, shaping and keymaps as reusable lkjscript library work. Keep browser
implementation defects in this repository rather than presenting them as compiler defects.
