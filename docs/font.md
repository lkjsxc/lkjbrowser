# Runtime TrueType and text painting

`src/font.lkj` reads TrueType SFNT bytes at runtime. `src/paint.lkj` paints an opaque ARGB framebuffer. No platform font API, precomputed atlas, external shaping process or rasterizer participates in browser execution.

The implementation reads head, hhea, maxp, loca, hmtx, cmap and glyf. It supports Unicode cmap formats 4/12, short/long glyph locations, repeated simple-glyph flags, implied quadratic points and compound glyphs (translation, transforms and matching point anchors). Quadratic curves flatten into edges, and a nonzero winding scan converter produces 4x4 supersampled coverage. Masks cache by glyph ID and integer font size. Layout and paint use identical rounded advances.

## Font inputs

The selected family is `/usr/share/fonts/truetype/liberation/LiberationSans-*.ttf`. The installed DejaVu Sans subset lacks oblique faces; Liberation has all four.

| Face | SHA-256 |
| --- | --- |
| Regular | `4659bc0c58c5028dd488ec928d41d9265db43d9b669fc14ca8b0832daca7b144` |
| Bold | `3973aa5054fb467dd5627245d3dc82e37bf16fe075756156a570455871351582` |
| Italic | `830c5fa600505fb4c1a271b4271c53c44bae43f492b2a240d0e98a3a7a380121` |
| BoldItalic | `c80fa7f2ffa0e01d4d8dcd6a6d1e43eda665222d1b4db597dde1174c456006cf` |

## API

`Font::parse(Vec<u8>) -> Result<Font,String>` validates tables and owns their bytes. `advance(codepoint:u32,size:i32)`, `text_width(text:&str,size:i32)`, `ascent(size:i32)` and positive `descent(size:i32)` provide layout metrics. `raster(&mut self,codepoint,size)` returns an index used immediately by Canvas; subsequent raster calls may evict entries.

`Canvas::new`, `rect`, `blend`, `glyph` and `text` draw pixels. Text coordinates specify a baseline. `Canvas::bgra()` produces wl_shm-compatible BGRA bytes. `ppm()` snapshots the same framebuffer as RGB.

## Proof

```sh
.toolchain/lkjscript test src/font.lkj --jobs 1
.toolchain/lkjscript build src/font_probe.lkj -o target/font-probe
./target/font-probe
sha256sum shots/font-proof.ppm
```

Eight cases pass native and independent-interpreter routes (`ok 16 tests`): four malformed-header cases plus oversized compound coordinates, compound expansion, glyph-mask allocation and cache-budget handling. The native probe loads installed fonts and draws regular/bold/italic, Latin accents and symbols at 14 through 56 px.

Observed `shots/font-proof.ppm` SHA-256: `ad18660d9ab6b743dd09c705ebfaaac5084e962d89f27664bc4b52702f6ba696`. The image was opened and reviewed: aligned baselines, readable small type, distinct glyphs and correctly placed compound accents. A PPM-to-PNG conversion for the local viewer did not change rendered pixels and is outside browser execution.

## Limits and gaps

No new language-form refusal was needed for font parsing or painting. The source library lacked a font decoder; the program implements one in ordinary lkjscript.

TrueType hinting bytecode, kerning, GSUB/GPOS shaping, bidi, font fallback, variable fonts, CFF/CFF2 and color fonts are absent. Unicode codepoints map independently. Complex scripts and missing glyphs do not get correct shaping or fallback.

Defensive local-font policy: raster sizes clamp to 1..512 px. Each glyph permits at most 16 nested components, 4096 glyph visits, 16384 points, 4096 contours, 65536 edges, a 1 MiB mask, absolute pixel coordinates within +/-4096, and 2,000,000 edge-times-row scan work. Policy violations yield an empty mask before conversion/allocation. Each face retains at most 32 MiB or 4096 cached glyphs and rebuilds on demand. These are explicit application resource rules, not compiler limits. This is not yet an audited downloadable web-font implementation.

OPINION: Font parsing and outline painting need no new trusted primitive. Keep them in source libraries. A text-shaping/fallback library is the next text requirement; two joined Arabic letters are a minimal missing witness.

Specification: [glyf](https://learn.microsoft.com/en-us/typography/opentype/spec/glyf), [cmap](https://learn.microsoft.com/en-us/typography/opentype/spec/cmap), [hmtx](https://learn.microsoft.com/en-us/typography/opentype/spec/hmtx).

## Malformed-font review

A complete tiny SFNT with 16 compound scale/translation levels reproduced `R0001 integer overflow` in the old native rasterizer, during float-to-integer bounding-box padding. Coordinates are now rejected before that conversion. A second witness uses an acyclic branching component graph to multiply outline work; an absolute depth bound alone did not control it. Traversal, points and masks now have independent budgets.

Both full witnesses passed native and interpreter after the fix. The routine interpreter test then changed to start near the work-budget boundary so routine gates do not spend a minute traversing thousands of components. The full native witnesses remain reproducible with `sh tools/font-security.sh`, which prints `true`. The same source and real-font screenshot hash remain unchanged for normal input.
