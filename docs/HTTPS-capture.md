# Capturing authenticated pages in the actual Wayland window

Use tools/capture-https.sh after the native build and offline TLS gate have
passed. The script does not build, install dependencies, change the trust store,
or start a web server. Coordinate a stable browser binary before starting it;
the final hash check rejects a capture during which the shared browser was rebuilt.

Prerequisites are the existing native browser, byte/descriptor bridge,
pixel-comparison tool, APNG assembler, and locally unpacked Weston 13 utilities.
The script freezes copies of the four native executables at the start. All
browser runs in that invocation therefore use the same exact executable bytes.

## Five public pages

Prepare docs/tls/public-pages.tsv with exactly five unique rows:

- The first field is a short filename name using letters, digits, underscore or hyphen.
- A literal tab separates the name from the complete URL.
- Blank lines and lines beginning with # are ignored.

Then run:

    bash tools/capture-https.sh --round r1

An explicit manifest and trust file can be supplied:

    bash tools/capture-https.sh --manifest docs/tls/public-pages.tsv \
      --round r2 --trust-file /etc/ssl/certs/ca-certificates.crt

The manifest accepts file/HTTP URLs so the capture machinery can be checked
offline, but those inputs are recorded literally and provide no HTTPS evidence.
The real-page proof must use the chosen authenticated public HTTPS pages.

Each page runs sequentially in one owned compositor. The script waits for the
browser's Wayland presentation marker, rejects a rendered error page, and obtains
a real weston-screenshooter screenshot. It compares every pixel against the
native browser's own PNG from that presentation. A mismatch fails the command;
the script does not refresh any expected picture to make a comparison pass.

Outputs are:

- shots/https-NAME-ROUND.png: actual compositor screenshot.
- shots/https-NAME-ROUND.layout: resulting URL, title, viewport and layout.
- docs/tls/wayland-ROUND.log: executable, compiler, trust-bundle, compositor and
  source hashes; requested URLs; browser timing/protocol logs; pixel comparisons;
  cleanup and exit result.
- target/latest-https-capture-ROUND: path of the retained temporary evidence.

The renderer still needs visual inspection. Open all five screenshots, identify
what makes actual page text unreadable, fix those findings, then capture another
round. A zero-pixel difference proves that the compositor showed the program's
pixels; it does not prove that the page layout is good.

## Enter-triggered still captures and timing

Use the optional --enter still mode to measure a navigation initiated through
the browser's ordinary Enter handler for each of the five HTTPS pages:

    bash tools/capture-https.sh --enter --round r2

For each manifest row, the same native window starts at about:welcome. A
generated live script replaces the address field at scheduled 100 ms and sends
Enter (key 28) at scheduled 200 ms. It performs address replacement through
application-event replay, not physical typing or hardware keyboard input.
The window remains owned by that browser process throughout the navigation.

The capture wait requires the Enter replay marker followed by an HTTPS
PAINT wayland-submit marker. The initial about:welcome presentation cannot
satisfy it. A successful HTTPS redirect is allowed; the proof records both the
requested URL and the final presented URL, and checks that the captured layout
matches that final URL. Error pages still fail the capture.

Each browser runs with --max-ms 12000 and exits naturally after its event-loop
lifetime. The screenshot and full-pixel comparison happen after the target
presentation while that window is still open. Five sequential pages therefore
take approximately one minute, plus compositor and capture overhead. The same
frozen binary and existing process cleanup are used.

In addition to the usual screenshots and layouts, this mode saves
shots/https-NAME-ROUND.live and records its hash, contents and Script markers.
The proof log includes one ENTER_TO_FIRST_WAYLAND line per page with elapsed_us,
requested_url and presented_url.

The elapsed value comes from the browser's monotonic navigation timer, started
inside the Enter handler and stopped at the first target Wayland presentation
submission. The 100/200 ms script values are scheduled event-loop offsets;
they are not precise event dispatch timestamps. Do not subtract those offsets
from screenshot time or describe the result as physical keypress latency.
The subsequent actual compositor screenshot and pixel comparison establish
what was displayed, but do not timestamp its first appearance on a display.

--enter requires HTTPS manifest URLs and cannot be combined with --motion.
Omitting it preserves the original direct CLI-navigation still capture.

## Continuous address, scrolling and link recording

Prepare a timestamped application-event script in the existing --live-script
format. Times are milliseconds after the Wayland event loop begins. Include
address editing and Enter (key 28), a scroll, and a coordinate click that follows
a link to a second HTTPS URL. Leave at least the final second still.

Run motion mode separately from the five-page capture to avoid extra page loads:

    bash tools/capture-https.sh \
      --motion tests/https-demo.live about:welcome \
      --round demo-r2 --frames 26 --delay-ms 400

The supplied events file is required; this command does not invent link
coordinates. Choose them from the inspected page layout. The complete last event
must fit before (frames × delay-ms) − 1000 milliseconds. Frame count is 16–30;
delay is 100–1000 ms. The defaults capture 26 frames with a nominal 400-ms delay.

One browser process remains open for the whole recording. After the first
submission marker, motion capture waits an additional 200 ms for the compositor
repaint before sampling. Inspect the first frame: submission alone does not prove
that the initial window is already visible. Each frame comes from
the actual compositor, never from an invented animation or rerendered page.
Actual frame-capture timestamps are saved alongside the PNGs. The native APNG
assembler retains their compressed pixel data and verifies its fallback frame.

Motion mode requires evidence of Enter, scrolling, a coordinate click and
presentation of at least two distinct HTTPS URLs. The final page must be
successful, and its entire compositor image must match the browser image.

Outputs are:

- shots/https-motion-ROUND/: original compositor PNG frames, actual frame times,
  the exact replay script, final layout/image and browser log.
- shots/https-motion-ROUND.apng: the round-specific animation.
- shots/https-first.apng: the current HTTPS demonstration.
- shots/scroll-and-link.apng: the same current recording at the owner's existing
  review path.
- docs/tls/wayland-ROUND.log: hashes, timing, pixel and animation evidence.

Input is application-event replay through the ordinary browser handlers. It is
not physical keyboard/mouse input, and the proof log states that distinction.
The APNG uses the requested nominal frame delay; the timestamp file records the
actual screenshot schedule.

## Isolation and cleanup

The script directly starts an owned Weston with a fresh mode-0700 runtime
directory. It does not use tools/wayland-headless.sh, because that older wrapper
sets a shared runtime directory internally. Browser, bridge, screenshooter and
compositor PIDs are individually owned, stopped and reaped on success, failure,
or interruption. The owned runtime directory is removed. No other browser,
compositor, project process, service, public port or system installation is
touched.

Network establishment in the pinned language still has its documented
unbounded-connect limitation. The capture harness therefore also gives initial
presentation a finite external wait and stops its owned process on failure.
That harness safeguard does not turn the browser's TCP connect into a
deadline-aware runtime operation.
