# HTTP content and stylesheet imports

The pages slice keeps all runtime work in lkjscript. HTTP framing and authenticated
transport still finish before content decoding. `src/net/content.lkj` supplies
bounded gzip, zlib-wrapped HTTP deflate, and a small document-encoding subset.
The existing PNG DEFLATE core now also exposes a raw stream plus consumed-byte
count; PNG retains its exact zlib envelope and Adler-32 checks.

## HTTP bodies

Requests advertise only `gzip, deflate`. Content-Encoding fields are combined in
wire order and decoded in reverse, with at most four layers. Gzip checks its magic,
method, reserved flags, optional header checksum, content CRC-32 and uncompressed
size. Optional name/comment/extra headers and concatenated members work. There are
at most sixteen members and a 64 KiB header budget per member. The existing raw
DEFLATE work bound is 8,192 blocks per stream.

The sixteen-MiB document/image byte policy applies to both received encoded bytes
and every expanded layer. Stylesheets use one MiB instead. Checks precede appending
beyond the limit. Chunk framing and Content-Length still describe the encoded
wire body; they are not confused with expanded length. Raw, unwrapped deflate and
unsupported codings such as Brotli are refused, rather than treated as text.

Specifications: [RFC 1952](https://www.rfc-editor.org/rfc/rfc1952),
[RFC 1951](https://www.rfc-editor.org/rfc/rfc1951) and
[RFC 1950](https://www.rfc-editor.org/rfc/rfc1950).

## Text

`net::document_text(body, content_type)` returns decoded UTF-8 or a plain unsupported
encoding error. UTF-8/UTF-16 byte-order marks take precedence. An HTTP charset
parameter takes precedence over an HTML meta declaration scanned in the first
1,024 bytes. Supported labels cover UTF-8, UTF-16LE/BE, and windows-1252 with the
common ASCII/Latin-1 aliases; invalid UTF-16 surrogate sequences become U+FFFD.
The windows-1252 punctuation mapping follows the
[WHATWG Encoding Standard](https://encoding.spec.whatwg.org/).

Unlabelled valid UTF-8 remains UTF-8. Unlabelled invalid UTF-8 is read as
windows-1252. This is an explicit limited detection policy, not an implementation
of every browser's encoding detector. Explicit unsupported encodings fail instead
of silently substituting another encoding. The HTML prescan is bounded and is not
a complete HTML5 encoding algorithm. CSS worker bodies use the same BOM/HTTP
charset handling; CSS `@charset` detection is not claimed.

## Ordered stylesheet imports

`resources::stylesheets` owns one batch for linked, inline and imported CSS.
The limits remain four distinct requested stylesheet URLs, one MiB per decoded
sheet, four MiB of assembled CSS, and one absolute three-second deadline for all
external fetch workers. Imports count against that same four-URL budget.

A leading `@import "file.css"` or `@import url("file.css")` is expanded in place.
Supported screen/width media conditions select imports without fetching print-only
or nonmatching sheets. Imports after ordinary style rules are not fetched. Quoted
or simple unquoted URLs work; escaped URL tokens, import layers and supports()
conditions remain outside the subset.

Fetched successes and failures are cached for the batch. Successful bytes are
expanded again at every source occurrence so repeated links/imports preserve
cascade order. Request and final redirected URLs take part in cycle checks.
Relative imports resolve against the final stylesheet URL returned by the worker,
including redirects. A 1,024-occurrence expansion budget bounds pathological
cached import graphs as well as the four-MiB output policy.

HTTPS documents and HTTPS sheets do not import HTTP resources. A stylesheet
received from the web cannot import a local file even when its parent document
was a user-opened local file. URL checks apply before cache replay, and the existing
per-fetch redirect/file/TLS checks remain active. Child workers still use the same
native executable and are killed and reaped at the shared deadline. An unavailable
sheet leaves later inline styles and readable document content available.

## Deterministic checks

```sh
sh tools/content-test.sh
sh tools/styles-test.sh
```

The first command ran 38 native module tests and 30 independent content cases:
gzip stored/fixed/dynamic blocks, optional headers, concatenation, checksums,
truncation, excessive expansion, layered codings, chunked HTTP and redirects,
plus encoding precedence, UTF-16, legacy punctuation and unsupported encodings.
The test peer uses Node/zlib only to generate and serve independent fixtures.
It is never part of the browser.

The stylesheet command ran 67 native module tests and eleven HTTP/HTTPS scenarios.
They establish import/cascade order, cycles, repeated cached sheets, the four-URL
budget, media/placement, redirected relative bases, compressed/legacy CSS,
local-file and mixed-content refusal, decoded size bounds, and one shared deadline
through a delayed nested import. The observed nested deadline was 3,000,378 us;
the two delayed imports did not each receive a fresh three seconds. Module counts
can grow as the shared parser tests grow; they are not independent security claims.

Every test listener uses loopback and an ephemeral port and is stopped by its
owner. Current raw logs live in `target/browser-pages-network/`.
