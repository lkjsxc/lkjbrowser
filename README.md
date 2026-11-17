# lkjbrowser

A native Wayland browser written in generation-two lkjscript. It fetches a document,
builds a tree, computes a small CSS subset, wraps text using runtime TrueType metrics,
rasterizes outlines, paints pixels, and speaks the Wayland wire protocol itself.

The first slice includes **file and plain HTTP navigation, scrolling, links, an address
line, back navigation and PNG images**. **HTTPS is not implemented.** Authenticated TLS
1.3 and certificate verification are the next milestone. JavaScript is not implemented.

## Run

Linux x86-64, a Wayland compositor, GCC for the temporary transport bridge, and installed
Liberation Sans or DejaVu Sans TrueType fonts are required.

```sh
sh tools/build.sh
sh tools/wayland-run.sh 'http://example.com/'
```

The second line runs the **same `target/lkjbrowser` binary** on a real Wayland desktop.
The launcher uses `XDG_RUNTIME_DIR` and `WAYLAND_DISPLAY`, creates an owned temporary
frame file, starts the bridge on a fresh loopback port, and cleans up that bridge.

For a local document:

```sh
sh tools/wayland-run.sh "file://$PWD/fixtures/article.html"
```

Without a compositor, the same binary writes its own image and layout:

```sh
target/lkjbrowser --headless --screenshot shots/article-local.png \
  --layout target/article.layout "file://$PWD/fixtures/article.html"
```

`--screenshot` writes PNG when the name ends in `.png`, otherwise PPM.
`--width`, `--height` and `--scroll` select the viewport and document position.
`--font-dir DIR` selects four LiberationSans font files; `--dns IPv4` selects an
IPv4 DNS resolver for TCP queries. `--help` lists the invocation.

### Controls

| Action | Input |
| --- | --- |
| Edit address / replace the entire address | Ctrl+L, type, Enter |
| Follow a link | Left click |
| Scroll | Wheel, Up/Down, Page Up/Page Down, Space |
| Beginning / end | Home / End |
| Back | The < button, or Ctrl+Left |
| Reload | Ctrl+R |
| Cancel address editing | Escape |
| Close | Compositor close, Ctrl+Q or Ctrl+W |

The minimal address editor appends text and supports Backspace and whole-address selection.
Keyboard text currently uses the US physical-key layout; modifier focus transitions and both
left/right modifiers are tracked. Clipboard, IME, keymap parsing and editable caret movement
are future work. The window advertises a fixed size selected at launch.

## What is implemented

| Layer | Implementation |
| --- | --- |
| Wayland | Registry, wl_compositor, wl_shm, xdg-shell configure/ping, seat pointer/keyboard, cursor, two release-tracked buffers |
| Networking | IPv4 TCP, DNS A queries over TCP, HTTP/1.1 response framing, chunked transfer/trailers, redirects, identity encoding |
| Documents | Indexed owned HTML tree, attributes, entities, selected optional close tags, raw style/title/script handling |
| CSS | Block/inline/none, supported selectors/cascade, margins/padding, colors/backgrounds/borders, font size, bold/italic, alignment and line height |
| Layout | Block and inline text, wrapping across style nodes, common baselines, list markers, anchors and text/image link hit tests |
| Fonts | Runtime SFNT TrueType cmap/metrics/glyf parsing, simple and compound outlines, quadratic curves, 4×4 coverage, cached masks |
| Images | Native PNG decoder and encoder; stored/fixed/dynamic DEFLATE, all five filters and supported 8-bit color types |
| UI | Address line, history, wheel/key scrolling, link following and ordinary error pages |

All browser code is in `src/*.lkj`. No web engine, font library, PNG codec, TLS helper,
HTML parser or renderer is called by the browser.

### The temporary exception

`bridge/byte_descriptor_bridge.c` is a small **freestanding syscall-only transport**,
compiled without libc or a dynamic loader. It connects an explicit Unix socket, transports
opaque bytes and attaches the supplied frame-file descriptor when asked. It performs no
Wayland interpretation, parsing, layout, text, pixels, DNS or HTTP. Incoming descriptors are
currently closed, which is one reason compositor keymaps are not consumed.

The pinned language has neither a Unix-path connector nor descriptor-message operations on
an opened stream. Those two capabilities remove the bridge. Writable mappings are optional:
the browser already paints through ordinary file writes. [GAPS.md](GAPS.md) records the
observed boundaries, exact probes, integration counts and replacement shapes.

The browser's `World` entry declares full authority. Its application policy allows explicitly
typed local-file navigation and local-page links, while an HTTP page cannot reach local files
through links, redirects or images. History/reload preserve that decision. Document and image
reads use `Directory.open_regular`: FIFOs, devices, directories and final symlinks are refused
before data-open. A separate reader accepts the OS-owned `/etc/resolv.conf` symlink, checks
the opened object is a regular file, and caps configuration reads at 64 KiB. A page cannot
select this configuration path. These policies use existing lkjscript capabilities.

## Reproducible tests

```sh
sh tools/test.sh
```

This one command verifies the toolchain hash, builds the native browser, runs the unit cases,
checks the documented negative and positive language probes, runs a native Wayland test peer,
starts a throwaway lkjscript HTTP server on `127.0.0.1:0`, and compares committed layout trees
and document-viewport SHA-256 pixel hashes.

It covers five visual goldens; file/HTTP/chunked/redirect equivalence; PNG over HTTP; scroll,
link click, back and key-code replay of Ctrl+L address navigation; malformed/truncated/oversized HTTP;
ordinary error pages; and synthetic local-file origin/FIFO/symlink/history/reload cases.
The pixel region excludes the URL/status chrome, whose ephemeral port and checkout path vary.
The layout comparison omits only its first URL line; the resulting URL is separately asserted
for navigation tests. Real font hashes are fixed in `tests/fonts.sha256`.

The default test command does not require an internet connection after the toolchain is
present. It needs the recorded Liberation Sans font version. Set `LKJBROWSER_FONT_DIR`
if those files are installed elsewhere. To deliberately accept reviewed visual changes:

```sh
sh tools/test.sh --update-goldens
sh tools/test.sh
```

Do not refresh goldens to conceal a failed comparison. The full malformed-font native witness
is also reproducible with `sh tools/font-security.sh`.

## Actual window proof

```sh
sh tools/capture-wayland.sh
```

This starts an owned Weston 13 headless pixman compositor, a fresh native HTTP fixture server,
the byte/descriptor bridge and the actual browser, then stops all processes it started.
It captures three actual compositor screenshots and compares every pixel with the browser's
own PNG: [article](shots/article.png), [PNG page](shots/simple.png), and
[unreachable endpoint](shots/error.png). The comparison record is
[docs/wayland-final-proof.log](docs/wayland-final-proof.log).

The same command also captures [a short scrolling/link animation](shots/scroll-and-link.apng)
from one continuously running native browser. `--live-script tests/demo.live` replays timed
application events while that window is open. This is event replay, not physical hardware
input; [docs/motion-proof.log](docs/motion-proof.log) records that distinction. The APNG tool
is also lkjscript and retains the exact compositor screenshot pixels.

The compositor packages are downloaded and unpacked only beneath `.deps`; no system package
installation or service is created. The helper package list targets this Ubuntu 24.04 host.
A different distribution can use its existing compositor or adapt the local package list.

The separate `sh tools/wayland-test.sh` verifies registry/seat traffic, fd intent,
configure acknowledgement, ping/pong, cursor requests, motion, click, wheel, key press/release,
focus restoration and close against a native lkjscript protocol peer. This is explicit input
protocol evidence; the pixman captures provide actual-compositor presentation evidence.

[docs/visual-review.md](docs/visual-review.md) records the repeated inspect/fix cycles.
The final proof includes corrections to spacing, balanced text, narrow wrapping and links.

## Pin and architecture

`toolchain.lock` fixes:

- Tag: `2026.11.17-e6d13590b`
- Commit: `e6d13590b7bb2d665d668727f1a8d1ee4f76c33d`
- SHA-256: `60149069984ecfe491e322eba406238555c13acc90375c5468e5d5d4954a83ca`

`tools/fetch-toolchain.sh` verifies both the published checksum and the downloaded binary
against the lock. The binary and build products are ignored by Git. A pin update must be a
deliberate commit. No generation-one release, moving compiler build, custom runtime override
or adjacent language-library checkout is used.

| Module | Responsibility |
| --- | --- |
| `main.lkj` | Application state, origin policy, input, navigation, chrome and painting dispatch |
| `net.lkj` | URLs, regular files, DNS/TCP, deadlines and HTTP framing |
| `html.lkj`, `css.lkj`, `layout.lkj` | Document tree, supported style semantics, boxes and inline runs |
| `font.lkj`, `paint.lkj` | Font parsing, outlines, glyph masks and pixel canvas |
| `png.lkj` | PNG/DEFLATE decoding and native PNG output |
| `wayland.lkj` | Wayland object state, wire messages, buffers and input |

`program.lkj` is the reviewed invocation. `.toolchain/lkjscript authority .` reports the
declared World authority and reachable effects. The language repository is read-only to this
project. This repository is local-only and has no remote or release.

## Remaining boundaries and next work

HTTPS/TLS and certificate authentication come next; see [docs/next-tls.md](docs/next-tls.md).
The source libraries needed for that work are not missing OS permissions. No insecure TLS
substitute or certificate-verification bypass is provided.

Navigation is currently synchronous. The six-second deadline covers I/O **after a connection
has been established**, not the pinned capability's blocking TCP handshake. Existing owned
processes could isolate a fetch today; a readiness-based connect operation is the cleaner direct
API. A dead handshake can therefore delay the UI and its initial window.

There is no JavaScript, complete HTML5 recovery, external stylesheet loading, flex/grid/table/SVG
layout, forms, cookies, authentication, compression, IPv6 or IDNA. Text is Unicode-decoded but has
no shaping, bidi, fallback-font selection or kerning. CFF outlines and non-8-bit/Adam7 PNGs are not
supported. Unsupported features are not silently delegated to another browser or library.

The precise subset and application resource policies are in [docs/html.md](docs/html.md),
[docs/font.md](docs/font.md), [docs/png.md](docs/png.md) and [docs/wayland.md](docs/wayland.md).
The document cap, font/cache budgets, PNG limits and CSS bounds are browser policies, not
claims about language limits.
