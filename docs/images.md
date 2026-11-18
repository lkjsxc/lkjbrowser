# JPEG, GIF and intrinsic image metadata

All decoded pixels come from lkjscript source. The browser does not call an external
codec. `src/images.lkj` dispatches by the PNG, JPEG or GIF signature and returns the
existing `png::Image` representation: width, height and unpremultiplied
`0xAARRGGBB` pixels. Unsupported formats return an ordinary error for the page's
alternate-text placeholder.

## Why these formats

The ten-page reading corpus requires JPEG for Wikipedia's Tim Berners-Lee portrait,
and GIF for the W3C table diagrams, Paul Graham's title and the FreeBSD daemon.
These were actual source resources, not synthetic replacements. Four retrieved GIFs
were compared against an independent decoder: every composited RGB channel and every
alpha value matched. The actual 250×187 JPEG portrait differed from libjpeg-turbo by
at most 4 out of 255 in a channel, with a mean absolute channel difference of 0.256.
The portrait was visually inspected as well.

The references used Pillow 13.0.0 and libjpeg-turbo 3.2.0 outside the browser.
They are development witnesses only. Re-running the checked-in offline gate requires
the pinned compiler and the stored fixtures, not Pillow or any external codec.

## JPEG profile

`src/jpeg.lkj` implements the marker reader, quantization and canonical Huffman
tables, byte-stuffed entropy bits, DC prediction, AC run lengths, restart intervals,
progressive spectral selection and successive-approximation refinement, dequantization,
fixed-point inverse DCT and color conversion.

Supported input:

- 8-bit baseline, extended sequential and progressive Huffman DCT.
- Grayscale, YCbCr and RGB, including Adobe RGB identification.
- Up to four quantization and four DC/four AC Huffman tables.
- Interleaved and separate component scans; regular integral sampling ratios.
- Common 4:4:4, 4:2:2 and 4:2:0 input, with centered bilinear chroma expansion.
- Restart markers, including progressive scans; checked scan order and EOB runs.
- 8- and 16-bit quantization values, within the decoder's coefficient budget.

CMYK/YCCK, arithmetic coding, lossless JPEG, 12-bit samples and hierarchical images
return an unsupported-format error. EXIF orientation and ICC color management are not
applied. The inverse DCT is a fixed-point implementation, so decoded channels need not
be bit-identical to another decoder.

JPEG resource policy is 32 MiB of input, at most 4096 pixels per axis and 8,388,608
pixels. Coefficient storage is limited to 400,000 blocks, coefficient magnitude to
32,767, marker segments to 4096, scans to 256 and cumulative scan coefficient visits
to 268,435,456. These are explicit untrusted-image limits, not language limits.
The decoder is not streaming; coefficients, sample planes, source bytes and output
pixels can coexist. An image near the maximum can consume roughly 200 MiB.

## GIF profile

`src/gif.lkj` decodes the first composited image of GIF87a/GIF89a. It supports global
and local palettes, transparent indices, image offsets, the four interlace passes and
LZW dictionary growth through twelve bits, including clear codes and a full frozen
dictionary. GIF animation is not played. Later image blocks are structurally traversed
to the trailer, but their entropy data is not decoded or claimed to be validated.
Plain-text extension rendering is absent.

The same 32 MiB input, 4096-axis and 8,388,608-pixel policy applies. LZW has 4096
dictionary entries and bounded prefix walks. Decoded pixel counts must exactly match
the frame rectangle; bad references, palette indices, extents, missing clear/end
codes and truncated subblocks return errors. Empty or clear-only streams have a
separate code-work limit. At most 4096 top-level blocks are accepted.

GIF transparent pixels are normalized to zero, so invisible RGB bytes may differ
from an independent decoder's palette value. The visible pixels and alpha match.

The Graphics Interchange Format and GIF service mark were defined by CompuServe
Incorporated; the format description is linked below.

## Unsupported SVG placeholders

`images::svg_dimensions` reads at most 64 KiB of root-header metadata and at most
256 attributes. It accepts positive bare/px width and height or a valid four-number
viewBox, derives one missing dimension from the aspect ratio, and bounds both axes
to 8192. XML declarations, comments and a bounded DOCTYPE are skipped without
expanding entities. Relative units, percentages and exponent notation are not resolved;
a valid viewBox can still supply fallback geometry.

This is metadata only. It never executes, fetches dependencies, expands entities or
paints SVG. The browser keeps the alternate-text placeholder visible at a useful
aspect ratio. SVG rasterization remains unsupported.

## Offline evidence

```sh
sh tools/image-test.sh
```

The command verifies fixture hashes, builds `src/image_test.lkj` and runs one native
process. The recorded run has **3,246 decisions**:

- Seventeen accepted JPEG fixtures and one independent CMYK refusal, covering smooth
  and noisy coefficients, direct RGB, grayscale, chroma subsampling, progressive
  refinement and restart intervals.
- JPEG channel comparison against stored independent RGB references: maximum error
  was 3/255 across this deterministic corpus; grayscale/direct RGB were at most 1.
- Six baseline/progressive pairs with exactly identical native decoded pixels.
- Six GIF fixtures with exact normalized independent pixel hashes: global/local
  palettes, transparency, interlace, a large dictionary and first-frame animation.
- Every truncated prefix of two JPEG and two GIF inputs, 384 mutation cases,
  targeted marker/table/dimension/restart/LZW refusals, a hand-checked one-pixel GIF,
  and fourteen dispatch/SVG metadata decisions.

These are targeted correctness and malformed-input checks, not a fuzzing campaign
or a security certification. The final log is `docs/images-verification.log`.
Fixture provenance and hashes are under `tests/images/`.

For inspecting a single source image with the same decoder:

```sh
.toolchain/lkjscript build src/jpeg_probe.lkj -o target/browser-pages-images/jpeg-probe
target/browser-pages-images/jpeg-probe /absolute/input.jpg /absolute/output.png
.toolchain/lkjscript build src/gif_probe.lkj -o target/browser-pages-images/gif-probe
target/browser-pages-images/gif-probe /absolute/input.gif /absolute/output.png
```

## Language observations

The codecs required no new runtime primitive. Their test harness encountered two
small source restrictions on the unchanged compiler pin:

| Probe | Observed rejection | Explicit treatment |
| --- | --- | --- |
| `probes/image-view-array.lkj` | E_BORROW for an owned array containing static string views | Store owned strings |
| `probes/image-owned-array-iteration.lkj` | E_TRAIT: owned arrays lack the required IntoIterator implementation | Use an owned Vec |

`probes/image-owned-vec-workaround.lkj` is accepted. Both observations are conveniences
at one test-harness site each; neither prevented source image decoding.

## Specifications

- [ITU-T T.81, JPEG syntax and Huffman DCT processes](https://www.w3.org/Graphics/JPEG/itu-t81.pdf),
  especially Annexes B, C, F and G.
- [GIF89a specification](https://www.w3.org/Graphics/GIF/spec-gif89a.txt), including its
  clarification that a full LZW dictionary need not immediately clear.
