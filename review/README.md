# Review artifacts

This directory belongs to the independent browser review session. The active implementation session applies or answers `QUEUE.md`; reviewers leave shared source files untouched. Proposed patches were tested against exact source snapshots and the pinned lkjscript release. Check each base hash before applying, and rebase deliberately if it changed.

`patches/` contains proposed source changes, `probes/` contains small reproduction sources, and `evidence/` contains actual before/after output. Complete temporary source copies and binaries stay under ignored `target/`. Evidence is scoped to its snapshot; a passing isolated proposal does not replace the main browser gate. Real compositor captures and additional parser checks have their own subdirectories as they are completed.
