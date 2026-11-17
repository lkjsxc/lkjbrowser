# Language-gap and bridge audit

Reviewed 2026-11-17 UTC against the fixed `2026.11.17-e6d13590b` compiler, its existing negative probes, `GAPS.md`, `docs/wayland.md`, the transport source and the checked authority report. This review did not modify the language checkout or browser sources.

## Findings

The temporary bridge is within the prompt's permitted scope. It is a freestanding static C executable with no libc, Wayland library, HTML/CSS, font, layout, HTTP or painting code. It forwards opaque bytes, attaches the already-open frame-file descriptor when requested, and closes received descriptors. The latter matters: the browser currently cannot consume a compositor-supplied keymap and uses the documented US physical-key subset. No claim of a wholly lkjscript-only launch path is justified yet.

The native browser performs its own protocol encoding and rendering. The authority report declares a sole World entry and conservatively reachable file, TCP, readiness, clock and entropy effects. That is full authority as declared, not a least-authority browser. The separate capability-demands discussion should preserve this distinction.

The first five rows of `GAPS.md` are accurately scoped to observed integration sites. The missing direct Unix connector and descriptor-message operations are blockers for removing the bridge. Writable shared mapping is an optimization: existing file writes plus descriptor transfer already support correct presentation. The lack of deadline-aware TCP connect remains a real user-visible limitation; a six-second post-connect I/O deadline must not be described as a total navigation bound.

## Final-ledger improvements for the writer

1. Replace the current "further entries ... will be updated" work-in-progress sentence when finalizing the report.
2. Retain both sending and receiving descriptors explicitly in the bridge-removal demand. Receiving cannot be omitted just because the first framebuffer only needs a send.
3. Merge the two source-form refusals already documented in `docs/wayland.md`: a temporary slice loan retained across owner assignment (one integration site) and typed empty-slice inference requiring an explicit element type (two sites). Keep their exact minimal forms and pinned diagnostics; these are separate from missing OS capabilities.
4. Distinguish absent source libraries (TLS/PKI, text shaping and font fallback) from language forms and runtime capabilities. Do not invent ten compiler defects to fill a top-ten table. Explain any fewer-than-ten observed compiler/runtime gaps and separately identify remaining library work.
5. Do not list the review's CSS arithmetic traps or ordinary file-loading policy as language shortcomings. They are browser implementation defects, and existing operations suffice to fix them.
6. Preserve the statement that the bridge does not implement DNS/HTTP, Wayland message interpretation, fonts or pixels; the proof screenshots independently show presentation through this boundary.

## Opinions for the lead

OPINION: Prioritize a confined Unix connector plus typed descriptor send/receive on an owned stream. Together they remove the complete transport helper; a writable mapping is not on that correctness path.

OPINION: Make nonblocking connect completion observable through Readiness with an absolute deadline. Response-read deadlines already work, but they cannot bound the current blocking handshake.

OPINION: Treat shaping, certificate validation and font fallback as reusable lkjscript libraries and browser milestones. Do not use the browser's own CSS bugs as evidence that the language needs an escape to another implementation language.
