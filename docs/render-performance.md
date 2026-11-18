# Cached Wikipedia rendering diagnosis

This is a read-only timing investigation of the pages slice's first integrated
Wikipedia capture. It made no public requests and did not edit shared CSS, HTML,
layout, application or font implementation files.

The test used cached `wikipedia.html` (625,733 bytes) and its two captured external
stylesheets. The combined CSS, including document style elements, was 235,832 bytes.
The parsed input had 10,767 nodes and 1,949 rules.

The isolated harness separates HTML parsing, rule parsing, CSS matching/cascade,
layout, a second layout using the same computed styles, visible-page painting and
PNG encoding. The CSS and HTML snapshots changed between the first two rows; the
layout, fonts, viewport and input bytes were frozen. This is an instrumented offline
snapshot, not an Enter-to-display or compositor timing.

| Snapshot | HTML parse | CSS parse | CSS compute | Layout | Cached reflow |
| --- | ---: | ---: | ---: | ---: | ---: |
| Before selector fast rejection | 15.982 ms | 12.690 ms | 17,466.694 ms | 24.834 ms | 23.876 ms |
| After keyed selector rejection | 15.994 ms | 12.632 ms | 5,803.389 ms | 32.857 ms | 36.831 ms |
| Also skip rule loop for non-elements | 18.211 ms | 19.700 ms | 4,938.960 ms | 25.542 ms | 27.293 ms |
| After indexed rule candidates | 14.389 ms | 12.763 ms | 1,774.554 ms | 21.382 ms | 21.177 ms |

All four produced 9,179 commands and a 48,970-pixel document height in the same
frozen layout implementation. The encoded first-viewport PNG length was 32,118 bytes.
These equal counts alone are not a pixel-equivalence assertion. The shared host
was active, so small differences between the short stages are not interpreted.

## Findings and changes proposed to the owners

CSS compute dominated more than 99% of the before snapshot's CSS/layout work.
The two cheap stages were HTML parsing and laying out already computed styles.
Recomputing selectors after an image's intrinsic dimensions arrived cost seconds;
laying out those dimensions using cached styles cost tens of milliseconds.

The CSS owner restored fast failure for unrelated outer selectors and cached
rightmost tag/id/class rejection keys, together with allocation-free class/id
checks. That measured about a threefold reduction here.

The remaining small direct improvement was to skip the entire matching-rule loop
for node tags beginning with `#`, since every such match already returns false.
The isolated one-line change initializes the loop index to `rules.len()` for those
nodes while retaining UA style, inheritance and the rest of the computation.
That saved a further 0.86 seconds in this run and was sent to the CSS owner.

The application/layout owner is caching the parsed document and computed styles
across intrinsic-image reflows. Styles still need recomputation when their document,
stylesheets or relevant viewport inputs change.

The CSS owner then added BTreeMap-backed rightmost-key candidate buckets, skipped
non-elements and preserved specificity plus explicit source-index tie ordering.
The last row includes construction of that RuleIndex inside CSS compute. It measured
9.84 times faster than the first snapshot, with the same frozen layout. The investigation
only measured this shared-owner change; it did not edit the shared implementation.

## Evidence

Snapshots, original hashes, harnesses and individual logs remain under:

- `target/browser-pages-performance/before/`
- `target/browser-pages-performance/after/`
- `target/browser-pages-performance/skip-text/`
- `target/browser-pages-performance/after-index/`

The before CSS hash was
`dc0b606950fb703cc3946c7e40e7261ff96eb72170ac2ad13f3dd4c1c0d70b6f`;
the after CSS hash was
`2204c92cb6902f3c3a81ac025b1b659d7b293f24a910ff8c7263ad7699870baa`.
The indexed CSS hash was
`fb9feffe44c0b1c3fcd8e119edd3c20021ba424e14288db4f90edfd1ea75d755`.
The CSS compute wrapper and supplied-style layout entry were added only to the
isolated copies for timing. These are intermediate snapshots; the final integrated
browser's capture timings are reported separately.
