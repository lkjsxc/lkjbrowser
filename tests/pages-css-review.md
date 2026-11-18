# CSS and HTML evidence for the ten-page slice

This file records the page-source observations that motivated the CSS/HTML changes.
The full-window screenshots and page verdicts belong to the parent pages report.

## Source-driven repairs

| Observed source | Repair and boundary |
| --- | --- |
| Hacker News table markup; ordinary optional HTML tags | Cells, rows and row groups close when the next peer begins; the nearest nested table bounds the operation. This is not the full HTML tree-construction algorithm. |
| Hacker News and Paul Graham numeric/percentage table widths; legacy font tags | Presentational width, height, alignment, background, font color/size and list-type hints precede author CSS. Cells take numeric cellpadding from their nearest owning table. |
| SQLite percentage margins and ex padding; Git percentage columns | Percentages are retained until the containing block is known. Every margin/padding percentage uses the containing block width. Width and maximum width retain separate percentages; border-box is explicit. |
| Python root-relative spacing and font sizes; Hacker News point lengths | rem uses the computed html font size. Points use exactly four thirds of a CSS pixel. ex currently uses one half of the computed font size, an explicit approximation rather than measured font x-height. |
| Python pre/code and explicit monospace font families | A monospace style flag inherits, UA code/pre/tt/kbd/samp choose it, and font-family/shorthand/legacy face hints can reset it. The renderer selects real mono faces; serif selection remains deferred. |
| Hacker News outer center element | The table box is centered while cell text starts at the leading edge. Explicit alignment and author CSS still win. |
| Python, curl, Git, Wikipedia and FreeBSD navigation | Styles retain inline-block/flex, row/column, growth/basis/order/gap, floats/clear and visibility for layout. Grid explicitly uses the readable block fallback; no grid algorithm is claimed. |
| Python's closed mobile menu | Fixed positioning, insets and translateX percentages/lengths, including the observed simple calc sum, are retained for layout. |
| Wikipedia and FreeBSD hidden dropdowns and accessibility labels | visibility is inherited; explicit empty clip rectangles and inset(100%) are marked for the renderer. A small width alone never hides text. |
| SQLite menu clearfix | Empty before/after content with block/table/flow-root display and clear produces a clearance flag. Content, display and clear honor the cascade. Other generated content is not rendered. |
| Python/Wikipedia/FreeBSD static selectors | Attribute selectors, initial checked/disabled state, first/last/only/nth siblings, compound not/is/where, and adjacent/general siblings match without broadening unsupported selectors. |

Selector lists preserve quoted attribute values and functional arguments. Specificity
counts attributes once, uses the most specific not/is argument and gives where zero
specificity. Unsupported selector syntax remains non-matching. Dynamic hover/focus,
visited and target states are false in the current static computed snapshot.

The full cascade still has deliberate omissions, including custom properties,
complete calculation syntax, escapes, generated text, full CSS tokenization,
downloadable fonts and shaping. The changes above do not imply complete CSS support.

## Native regression evidence

The isolated HTML/CSS suite is reproducible by copying src/html.lkj and src/css.lkj
into an ignored directory beside a two-module entry, then running the pinned compiler:

```sh
mkdir -p target/browser-pages-css
cp src/html.lkj src/css.lkj target/browser-pages-css/
printf 'mod html;\nmod css;\nfn main() -> i32 { 0 }\n' > target/browser-pages-css/probe.lkj
.toolchain/lkjscript test target/browser-pages-css/probe.lkj --engine native --jobs 1
```

The final focused run passed **34 tests**: six HTML tests and twenty-eight CSS tests.
New cases cover optional table boundaries, percentage reset and invalid declarations,
root-relative units/points, legacy hint precedence, inherited list types and layout
flags, quoted/static/structural selectors, specificity, invalid negation, empty
pseudo clearance, explicit accessibility clipping, nested-table cellpadding, legacy centered table boxes, monospace family inheritance and indexed-versus-exhaustive selector equivalence.
The parent full gate additionally exercises their actual layout and pixels.

## Selector matching cost

The original extended matcher revalidated every selector against every element and
allocated class-word vectors even for unrelated rules. The repair retains full
validation inside functional negation while rejecting unrelated outer selectors
early, caches required rightmost tag/id/class keys per rule and uses allocation-free
DOM predicates. These changes preserve the unsupported-selector refusal rules.
A second step indexes each rule into one disjoint rightmost ID/class/tag bucket using
the pin's source BTreeMap. Nodes inspect their own buckets and unkeyed rules;
non-elements inspect no selectors. Duplicate class tokens do not duplicate a rule.
Matching entries are sorted by specificity and explicit source index, preserving
the cascade even though candidates arrive from several buckets.

The independent frozen Wikipedia measurement used 10,767 DOM nodes and 1,949 rules,
the same cached HTML/CSS, layout and fonts. CSS computation fell from 17,466,694 us
to 5,803,389 us with the first repair and to **1,774,554 us** with indexed candidates
(including index construction), about 9.84 times faster than the initial extended
matcher. The captured structural result remained 9,179 commands and 48,970 px high;
PNG byte count was also unchanged. This is isolated CSS timing, not whole-page
navigation timing or a claim about final rendering geometry.

Exact snapshots and logs are under target/browser-pages-performance/before,
after and after-index; the pages report records whole-browser timings.

## Pinned source-form refusal

probes/string-match-loop-compare.lkj is a thirteen-line rejecting witness at
2026.11.17-e6d13590b. A match arm loops over an owned Vec<String> returned from a
helper, while its inputs are views of owned strings. Direct item == desired is
rejected with E_TYPE, expected &str, found string::String. A plain isolated loop is
accepted, so this is not a claim that all String/str comparison is unsupported.

probes/string-match-loop-compare-workaround.lkj changes only that comparison to
item.as_str() == desired and is accepted. There was one originating selector
attribute-token comparison site. No helper in another language is involved.

## Standards consulted

- [HTML optional tags](https://html.spec.whatwg.org/multipage/syntax.html#optional-tags)
  for paragraph, cell, row and row-group boundaries.
- [CSS margin and padding percentages](https://www.w3.org/TR/CSS2/box.html)
  for the containing-width basis, including vertical sides.
- [CSS width calculation](https://www.w3.org/TR/CSS2/visudet.html)
  for retaining percentages until a containing block is known.
