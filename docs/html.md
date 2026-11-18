# HTML, CSS and document layout

The document pipeline is written in lkjscript. It does not call a host HTML
parser, CSS library, text layout engine, browser, or drawing library. Its goal
is readable, navigable documents within the explicit subset below.

- `html::parse(&str)` builds an owned indexed tree with attributes, decoded text,
  the first title and embedded style text.
- `css::compute_viewport(&Document, width, height)` applies the supported cascade,
  width media conditions and viewport lengths. Parents precede children, so
  inheritance is iterative; `css::compute` remains a compatibility wrapper.
- `layout::build_styled_faces` lays out the cached DOM and computed styles with
  four proportional and four monospace faces, plus decoded image dimensions.
  Compatibility entry points still support the earlier four-face callers.
- Painting uses each fragment's actual font, size, x coordinate and baseline.
  Layout and painting share `Font::advance`. Scrolling and browser chrome belong
  to main.

The browser retains the parsed DOM and computed styles across image-dimension
relayouts. There are no heap-stored borrowed references in the DOM. Owned vectors,
temporary checked views, strings, enums and scalar arithmetic suffice without a
helper in another language.

## HTML subset

The parser accepts ordinary tags and text, quoted and unquoted attributes,
comments and declarations, void elements and explicit closing tags. Selected
optional closing rules cover paragraphs, list items, table cells, rows and row
groups. Table closing searches stop at the nearest owning table, so a nested
table does not accidentally close an outer cell. This is a forgiving document
parser, not the complete HTML5 tree builder.

Title, style and script contents are read as raw text. Scripts are neither
executed nor displayed. Common named entities and decimal/hexadecimal numeric
entities decode valid Unicode scalars. The `hidden` boolean attribute suppresses
display. A closed `details` element exposes its first `summary`; the browser can
toggle it and recompute styles/layout without JavaScript.

Presentational hints apply before author declarations: supported `width` and
`height` attributes on images/table elements; `align` and `bgcolor`; legacy
`font` size, color and face; and list `type`. Cells inherit numeric `cellpadding`
from their nearest owning table. Legacy `center` centers a table's outside box;
the table's contents start with normal text alignment unless their own hints or
author styles override it.

## Selectors and cascade

The selector matcher supports:

- Type, universal, class and id selectors; compound selectors; descendants and
  direct children; adjacent and general siblings; comma-separated lists.
- Attribute presence, exact equality and the `~=`, `|=`, `^=`, `$=`, `*=`
  operators, quoted values and the explicit ASCII-insensitive `i` flag.
- `:root`, initial attribute-based `:checked`, `:disabled` and `:enabled`;
  first/last/only child and type tests; `nth-child`, `nth-last-child`,
  `nth-of-type` and `nth-last-of-type`.
- `:not()`, `:is()` and `:where()` with compound-selector arguments.
  Complex selector arguments inside these functions are not supported.
- Specificity, source order, inline styles and `!important` within this subset.
  `:is()` and `:not()` use the greatest argument specificity; `:where()`
  contributes zero.

Selector lists and compounds are split with awareness of quotes, brackets and
parentheses. Unknown or malformed selectors fail closed, including unsupported
syntax inside negation. Interactive pseudo-classes such as hover, focus, active,
visited and target do not match the static style snapshot. Checkbox state is read
from markup; this does not imply an implemented interactive form control.

Rules are indexed by a required id, class or tag in their rightmost compound.
Rules without such a key use a universal bucket. Each element considers only
its applicable buckets; text and document nodes do not run selector matching.
Matches are still ordered by specificity and source index, so indexing does not
change cascade order. DOM class and attribute comparisons avoid allocating
temporary strings in the hot matcher.

## Properties and layout

### Text and fonts

Text color, font size, normal/bold weight, normal/italic style, underline and
left/center/right alignment are implemented. The supported `font` shorthand
expands style, weight, size, line-height and family while retaining declaration
order and importance. Family selection distinguishes a proportional face from a
monospace face using the generic monospace family and recognized common mono
family names. It does not select arbitrary installed fonts or a separate serif
face. The UA styles for `pre`, `code`, `tt`, `kbd` and `samp` select monospace.

Eight independently owned runtime faces provide regular, bold, italic and bold
italic for proportional and monospace text. The optional font directory retains
the four required Liberation Sans files. Mono files are optional there, then
looked up in the system; an independently loaded corresponding Sans face is the
last fallback. This is startup face selection, not per-glyph font fallback.

Font sizes accept px, pt, em, rem and percentages. Relative font sizes use the
parent; rem uses the computed root size, initially 18 px. A point is 4/3 of a CSS
pixel. Box lengths additionally support vw/vh; ex is an explicit approximation
of half the computed font size, not a measured x-height. Supported line heights
include unitless ratios, lengths and percentages. Ratios inherit as ratios so
a descendant's font-size change also changes its line spacing.

Inline text wraps using glyph advances and shares a baseline even when sizes or
faces differ. A word crossing a style boundary moves as one word when it fits
a new line; a longer word splits at character boundaries without losing text.
Preformatted whitespace is retained with soft wrapping to the available column.
Text and image fragments retain link destinations for hit testing.

### Boxes, lists and document flow

Supported box properties include margin/padding shorthands and sides, horizontal
auto margins, width and max-width, minimum ordinary block height, solid uniform
borders, opaque backgrounds and content-box/border-box sizing. Width/max-width
and margin/padding percentages are resolved from the containing block's width,
including vertical margin/padding percentages. Replacing a percentage declaration
with an absolute value or auto/none clears its earlier percentage component.
Bounded two-argument `min()`/`max()` on supported lengths are accepted; this is
not the full CSS math-expression model.

List styles include none, disc, circle, square, decimal, lower/upper alpha and
lower/upper Roman. Markers hang beside the first text baseline. List-style-position
and list-style-image are not implemented. The curl corpus uses ordinary outside
markers; its two-digit marker clipping was a layout gutter issue, not evidence
for adding an inside-marker rule.

`display` recognizes none, block, inline, list-item, inline-block, flex and
inline-flex. Full atomic inline-block/inline-flex formatting is not implemented.
Grid and CSS table display values have a readable block fallback; actual HTML
tables use the dedicated bounded table algorithm described in
[Table layout](tables.md).

The finite flex implementation lays out ordinary rows or columns with order,
basis, growth and a gap. Widths shrink to the available row, with a stacked
fallback for a severely crowded row. Flex wrapping, alignment/distribution
properties and the complete flex min-size/shrink algorithm are absent.

Basic left/right floats use their declared or measured width and reserve a
side exclusion area. Following text moves below a float if its remaining column
would be unreadable. Clear-left/right/both is applied. The common empty
`::before`/`::after` clearfix pattern contributes clearance when its cascaded
content is an empty string and its display is block, table or flow-root.
Other pseudo-element content and geometry are not generated.

### Visibility and positioned controls

Visibility is inherited; hidden ordinary content keeps its layout space while
its text/decoration is not painted. Position keywords, simple inset lengths and
a single `translateX()` are parsed. Translation accepts a length, percentage or
the observed two-term `calc()` sum/difference. Absolute/fixed controls that are
hidden, explicitly empty-clipped or wholly translated outside the viewport are
excluded. This handles static closed drawers without placing their text before
an article.

Only explicit empty `clip:rect(...)` geometry and `clip-path:inset(100%)` are
recognized for that exclusion. General clipping, transforms, stacking contexts
and positioned containing-block layout are absent. Visible positioned content
uses the readable flow fallback; relative and sticky positioning are not full
positioning implementations.

## Stylesheet resources and media

Inline style elements, linked stylesheets and leading `@import` statements are
expanded in source order. Imports accept quoted URLs or `url(...)` with an
optional supported media condition. Relative imports resolve against the final
redirected stylesheet URL. Cached repeated occurrences are still expanded at
their own source positions; active URL cycles are skipped.

The whole batch permits four distinct external stylesheet requests, including
imports and failed requests, one MiB per external body, four MiB assembled CSS,
and 1,024 expansion attempts. One shared three-second owned-child deadline bounds
external loading. HTTPS and local-file origin restrictions remain enforced.
Font downloads are not followed.

HTML media attributes and CSS media blocks support screen/all, optional only,
min/max-width in px/em/rem, comma alternatives and nesting to eight levels.
Unsupported conditions, print media and general media negation are skipped.
Media width is the actual window width; media em/rem use the initial font size,
independent of author root-font declarations.

## Images and tables

PNG, supported JPEG profiles and the first composited GIF frame are decoded
from lkjscript source as boxes enter the visible viewport. Decoded dimensions
trigger layout with the retained DOM/styles so images without explicit dimensions
can reserve their actual ratio. Explicit HTML/CSS dimensions remain inputs to
layout and oversized images scale to the reading column. SVG root metadata can
provide placeholder geometry, but SVG pixels are not painted. See
[Image formats and evidence](images.md) for exact codec profiles and limits.

HTML tables support a bounded grid with row groups, colspan/rowspan, intrinsic
widths, legacy spacing/alignment and a readable stacked fallback. Table details,
resource limits and regression evidence are maintained in [Table layout](tables.md).

## Deliberate boundaries

There is no complete HTML error recovery, JavaScript, full form-control
implementation, general generated content, CSS grid, full positioning/flex/table
layout, general alpha colors, custom-property substitution or complete CSS
length/cascade model. Unsupported declarations preserve the earlier usable
value where the implemented parser can establish invalidity.

Vertical margins are additive rather than collapsed. Full inline box/background
geometry is absent. Line heights never overlap the font's ascent/descent. Widths
stay within the reading column. Height is a minimum for ordinary blocks; images
use their specified height.

Font sizes are constrained to 6..160 px, absolute box lengths to -8192..8192 px,
padding to nonnegative values, and borders to 0..16 px. These are application
policies, not language limits. There is no shaping, bidi reordering, kerning,
per-glyph font fallback or Unicode line-breaking yet. The corpus and runtime
font selection remain Latin-focused.

## Ten-page CSS/HTML evidence

The isolated current CSS/HTML native gate passed **34 tests**: six HTML tests and
28 CSS tests. These include optional table-close boundaries, nested tables,
static selectors and specificity, percentage resets, root rem/point sizing,
presentational hints, empty clearfixes, clipped controls, nearest-table
cellpadding, monospace inheritance/resets and legacy centered tables.
An indexed-versus-exhaustive matcher regression checks that candidate filtering
preserves matches and equal-specificity source order.

[The CSS review](../tests/pages-css-review.md) maps these changes to actual cached
Python, SQLite, Wikipedia, curl, Git, Hacker News and Paul Graham source patterns.
The final full application gates and real Weston captures are recorded by the
main ten-page review; offline renders are diagnostic evidence only.

A frozen Wikipedia measurement used 10,767 nodes and 1,949 rules with the same
layout and font implementation. Computed-style time fell from 17,466,694
microseconds before matcher optimizations to 1,774,554 microseconds including
candidate-index construction. Command count, document height and encoded PNG byte
count remained equal in that comparison. These measurements isolate CSS work;
they are not end-to-end navigation timings or a claim of pixel hash equality.

The matcher also exposed one pinned-compiler type-checking refusal:
`probes/string-match-loop-compare.lkj` places a `String == &str` comparison inside
a loop in a match arm returning `Option<bool>`. The 13-line probe is refused with
E_TYPE; the accepted counterpart explicitly compares `item.as_str()`.
A plain isolated comparison loop can be accepted, so this observation is limited
to the minimized context. It needs no runtime primitive or external helper.
The older language observations below are retained separately.

## Earlier test and visual evidence

The HTTPS public-page follow-up passed 55 focused native tests through
src/layout_public_probe.lkj. Nine new regressions cover viewport/shorthand/media
semantics and table alignment, bounds, links and styled intrinsic widths.
[The public-page review](../tests/layout-public-review.md) records two inspect/fix
cycles using cached actual HTML/CSS; the final real Weston screenshots and timing
logs are separate from those offline renders. The original fixture evidence below
is retained as historical evidence from the first browser slice.

The ordinary test functions cover DOM structure and malformed input; raw style
text and entity decoding; specificity, important declarations and inheritance;
relative sizes and hidden boolean attributes; unsupported selectors; long-word
splitting; text/image link hit boundaries; ordered-list marker baselines; anchor
lookup; image aspect ratios; and a word crossing inline style elements.

At 80 px, the regression xx abc<b>def</b> must produce lines xx and abcdef, not
split at the bold boundary. It also verifies that the final fragment stays bold.

Layout-only tests use a deterministic metrics fixture from font.lkj. The actual
browser always reads real font files at runtime. After the final wrapping fix,
the combined HTML/CSS/layout/font slice passed 16 native tests. The root test
command also renders real-font fixtures and compares layout dumps and pixels.

An early real-font article proof produced 147 DOM nodes, 37 block boxes, 591
commands and a 2283 px document at 1000 px width. These numbers are from the
pre-final visual round; final geometry and hashes belong to the golden files.

## Visual review

1. Opened the program's layout-article-proof.ppm, then simple-r1.png and
   article-scroll-r1.png. Baselines and list markers were consistent. The simple
   page's lead left one final word alone on its second line, and its caption was
   an overlong technical aside.
2. Changed that lead to two balanced authored lines and shortened the caption
   to “Hills, a river, and a little room to think.” The root integrated actual
   PNG painting, adjusted error-page spacing and the long address presentation,
   and records the final image inspection in its visual proof.
3. Opened simple-r3.png after integration: the lead is balanced, the short
   caption has clear spacing, the landscape PNG paints at the intended ratio,
   and text in the bordered card stays on consistent baselines. No remaining
   clipping or wrapping problem was visible in that final page.

The visual changes live in the fixture HTML. Relative CSS lengths and
style-boundary wrapping were corrected in the renderer with regression tests.

## Observed pinned-toolchain gap

Pin: 2026.11.17-e6d13590b. A helper guarded with #[cfg(test)] was hidden while the
test function calling it was still checked. Both an ordinary build and the
native test command reported E_NAME at those calls. The diagnostic explicitly
states that this exclusion applies even under the test command; it is a known
configuration limitation.

Evidence: probes/html-cfg-test.lkj. One helper definition affects five current
layout-test calls (four at the first refusal). The workaround leaves the pure
metrics fixture unconditionally declared; the browser never calls it. No
external-language helper was introduced.

OPINION: Evaluate cfg(test) as true while discovering and compiling test entries.
For ordinary builds, exclude test-only bodies consistently with their helpers,
or provide a documented convention that does so. A #[cfg(test)] helper returning
7, called by a #[test] assertion, is the complete reproducer. This is a
test/source-configuration improvement, not a new runtime capability.


## Reduced borrow-checker refusal from the HTTP decoder

The original HTTP text decoder was refused at a continue in an inner UTF-8
match, inside a loop in the Err arm of an outer UTF-8 match. The complete original
diagnostic was recovered from gateway operation browser-net-check-poll-012.

The rejected reproducer is now probes/html-loop-view.lkj. It needs no owned
String, no mutation of input bytes, and not even a bound inner payload view.
An outer Result containing a possible view, its Err arm, and the inner
view-returning match with continue suffice. The pin reports:

    E_BORROW loop backedge changes the reference holders or origins required at loop entry

There was one originating application site in the text decoder. The browser
source already uses a successful same-language rewrite. The reduced accepted
counterpart, probes/html-loop-view-workaround.lkj, completes the outer match
into an owned bool before entering the loop. The previously written
probes/loop-view.lkj is also accepted; it has no outer match and must not be
cited as a negative test.

OPINION: Close view-bearing match temporaries consistently on continue edges,
and preserve the proven inactive payload state of the outer Err variant.
The accepted block-owned discriminator rewrite demonstrates that no new
capability, unsafe escape or external helper is necessary. Until the checker
can establish this directly, keep the lexical-boundary rewrite explicit.

### Contained flex margins and marker gutters

The readable flex fallback clamps negative horizontal item margins to zero, retains
intrinsic minimum box widths, and stacks items when those minima cannot fit. This is
an explicit limitation of the partial flex model: it prevents intersecting item boxes
and adjacent navigation labels running together. It does not claim full CSS negative
margin or flex shrinking semantics. Percentages are resolved once against the parent,
then the allocated item width becomes authoritative.

Outside list markers reserve only the extra gutter needed to keep their full number
inside a marginless viewport. A two-digit label therefore remains visible when the
source removes the body margin; ordinary inset lists keep their existing geometry.
