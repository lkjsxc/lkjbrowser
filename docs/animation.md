# Lossless live-session animation

`src/animate.lkj` is a standalone development tool compiled by the pinned lkjscript build. It packages existing PNG frames as APNG. It does not paint, generate browser states, run a compositor or implement browser input.

```sh
.toolchain/lkjscript build src/animate.lkj -o target/animate
./target/animate shots/browser-live.apng 300 shots/live-01.png shots/live-02.png shots/live-03.png
```

Run it from the repository root. Arguments are `OUTPUT.apng DELAY_MS FRAME1.png ...`; paths remain beneath the current directory capability. Add every captured frame in playback order. The fixed playback delay is an exact reduced numerator/denominator in seconds; positive delays that cannot fit APNG's fields reject. Playback loops indefinitely.

## Format and preservation

Every input is first decoded and validated by the browser's own `png::decode`. All frames must have identical IHDR bytes and identical pre-IDAT metadata, so dimensions, sample/color format and shared color/palette information agree. Already animated inputs reject. The tool retains the original IDAT zlib streams; it does not recompress, resize, interpolate, repaint or drop frames.

The output has the PNG signature/IHDR, common metadata, acTL, one fcTL per frame, first-frame IDAT chunks, later-frame fdAT chunks and IEND. fcTL/fdAT share a contiguous sequence beginning at zero. Each full-frame update uses zero offsets, NONE disposal and SOURCE blending. Chunk CRCs are calculated in lkjscript. Output is limited to 32 MiB. All input validation and fallback-frame verification finish before the output file is created.

The tool decodes its completed APNG with the native PNG decoder, which sees the first frame as an ordinary PNG, and compares its dimensions and pixel hash with the first source image. It reports the frame count, dimensions, configured delay, file size and verified first-frame hash.

## Observed smoke proof

```sh
./target/animate shots/animation-smoke.apng 500 shots/article.png shots/simple.png
```

Observed result: two 1000x760 frames, 500 ms per frame, 95,036 bytes. Native first-frame pixel hash: `7097053c50212a5f` (FNV-1a over BGRA bytes).

An independent local Pillow decoder read both animation frames. They matched the original images' native-decoder hashes exactly:

| Frame | Source | Pixel FNV-1a |
| --- | --- | --- |
| 0 | article.png | `7097053c50212a5f` |
| 1 | simple.png | `ba26ffafbd59bbf2` |

An independent chunk walk verified every CRC, the contiguous sequence `[0,1,2,3,4,5,6]` (the second PNG has multiple IDAT chunks), full-frame geometry, 1/2-second delay, and SOURCE/NONE operations. The browser host needs no ffmpeg, Pillow or foreign codec; Pillow was only an external development witness.

## What the demonstration proves

The final live demonstration uses **scripted application input** while the native browser is connected to the actual Weston compositor. Its frame/run logs establish that provenance; the multiplexer alone cannot establish it. Playback presents the captured states losslessly at the configured interval. It does not claim that the script represents physical mouse or keyboard input, and it does not establish wall-clock capture timing by itself.

PNG decoder correctness and Wayland pointer/keyboard wire-event handling remain separate proofs in their codec tests and compositor/test-peer exchanges. The two-frame smoke artifact above checks the animation container; it is not the final live-session recording.

Specification: [W3C PNG, animation information](https://www.w3.org/TR/png/#11APNG).
