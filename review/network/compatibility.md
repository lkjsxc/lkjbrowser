# Network compatibility and existing coverage

Static review of `src/net.lkj`, its five embedded test functions, `tools/test.sh`,
`src/fixture_server.lkj`, and the existing navigation scripts. No builds, test
traffic, new test cases, or runtime verification were performed for this review.

Source snapshot: `src/net.lkj` SHA-256
`d1dce471ab3d8ab3bceb036e7981d2f4412954a6170769002e2fd4870aa22cac`.
The implementation is being edited concurrently, so this identifies the reviewed version.

## Ordinary behavior covered by existing tests

| Behavior | Existing coverage |
| --- | --- |
| HTTP address with explicit port, query and fragment | `net::urls` checks the parsed port; other component values are not individually asserted. |
| Local-file paths with percent-encoded spaces | `net::urls` checks decoding; fixture renders use absolute local-file URLs. |
| Parent-directory relative links and empty references | `net::urls` and `net::reference_resolution`; the latter also covers dot segments, repeated path separators and retaining an explicit scheme. |
| Decimal Content-Length response | `net::framing`; the local HTTP article render is compared with the same document loaded from a file. |
| Chunked response with multiple chunks and a trailer | `net::framing`, `net::incremental_chunks`, and the fixture server's chunked article. The incremental test checks every byte prefix. |
| Relative HTTP redirect | The fixture server returns a 302 with a relative Location; its resulting layout and document pixels are compared with the article. |
| HTTP PNG subresource and plain-text media type | Existing HTTP/file image comparison; plain-text rendering is compared across media-type letter case. |
| Link click, back navigation and typed address | Existing click, history and typed-address scripts, with document-layout or resulting-address checks. |

These are coverage observations, not a claim that this review executed the gate.

## Implemented paths without focused ordinary coverage

The source handles HTTP/1.0 status lines, close-delimited bodies, informational
responses, empty 204/304 responses, and redirect statuses 301/303/307/308. The
reviewed gate principally exercises HTTP/1.1, Content-Length/chunked framing and
302 redirects. The fixture server defines an empty-response endpoint, but the
gate does not request it.

DNS uses TCP and IPv4 A records. The fixture traffic uses numeric loopback
addresses, so it provides no DNS-response or hostname-resolution coverage.

## Remaining ordinary compatibility limits

- HTTPS, IPv6, IDNA host conversion, HTTP authentication, cookies, connection
  reuse and content decompression are absent. Requests advertise identity
  encoding and close the connection; compressed responses return an error.
- Accepted transfer coding is a single chunked coding. Combined coding chains
  and comma-combined Content-Length field values are unsupported.
- Header blocks must decode as UTF-8. The source does not provide a separate
  byte-oriented treatment for other header-value encodings.
- Scheme matching in URL parsing is case-sensitive. File URL queries are not
  separated from filesystem paths. Fragment text in path-relative references
  also needs independent handling before path normalization.
- DNS uses the first suitable IPv4 resolver, has no cache or separate alias
  follow-up, and does not accept trailing-dot hostnames. Only localhost gets
  a local name shortcut.
- Response I/O has an absolute six-second deadline and document-size limits;
  the initial connection remains blocking under the pinned capability API.

The current normal-path coverage is strongest for local files and numeric-IPv4
HTTP pages, with deterministic layout/pixel comparisons. Hostname navigation,
additional response framing paths and broader URL compatibility remain less
established by the existing tests.
