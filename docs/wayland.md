# Wayland implementation and proof

The pinned generation-two compiler builds `src/wayland.lkj` into the browser's
native executable. All object allocation, registry binding, wire encoding,
message validation, xdg configure acknowledgements, shm pool/buffer creation,
surface commits, ping/pong, pointer/keyboard handling and buffer release tracking
are lkjscript code. No Wayland client library is linked.

## Actual compositor proof

Weston 13.0.0 from Ubuntu Noble packages was downloaded and unpacked beneath
`.deps/`; nothing was installed system-wide. Its headless backend uses Pixman,
with a 1000 x 760 output and kiosk shell. The compositor ran at 2026-11-17
16:50 UTC, about five minutes after the initial dependency survey.

The standalone native smoke opened an xdg toplevel, presented two different
buffer objects, and observed release of the previous buffer. The observed
counters are in [wayland-smoke.log](wayland-smoke.log).
[The transport screenshot](../shots/wayland-transport-proof.png) was captured
by Weston's own `weston-screenshooter`, not copied from the client's buffer.
The screenshot was opened and inspected: the full viewport matches the native
program's test gradient. This is real-compositor proof, not a mock peer.

Startup initially failed because the bridge opened the framebuffer descriptor
read-only; Weston maps shm buffers writable. Changing only that open mode to
read/write fixed the failure. The bridge did not gain protocol knowledge.

## Temporary byte and descriptor transport

`bridge/byte_descriptor_bridge.c` is compiled freestanding with `-nostdlib
-static -fno-builtin`. It contains Linux x86-64 syscall glue and no libc,
Wayland, text, layout, networking-protocol, or painting implementation.

It takes exactly a Unix socket pathname and an existing frame-file pathname.
It binds a fresh loopback TCP port and prints the assigned port. A private
32-byte credential arrives on inherited stdin; it is not an argument or environment
value. Each TCP candidate must supply the exact credential within an absolute
250 ms window. Wrong, short and stalled candidates are closed while the same
listener remains available. Only the authenticated client causes the bridge to
connect to the Unix stream and open the frame file read/write. It then closes the
listener. No fixed/occupied port is used.

Each client-to-bridge transport frame has two little-endian u32 words:
payload length and operation. Operations forward opaque bytes, attach the opened
frame descriptor, attach a fresh pipe's write end, write bytes to a received
descriptor, or close a descriptor token. Unix reads are framed separately with
their received SCM_RIGHTS tokens; fragmentation does not insert metadata into the
Wayland byte stream. The helper does not interpret Wayland objects, opcodes or MIME.

The bridge bounds descriptor work to 64 live handles, one MiB per transfer and
five seconds of inactivity. Read transfers report EOF or failure separately from
their bytes. The lkjscript client accepts a paste only after successful EOF and
UTF-8 validation, never a partial failure. Unused descriptors, including keymaps,
are closed. `sh tools/descriptor-bridge-test.sh` exercises actual Unix descriptors,
fragmented opaque bytes, successful transfers, oversize rejection and closed consumers.

This is temporary infrastructure, **not an lkjscript-only browser claim**.
Removing it requires typed Unix connection and descriptor-message capabilities.
Keyboard text uses the documented US physical-key subset. IME and arbitrary XKB
layouts are not implemented. Plain-text clipboard semantics are implemented in
`src/wayland.lkj` through `wl_data_device_manager` version 1, `wl_data_device`,
`wl_data_source` and `wl_data_offer`.

Clipboard access requires the data device, descriptor transport and keyboard
focus. Copy also requires an input serial. It offers UTF-8/plain text and a private
per-instance nonce MIME marker. The client confirms its own marker in the
compositor's selection offer and completes a display round trip before reporting
copy success, so a rejected ownership request cannot delete cut text.
The marker is ownership evidence, not a payload format. Paste prefers UTF-8 plain
text, falls back to plain text, and is ignored after focus or editor state changes. The source offer is selected
at the time paste is requested; a later external selection does not substitute
another source mid-transfer. No-manager and no-authority operations return without changing text.

The framebuffer uses two slots. A slot remains unavailable until wl_buffer.release
arrives. Callers must seek/write into an available slot without truncating or
replacing the backing inode. An immutable 24 x 24 ARGB cursor follows the two
slots. The lkjscript client draws that cursor and presents its own cursor surface.

## Integration API

```text
Wayland::open(&mut World, port:u16, width:i32, height:i32, title:&str)
    -> Result<Wayland,String>
Wayland.slot_len() -> usize
Wayland.available(slot:u32) -> bool
Wayland.present(slot:u32) -> Result<(),String>
Wayland.poll(timeout_ms:usize) -> Result<Vec<Event>,String>
Wayland.clipboard_available() -> bool
Wayland.clipboard_copy(text:&str) -> Result<bool,String>
Wayland.clipboard_paste() -> Result<bool,String>
Wayland.clipboard_pending() -> bool
Wayland.take_clipboard() -> Option<String>
wayland::cursor_bytes() -> Vec<u8>  // exactly 2304 bytes
wayland::frame_file_size(width:usize,height:usize) -> usize
wayland::key_ascii(evdev_code:u32, shift:bool) -> u8
```

Events are Scroll(i32), Key(u32,bool), Click(i32,i32,u32), Release(i32,i32),
Motion(i32,i32), Leave, Resize(i32,i32), and Close. Scroll/pointer coordinates are logical pixels.
Key numbers are Linux evdev codes; bool is press/release. Click is a left press;
its final value preserves the compositor's millisecond timestamp. Multi-click
intervals use that event time, including its 32-bit wrap, so delayed event delivery
does not turn separate clicks into a double-click.
Keyboard leave clears physical modifier state; enter restores held modifiers from
the compositor's key array. Held non-modifier keys are not replayed as new actions.
The first slice requests fixed viewport size through xdg min/max constraints.
Resize carries compositor suggestions; the owner may keep the fixed viewport.

Run `sh tools/wayland-headless.sh` for the test compositor.
For test screenshots, set XDG_RUNTIME_DIR to the repository's `.deps/runtime`,
WAYLAND_DISPLAY to `browser-test`, and LD_LIBRARY_PATH to both unpacked
library directories; then run `.deps/root/usr/bin/weston-screenshooter`
from a chosen output directory.

## Language gaps observed

| Rank | Missing form | Sites | Blocked work | Smallest shape |
|---|---|---:|---|---|
| 1 | Unix stream connection capability | 1 | All native Wayland transport | `world.unix_connector(path)?.connect()?` |
| 2 | Descriptor send on owned socket | 1 | `wl_shm.create_pool` | `socket.send_message(bytes, &[&file])?` |
| 3 | Descriptor receive on owned socket | 1 | Removing clipboard transport bridge; future XKB keymap | `let (bytes,files) = socket.receive_message()?` |
| 4 | Mutable mapping | 0 required | Efficient direct paint, not this slice | `file.map_mut()?.bytes_mut()` |
| 5 | Source-view loan retained across owner assignment | 1 | Compacting incoming bytes | `v = v[n..].to_vec()` rejects; a lexical block holding the owned copy succeeds. |

Writable mapping is not necessary for correctness here: File.seek/write updates the
shared backing inode, and compositor reads only committed, unreleased buffers.
The transport does not need threads.

OPINION: Add an affine UnixConnector derived from an explicit directory/path capability, returning an owned socket; preserve Readiness integration and avoid raw descriptor integers.
OPINION: Add typed send_message/receive_message operations on owned Unix sockets, transferring or borrowing File owners with exact descriptor counts and close-on-failure behavior. This removes the whole bridge and admits real keyboard keymaps.
OPINION: Writable shared mappings can follow later; native File.seek/write is sufficient for this milestone. If added, exclusive byte loans must retain the mapping owner and its writable-file authority.
OPINION: The explicit-block workaround for owned slice copies is safe and local, but an agent-facing fix-it should be retained; the pinned compiler already emitted a correct concrete edit.

## Protocol sources

- [Official Wayland wire format](https://wayland.freedesktop.org/docs/book/Protocol.html)
- [Official core protocol XML](https://gitlab.freedesktop.org/wayland/wayland/-/blob/main/protocol/wayland.xml)
- [Official stable xdg-shell XML](https://gitlab.freedesktop.org/wayland/wayland-protocols/-/blob/main/stable/xdg-shell/xdg-shell.xml)

## Input decoder proof

`sh tools/wayland-test.sh` builds a native lkjscript test peer and a native
client probe. The peer dynamically tracks the client's object IDs, emits seat
capabilities and pointer/keyboard events, and independently checks the client's
configure acknowledgements, pong, cursor request, and shm descriptor flag.
The client verifies motion/click coordinates, wheel distance, both key states,
resize, focus loss/restoration, both Alt keys, close, and focused clipboard calls
with no advertised data-device manager. [The original observed results](wayland-input-proof.log)
record the earlier input proof; the address slice records its current run separately.
This is a test-only protocol peer; actual window presentation is independently
proved with Weston above. Headless Weston has no physical input seat, so no
claim is made that physical keyboard/mouse hardware was tested.

The test peer also exposed two empty-slice inference refusals: `&[]` still
needs `&[0u32;0]` even when the destination parameter is typed `&[u32]`.
The pinned compiler provided the exact applicable edit.

The xdg-shell XML was also read directly from the locally unpacked
`wayland-protocols` package. Constants are encoded explicitly in lkjscript;
there is no generated C/Rust protocol glue.

## Address editing compositor proof

`bash tools/address-proof/capture.sh PATH_TO_UNPACKED_DEPS_ROOT` starts a private
Xvfb display and Weston X11 backend, then injects XTest input into that compositor.
The native browser receives real wl_keyboard and wl_pointer events through its
normal entrypoint. An independent raw-Wayland source/sink transfers only synthetic
clipboard data. The harness never connects to the owner's desktop or clipboard.
It captures the four Claude acceptance states at 1440 and 480 and checks exact
clipboard bytes, pointer selection, word keys, Escape, outside discard and Alt history.
[Harness instructions](../tools/address-proof/README.md) distinguish this from physical
hardware input and from the older application-event replay.

## Authenticated launch

All real launch and capture scripts source `tools/wayland-auth.sh`. It creates
exactly 32 kernel-random bytes with mode 0600 inside a fresh mode-0700 directory,
opens two independent read handles, and unlinks the file before either endpoint
starts. The bridge and browser each inherit only their own stdin handle. The
launcher closes extra handles in intervening children and after both endpoints
start. Authentication completes before compositor bytes or descriptors can be
forwarded. The credential is never written to source, argv, environment or evidence.

The normal `tools/wayland-run.sh` entrypoint handles this automatically. Direct
invocation of `target/byte-descriptor-bridge UNIX_SOCKET FRAME_FILE` and a native
browser using `--wayland PORT` requires the same exact 32-byte credential on each
process's stdin. Closed or incomplete credential input is refused. Use
the launcher instead of supplying a credential interactively. The synthetic raw
protocol peer has an explicitly separate clipboard-disabled test entrypoint;
real launchers cannot use that bypass to access an authenticated bridge.

This isolates the listening endpoint from other unprivileged local user IDs;
it does not establish a boundary against another process with the same account's
permissions or a privileged process. A local connection flood can still consume
listener/backlog time. Per-candidate deadlines bound an individual stalled
attempt, while the harness verifies that rejected attempts leave the same listener
usable by the authorized client. The launcher retains its existing cleanup and
startup watchdogs; there is no claim of denial-of-service isolation.

See [clipboard transport details](clipboard-transport.md) for selection ownership,
source/offer cleanup, total paste deadlines and the independent regressions.
