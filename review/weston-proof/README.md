# Independent real-compositor review

## Result

On 2026-11-17 at 17:14:32–17:14:52 UTC, the existing native browser displayed all
three required pages on a fresh Weston 13.0.0 headless compositor. These PNGs
were captured by Weston's `weston-screenshooter` from the actual compositor
output. No browser screenshot or framebuffer-dump option was used.

- [Article](article.png): long article loaded over HTTP, with headings, links,
  bold/italic runs, comfortable line spacing, and a visible scrollbar.
- [Simple page](simple.png): single-column page loaded over HTTP, including
  the PNG landscape fetched separately and decoded by the browser.
- [Unreachable destination](unreachable.png): a real refused connection to
  a freshly allocated then closed loopback port, displaying the browser's
  connection-error document.

All images are 1000 × 760 pixels. The independent reviewer opened all three:
text is readable, baselines and wrapping appear consistent, the image is
visible, and error copy fits without overlap.

## Isolation and commands

The review used only its own directory and
`target/independent-review-weston-1r1nMm`. It copied the existing browser,
descriptor bridge, and fixture-server executables there before launching them.
It did not rebuild or alter shared sources, binaries, sockets, logs, or
processes. The original compositor was left running untouched.

The exact orchestration is [capture.sh](capture.sh); expanded commands are in
[commands.log](commands.log). The capture used a private mode-0700 runtime
directory, a separate Wayland socket, fresh loopback ports, and no system
installation. All its child processes exited and were reaped. A process
inspection after cleanup found no remaining process using the private path.

The fixture server handled four successful requests: article, simple page,
PNG image, and shutdown. The error attempt used another, closed port.
Each browser log reports:

```text
Wayland: sent 25 messages, received 34, presented 1 frames
```

The three browser stderr logs and screenshot stderr logs are empty.
See [weston.log](weston.log), the per-page subdirectories, and
[http-server.log](http-server.log) for the observations.

## Identity

The exact browser binary was:

```text
12d3d9ef84212471c8d0af5581eb90ebf41b8d13ba9bad9b9f319f772939bcae
```

The installed compiler executable matches the pinned generation-two release
`2026.11.17-e6d13590b`:

```text
60149069984ecfe491e322eba406238555c13acc90375c5468e5d5d4954a83ca
```

Full hashes are in [binaries.sha256](binaries.sha256),
[frozen-binaries.sha256](frozen-binaries.sha256),
[source-fixtures.sha256](source-fixtures.sha256),
[compositor-binaries.sha256](compositor-binaries.sha256),
[fonts.sha256](fonts.sha256), and
[screenshots.sha256](screenshots.sha256). Source and fixture hashes stayed
unchanged during capture.

## Limits

This review deliberately reused the supplied executable. Its claims apply to
the exact browser hash above, not to any later rebuild. Recording current
source hashes is not an independent reconstruction of that executable.

These are actual compositor presentation proofs. The headless compositor has
no physical keyboard or pointer, so these captures do not prove hardware input,
scrolling, or clicking. Those behaviors have separate protocol-peer and
application-replay tests. The run proves a refused loopback connection, not a
remote-host connection timeout. It makes no HTTPS, JavaScript, XKB, or IME claim.

The byte/descriptor transport remains the documented temporary freestanding
C bridge. Protocol encoding, HTTP, HTML/CSS/layout, TrueType painting, PNG
decoding, and browser UI are performed by the native lkjscript-built program.
