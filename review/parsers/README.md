# HTML/CSS adversarial review: verified browser bugs and proposed correction

This review changes no shared implementation files. The failures below are browser arithmetic/cascade bugs, not missing language capabilities.

## Ready-to-review patch

- Patch: `review/parsers/css-parser-safety.patch`
- Patch SHA-256: `48a1834f8e2fda368b575b70be502fcd26dccf25d4f6aa318887f8b11c142433`
- Required base: the tested R001 two-pass font cascade, CSS SHA-256 `6ead98a750dfa141626324aef9a03257bf9bfdcf35853720401c6e6a1c708c90`.
- Proposed CSS SHA-256: `8c18e2538457cdb043d106ec5b06d3c5b7e4736693a6ab72e09af92e0c04a578`.
- HTML snapshot SHA-256: `08e0d82733b9694d6c0bde8aeadb2cc0b0326010789f040df8b1805a3ba94183`.

The patch preserves R001. It replaces weighted i32 specificity with lexicographic
`[usize; 3]` ID/class/type counts and an explicit comparator, keeping stable source order for ties.
It applies the existing 6..160 application font-size policy to the big/small element defaults.
Every inherited font-size multiplication is consequently bounded.

Four regressions exercise ID versus many classes, class versus many types, the formerly overflowing
valid selector, and deeply nested big/small defaults including an em margin.

## Actual before/after observations

Each case ran in a separate native process with a 10-second timeout. No process timed out.
One compiler/test job ran at a time. All probes are offline.

| Case | Original snapshot | Proposed correction |
|---|---|---|
| unicode | 18 malformed/Unicode HTML and embedded-CSS inputs; exit 0 | exit 0 |
| numeric | Oversized and malformed lengths/colors; exit 0 | exit 0 |
| depth | 4,096 nested div elements; exit 0 | exit 0 |
| font-boundary | 93 nested big elements: font size 376763451; exit 0 | font size 160; exit 0 |
| font-overflow | 94 nested big elements: css.lkj:110 R0001 integer overflow; exit 1 | font size 160; exit 0 |
| font-em-overflow | 65 nested big elements, innermost margin-left:1em: css.lkj:181 R0001 integer overflow; exit 1 | font size 160; exit 0 |
| font-small-policy | 64 nested small elements: font size 0; exit 1 | font size 6; exit 0 |
| specificity-boundary | 214,748 valid #x components: one rule; exit 0 | one rule; exit 0 |
| specificity-overflow | 214,749 valid #x components, 429,509 CSS bytes: css.lkj:322 R0001 integer overflow; exit 1 | one rule; exit 0 |
| specificity-order | 100 matching classes wrongly beat one ID: blue ff0000ff; exit 1 | ID wins: red ffff0000; exit 0 |

The proposed module set also passed `ok 14 tests` on the native engine, including
the three R001 regressions and four new regressions.

Why overflow-only saturation is insufficient: the original numeric weighting gives 100 classes
the same score as one ID, allowing a later class selector to win. Lexicographic counts preserve
CSS precedence at every selector size represented by the already allocated input.

## Repeatable one-job verification

After the writer applies the patch, run from the repository root:

```sh
bash review/parsers/run.sh
```

The script copies the current shared HTML/CSS modules into a fresh ignored target directory,
records their hashes and the compiler hash, runs native module tests with `--jobs 1`,
builds the probe, and runs all ten cases separately. It returns nonzero if any check fails.
It never modifies shared source files or opens a network connection.

To verify the isolated proposal instead:

```sh
bash review/parsers/run.sh target/independent-review-parsers-fixed-20261118
```

Compiler SHA-256 used: `60149069984ecfe491e322eba406238555c13acc90375c5468e5d5d4954a83ca`.

## Evidence and immutable snapshots

- Original failing snapshot: `target/independent-review-parsers-20261118/`.
  Its CSS SHA-256 is `c7eb5295245321278390a28a36e652a52bf5ef0bc26d9b5da34d45b36c4add72`.
  The original modules and baseline logs were not changed.
- R001-based proposal: `target/independent-review-parsers-fixed-20261118/`.
  `css.before.lkj` preserves the exact patch base.
- Successful independent rerun: `target/independent-review-parsers-run-u1RKIqTt/`.
  Binary SHA-256: `c418a4299b5bc7b13e72eece6550c0469eb1839241feb68f26aa496223b0fba2`.
- Compact evidence beside this note: `before.tsv`, `after.tsv`,
  `before-diagnostics.log`, `after-unit-tests.log`.
- Probe SHA-256: `9577b5353fc6e73287e48d29bab843e57f345d6ea9bed1bdd1f774e2b10933f9`.

Readable small HTML reproductions are `nested-big-overflow.html`,
`nested-big-em-overflow.html`, and `specificity-class-vs-id.html`.
Long selectors are generated deterministically rather than stored as repetitive fixtures.

The Unicode checks include entity scans crossing 32-byte boundaries, unterminated
comments/quotes/raw-text tags, Unicode attributes/selectors, and malformed numeric tokens.
The nesting check covers the iterative HTML parser and CSS computation only.
It does not claim recursive layout or arbitrary hostile documents are exhaustively tested.
