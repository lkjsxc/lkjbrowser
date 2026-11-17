# HTML, CSS and document layout

The document pipeline is written in lkjscript. It does not call a host HTML
parser, CSS library, text layout engine, browser, or drawing library.

- html::parse(&str) builds an owned indexed tree, with attributes and decoded
  text, plus the first title and embedded style text.
- css::compute_viewport(&Document, width, height) applies the supported cascade,
  width media conditions and viewport lengths. Parents precede children, so
  inheritance is iterative; css::compute remains a compatibility wrapper.
- layout::build_in_viewport accepts separate layout width and full viewport
  dimensions, then creates document-relative boxes, text/image fragments and
  anchors. The older layout::build entry remains a compatibility wrapper.
- Painting uses each fragment's real font, size, x coordinate and baseline.
  Layout and painting share Font::advance. Scrolling and chrome belong to main.

There are no heap-stored borrowed references in the DOM. Owned vectors, temporary
checked views, strings, enums and scalar arithmetic were sufficient without a
helper in another language.

## Implemented subset

HTML supports ordinary tags and text, quoted and unquoted attributes, comments
and declarations, void elements, explicit closing tags, and selected optional
closing rules for paragraphs and list items. Title, style and script contents
are read as raw text. Scripts are neither executed nor displayed. Common named
entities and decimal/hexadecimal numeric entities decode valid Unicode scalars.
This is a forgiving document parser, not the full HTML5 tree builder.

CSS supports:

- Type, universal, class and id selectors; compounds; descendants; children;
  comma-separated lists. Unsupported selectors never broaden a match.
- Specificity, source order, inline style and !important within this subset.
- Display block, inline and none; text color and font size; bold and italic;
  underline; left, center and right text alignment.
- Block margin and padding shorthands/sides, horizontal auto margins, content
  width and maximum width, a minimum content height, solid uniform borders and
  opaque backgrounds.
- Font sizes in px, em, rem (the initial 18 px root size) and percentages.
  Relative font sizes use the parent's font size.
- Pixel, em/rem and viewport vh/vw box lengths. Percentage box lengths are ignored
  rather than incorrectly interpreted relative to the font.
- The supported font shorthand fields: style, weight, size and line height, with
  declaration order and importance retained. Font-family selection is absent.
- Screen/all width media conditions, optional only, min/max-width in px/em/rem,
  comma alternatives and nesting to eight levels. Unsupported conditions and
  print media are skipped; media width is the actual window width.
- Unitless and pixel line height. Unitless line height inherits as a ratio, so
  changing a descendant's font size also changes its line spacing.
- Opaque #rgb, #rrggbb, decimal rgb(r,g,b), and a small set of color names.
- Preserved preformatted whitespace with soft wrapping to the available column.

Inline fragments wrap using glyph advances and share a baseline even when sizes
or faces differ. A word crossing a style boundary moves as one word when it fits
a new line; a longer word splits at character boundaries without losing text.
Lists have hanging bullet or numeric markers on the first text baseline.
Text and image fragments retain their link destination for hit testing.

Images use explicit HTML/CSS dimensions and scale down while preserving that
ratio. The browser fetches PNG data as boxes enter the visible viewport. Loading
an image does not rebuild layout, so reserved dimensions and the reading position
remain stable even when no explicit dimensions were supplied.

Tables have a bounded readable fallback: rows share intrinsic column widths,
headers are bold, links/anchors survive, and colspan spans up to 64 columns.
Crowded tables reduce inter-column gaps before shrinking columns; insufficient
width selects a stacked fallback. This is not the full CSS table algorithm.

Inline style elements and up to four distinct linked stylesheet URLs are applied
in DOM order, including cached repeated links. Both HTML media attributes and CSS
media blocks filter rules. Linked bodies have a one-MiB cap, the assembled CSS
has a four-MiB cap, and one shared three-second owned-child deadline limits the
whole external-sheet batch. HTTPS and local-file origin rules remain enforced.
CSS imports and font downloads are not followed.

## Deliberate boundaries

There is no complete HTML error recovery, full CSS table/SVG layout, form-control
implementation, JavaScript, generated content, CSS flex/grid, positioning,
floats, or CSS font selection. Rowspan, collapsed borders and column styles are
outside the table fallback. General media features and negation are unsupported.

Vertical margins are additive, not collapsed. Inline margin/padding boxes and
full inline-background geometry are absent. Line heights never overlap the
font's ascent/descent. Widths stay within the reading column. Height is a
minimum for ordinary blocks; images use their specified height.

Percentage box geometry, general alpha colors and the full CSS
length/cascade model remain absent. Font sizes are constrained to 6..160 px,
absolute box lengths to -8192..8192 px, padding to nonnegative values, and
borders to 0..16 px. These are application policies, not language limits.

There is no shaping, bidi reordering, kerning, font fallback, or Unicode
line-breaking yet. Four runtime font files supply regular, bold, italic and
bold italic faces for the Latin-focused fixtures.

## Tests and evidence

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
