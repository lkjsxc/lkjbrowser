# Address editing verification

## Result and exact candidate

The address editor is implemented and verified on local source/harness commit
`5a8216119d57a695fdcbca0e748a43da42d1af15`, based on public
`3025bc82344a35fb052dffac743a46f4931c35e6`. The implementation commits are
`27895ea` (editor and authenticated clipboard), `b0a3c7e` (compositor click
timestamps), and `5a82161` (proof gate ownership and documentation precision).
All remain local; this work does not merge the canonical branch or push publicly.

The final [real compositor proof](../review/address-editing.Ohnr6l/README.md)
passed at 1440 × 760 and 480 × 760 in 74.3 seconds. The final canonical offline
gate passed with exit 0 in 50 seconds. Both runs used the unchanged normal pinned
compiler and CPUs 24–31 at nice 10, serialized through the shared mkdir gate.
The capture acquired and released the gate itself, including its documented-build
upgrade check. Source and executable identities stayed unchanged across both runs.

## What changed

The existing address pill now has a measured UTF-8 editor with a caret, anchored
selection, scalar and Unicode word movement, Home/End, deletion and replacement.
The Unicode word rule is Letter or Decimal_Number; other scalars are separators.
The editor follows the [Claude interaction and appearance contract](address-editing.md):
click or Ctrl+L/Alt+D/F6 enters editing with all text selected; an editing click
places the caret; double-click selects a word and triple-click selects all.
The fourth click restarts the sequence. Dragging selects and scrolls horizontally,
with a bounded step on each 50 ms tick.

Shift extends selection, Ctrl modifies word movement/deletion, and typing replaces
the selected range. Escape restores changed text and selects it while remaining in
editing; an unchanged Escape leaves editing. Outside clicks discard the pending edit.
Alt+Left and Alt+Right keep history precedence while editing. Edited long text is
clipped and scrolled without an ellipsis. The existing nonediting chrome and page
renderer are preserved.

Multi-click intervals now use the compositor's event timestamp, including its
32-bit wrap. A delayed batch therefore cannot turn clicks separated by more than
400 ms into a double-click. Native controller tests and the raw-wire probe cover
this through the actual event decoder and editor.

Copy, cut and paste use real Wayland data-device objects and descriptor transfers.
Cut deletes only after the compositor confirms ownership with the browser's private
per-instance marker, a display round trip, and retained focus. Paste is published
only after successful EOF and valid UTF-8, with unchanged editor state and no
earlier deferred input. Line breaks are removed, tabs become spaces, and surrounding
Unicode whitespace is trimmed. Missing authority leaves the text unchanged.

The transport authenticates each launch with a fresh 32-byte credential passed
through separate inherited stdin handles. The private file is unlinked before
either endpoint starts; credential bytes do not enter arguments, environment or
evidence. Invalid candidates cannot open the compositor or frame file. The normal
launcher rebuilds the tiny C bridge atomically, including when an older bridge is
already present. [Transport details](clipboard-transport.md) document the authority,
ownership, lifetime and failure rules.

## Verification

| Check | Observed result and receipt |
| --- | --- |
| Canonical offline gate | `sh tools/pages-test.sh`, exit 0; [complete log](../review/address-editing.Ohnr6l/offline-pages.log), [command and identities](../review/address-editing.Ohnr6l/offline-pages.identity.txt) |
| Native browser suite | 129 tests passed, plus the World program case; included in the canonical log |
| Existing rendering and network checks | All five layout/pixel goldens, HTTP and authenticated local TLS cases, image/content/stylesheet suites passed |
| Actual input timestamps | Ten presses and releases in one poll; slow single, exact 400 ms double, 401 ms reset, timely double/triple, fourth reset, and clock wrap passed |
| No clipboard manager | Focused native peer confirmed copy/paste refusal, no pending transfer and no result before explicit acknowledgement and close |
| Descriptor/auth regression | Wrong, short and stalled candidates rejected before Unix connect; same-listener recovery, frame FD, fragmented opaque bytes, descriptor transfer, overflow and broken pipe passed |
| Clipboard lifecycle | Ownership confirmation/refusal, late retired-source FD ordering, drag/focus offer cleanup, late EOF rejection, and deferred-input paste ordering passed |
| Real Weston editor | 16 independent exact-byte assertions per width, 32 total; [wide receipts](../review/address-editing.Ohnr6l/1440/assertions.log), [narrow receipts](../review/address-editing.Ohnr6l/480/assertions.log) |
| Actual launcher upgrade | Compiled the real bridge from `3025bc8`; documented browser build retained it, then normal launcher rebuilt/authenticated/presented successfully; frozen and final binaries matched |
| Cleanup and stderr | Browser/bridge/launcher stderr empty; owned processes reaped; gate released |
| Independent review | `lkj-address-review` independently checked source/runtime identities, all 32 byte comparisons, image equality, launcher/auth receipts and the canonical gate; [Crew mail #27–28](../review/address-editing.Ohnr6l/engineering-review.txt) records engineering PASS with no remaining blocker |

The canonical log SHA-256 is
`91b46dceb1b603e922bf6ad2accbd39b543b64a656fd633c8114624fa65d8491`.
The [post-gate source manifest](../review/address-editing.Ohnr6l/source-after-offline.sha256)
equals the capture's initial source manifest. The raw-wire timing receipt is also
committed at [wayland-input-proof.log](wayland-input-proof.log).

## Visual acceptance

Claude concierge approved the corrected caret in Crew mail #25. All eight final
acceptance originals and the contact sheet are byte-identical to that approved
`pSJ0QP` run; [the comparison receipt](../review/address-editing.Ohnr6l/approved-png-comparison.tsv)
records each file. The final images were sent directly to concierge and lead.

| Contract state | 1440 | 480 |
| --- | --- | --- |
| Middle caret in a long address | [PNG](../review/address-editing.Ohnr6l/1440/01-middle-caret.png) | [PNG](../review/address-editing.Ohnr6l/480/01-middle-caret.png) |
| Partial middle selection | [PNG](../review/address-editing.Ohnr6l/1440/02-partial-selection.png) | [PNG](../review/address-editing.Ohnr6l/480/02-partial-selection.png) |
| Caret at the start | [PNG](../review/address-editing.Ohnr6l/1440/03-start-caret.png) | [PNG](../review/address-editing.Ohnr6l/480/03-start-caret.png) |
| After multiline paste | [PNG](../review/address-editing.Ohnr6l/1440/04-after-multiline-paste.png) | [PNG](../review/address-editing.Ohnr6l/480/04-after-multiline-paste.png) |

[Acceptance contact sheet](../review/address-editing.Ohnr6l/acceptance-contact.png).

The screenshots come from Weston. XTest feeds the private Xvfb/Weston input path;
the browser receives actual compositor keyboard and pointer events through its
normal entrypoint. An independent raw-Wayland source/sink transfers synthetic
clipboard fixtures. No owner display or clipboard is used. This establishes
compositor input and data-device transfer, not physical keyboard hardware.

## Reproduction

From the assigned worktree, run the offline gate only when the shared lane is free:

```sh
cd /home/coder/workspace/lkjbrowser-address-editing-20261118
(
  set -eu
  address_gate=/home/coder/workspace/prompts/talk/lkjscript-gate.lock
  mkdir "$address_gate"
  trap 'rmdir "$address_gate"' EXIT
  trap 'exit 130' HUP INT TERM
  nice -n 10 taskset -c 24-31 sh tools/pages-test.sh
)
```

The capture manages its own gate; do not put it inside an already-held gate:

```sh
taskset -c 24-31 nice -n 10 bash tools/address-proof/capture.sh /home/coder/workspace/lkjbrowser/.deps/root
node tools/address-proof/contact.cjs "$(cat target/address-proof-last)"
```

The [harness instructions](../tools/address-proof/README.md) give prerequisites,
precise injected input, clipboard oracles and the distinction from older
application-event replay. Each proof directory records its commit, pinned compiler,
source, harness and frozen/final executable hashes.

## Supported boundaries

Clipboard text is limited to one MiB. Copy ownership confirmation has a 750 ms
budget. Paste has a five-second total deadline; bridge descriptor transfers have
a five-second inactivity deadline and 64 live descriptor slots. Invalid, oversized,
late, incomplete or stale data never produces a partial paste or authorizes cut.

Keyboard text retains the existing US physical-key mapping. Arbitrary XKB layouts,
IME, grapheme-cluster navigation and key-repeat scheduling remain outside this
slice. Unicode text can arrive through valid UTF-8 clipboard data; movement is by
scalar, not grapheme cluster.

The authenticated local handoff does not isolate processes sharing the same
account's permissions or privileged processes. A local connection flood may still
consume listener/backlog time; individual candidate deadlines and recovery checks
do not establish denial-of-service isolation. The temporary syscall-only bridge
remains necessary for Unix connection and descriptor capabilities absent from the pin.

The toolchain pin, canonical `lkjbrowser/GAPS.md`, and separate World-less window
witness were not modified. Existing renderer/network limitations remain documented
in the repository; this slice adds no resize implementation or UI reskin.
