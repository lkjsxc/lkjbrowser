# Isolated address editor proof

These are independent test programs, not browser runtime dependencies.

`xinput.c` sends XTest events to an owned Xvfb display running Weston's X11 backend. Weston translates those events into real `wl_keyboard` and `wl_pointer` messages on the private Wayland socket. No `--script` or `--live-script` browser replay is used. This establishes compositor input, not physical keyboard hardware.

`clipboard-peer.c` independently implements the minimum Wayland wire protocol for a synthetic data-device source and sink. It maps a small surface, obtains a real keyboard serial, and offers the explicit input fixture using `text/plain;charset=utf-8` and `text/plain`. The sink obtains an actual compositor offer and reads the descriptor transfer into a new output file. Both programs require an owned `address-proof-owned` marker next to the private socket. They never connect to the owner's display or clipboard.

## Prerequisites

Build the normal pinned browser and its byte/descriptor bridge first. GCC, Xvfb, libX11.so.6 and libXtst.so.6 must be present. The unpacked Weston 13 dependency tree must include the X11 backend, kiosk shell and screenshooter. Pass its root as the optional argument; the default is `.deps/root`.

The shared compiler gate must be free. On this workspace the lane is bounded to CPUs 24–31 at nice 10:

```sh
taskset -c 24-31 nice -n 10 bash tools/address-proof/capture.sh /home/coder/workspace/lkjbrowser/.deps/root
```

The script freezes the browser, bridge and helper binaries before starting. Each launch uses `tools/wayland-auth.sh` to give the bridge and browser independent inherited read descriptions of a fresh 32-byte random credential. The private token file is unlinked before either endpoint starts; credential bytes never enter argv, environment, logs, or evidence files. The proof first submits wrong, short, and stalled unauthenticated clients to the same listener, checks rejection, and then launches the legitimate native browser. The ordinary descriptor bridge regression separately checks that no compositor connection occurs before authentication. It creates fresh runtime directories and Xvfb displays, allocates fresh bridge ports, and kills/reaps only its own children. After the frozen browser checks, the ordinary `tools/wayland-run.sh` launcher also presents and exits cleanly on the same private compositor at each width. The wide smoke first installs an actual pre-change bridge compiled from `3025bc8`, then executes the documented `sh tools/build.sh` → `sh tools/wayland-run.sh` sequence. It verifies that the launcher replaces the stale bridge and that both resulting binaries equal the frozen candidate bytes. A cleanup guard restores the frozen binaries if this upgrade check fails. The normal launcher always rebuilds the small C transport before using it. A new `review/address-editing.*` directory receives screenshots, command scripts, input logs, clipboard byte oracles, compositor/client logs, and identities. `target/address-proof-last` names the output.

## Acceptance states and assertions

The ordinary native browser entrypoint starts at `about:welcome`. At both 1440 × 760 and 480 × 760, the script captures:

1. `01-middle-caret.png`: caret at byte/character 120 of the long ASCII address, reached with real Home and Right events.
2. `02-partial-selection.png`: Shift+Right extends that position by sixteen characters.
3. `03-start-caret.png`: Home returns to the start of the long address.
4. `04-after-multiline-paste.png`: real Ctrl+V receives the synthetic fixture containing CR, LF, tab and outer whitespace.

All PNGs come from `weston-screenshooter`, not from the browser framebuffer. Pointer movement to the page before capture keeps the pointer away from the address field.

Additional real clipboard transfers check the normalized pasted string exactly, double-click word selection (`https`), triple-click whole-address selection, drag selection with automatic horizontal scrolling, a pointer insertion at the start, copy/cut exact bytes, paste of the browser's own clipboard source, Ctrl+Shift word selection, and word deletion. Enter opens the local article fixture; Alt+Left/Right return the exact history addresses even while editing. Changed/unchanged Escape, F6, Alt+D, and outside-click discard are checked by independent clipboard byte oracles. `05-after-cut.png` records the emptied field. Per-check `*.input` files are the precise event reproduction; `*.sink.log` and `*.txt` record independent transfer evidence.

Run `node tools/address-proof/contact.cjs` after a successful capture to assemble unscaled toolbar crops into `acceptance-contact.png`. Rows 1–4 match the state list above; columns are 1440 and 480. The compositor PNGs remain the source evidence. This contact tool uses only Node standard libraries.

The headless no-data-device behavior belongs to the browser's ordinary input/unit/protocol tests; this real Weston proof requires clipboard authority and fails if it is unavailable. It must not be described as proof that an absent authority was provided.

## Peer self-check

After compiling the two helper programs (the capture script does this), run:

```sh
taskset -c 24-31 nice -n 10 bash tools/address-proof/selftest.sh /home/coder/workspace/lkjbrowser/.deps/root
```

This checks only the independent harness: XTest acquires an input serial, the source offers a 38-byte multiline fixture, and a second independent peer receives exactly those 38 bytes. It does not establish browser editing behavior.
