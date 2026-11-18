# Wayland clipboard and descriptor transport

The address editor uses the compositor's ordinary `wl_data_device_manager` version 1.
The Wayland implementation and selection ownership stay in `src/wayland.lkj`.
The temporary syscall-only C bridge transports opaque Unix-stream bytes and file
descriptors; it does not parse Wayland, MIME types, text, or clipboard ownership.

## Authenticated launcher handoff

The launcher creates 32 bytes from the kernel random source in a private
0700 directory, opens independent inherited input descriptors for the bridge and
browser, and unlinks the 0600 token file before starting either child. The token
does not appear in arguments, environment variables, logs, or committed files.

The bridge consumes exactly 32 bytes from stdin. Each loopback connection must
supply that exact raw preamble within an absolute 250 ms deadline before any
framed command. It compares every byte, closes wrong, short, and stalled
candidates, and continues accepting on the same listener. Only the successfully
authenticated connection causes it to connect the compositor socket and open the
frame file. The normal native entry reads the other inherited descriptor and
sends the same 32-byte preamble before registry discovery.

The raw protocol fixture uses the explicit `open_test_peer` entry. That entry
rejects descriptor-capable framing and cannot acquire clipboard authority.
Authenticated clipboard regressions use the normal entry with an entirely
synthetic fixture key.

## Ownership and transfer

A copy requires an authenticated descriptor transport, an available data device, a focused keyboard surface, an observed
input serial, descriptor transport, and a per-instance random nonce. The source
offers `text/plain;charset=utf-8` and `text/plain`. It also offers a private
`application/x-lkjbrowser-clipboard-<nonce>-<source>` marker used only to identify
its resulting selection offer; this marker is not served as a data format.

After `set_selection`, copy waits at most 750 ms for a display round trip and the
compositor's selection offer containing that exact marker. It returns true only
when both arrived and keyboard focus remains. The editor may then cut. A
successful socket write alone never authorizes deleting the selected text.
Events encountered during that short round trip are retained for the normal
application event loop. A paste completion encountered in the same round trip
remains pending until those earlier input events have been delivered, so the
application checks the editor revision in event order.

Consumers request plain text through `wl_data_source.send`. The received FD is
represented by an opaque transport token; native code sends the source bytes to
that token, and the bridge writes and closes the actual descriptor. Sources remain
available while they own the selection. A cancelled source is destroyed. Its payload storage is released, while a small
interface tombstone remains until `wl_display.delete_id`. A send event already
in flight still consumes and closes its descriptor, preserving the descriptor
order for subsequent live sources.

Paste selects UTF-8 plain text when offered, otherwise `text/plain`, and calls
`wl_data_offer.receive` with a real pipe descriptor. The bridge forwards the pipe
bytes and EOF separately. Native code exposes text only after successful EOF and
valid UTF-8. Focus loss, failed transfers, invalid UTF-8, size overflow, and timeout
produce no partial text. The application additionally rejects a result if the
editor changed after the request. The requested offer is the clipboard snapshot
for that paste; later selection changes do not replace its payload.

Keyboard focus loss retires the old selection offer and cancels pending paste.
Returning focus requires a new compositor offer. Drag-and-drop offers are never
accepted; unused enter, leave, and drop offers are explicitly destroyed.

Clipboard content is limited to 1 MiB per copy or paste. Native paste has a
five-second total deadline; bridge descriptor work has a five-second inactivity
deadline. Descriptor writes are nonblocking, and a slow consumer cannot block the
Wayland event stream. A copy over the limit returns false, preserving cut text.
An oversized paste is discarded in full. These are resource policies, not claims
about Wayland protocol limits.

When the manager or descriptor transport is absent, or the window lacks keyboard
focus, copy/cut/paste do nothing. There is no fallback clipboard, shell clipboard
command, or direct shortcut from the browser's stored source to paste: even
pasting its own source goes through the compositor's offer and real pipe.

## Generic bridge protocol

The original client command framing remains two little-endian uint32 values,
`payload_length` and `operation`, followed by payload bytes.

| Operation | Payload and effect |
| --- | --- |
| 0 | Forward opaque bytes to the Unix socket. |
| 1 | Forward opaque bytes with the existing frame-file FD. |
| 2 | Client transfer token, then opaque bytes; attach a new pipe write FD and observe its read end. |
| 3 | Received-descriptor token, then bytes; write asynchronously and close. |
| 4 | Descriptor token; close and cancel. |

Server records begin with uint32 zero, then uint32
`(record_size << 16) | kind`. Their total size includes the eight-byte header and
zero padding to four-byte alignment.

| Kind | Payload |
| --- | --- |
| 3 | Descriptor capability version, currently uint32 1. |
| 4 | Unix byte count, FD count, that many received-FD tokens, then opaque Unix bytes. |
| 1 | Pipe token, byte count, then transferred bytes. |
| 2 | Pipe token and terminal status: 0 for EOF, 1 for failure, 2 for size overflow. |

A failed or partial command write makes the native transport terminal. Later
clipboard operations cannot continue on corrupted framing; the application
receives a close event.

Unix reads and application messages have independent boundaries. The native
client first unwraps transport records, then accumulates the original Unix byte
stream for Wayland decoding. Ancillary FD tokens are consumed in protocol order.
An incoming keymap FD is explicitly closed because XKB interpretation remains
outside this slice.

At most 64 descriptor handles are live in the bridge. Received-FD tokens use the
low uint32 range, and client-created pipe tokens use the high range. Exhausted
or failed descriptor creation yields a failed transfer, not substitute data.
The existing native protocol peer may still supply raw event bytes without the
capability announcement; this path deliberately has no clipboard authority.

## Independent checks

`sh tools/descriptor-bridge-test.sh` creates an isolated Unix listener and only
synthetic files, pipes, and bytes. It first sends wrong, short, and stalled
authentication candidates, proves the Unix listener has received no compositor
connection after each rejection, then authenticates successfully on the same
TCP listener. It also proves the unchanged frame-FD path, opaque
fragmentation around received descriptors, 64 KiB descriptor writes and pipe
reads, explicit close, oversized-transfer rejection, and survival of a consumer
closing its pipe.

`sh tools/wayland-test.sh` uses the native protocol peer. Its focused
missing-manager case asserts copy and paste are refused, no transfer is pending,
and no clipboard result exists. The real Weston source/sink proof separately
checks the data-device behavior through the application entrypoint.

`sh tools/wayland-clipboard-test.sh` runs an authenticated native scripted peer
and the production Wayland implementation. It proves late retired-source
descriptor ordering, ignored drag/focus offer retirement, a completion observed
after the total paste deadline, and paste completion held behind deferred input.
It also refuses a second paste while the first completion awaits delivery.
