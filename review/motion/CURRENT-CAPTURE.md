# Current integrated motion capture

The writer independently integrated absolute-time live scripts. The earlier
[proposal](README.md) and `main-live-script.patch` are retained as review history;
their `--script-interval-ms` CLI is not the current implementation.

Current syntax:

```text
1600 scroll 120
5000 key 102
6200 click 130 120
```

Pass that file with `--live-script FILE` while running a real Wayland window.
Existing `--script FILE` retains its earlier prepaint behavior.

The completed final recording and evidence are in:

[captures/independent-review-motion-capture-wQWDXO/README.md](captures/independent-review-motion-capture-wQWDXO/README.md)

It used the shared 17:34:06 binary after the parser, underline, and resolver
repairs. One browser process completed ten timed inputs and presented eleven
frames. Fifty-five real compositor screenshots were retained and losslessly
packaged as an animated PNG with measured capture intervals.

Run a future capture only after identifying an approved rebuilt binary hash:

```sh
bash review/motion/capture-integrated.sh APPROVED_BROWSER_SHA256
```

Each invocation creates a fresh evidence directory, freezes the existing
executables and fixtures, starts only private owned processes, and preserves
earlier recordings. It performs no build or shared-source write. An explicit
SHA guard prevents accidentally recording a moving executable. No system
package installation, external network, Python, ffmpeg, or image alteration
is needed. Input remains test-harness replay through ordinary browser handlers;
the result is not physical-seat proof.
