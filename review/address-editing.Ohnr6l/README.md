# Address editing: final candidate Weston proof

## Result

PASS on immutable local candidate `5a8216119d57a695fdcbca0e748a43da42d1af15` at 1440 × 760 and 480 × 760, using the normal native entrypoint, real compositor keyboard/pointer events, and real `wl_data_device` pipe transfers. All sixteen exact-byte assertions passed at each width. Capture command completed with exit 0 in 74.3 seconds on 2026-11-18 UTC. Browser source hashes stayed unchanged; browser and bridge stderr were empty. The normal published launcher also painted and exited cleanly at both widths; the actual stale-transport upgrade regression passed at 1440. The script's owned processes were killed/reaped; no process remained using its private runtime paths.

[Acceptance contact sheet](acceptance-contact.png) contains unscaled toolbar crops. Rows 1–4 follow Claude's contract; left is 1440 and right is 480. Full compositor captures:

| State | 1440 | 480 |
| --- | --- | --- |
| Caret in the middle of a long address | [PNG](1440/01-middle-caret.png) | [PNG](480/01-middle-caret.png) |
| Partial selection in the middle | [PNG](1440/02-partial-selection.png) | [PNG](480/02-partial-selection.png) |
| Caret at the start, text scrolled to the start | [PNG](1440/03-start-caret.png) | [PNG](480/03-start-caret.png) |
| After actual multiline clipboard paste | [PNG](1440/04-after-multiline-paste.png) | [PNG](480/04-after-multiline-paste.png) |
| Additional cut result | [PNG](1440/05-after-cut.png) | [PNG](480/05-after-cut.png) |

## Reproduction

From the assigned worktree, run directly. The harness acquires the shared compiler gate itself, retains it through the documented build, and releases only its own gate on exit. Do not wrap this command with an already-held gate:

```sh
taskset -c 24-31 nice -n 10 bash tools/address-proof/capture.sh /home/coder/workspace/lkjbrowser/.deps/root
node tools/address-proof/contact.cjs
```

The capture script creates fresh Xvfb displays, private mode-0700 Wayland runtime directories, a unique runtime marker, fresh loopback transport ports, and independent synthetic clipboard peers. It freezes the browser, bridge and helpers before launch. No owner display or clipboard is used. Its XTest events go into Weston's X11 backend, which delivers real `wl_keyboard` and `wl_pointer` messages. No browser application-event replay is used. This proves compositor input, not physical keyboard hardware.

The source publishes only `paste-input.txt`: 38 synthetic UTF-8 bytes containing CR, LF, a tab, and outer whitespace. A separate sink window requests the browser's offered plain text through a real received pipe. It verifies the normalized 31-byte result against `paste-expected.txt`. Subsequent sinks verify exact editor selections and browser state. Each width's `*.input` file is a precise event sequence, `*.input.log` records injected events, `*.sink.log` records the independent offer and transfer, and `assertions.log` records the byte comparisons.

The long address is 216 ASCII characters. State 1 uses Home then 120 Right presses; state 2 extends by sixteen characters with Shift+Right; state 3 presses Home. Drag proof holds beyond the right edge for nine seconds so both viewports reach the end at their ordinary scrolling speed. An earlier four-second harness hold reached only a prefix at 480; extending the harness wait required no browser change.

## Assertions at each width

| Assertion | Independent received result |
| --- | --- |
| Multiline paste normalization | `https://example.test/alpha beta` (31 bytes) |
| Double-click selection | `https` (5 bytes) |
| Triple-click selection | Entire long address (216 bytes) |
| Drag with horizontal scrolling | Entire long address (216 bytes) |
| Pointer insertion at start | `X` + long address (217 bytes) |
| Cut | Same 217 clipboard bytes, field empty in screenshot |
| Paste own clipboard source | Same 217 bytes restored |
| Ctrl+Shift+Right word range | `.beta` (5 bytes) |
| Ctrl+Backspace and Ctrl+Delete | `/gamma?` (7 bytes) |
| Enter local navigation | Exact file URI (86 bytes) |
| Alt+Left while editing | `about:welcome` (13 bytes) |
| Alt+Right while editing | Exact file URI (86 bytes) |
| Changed Escape | Page URI copied without re-entering editing |
| Unchanged Escape and F6 | Typed `X` ignored outside editing, page URI selected by F6 |
| Alt+D | Page URI selected |
| Click outside | Pending text discarded, page URI restored |

## Comparison with the approved pictures

All eight required compositor PNGs are **byte-identical** to the concierge-approved captures in `../address-editing.pSJ0QP`. The contact sheet is also byte-identical (SHA-256 `b7df32af1452aa801739b9faa4b33524dd3479a3ccf74d6650f5bb31aa7c6ce0`). See `approved-png-comparison.tsv` and `contact.sha256`. The timestamp/event-order correction in the final browser code did not alter any acceptance picture.

## Authentication and documented upgrade

Each real bridge/browser pair received independent inherited read descriptions of a fresh 32-byte random credential. Its mode-0600 file lived in a private mode-0700 directory and was unlinked before either endpoint started. Credential bytes were never placed in argv, environment, logs or evidence files. Unrelated subprocesses closed the credential descriptors.

Before each legitimate browser launch, the proof submitted three unauthenticated candidates to the same bridge listener:

| Candidate | 1440 rejection time | 480 rejection time |
| --- | --- | --- |
| Wrong 32-byte credential | 2 ms | 2 ms |
| Short input and EOF | 0 ms | 0 ms |
| Stalled candidate | 252 ms | 252 ms |

Every candidate was disconnected without receiving transport data. The bridge stayed alive and the legitimate browser then authenticated, presented, and completed the clipboard assertions. See each width's `auth-rejection.log`. The separate descriptor-bridge regression establishes that the Unix compositor is not connected before valid authentication; this screenshot harness verifies the surviving listener and subsequent real application path.

The wide launcher smoke compiled the actual pre-change transport from `3025bc8:bridge/byte_descriptor_bridge.c`, recorded its source/binary hashes, and installed that executable only after the frozen primary browser and bridge had exited. It then ran the documented `sh tools/build.sh` → `sh tools/wayland-run.sh` sequence. The browser build left the old bridge intact; the normal launcher rebuilt the transport, authenticated successfully, presented `about:welcome`, and exited with empty stderr. The resulting browser and bridge matched the frozen candidate byte for byte. The narrow launcher smoke also passed. See `legacy-bridge-commit.txt`, `legacy-bridge.sha256`, `1440/documented-build.*`, and both widths' `launcher-smoke.*`.

## Identity and scope

Frozen browser SHA-256: `514da8b45cf147b6b117e78dae3a05db04bc848c87084b8149d8c99ee085ca62`.

Frozen bridge SHA-256: `fe496afd1271743d69db0694127bb93b53c4d04f96305759476d77e3e2c31ed3`.

Pinned compiler SHA-256: `60149069984ecfe491e322eba406238555c13acc90375c5468e5d5d4954a83ca` (release `2026.11.17-e6d13590b`). See `commit.txt`, `binaries.sha256`, `final-binaries.sha256`, `toolchain.lock`, `source.sha256`, `source-after.sha256`, and `source-stability.txt`. `harness.sha256` records the exact launcher, authentication helper, bridge/browser build scripts and proof tools. The original source and harness remained unchanged throughout this run. The capture's shared gate was held throughout both widths and the wide documented build, then released by cleanup; absence was explicitly checked before handing the lane back to the parent. The corrected browser source is from `b0a3c7e`; `5a821611` adds the gate-owning harness and documentation.

All source/sink operations here have real data-device authority. Absent-authority no-op behavior is established separately by the synthetic protocol/application checks; these pictures do not claim to provide an unavailable authority. Visual approval belongs to Claude; these files provide the requested evidence for that review.
