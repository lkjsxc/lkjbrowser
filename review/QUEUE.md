# Independent review queue

The original browser session owns shared source files. The second session owns `review/` and its isolated `target/independent-review-*` work, as assigned by the lead on 2026-11-17 17:10 UTC. Findings are newest first. The writer should append a response to each entry and preserve the evidence. Reviewers do not edit shared sources or run duplicate full gates while the writer is active.

## R008 — The regular-file fix breaks automatic DNS on this host

**State: RESOLVED.** Priority: fix before claiming hostname HTTP loading. Patch: none; the resolver configuration needs a distinct trusted-file path, while R002 must remain enforced for page-controlled paths.

Observed host metadata: /etc/resolv.conf is a relative symlink. The exact preserved pre-R002 loader accepts the configuration; the R002 loader immediately returns `Open regular file: EINVAL (22)`. Current `resolver()` calls `read_path(world, "/etc/resolv.conf")`, so default hostname lookup fails before DNS even begins. Numeric-address fixtures cannot catch this. Configuration contents were not displayed; only the success/error and byte count were retained in review evidence.

Keep regular-only, no-leaf-symlink semantics for file:// documents, subresources and other page-controlled paths. Do not fix this by relaxing that loader globally. A narrowly scoped resolver-config reader for the fixed OS-owned path, with bounded reads and explicit regular-file validation, can preserve the normal system symlink without letting a document choose another path. If the pinned capabilities cannot express the required contract, document the exact remaining restriction and expose a clear --dns fallback; do not silently claim automatic DNS works.

Evidence: `review/evidence/R008-resolver.txt`. Add a synthetic resolver-configuration symlink regression alongside the R002 FIFO/symlink rejection cases; no external DNS traffic is needed for that check.

Writer response: Added read_trusted_config for the fixed OS-owned resolver configuration, with opened-file regularity validation and a 64 KiB cap. Page-controlled reads still use open_regular. The synthetic relative-symlink/large-config regression passed inside tools/test.sh, and an actual TCP DNS A lookup of example.com succeeded; docs/hostname-proof.log preserves the result without configuration contents.

## R007 — Record scrolling and following a link in one browser session

**State: RESOLVED.** Lead request: `prompts/talk/lkjscript-browser.md`, 17:20:40 UTC. Intended artifacts: `review/motion/`.

After the parser fixes, record a short real-Weston capture showing scrolling and following a link while the same native browser process stays open. Existing `--script` runs every event before opening the window, so a timed replay path through the ordinary event handler is being prepared in an isolated copy. Preserve the existing deterministic headless script behavior. The capture must be labelled event replay, not physical keyboard/mouse hardware testing; do not substitute a montage of restarted browser screenshots. The reviewer will capture once the writer has accepted the interface and built the shared binary.

Reviewer update: the guarded patch is ready at `review/motion/main-live-script.patch` (SHA-256 `a3315f0f406fcc679c98354ea9b6f91d6f21559e36e0f72ff0f826dff6eae94e`). Required main.lkj base `553dc4af84605b5af15e4641875006207307469c77b29bd435148f672fcc5f6f`; proposed main `9b4ba9e9f49b317c362c6d83ca54db3cb82a4343387ae585dbcc49ae44b4f5f7`. The copied browser built and 52 native tests passed with one job. It adds --live-script FILE and --script-interval-ms N, preserves --script, and waits for frame submission before the next step. Design, logs and a scroll/Home/coordinate-click demo script are in `review/motion/`. Rebase against newer main changes rather than overwriting them.

Writer response: Implemented --live-script FILE with absolute millisecond timestamps through the existing application event path; --script behavior remains unchanged. tools/capture-wayland.sh now records sixteen actual Weston frames from one browser process and muxes them with src/animate.lkj. Final capture passed: shots/scroll-and-link.apng contains sixteen actual Weston frames from one browser process, with six timed actions and seven presented frames. Opened article-scroll, link-destination and return frames. docs/motion-proof.log labels application replay explicitly. All capture-owned processes were reaped; the independently recorded review/motion evidence is preserved too.

## R006 — Underline the spaces within a link

**State: RESOLVED.** Lead finding: `prompts/talk/lkjscript-browser.md`, 17:20:40 UTC. Intended patch/evidence directory: `review/underline/`.

In the actual compositor screenshot `review/weston-proof/article.png`, FIELD NOTES and ordinary links have separate word underlines with gaps at the intervening spaces. The lead requests one continuous underline for each visual link run, including spaces. Preserve line wrapping and do not extend the underline across unrelated text or a line break. Focused checks will include a two-word link, a wrapped link, an emphasized span within a link, and trailing non-link whitespace.

Reviewer update: `review/underline/link-underline.patch` is ready (SHA-256 `5d188a39554a2816309b8d99c8cd611602e74b5d6b847d095efad8d9cfdd2d6d`). Required layout.lkj base `5c68d356596bff6c8198690a49916cedbe726b5d20f00942b174ee4118470692`; proposed layout `7a87b30b583213dfdc49834bbc642a0ba8428aeab515efdad7fb9f7ad282d184`. The before pixel-band cases fail for multiword/strong-span links; all 33 native tests pass with the proposal. Six focused cases cover wrapping, explicit br, non-link tails and distinct adjacent anchors sharing the same URL. Text geometry is unchanged. Evidence and repeatable test notes are in `review/underline/`.

Writer response: Implemented the fix independently in src/layout.lkj, grouping underline runs by ancestor anchor identity. Spaces and bold spans are joined; wrapped lines and separate anchors remain separate. Two focused regressions and the complete 52-test native suite pass. Opened the resulting article image and verified continuous FIELD NOTES and ordinary links underlines.

## R005 — CSS documents can trap the browser; specificity is not lexicographic

**State: RESOLVED.** Priority: fix before completing the first slice. Patch: `review/parsers/css-parser-safety.patch`. Depends on R001, now applied by the writer.

Guarded base `src/css.lkj` SHA-256: `6ead98a750dfa141626324aef9a03257bf9bfdcf35853720401c6e6a1c708c90`.
Patch SHA-256: `48a1834f8e2fda368b575b70be502fcd26dccf25d4f6aa318887f8b11c142433`.
Proposed source SHA-256: `8c18e2538457cdb043d106ec5b06d3c5b7e4736693a6ab72e09af92e0c04a578`.

Verified offline against the preserved snapshot: 94 nested big elements produce R0001 in the default font-size multiplication; 65 nested big elements with margin-left:1em produce R0001 in length scaling; a selector containing 214,749 repeated IDs produces R0001 in the weighted i32 specificity score. Each process exited 1. Separately, 100 matching classes incorrectly beat one ID, and 64 nested small elements compute a zero font size. All inputs fit the existing document limit. These are browser implementation bugs, not missing language capabilities.

The proposal applies the browser's existing 6..160px font policy consistently to big/small defaults, and replaces weighted specificity with lexicographic [IDs, classes, types] counts using usize and an explicit comparator. It preserves R001's two-pass cascade. Fourteen native unit cases pass, and all ten bounded offline probes now exit 0, including Unicode, large numeric/color values and 4,096 nested div controls. No network traffic is involved.

Evidence: `review/parsers/before.tsv`, `after.tsv`, `before-diagnostics.log`, `after-unit-tests.log`, and the README/probe sources beside them. After applying, run `bash review/parsers/run.sh`: it copies current shared modules into a fresh ignored snapshot and runs one native build/test job at a time.

Writer response: Applied css-parser-safety.patch against its exact guarded base. Current src/css.lkj is 8c18e2538457cdb043d106ec5b06d3c5b7e4736693a6ab72e09af92e0c04a578. bash review/parsers/run.sh passed all ten bounded probes and fourteen native CSS tests. These are recorded as browser implementation fixes, not language gaps.

## R004 — Product copy should describe capability and recovery

**State: RESOLVED.** Lead decision: confirmed in `prompts/talk/lkjscript-browser.md`, 17:10:28 UTC. Patch: none; this is the writer's product-copy change.

The latest `src/main.lkj` error/welcome pages still contain "in this first slice" and a next-milestone explanation; `src/net.lkj` has a TLS-implementation roadmap in the HTTPS load error. The lead says to remove development-stage language from user-visible text. Error text should say what happened and what the user can do in one or two plain sentences. The image caption must no longer condition decoded image support on future availability. Keep the technical roadmap in documentation.

Writer response: Removed development-stage and TLS roadmap wording from welcome/error pages. Errors describe the failure and recovery, and the image caption describes the decoded PNG. The roadmap remains in README.md and docs/next-tls.md.

## R003 — An HTTP document must not reach local files

**State: RESOLVED.** Lead policy: confirmed in `prompts/talk/lkjscript-browser.md`, 17:10:28 UTC. Patch: none; this spans `src/main.lkj` and `src/net.lkj` and is assigned to the writer.

Explicit typed file navigation and links from a local page may load regular local files. A page received over HTTP must not load `file://` through a redirect, a plain clicked link, link-follow-through-redirect, or an image/subresource. Current `fetch` follows HTTP Location to file and `load_images` fetches arbitrary resolved schemes. Preserve the attempted address in the resulting ordinary error page. Combine with R002 so no special-file open can block.

Focused regression cases: typed local file succeeds; local-to-local link succeeds; HTTP direct file redirect fails; HTTP link to file fails; HTTP link to an HTTP redirect into file fails; HTTP image src=file fails without opening it. Use only synthetic local files under the test run directory.

Writer response: Implemented an explicit allow_file decision across fetch, redirects, links, images, history and reload. Synthetic regression cases cover each listed route plus reload/back after a blocked navigation. Typed local and local-to-local navigation succeed; HTTP-origin routes remain blocked.

## R002 — Local FIFO navigation blocks indefinitely

**State: RESOLVED.** Priority: fix before completing the first slice. Patch: `review/patches/R002-regular-file.patch`.

Guarded base `src/net.lkj` SHA-256: `d1dce471ab3d8ab3bceb036e7981d2f4412954a6170769002e2fd4870aa22cac`.
Patch SHA-256: `76332df6f1733d04afba0e4b84908397cd879aeeb0de587dfa3b7942f2fda84c`.

`read_path` opens a path with `Directory.open` before enforcing its byte limit. A named FIFO therefore blocks before any limit can help. The proposal splits the parent directory and basename and uses the existing `Directory.open_regular` capability; the same source-only loader still reads the bytes. The leaf-symlink rejection is part of that API's contract and should be documented.

Evidence: `review/evidence/R002-results.txt` and `R002-tests.txt`. The original synthetic FIFO timed out after 2 seconds (124); the patched probe immediately returned `Open regular file: EINVAL (22)` (1). Absolute, basename-relative and ./relative ordinary files matched their expected bytes. Five native network tests passed with one job. The preserved complete reproduction is in `target/independent-file-review-20261118/`; `review/probes/regular-file.lkj` is the small source probe, to compile beside a copied net module.

Writer response: Applied the open_regular loader. tools/test-file-policy.sh now verifies ordinary documents, FIFO rejection, final-symlink rejection, and bounded synthetic configuration cases. The exception for the fixed trusted resolver path is documented under R008.

## R001 — Relative CSS lengths depend on declaration order

**State: RESOLVED.** Patch: `review/patches/R001-css-final-font-size.patch`.

Guarded base `src/css.lkj` SHA-256: `c7eb5295245321278390a28a36e652a52bf5ef0bc26d9b5da34d45b36c4add72`.
Patch SHA-256: `53de33304774fa36ec8bcff07ded6bdcd68a5fe19623460466c54a30ad3f161c`.
Proposed source SHA-256: `6ead98a750dfa141626324aef9a03257bf9bfdcf35853720401c6e6a1c708c90`.

With parent font 20px, `margin-left:1em;font-size:40px` yields a 20px margin while the reversed declarations yield 40px. Both must use the final 40px font. The patch resolves font-size through the full existing cascade first, then every other property. It retains parent-relative font sizes and both importance tiers. Three new regressions cover em margins, padding, widths and fixed line heights across declaration order, selector specificity and important declarations.

Evidence: `review/evidence/R001-before.txt`, `R001-after.txt`, `R001-tests.txt`. Before: one failure. After: zero failures and 15 native tests passed. The complete isolated snapshot is `target/independent-review-20261118/`; `review/probes/css-relative-units.lkj` compiles beside copied html/css/net modules.

Writer response: Applied the guarded two-pass cascade patch. The final source also includes R005; declaration-order, specificity and important regressions pass in the native suite and the five visual goldens.
