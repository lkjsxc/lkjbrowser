# Table layout used by the ten-page slice

`src/layout/table.lkj` builds a grid from table rows and row groups. It reserves
occupied columns for rowspan, applies colspan, keeps `rowspan=0` inside its row
group, places header groups before the body and footer groups afterwards, and lays
out captions before the grid. Up to 64 columns are supported. An invalid or
unreadably narrow grid falls back to stacked rows/cells with the same text order.

## Widths and heights

Each cell contributes a minimum word width and a preferred line width. Font sizes
and weights come from styled descendants. Block boundaries finish a measured line;
paragraphs are not added together as if they were one huge line. Replaced images
contribute their declared or decoded size. Pixel and percentage cell-width hints
participate in the columns before the cell block is laid out. The parent therefore
treats the grid-assigned cell width as authoritative instead of applying percentage
widths a second time.

Colspan constraints distribute a missing width across their covered columns.
The grid gives narrow rank, arrow and empty spacer columns their measured widths,
rather than a fixed 32 px minimum. Actual `cellspacing` is used, with a 2 px default.
Gaps shrink before a word that fits the available table would be split. Automatic
tables use their preferred width when it fits; explicit-width tables distribute
the remaining space among columns. The parent can use `table::preferred` to size
the automatic table's outside box too.

Cells are laid out once. The module records their command, box, anchor and
disclosure ranges, computes row heights and the additional space required by
rowspans, then translates those records into their final rows. Cell backgrounds
and borders stretch to the spanned height while descendant content keeps its own
size. Legacy top/middle/bottom valign chooses the content offset. Link and
disclosure hit areas move with the pixels.

Intrinsic measurement is capped at 8,192 px and has a 128-level traversal fallback.
These are layout resource policies, not language/runtime limits. Full CSS automatic
table layout, collapsed borders, column/colgroup styling, caption-side, CSS vertical
alignment, and writing-mode table layout are not claimed.

## Evidence

The isolated native layout gate passed 80 module tests after integration with the
current source. Five focused table regressions establish:

- Rowspan columns remain occupied and links move to the final row.
- Rowspan zero stops at its group and a source-leading footer displays last.
- Narrow rank/spacer columns and a 435 px article hint remain distinct.
- Two paragraphs measure as two lines, and a 69 px image reserves 69 px.
- Details controls still hit their own summaries after cell translation.

Existing regressions still establish that two 72 px words fit a 150 px table,
styled descendants contribute their real widths, headings share row baselines,
and narrow fallback retains all text. The focused source fixture is
`fixtures/table-spans.html`; the normal native test command includes the module.

Offline cached-page diagnostics in `target/browser-pages-network/` were opened
after rendering. Paul Graham's outer table reserves the actual 69 px image rail,
26 px spacer and 435 px article column. Hacker News retains narrow ranks and one
row per headline; the first diagnostic also exposed legacy center alignment
leaking into cell text, which was reported to the shared CSS owner. These are
offline diagnostics, not substitutions for the run's real Weston captures.
