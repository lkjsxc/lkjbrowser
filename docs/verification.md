# Final verification

Verified on 2026-11-18 JST (2026-11-17 UTC). This is evidence for the first slice and PNG,
not a claim that HTTPS, arbitrary websites or physical input devices are implemented/tested.

## Gates

| Command / check | Observed result | Evidence |
| --- | --- | --- |
| `sh tools/test.sh` | Exit 0; 52 native tests, one program case; 12 expected compiler/test refusals and two accepted rewrites | [test-proof.log](test-proof.log) |
| Layout and pixels in that command | Five committed goldens match; HTTP/file/chunked/redirect output agrees; PNG, navigation, scroll, history and address replay pass | Same log; `tests/golden/` |
| File policy in that command | Typed/local links pass; FIFO/final symlink refused; HTTP file redirects/links/images blocked; history/reload retain authority; trusted resolver-symlink and size-cap checks pass | `tools/test-file-policy.sh`, same log |
| Native Wayland peer | Registry, shm descriptor intent, configure/pong/cursor; motion, click, scroll, key press/release, focus restore and close pass | [wayland-input-proof.log](wayland-input-proof.log) |
| `sh tools/font-security.sh` | Exit 0; full malformed-font overflow witness is rejected without the prior R0001 trap | [font-security-proof.log](font-security-proof.log) |
| `bash review/parsers/run.sh` | Ten bounded parser probes and fourteen focused native CSS tests pass | `review/parsers/`, [parser-review-proof.log](parser-review-proof.log) |
| Actual TCP DNS A lookup of example.com | Succeeded after the fixed resolver configuration reader repair | [hostname-proof.log](hostname-proof.log) |
| `sh tools/capture-wayland.sh` | Exit 0; real Weston 13 pixman, three screenshots, zero differing pixels in each 1000 by 760 comparison | [wayland-final-proof.log](wayland-final-proof.log) |
| Continuous scroll/link recording | One native process, six timed application events, seven presented frames; sixteen captured PNGs in a lossless APNG | [motion-proof.log](motion-proof.log), `shots/scroll-and-link.apng` |
| Final process inspection | No executable under this repository was still running; no browser-owned runtime socket remained | Capture cleanup and final /proc executable inspection |

The default deterministic test was run **after** reviewed golden regeneration and succeeded
without `--update-goldens`. The external DNS lookup is separate from that offline gate.
The full native malformed-font witness is separate from fast ordinary unit cases.

## Visual inspection

[visual-review.md](visual-review.md) records three inspect/fix rounds and the final review.
Corrections include error-page spacing, balanced lead/caption copy, narrow-address ellipsis,
relative font/line-height semantics, style-boundary word wrapping and continuous link underlines.
Final actual compositor screenshots and sampled motion frames were opened and inspected.

## Exact artifacts

The verified browser is a native x86-64 ELF executable emitted by the locked compiler:

```text
SHA-256 abde047a327ad2b8436e508e54af90357fd0c3b6289d47427c25cea758572039
Size    925937 bytes
```

The bridge is a 9880-byte freestanding x86-64 ELF with no PT_INTERP or PT_DYNAMIC program
header. It contains syscall-only transport; protocol and page processing remain in lkjscript.
[artifact-hashes.sha256](artifact-hashes.sha256) binds the exact browser/bridge, sources,
fixtures, tests, static screenshots and animation used for this report. Build products remain
ignored and are not committed.

Independent review findings R001 through R008 have writer responses in `review/QUEUE.md`.
The older guarded patches and isolated recordings are retained as review history; they must
not be applied over the current sources merely because they remain in that directory.

No system-wide installation, persistent service, remote, release or deployment was created.
Only this repository and the explicitly requested report were written by the writer team.
