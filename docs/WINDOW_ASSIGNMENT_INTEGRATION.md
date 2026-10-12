# WindowAssignment adapter surface

`WindowAssignment.swift` is intentionally independent of AppKit and Accessibility.
The future `WindowService` adapter should:

1. Convert each saved `WindowInfo` to a `WindowSnapshot` with a stable target ID,
   app bundle identifier when available, legacy `appName`, title, AX role/subrole,
   and saved frame.
2. Convert the current AX window list to snapshots. The adapter owns all
   `AXUIElement` reads; the matcher must receive values, never AX objects.
3. Call `WindowAssigner.assign(targets:current:)` once per restore operation.
4. Apply frames only for `.matched(currentID:)` results. Treat both
   `.ambiguous` and `.skipped` as non-actionable and expose them in restore
   diagnostics.
5. Keep the current-window IDs stable for the duration of one assignment call;
   they need only be unique within that snapshot.

Identity is bundle ID when both snapshots provide one. For old layouts with no
bundle ID, the matcher uses exact `appName` equality. Exact titles are preferred;
changed or empty titles are accepted only when role metadata and geometry leave a
single candidate. No fuzzy title matching should be added without an explicit
safety design and tests.

This module is speculative until the P0-2 gate passes and is not integrated into
`WindowService` by this lane.
