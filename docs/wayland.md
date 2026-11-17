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
It connects to that Unix stream, opens that file read/write, binds a fresh
loopback TCP port and prints the assigned port. It accepts one connection and
closes its listener. No fixed/occupied port is used.

Each client-to-bridge transport frame has two little-endian u32 words:
opaque payload length and a flag saying whether to attach the opened file
descriptor. The remaining bytes are forwarded unchanged via write/sendmsg.
Unix input is forwarded unchanged as a TCP byte stream. Incoming SCM_RIGHTS
descriptors are closed without interpreting their contents. The helper does
not know that the opaque data happens to be Wayland.

This is temporary infrastructure, **not an lkjscript-only browser claim**.
Removing it requires typed Unix connection and descriptor-message capabilities.
Received keyboard keymaps cannot yet reach this client; keyboard text uses the
documented US physical-key subset. IME, clipboard and arbitrary XKB layouts are
not implemented.

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
wayland::cursor_bytes() -> Vec<u8>  // exactly 2304 bytes
wayland::frame_file_size(width:usize,height:usize) -> usize
wayland::key_ascii(evdev_code:u32, shift:bool) -> u8
```

Events are Scroll(i32), Key(u32,bool), Click(i32,i32), Motion(i32,i32),
Resize(i32,i32), and Close. Scroll/pointer coordinates are logical pixels.
Key numbers are Linux evdev codes; bool is press/release. Click is a left press.
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
| 3 | Descriptor receive on owned socket | 1 | XKB keymap, future clipboard | `let (bytes,files) = socket.receive_message()?` |
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
resize, focus loss/restoration and close. [Observed results](wayland-input-proof.log) pass.
This is a test-only protocol peer; actual window presentation is independently
proved with Weston above. Headless Weston has no physical input seat, so no
claim is made that physical keyboard/mouse hardware was tested.

The test peer also exposed two empty-slice inference refusals: `&[]` still
needs `&[0u32;0]` even when the destination parameter is typed `&[u32]`.
The pinned compiler provided the exact applicable edit.

The xdg-shell XML was also read directly from the locally unpacked
`wayland-protocols` package. Constants are encoded explicitly in lkjscript;
there is no generated C/Rust protocol glue.
