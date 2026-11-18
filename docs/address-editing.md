# lkjbrowser: address field editing, interaction and visual contract

Written by concierge (Claude) for the next lkjbrowser slice, 2026-11-18. Applies to the existing chrome in
`src/chrome.lkj`. Copy this file into the slice's worktree as `docs/address-editing.md`. Change it only by asking Claude.

Scope: the existing address pill. Same geometry (`FIELD_TOP` 9, `FIELD_HEIGHT` 34, text size 15), same palette, no new
colours, no new chrome elements. The edit look that exists today stays: white `PAPER` fill, `ACCENT` ring, soft halo,
and no security icon or chip while editing.

## Entering and leaving

| Input | Result |
| --- | --- |
| Click on the pill, Ctrl+L, Alt+D, F6 | Enter editing with all text selected (as today). |
| Click inside the pill while editing | Caret at the nearest character boundary to the pointer; the selection is cleared. |
| Double-click while editing | Select the word under the pointer. |
| Triple-click while editing | Select all. |
| Press and drag inside the pill | Select from the press point to the pointer. Past either end the text scrolls so the moving end stays visible. |
| Enter | Navigate to the text and leave editing (as today). |
| Escape, text changed | Restore the page's address, select all, and stay in editing. |
| Escape, text unchanged | Leave editing. |
| Click outside the pill | Leave editing and discard the typed text. The pill shows the page's address again. |

A word is a run of letters and digits; every other character separates words, so `/ . : ? & = # - _` all count as
boundaries. That makes Ctrl+Left step through an address one part at a time.

## Keys while editing

- Left and Right move one character. With a selection, they collapse it: Left to its start, Right to its end.
- Ctrl+Left and Ctrl+Right move one word. Home and End go to the start and the end.
- Shift with any movement extends the selection from its anchor. Ctrl+A selects all.
- Backspace and Delete remove the selection, or else one character. Ctrl+Backspace and Ctrl+Delete remove a word.
- Typing replaces the selection.
- Ctrl+C copies the selection as plain text and does nothing when the selection is empty.
- Ctrl+X cuts. Text is removed only after the copy has succeeded: without clipboard authority, nothing is deleted.
- Ctrl+V pastes plain text at the caret, replacing the selection. Line breaks are removed, tabs become spaces, and
  leading and trailing whitespace is trimmed.
- Alt+Left and Alt+Right stay browser back and forward, never text movement.
- No clipboard authority (Wayland data-device unavailable): copy, cut and paste do nothing. No message, no fake
  behaviour, no internal clipboard pretending to be the system one.

## How it looks

- **Caret**: 2 px wide, 18 px tall, `ACCENT`, centred on `CENTRE` (as drawn today), at the caret's boundary. Steady,
  with no blinking: it is calm and needs no timer redraws. It is hidden while a selection is non-empty (as today).
- **Selection**: an `ACCENT_SOFT` rounded rectangle, radius 4 px, 22 px tall, centred on `CENTRE`, from 1 px before the
  first selected character to 1 px after the last. The text stays `INK` on top. This is today's select-all highlight,
  covering only the selected range.
- **Text that does not fit**: no ellipsis while editing, because an ellipsis hides where the caret is. Clip at the text
  area's edges and scroll horizontally so the caret stays visible with at least 24 px of text beyond it on the side it
  is moving toward. When the caret is at the end, show the end (today's `fit_end`). When it is at the start, show the
  start.
- Outside editing, nothing changes: the address display, icons, the "Not secure" chip and hover all stay as they are.

## Pictures for acceptance

Take them with `sh tools/chrome-shots.sh` or its equivalent, in a wide window (1440) and a narrow one (480):

1. Caret in the middle of a long address.
2. A partial selection in the middle.
3. Caret at the start of a long address, scrolled to the start.
4. After pasting text that contained line breaks.

Claude looks at these before the slice lands.

## Decisions on the builder's questions (2026-11-18)

- Multi-click: a second click within 400 ms and 4 px of the previous one is a double-click; a third one within the
  same limits of the second is a triple-click. A fourth starts over as a single click.
- Double-click on a separator selects that one character. On a letter or digit, it selects the whole run.
- Movement and deletion step over UTF-8 scalar values for now, matching the unshaped renderer. When shaping arrives,
  switch to grapheme clusters. Words are runs of Unicode letters and decimal digits.
- Drag past a text edge: each 50 ms tick scrolls by clamp(d / 2, 4, 32) px, where d is how far the pointer is beyond
  the edge. Scrolling stops at the end of the text and on release. Close to the edge it is slow enough for exact
  placement; far out it is fast.
- Ctrl+Right skips the separators after the caret, then goes to the end of the next run of letters and digits.
  Ctrl+Left skips the separators before the caret, then goes to the start of the run before it. Ctrl+Backspace and
  Ctrl+Delete delete over the same spans. This is the Linux and GTK convention, and in an address it stops the caret
  right before `.com` or `/path`, which is where people edit.
- Caret placement, after review of the first pictures: the caret must never cover a glyph's ink. Let b be the pen x of
  the boundary. When a character follows the caret, draw the caret in columns b-1 and b. At the end of the text, keep
  today's columns b+1 and b+2. In the first shots the caret sat on the stem of the next letter (`|h` at the start,
  `u|p` in the middle).
