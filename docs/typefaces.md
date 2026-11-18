# Runtime sans and monospace faces

`src/typefaces.lkj` owns the browser's eight runtime TrueType faces and exposes
`typefaces::load(world, directory) -> Result<Fonts, String>`.

| Family | Regular | Bold | Italic | Bold italic |
| --- | --- | --- | --- | --- |
| Sans | `normal` | `bold` | `italic` | `bolditalic` |
| Monospace | `mono` | `monobold` | `monoitalic` | `monobolditalic` |

This separates actual equal-width font metrics from whitespace preservation.
The cached Python tutorial contains 42 pre elements and 77 code elements;
its stylesheet explicitly requests a monospace stack for tt, code and pre.
Preserving spaces with a proportional face cannot preserve code-column alignment.

## Loading policy and compatibility

The existing Sans behavior is unchanged. An explicit `--font-dir` supplies the
four named LiberationSans files. Without it, the loader checks the existing
Liberation and Liberation2 directories, then the corresponding DejaVu face and the
existing DejaVuSans regular fallback. The existing plain error text is retained.

The four LiberationMono files are optional in an override directory. Each mono face
checks that directory first, then system Liberation/Liberation2 and the corresponding
DejaVuSansMono face. If none can be read, it loads the corresponding selected Sans
face independently. Existing directories with only the four Sans files therefore
remain usable. Every face owns its own parsed font and glyph cache.

A readable but malformed font returns the existing parser error; optional-font
fallback does not conceal a malformed readable file. This policy requires no new
runtime capability, font service, downloadable font, or system installation.

The loader provides two families, not arbitrary installed-font selection, per-glyph
fallback, font synthesis, shaping or kerning. See the existing [font parser
profile](font.md) for those limits. If system Mono files and optional overrides are
all absent, the explicit Sans fallback cannot guarantee equal-width code columns.

## Verification

An isolated native smoke test used the unchanged pinned compiler and the actual
font files. It checked all four mono faces, comparing W, i and space at size 18.
Every advance was **11 pixels**. The regular Sans face measured **17 pixels for W**
and **4 for i**, establishing that a distinct equal-width face was loaded.

The same test passed with a temporary override directory containing only the four
LiberationSans files. The optional mono faces then came from the system paths.
Logs and the isolated test snapshot are in `target/browser-pages-typefaces/`.

The browser's layout and painter must choose the same face for each run so that
wrapping, baselines, link hit testing and painted glyphs agree. Chrome continues
to use the Sans faces.
