# Continuous real-Weston motion proof

## Result

On 2026-11-17 from 17:37:17 to 17:37:32 UTC, one native browser process
(PID 3583610) stayed open on a private Weston 13.0.0 headless compositor.
It scrolled the HTTP article, returned to the top, clicked its navigation link,
loaded the workshop page and its PNG, then scrolled that page and returned home.

[Watch the continuous capture](scroll-and-link.png) (animated PNG, 1000 × 760,
55 actual compositor captures, 2,677,918 bytes). Its SHA-256 is:

```text
73ba0715fb73998f6185ef37304dc8bd4a8d3d5b3fbaf02811380d48e02948a9
```

Weston's own `weston-screenshooter` captured every frame while that same
browser process remained mapped. No browser screenshot/framebuffer output
was used. Each PNG's compressed pixel stream is preserved in the APNG. Playback
uses the measured capture intervals and an explicit one-second final-frame
hold; one cycle lasts 11.789 seconds and repeats for review.

## Observable steps

| Keyframe | Capture offset from process launch | What is visible |
|---|---:|---|
| [Initial article](keyframes/01-article.png) | 696 ms | Initial title, prose, emphasis, links, and scrollbar |
| [Scrolled article](keyframes/02-article-scrolled.png) | 4504 ms | Six scroll events have exposed the list and another heading |
| [Home](keyframes/03-home.png) | 5500 ms | Home-key handling restores the original article frame exactly |
| [Clicked destination](keyframes/04-clicked-workshop.png) | 7101 ms | URL changed to simple.html, back button is active, PNG is displayed |
| [Scrolled workshop](keyframes/05-workshop-scrolled.png) | 8288 ms | The destination document has scrolled after navigation |

The reviewer opened the initial article, scrolled article, and clicked-destination
keyframes. Text wrapping, list spacing, continuous link underlines, and the
displayed image are clear. The initial and Home frames have identical hashes.

The native event log records all ten scheduled actions. Its final summary is:

```text
Wayland: sent 55 messages, received 44, presented 11 frames
```

The final native layout dump confirms:

```text
URL http://127.0.0.1:44881/simple.html
VIEW 1000 760 SCROLL 0
```

The HTTP fixture server handled article, workshop, PNG, and shutdown requests.
Browser and bridge stderr logs are empty, and the compositor log reports no
errors. The 55 captured frames include repeated presentations between the
browser's 11 committed frames.

## Identity and isolation

The exact frozen browser binary was:

```text
73b03dd2d77cf55c243259680caf00032b61fad9589c6fc36bc2959a1d3e8e98
```

The shared binary was built at 17:34:06 UTC, after the current main, underline
layout repair, and resolver repair source timestamps. Its hash still matched
after capture. Source and fixture hashes also stayed unchanged.

[binaries.sha256](binaries.sha256), [frozen-binaries.sha256](frozen-binaries.sha256),
[source-fixtures.sha256](source-fixtures.sha256),
[source-fixtures-after.sha256](source-fixtures-after.sha256),
[fonts.sha256](fonts.sha256), and [capture.sha256](capture.sha256) retain the
exact identities. The pinned compiler SHA remains
`60149069984ecfe491e322eba406238555c13acc90375c5468e5d5d4954a83ca`.

Only owned temporary processes and files were used. The private compositor,
socket, fixture listener, transport bridge, and browser all exited and were
reaped. A subsequent process inspection found no remaining process with the
owned runtime path. Shared sources, binaries, existing processes and previous
proofs were left untouched.

## Reproduction and limits

The writer's actual `--live-script` format is `MILLISECONDS ACTION`, with
absolute, ordered timestamps. The supplied [events.script](events.script)
uses ordinary scroll, Home-key, and coordinate-click handlers. It does not use
the replay helper's direct open/follow commands.

[commands.log](commands.log) records the expanded command sequence.
[frames.tsv](frames.tsv) records actual capture offsets from process launch.
[capture-summary.json](capture-summary.json) maps keyframes to original files.
The reusable script is [capture-integrated.sh](../../capture-integrated.sh);
it requires an explicitly supplied approved browser hash before freezing and
running that binary.

The replay validates live application event handling, hit testing, navigation,
rendering, and actual Wayland presentation. Input is deliberately injected by
a test harness; this does not establish physical keyboard/mouse or real-seat
delivery. The native Wayland input-peer test supplies separate decoder evidence.
The temporary byte/descriptor bridge remains in use. No HTTPS or JavaScript
behavior is claimed. This proof applies to the exact recorded binary.
