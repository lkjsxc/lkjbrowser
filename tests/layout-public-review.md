# Cached public page CSS/layout review

This slice was driven by the HTML and CSS fetched during the HTTPS acceptance run. All follow-up renders used those cached files. The offline probe opens regular files only and does not include the network module.

## Findings and fixes

1. **Example Domain:** the actual 577-byte source contains one paragraph and a script, with no heading or anchor. The paragraph-only output was faithful to the source; `html.lkj` was not changed. The real styling defects were unsupported `font:16px/1.6 system-ui,sans-serif` and `padding:25vh 2em 2em`. The computed result is now 16px text, 1.6 line height, a 416px content column, 32px horizontal padding and 165px top padding in the 662px content viewport.
2. **Kernel header:** the cached external stylesheet hides `#mobile-banner` on desktop and uses `@media screen and (max-width:848px)` for mobile. Width media rules now use the explicit full window width, independently of the 12px scrollbar reservation. At 1000px, the cached page has one desktop header.
3. **Kernel tables:** rows previously ran together as inline content. The fallback now lays out rows and shared columns, bold headers, captions and bounded `colspan`, retaining links and anchors. Visual inspection first found excess wrapping from 12px gaps, then a bold-child measurement underestimate. Crowded tables now reduce gaps to 4px before shrinking columns, and intrinsic widths measure the computed styles of descendant text. In the cached release table, all ten rows are 35px high, dates and link brackets stay intact, and `next-20261116` is one 123px text run.

## API and limits

- `css::compute_viewport(document, viewport_width, viewport_height)` resolves `vh` and `vw`; `compute` remains available.
- `layout::build_in_viewport(document, layout_width, viewport_width, viewport_height, regular, bold, italic, bolditalic)` distinguishes layout width from the CSS viewport. The browser passes `window_width - 12`, `window_width`, and `window_height - TOP - BOTTOM`.
- `layout::build` and `layout::build_viewport` remain compatible wrappers.
- `css::media_matches(query, viewport_width)` supports screen/all, optional only, min-width/max-width, comma alternatives, and px/em/rem (em/rem use this browser's initial 18px font). Empty input returns false; HTML callers treat an absent/empty media attribute as all. Print, unknown media types/features, negation and unsupported units are skipped.
- Media parsing is bounded to 1024 query bytes, 16 conditions, 8 nested media blocks and 8192px query widths. Unsupported semicolon at-rules such as imports are skipped without swallowing the next style rule.
- Font shorthand expands the supported size, weight, style and line-height fields before normal cascade ordering. It resets supported font fields, respects importance and uses the existing font fallback. Font family selection, font downloads and unsupported font variants are outside this slice.
- Table support is a readable fallback, not the complete CSS table algorithm. It supports up to 64 columns and bounded colspan, with a stacked fallback when insufficient width remains. Rowspan, border collapsing, column styling, floats, grid and flex layout are not implemented by this change.

## Verification

The pinned native toolchain passed **55 tests** through the focused offline rendering entry point:

```sh
.toolchain/lkjscript test src/layout_public_probe.lkj --engine native --jobs 1
.toolchain/lkjscript build src/layout_public_probe.lkj -o target/browser-https/layout-public-probe
```

Nine new deterministic source regressions cover:

- Viewport lengths, shorthand expansion, declaration order and extreme input overflow rejection.
- Font shorthand importance and invalid shorthand rejection.
- Display visibility under wide/narrow media queries.
- Media boundaries, unsupported conditions and nested source order.
- Public-page vertical padding across viewport heights.
- Table row/column alignment, bold headers, colspan, link hit testing and narrow content retention.
- Full viewport width with a separately reserved scrollbar.
- Reduced gaps before unnecessary word splitting.
- Intrinsic width of styled descendant text.

`git diff --check` passed. No language checkout or toolchain files were changed. Final application/Weston and complete-project gates are owned by the lead agent.

## Offline visual evidence

The probe uses a 988x662 content canvas with a 1000px CSS viewport and installed Liberation Sans faces. It draws image placeholders and does not fetch subresources. Optional CSS arguments are prepended in argument order before the document's inline styles; the production loader handles document source order separately.

```sh
target/browser-https/layout-public-probe target/public-candidates/example.com.html target/browser-https/layout-offline/example
target/browser-https/layout-public-probe target/public-candidates/www.kernel.org.html target/browser-https/layout-offline/kernel-css 0 target/public-candidates/kernel-main.css
target/browser-https/layout-public-probe target/public-candidates/www.kernel.org.html target/browser-https/layout-offline/kernel-css-tables 920 target/public-candidates/kernel-main.css
target/browser-https/layout-public-probe target/public-candidates/www.debian.org.html target/browser-https/layout-offline/debian-css 0 target/public-candidates/debian.css target/public-candidates/debian-en.css
```

Each output base produces a PNG and an exact layout dump. Visually inspected: `example.png`, `kernel-css.png`, and `kernel-css-tables.png`. Debian was rendered as an additional offline smoke check; the lead owns its final visual acceptance.

A full-image preview appeared to omit two release columns. Independent zlib decoding and a pixel-preserving crop confirmed that the PNG actually contains both columns with opaque text: first-row label 381 dark pixels and version 352 dark pixels. The crop `kernel-css-tables-left-crop.png` visibly shows the labels and versions. No overlapping later rectangle exists at those coordinates, and no paint/PNG change was made.

## Cached input identities

| Input | SHA-256 |
| --- | --- |
| example.com.html | 25ddf2c883e0d1958ea971d279a7e4f0fd446724ee3db7db19dadabd4a62e484 |
| www.kernel.org.html | 5fd328d40623920a3ee1f8f659276bcf1499711cbf5b594ac6dc7ea0df6abd75 |
| kernel-main.css | 03b2a8c8c1f8a5b1f286e4c267b3a0d8e07c94aa470f4f23a4b72be926216075 |
| www.debian.org.html | 7a5d40eec4df80f2399cdead4c46efadfc97e202d526043dd7dd812da8c5d974 |
| debian.css | c63ccc983ab22b239286b58b0fc8838d56e17c157fca58206ba6b91f76eefad8 |
| debian-en.css | 752495a8a164e0f64d717ad6a392518c193c98a7ad2da6f23f73a5b0360d15ad |
