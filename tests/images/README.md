# Deterministic image fixtures

These small fixtures are generated data, not copies of public photographs or logos.
The offline gate does not regenerate or download them. `SHA256SUMS` records every
stored input and JPEG RGB reference. JPEG `.rgb` files contain tightly packed RGB
bytes in row-major order. GIF expectations in `src/image_test.lkj` are FNV-1a over
BGRA bytes, with fully transparent pixels normalized to zero.

Independent witness: Pillow 13.0.0 with libjpeg-turbo 3.2.0 (JPEG API compatibility
version 6.2), used during development outside the browser. No runtime dependency
was added.

## JPEG construction

All accepted JPEG inputs are 31×23.

- Smooth grayscale pixel: `35 + 4*x + 2*y`.
- Smooth RGB pixel: `(20 + 5*x, 30 + 7*y, 80 + 2*x + 2*y)`.
- Ordinary images use quality 90, subsampling 0/1/2 (4:4:4/4:2:2/4:2:0) and
  sequential or progressive encoding as named.
- `*-restart-1` and `*-restart-3` use quality 88, subsampling 0 and one/three
  restart blocks.
- Noisy RGB starts at unsigned state 123456 and updates
  `state = (1664525*state + 1013904223) mod 2^32` once per channel;
  the high byte is the channel value. Quality 90, subsampling 0.
- `rgb-progressive-restart` is that noisy input, progressive, with one restart block.
- `rgb-direct-*` uses the smooth RGB image and `keep_rgb=True`, preserving RGB
  rather than converting it to YCbCr.
- `unsupported-cmyk.jpg` is a 2×2 CMYK image with pixel (33,77,99,12); rejection is
  expected. It has no RGB reference.

Each `.rgb` reference was produced by independently reopening the encoded JPEG
and converting to RGB. The accepted tolerance is four levels in any channel and
less than one mean level; the observed maximum in the recorded run is three.

## GIF construction

The 256-color palette is `((47*i)%256, (83*i)%256, (131*i)%256)`.

- `palette`, `local-palette`, `transparent` and `interlaced`: 39×27,
  index `(3*x + 7*y)%16`, no palette optimization. Transparent index is zero
  where named; interlace is enabled where named.
- `local-palette` moves the global palette bytes to the image descriptor and
  updates the global/local flags, leaving indices unchanged.
- `dictionary`: 137×103, state begins at 27, uses the same 32-bit LCG, and
  takes its high byte per pixel. The result grows the LZW dictionary through
  its full-size regime.
- `animation`: two 17×13 frames, all indices one then two; 20 ms duration,
  loop zero, no optimization. The expected decoded image is frame one.

The hand-checked one-pixel GIF lives directly in the native test source. Public
corpus resources were inspected separately under ignored `target/browser-pages-images/`;
they are not vendored as fixtures.
