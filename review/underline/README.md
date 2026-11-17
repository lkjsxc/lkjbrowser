# Continuous link underlines

The lead's actual Weston screenshot showed each word underlined separately.
Collapsed spaces advance the inline flow's horizontal offset without producing text fragments.
The old painter emitted an underline rectangle for each fragment's own width, leaving every space blank.

## Proposed change

`link-underline.patch` changes only `src/layout.lkj`.
Fragments retain their nearest anchor node. During line flush, an underlined text fragment
extends its rectangle left across the preceding gap only when the adjacent text fragment
is also underlined and belongs to that exact same anchor.

This retains the current text positions, widths, baselines and wrapping.
A new line starts with an empty fragment list. Trailing whitespace, unrelated text,
images, and separate anchors cannot bridge a decoration gap.
Anchor identity is used instead of URL equality, so adjacent links to the same URL remain distinct.

| Artifact | SHA-256 |
|---|---|
| Required layout base | 5c68d356596bff6c8198690a49916cedbe726b5d20f00942b174ee4118470692 |
| Proposed layout | 7a87b30b583213dfdc49834bbc642a0ba8428aeab515efdad7fb9f7ad282d184 |
| link-underline.patch | 5d188a39554a2816309b8d99c8cd611602e74b5d6b847d095efad8d9cfdd2d6d |
| underline_probe.lkj | 579670405e6eb6d2ab4c46596bae951ac420731f41bf805ff15931749fa06068 |

No shared implementation files were modified by this review.

## Guard and writer verification

From the repository root, the original writer can check the exact base and patch:

```sh
bash review/underline/check-patch.sh
```

This verifies both hashes and runs `git apply --check`; it does not apply the patch.
After the writer applies it, the focused verification command is:

```sh
bash review/underline/run.sh
```

The command copies the current modules into a fresh ignored target snapshot and runs
one native test job with a 40-second timeout. It does not run the full browser gate
or launch a compositor, server or network client.

The tested proposal can also be rerun without applying anything:

```sh
bash review/underline/run.sh target/independent-review-underline-fixed-20261118
```

## Actual test evidence

The existing deterministic metric font gives every character, including spaces,
a 12-pixel advance at 20px. Tests check text-run geometry and rasterize the actual
display-list rectangles through `paint::Canvas::rect`, then inspect every pixel
in the underline bands and surrounding whitespace.

Six focused cases cover:

1. Two-word link: one continuous blue band across the 12-pixel internal space.
2. Wrapped link: each line stops at its visible text end.
3. Bold span inside a link: continuous decoration across both inline boundaries.
4. Non-link trailing whitespace and text: no underline beyond the link's last glyph.
5. Separate anchors sharing a URL: the gap between them stays undecorated.
6. Explicit br inside a link: two separate line bands.

On the original snapshot, cases 1, 3 and 4 reported assertion failures at the
missing internal-space pixels. The corrected snapshot passed `ok 33 tests`,
including the six cases and all imported module regressions. Baseline exit was 1;
proposal exit was 0. No timeout occurred.

Evidence: `before.log`, `after.log`, `results.tsv`, `dependencies.sha256`.

Immutable snapshots:

- `target/independent-review-underline-base-20261118/`
- `target/independent-review-underline-fixed-20261118/`
