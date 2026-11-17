# Timed input replay for a continuous Wayland capture

## Purpose and ownership

This is a proposed `src/main.lkj`-only patch. Shared sources were not edited.
The patch was developed and built in the copied snapshot recorded in
[snapshot-path.txt](snapshot-path.txt).

The writer should apply or rebase [main-live-script.patch](main-live-script.patch).
Its exact base `src/main.lkj` SHA-256 is:

```text
553dc4af84605b5af15e4641875006207307469c77b29bd435148f672fcc5f6f
```

The proposed file SHA-256 is:

```text
9b4ba9e9f49b317c362c6d83ca54db3cb82a4343387ae585dbcc49ae44b4f5f7
```

If the shared file differs, rebase the small changes rather than replacing the
file. The snapshot's native build and 52 native tests passed with one job;
see [build.log](build.log), [tests.log](tests.log), and
[patched.sha256](patched.sha256).

## Behavior

- Existing `--script FILE` keeps its current behavior: execute the complete
  script before initial painting, including in headless mode.
- New `--live-script FILE` is explicitly test-only and requires `--wayland`.
  It reads the supplied file once, ignoring blank/comment lines.
- `--script-interval-ms N` sets the interval, default 1000 milliseconds.
  Zero and values that overflow nanosecond conversion are rejected.
- Once the window opens, the event loop feeds one script line through the
  existing replay and ordinary browser event/navigation handlers per interval.
  A queued input does not advance while the previous framebuffer is still
  pending submission.
- Each step writes its elapsed time, command, resulting URL, and scroll
  position to stdout. No UI text or page copy is added.
- Lifetime remains controlled by the existing `--max-ms` option or ordinary
  window input. The capture script should set an explicit duration.

[scroll-and-link.script](scroll-and-link.script) scrolls the article, uses the
ordinary Home-key handler to return to the top, then clicks the existing
navigation link at (130,120). It does not invoke the script's direct
`open` or `follow` commands.

Example invocation after the writer has applied the patch:

```sh
target/lkjbrowser --wayland BRIDGE_PORT --frame-file FRAME_PATH \
  --live-script review/motion/scroll-and-link.script \
  --script-interval-ms 1200 --max-ms 11000 \
  http://127.0.0.1:FIXTURE_PORT/article.html
```

## Continuous proof plan

Start one private compositor and one browser process. Capture the compositor
output repeatedly while this same process stays mapped: initial article,
several scroll positions, Home, and the clicked destination containing its PNG.
Keep the browser PID, binary/source hashes, step log, and capture timestamps
with the resulting short video. There must be no browser restart between
frames and no substitution of browser-owned framebuffer dumps.

The writer should rebuild after integrating parser fixes and this patch before
that final capture. This review has not started a long capture or edited the
existing real-Weston proof.

## Honest limit

These events are injected into the browser's ordinary handlers by an explicit
test harness. The recording proves the live application's scroll/hit-test/
navigation/rendering behavior and its Wayland presentation in one process.
It does not prove physical input hardware or delivery from a real Wayland seat.
The protocol-peer tests remain separate evidence for Wayland event decoding.
