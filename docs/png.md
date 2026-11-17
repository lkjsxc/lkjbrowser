# PNG in ordinary lkjscript

`src/png.lkj` contains the decoder, zlib wrapper, DEFLATE reader, PNG filters, color conversion and a deterministic PNG encoder. No compression or image library is linked or invoked by the browser.

## Supported input

- Noninterlaced PNG, 8-bit samples.
- Grayscale, RGB, indexed color, grayscale with alpha and RGBA.
- All five PNG filters: None, Sub, Up, Average and Paeth.
- Palette transparency and grayscale/RGB color-key transparency (`tRNS`).
- Consecutive IDAT chunks; unknown ancillary chunks are skipped after checksum validation. Unknown critical chunks reject.
- Stored, fixed-Huffman and dynamic-Huffman DEFLATE blocks, including repeated code lengths and overlapping backward copies.
- PNG CRC-32 and zlib Adler-32 validation, checked lengths/order, output bounded by declared dimensions.

`decode(data:&[u8]) -> Result<Image,String>` returns `Image { width:usize, height:usize, pixels:Vec<u32> }`. Pixels are unpremultiplied `0xAARRGGBB`.

`Canvas::image(source_width,source_height,pixels,x,y,width,height)` clips, scales with nearest sampling, and alpha blends them over the existing framebuffer.

## Native output

`encode(width,height,pixels:&[u32]) -> Result<Vec<u8>,String>` writes RGBA PNG. Its own small LZ77 matcher uses a 32 KiB backward window and fixed Huffman codes. PNG screenshots can therefore be written directly from the same framebuffer that is shown through Wayland; no helper conversion is required.

## Reproducible proof

```sh
.toolchain/lkjscript test src/png.lkj --jobs 1
.toolchain/lkjscript build src/png_probe.lkj -o target/png-probe
./target/png-probe
./target/png-probe fixtures/workshop.png
```

Seventeen cases pass on both native and independent-interpreter routes (`ok 34 tests`). The immutable reference PNG streams were generated once with Python's standard zlib as an external witness. The test command needs no Python or external codec. They cover all five color types, all filters and all three DEFLATE block types; palette/transparency; known checksum values; bad CRC/Adler; every truncated prefix of a reference image; invalid backward distance; unsupported depth/interlace; excessive dimensions; encoder roundtrip with alpha; incomplete Huffman trees; empty-block work; and sixteen IDAT mutations whose PNG CRC is recomputed so they enter the zlib decoder.

`src/png_probe.lkj` paints a deterministic landscape and encodes `fixtures/workshop.png` itself. The result is 740x225, 6,774 bytes. It decodes back to every original pixel. The pixel FNV-1a, over BGRA byte order, is `4f522fe5c7f2aeea`. Pillow independently decoded the native-produced PNG and reproduced that hash. The actual image was viewed: a pale sky, sun, layered green hills, a tree and river. The probe and external witness are development checks, not browser runtime helpers.

## Explicit policy and limitations

PNG input is limited to 32 MiB, 4096 pixels per axis and 8,388,608 pixels overall. Decoded DEFLATE bytes may not exceed the scanline byte count computed from the validated header. At most 8192 DEFLATE blocks are accepted, bounding streams filled with empty blocks. Incomplete Huffman alphabets reject except the format's single-symbol or unused-distance cases. Encoded output uses the same 32 MiB file policy. These limits prevent a small untrusted image from allocating uncontrolled memory; they are browser policy, not language limits.

Adam7 interlace, sub-8-bit/16-bit samples, APNG animation, ICC color management and gamma conversion are not implemented. Unsupported image forms return an explanation and the browser can retain the image's alternate text. Scaling is nearest-sample in this slice.

## Language observation

One form was refused at one test site:

```rust
fn probe() -> Vec<u8> { b"abc".to_vec() }
```

The pinned compiler reports `E_UNSUPPORTED array.to_vec requires a slice receiver and Clone elements`. `b"abc"[..].to_vec()` works. The codec itself required no external bridge and no new trusted effect.

OPINION: Forwarding array `to_vec()` to the existing slice implementation would remove this small source-library friction without new checker/runtime authority. PNG/DEFLATE algorithms need no new trusted primitive.

## Specifications

- [W3C PNG](https://www.w3.org/TR/png/)
- [RFC 1950: zlib](https://www.rfc-editor.org/rfc/rfc1950)
- [RFC 1951: DEFLATE](https://www.rfc-editor.org/rfc/rfc1951)

## Review outcome

The targeted malformed-input review found no unchecked network-PNG indexing/overflow trap: chunk arithmetic follows length checks, dimensions bound products before allocation, bit reads check their source, and backward copies check their distance/output budget. A small valid-CRC mutation corpus returned ordinary errors or a dimension-consistent decoded image on both execution routes. This is targeted evidence, not a general fuzzing or security-audit claim.

The review fixed two format/resource mismatches: overly permissive incomplete Huffman trees and an encoder that could emit more bytes than the decoder's file policy accepted. The new empty-block budget prevents input size alone from permitting arbitrarily many tree reconstructions. Worst-case allocations are bounded but include several simultaneous decoded/compressed buffers; an 8 Mpixel image can still require roughly 200 MiB peak, so this is not a streaming image decoder.
