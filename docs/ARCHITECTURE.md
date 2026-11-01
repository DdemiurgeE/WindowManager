# WindowManager architecture

This document describes the implemented WindowManager architecture and the restore algorithms used by the current code. It is intended for maintainers who need to understand what is persisted, how a target display is selected, and how automatic restore handles unstable topology and partial results.

Russian version: [`ARCHITECTURE.ru.md`](ARCHITECTURE.ru.md)

## Purpose and runtime components

WindowManager is a SwiftUI + AppKit macOS menu-bar application that captures window layouts and restores them through the Accessibility API. SwiftUI provides the main window, layout list, save sheet, and permissions UI; AppKit provides the status item, running applications, displays, and application lifecycle; `LayoutStorageService` coordinates local storage; `ApplicationServices` reads and changes third-party window frames.

```text
WindowManagerApp
├── ContentView / LayoutListView / SaveLayoutSheet
├── PermissionsView
├── StatusBarService
├── ScreenMonitorService
├── WindowService
├── LayoutStorageService
└── PermissionsService
```

On startup, `WindowManagerApp` creates and injects `WindowService`, `PermissionsService`, and `LayoutStorageService`. When the main view is ready, it configures `StatusBarService` and `ScreenMonitorService`. The app remains available from the menu bar after the main window closes.

## Persisted data model

`Layout` contains an id, user-visible name, captured `windows`, creation date, optional `lastUsed` date, and optional `screenConfiguration`. Before the first confirmed import, `LayoutStorageService` reads and writes the legacy ISO-8601 `[Layout]` JSON in `UserDefaults` under `SavedLayouts`. Explicit backup export writes a portable versioned envelope with `format=com.windowmanager.layouts`, `schemaVersion=1`, `exportedAt` and ordered `layouts`; legacy `[Layout]` backups remain importable. `LayoutImportCodec` checks bounds, duplicate JSON keys, schemas, finite geometry, IDs, dates and collisions before a non-mutating preview; version 1 emits UTC millisecond dates and also accepts legacy whole-second ISO-8601 dates.

The first confirmed import stages old and incoming layouts in one `TransactionalLayoutStore` payload (`version=1`, ordered layouts and `quarantinedImportedLayoutIDs`) under the user's Application Support/`obelisk.WindowManager` directory. The app-specific directory is 0700 and the canonical `SavedLayouts-v1.json` file 0600; a separate stable lock serializes cooperative writers. The canonical file is written through a same-directory private temporary file, fsynced, renamed and followed by directory fsync and read-back before publishing memory. An error before rename leaves the previous canonical bytes and memory unchanged. An error after rename is **ambiguous**: mutations and Auto-apply freeze rather than falsely reporting unchanged bytes. Recovery reads and strictly validates the actual canonical file, fsyncs its directory, then replaces the published snapshot; the UI directs users to restart rather than retry blindly. On a supported local filesystem, a crash before rename retains old canonical bytes (or the legacy blob on first import); a crash around rename/directory sync can recover complete old **or** complete new canonical bytes, never a promised rollback. A missing, invalid or unsupported canonical file after an ambiguous outcome remains blocked pending manual recovery. The original `SavedLayouts` blob is never deleted or changed by import; it remains a fallback only when the canonical file is absent. A corrupt, unsupported, insecure or unreadable canonical file fails closed. File edits compare the previously read bytes under the stable lock and reject stale writers. Older binaries cannot cooperate with the new lock and may mutate the stale defaults snapshot; no automatic reverse migration exists. Local fsync/rename, read-back and cooperative single-writer assumptions are not universal power-loss or hostile same-user guarantees. Synthetic fault tests exercise the production store with isolated fixtures, not physical power cuts. The authoritative data remains in ordinary user backups, so users should consider encrypted backup storage.

### WindowInfo

`WindowInfo` is the persisted description of one captured window:

| Field | Meaning |
| --- | --- |
| `id` | UUID used to correlate a window across restore attempts and retries |
| `appName` | Localized application name |
| `bundleIdentifier` | Optional bundle identifier; preferred over name when matching a running app |
| `windowTitle` | Captured AX title |
| `axRole`, `axSubrole` | Optional Accessibility role metadata used during assignment |
| `frame` | Absolute frame in `NSScreen` coordinates |
| `relativeFrame` | Optional normalized frame relative to the captured display |
| `screenID` | Optional current-observation display identifier |
| `savedDisplayFrame`, `savedVisibleFrame` | Display geometry captured with the window |
| `preservePresentation` | Whether fullscreen/maximized-style presentation should avoid resolver clamping |
| `savedScale` | Optional captured backing scale |
| `screenIndex` | Captured display index, retained as a legacy fallback |
| `timestamp` | Capture time |

Older JSON remains decodable: the newer metadata fields are optional, and layouts without them use the resolver's legacy fallbacks rather than being rejected.

### ScreenConfiguration

A screen configuration stores sorted display IDs, a display count, and (for current captures) sorted display records containing ID, frame, visible frame, and backing scale. New captures use a SHA-256 fingerprint of nonzero Core Graphics vendor/model/serial values when that fingerprint is unique among connected displays; raw serial numbers are not stored. A missing or duplicated hardware serial falls back to a `screen_<number>` observation key (or a geometry key when the number is unavailable).

Old `screen_` keys are not permanent hardware identities: macOS may reassign them on hot-plug. On manual restore, the resolver uses saved frame geometry instead of trusting such a key. When a new physical fingerprint is unavailable or duplicated, the resolver skips the window rather than moving it to a different display. Auto-apply matches the unique physical display set, independently of arrangement and resolution, only for layouts captured with complete physical identities. **Existing layouts must be captured again to enable safe Auto-apply**; they remain readable and available for manual preview/restore. If a monitor lacks a unique serial, Auto-apply skips the topology instead of guessing.

## Per-display window snapping (v3.2 candidate)

`WindowSnap` calculates halves, quarters, thirds, two-thirds and fill-area
frames from the selected `NSScreen.visibleFrame`. `SnapPlanner` refuses an
absent or duplicated current display identity. The main view lets the user
refresh accessible windows, choose one window and one display explicitly, then
select a tile. `WindowService.snapWindow` reuses the existing assignment and AX
frame read-back engine, checks the display again after assignment, and never
writes the saved layout store. The user can then save the resulting arrangement
using **Save Current Layout** for later restoration on the same physical set.

`SnapDragService` is separately opt-in (default off). A global mouse observer
tracks a focused standard window's Accessibility position while the user drags
its title bar; a stationary pointer or top-border resize does not qualify. On
mouse release near an edge, it snaps that exact window through the same AX
write/read-back engine. The monitor never intercepts mouse input or reads
keyboard events. If permission or the monitor is unavailable, no automatic snap
is attempted. The synthetic harness validates geometry, drag gate and target
uniqueness; it does not validate live mouse, AX or permission behavior.

## Capturing a layout

`WindowService.captureCurrentLayout()`:

1. Requires Accessibility permission.
2. Enumerates running regular, non-terminated applications.
3. Reads each application's AX windows and captures title, role, subrole, position, and size.
4. Uses the primary display identified by `CGMainDisplayID()` as the anchor for AX/Quartz-to-`NSScreen` conversion; it does not use `NSScreen.main`, which follows keyboard focus.
5. Skips windows smaller than 50×50 points and windows that do not intersect the union of current displays.
6. Assigns a window to the display with the largest intersection area.
7. Stores the absolute frame, normalized relative frame, display metadata, and matching metadata in `WindowInfo`.

The normalized frame is calculated as:

```text
x      = (window.x - display.x) / display.width
y      = (window.y - display.y) / display.height
width  = window.width  / display.width
height = window.height / display.height
```

AX/Quartz uses a top-left, downward-growing Y axis while `NSScreen` uses a bottom-left, upward-growing axis. `WindowCoordinateConverter` performs both directions using the primary display frame.

## Restoring a layout

`WindowService.restoreLayout(_:, windowIDs:)` can restore all windows or only the supplied UUID subset. It returns a `RestoreResult`, including one `WindowRestoreResult` per requested target when the result can be determined. A partial retry therefore retains stable IDs instead of relying on array positions.

For each target, the service:

1. Resolves a display and target frame through `ScreenResolver`.
2. Matches a running app by saved bundle identifier; targets without one fall back to localized name. A saved bundle identifier is authoritative and must match the current bundle identifier.
3. Reads the app's current AX windows once and assigns targets using title/role/subrole/frame metadata through `WindowAssigner`.
4. Uses the assigned AX element to set the frame.
5. Reports the final status from AX operations and read-back, not merely from a successful set request.

### Display selection and frame resolution

`ScreenResolver` selects a display in this order:

1. unique captured physical `display_` fingerprint; a missing or duplicated physical match skips this window;
2. for legacy `screen_` observation keys, display containing the saved frame's center (the old numeric ID is not trusted);
3. captured `screenIndex` when geometry cannot identify a display;
4. deterministic first display ordering.

An exact absolute frame is used only when saved display frame, visible frame, scale, and current display geometry are all available and equal. Otherwise a finite `relativeFrame` is converted to the selected display. If no usable relative frame exists, the saved absolute frame is retained as a legacy fallback. Unless `preservePresentation` is true, the candidate frame is clamped so a useful title-bar strip remains reachable within the current visible frame; the saved size is not silently reduced.

### AX frame write and read-back

`FrameRestoreEngine` writes position, waits briefly, writes size, waits briefly, writes position again, and reads position and size back. A bounded drift correction is performed when needed. The result is one of:

- `positionSet`: read-back matches the target;
- `appImposedClamp`: the app accepted the operation but retained a different frame;
- `axFailure`: an AX set/read operation failed;
- `restoreSuperseded`: the restore was invalidated before completion;
- `coordinateUnavailable`: no primary display converter was available;
- `appNotFound`, `windowSkipped`, or other matching statuses when the target could not be assigned.

`RestoreResult.windowsRestored` counts only `positionSet`. `windowMatched` is an assignment state and is not counted as restored.

## Automatic apply lifecycle

`ScreenMonitorService` observes `NSApplication.didChangeScreenParametersNotification` with a 0.5-second debounce. Every new topology event cancels pending stability work, retries, and pending notification state.

When Auto-apply is enabled (the `UserDefaults` key is `autoApplyEnabled`, default `true`):

1. The service polls the display snapshot every 0.25 seconds.
2. It requires three consecutive equal snapshots before applying; geometry and scale are part of the current snapshot.
3. If stability is not reached within 10 seconds, it skips the auto-apply rather than treating an unstable topology as safe.
4. It matches layouts by a unique set of physical `display_` identities; geometry changes no longer confuse one physical monitor with another. Legacy or ambiguous identifiers are ineligible until the layout is captured again.
5. It excludes imported layout IDs persisted in the same store transaction (even after manual restore or last-used updates), then selects the most recently used eligible matching layout. Eligibility is checked again before initial restore and each retry; unavailable or changed storage fails closed.
6. It records `started` and `completed`, `noMatch`, or `cancelled` events in an in-memory restore log capped at 20 entries.
7. It records `lastUsed` as the time of the latest apply attempt; this field is not evidence that every window was restored successfully. The UI labels it “Last attempted”.

Missing applications and windows are retried at most three times, one second apart. The retry set is computed by `WindowRestoreResult.id`; mixed or reordered result arrays cannot associate a status with the wrong window. A retry runs only for the current topology generation and only while Auto-apply remains enabled. A topology change or disabled toggle invalidates pending callbacks and prevents further writes.

The final notification is deferred until the initial attempt and all bounded retries finish, or until retrying is cancelled by the Auto-apply toggle. It is emitted at most once per attempt and reports the number of windows whose final status is `positionSet`. Notification delivery still depends on macOS notification authorization.

The UI keeps the last `RestoreResult` and an in-memory history capped at 20 results. It shows verified `positionSet` restores separately from skipped/missing windows, AX failures, and application clamps. “Retry only missing / failed” is an explicit bounded manual action keyed by each `WindowRestoreResult.id`; no retry is triggered by merely viewing diagnostics. **Copy summary** includes counts only, never layout, app or window names. **Copy with names…** requires confirmation on every invocation; Cancel writes nothing, and a confirmed copy leaves names on the system clipboard until replaced. The former stored `includeDetailedRestoreDiagnostics` value is ignored. The separate on-screen names toggle affects display only; the Last restore heading still displays the layout name.

Restore, Auto-apply, menu-bar apply, and restore-event console lines omit layout, application, and window names. They retain display counts/index/selection, event status, restored/total counts, and allowlisted AX operation/reason codes; notification errors print numeric codes rather than arbitrary error descriptions. The in-memory restore results/events and explicitly user-facing menu and notification still contain names; copied diagnostics include them only after confirmation for each named copy. These console guards are static/synthetic and do not establish privacy of third-party or OS logs.

## Manual and menu-bar flows

`LayoutListView` and `StatusBarService` call the same `WindowService.restoreLayout` path. The status-item menu is rebuilt when opened and includes saved layouts, save-current-layout, the Auto-apply toggle, open-window, and quit. Saving from the menu bar opens the main window and posts `ShowSaveLayoutAlert` for `ContentView`.

## Backward compatibility and limitations

- Layouts remain local. Import and export require explicit action; there is no cloud synchronization or automatic launch migration. Older binaries see the stale original defaults snapshot after first import.
- Missing optional `WindowInfo` and `ScreenConfiguration` metadata is supported for older layouts. Such layouts may use frame-center, index, or absolute-frame fallbacks and cannot claim exact display identity.
- The app does not launch missing applications.
- Dynamic titles and changing application window sets can prevent assignment; bundle IDs and AX role metadata improve matching but do not guarantee it.
- Some applications reject AX changes, clamp frames, or change them after read-back. The result reports that outcome rather than claiming success.
- Accessibility is required for capture and restore. Screen Recording status is checked heuristically through window-list access.
- Physical display fingerprints from unique nonzero vendor/model/serial data survive a transient screen-number change; when unavailable, manual legacy geometry fallback remains a best-effort choice rather than proof of physical identity. Auto-apply will not use an ambiguous or legacy configuration.
- No live GUI/display mutation was part of the automated verification. The WindowManager scheme has no test action, so `xcodebuild test` is not available for this target.

## Verification evidence

The implementation was verified at the approved commit with a successful Debug build, focused policy and result-mapping harnesses, reopen-lifecycle checks, and a clean diff check. The focused harnesses cover 17 auto-apply policy checks, 4 stable-ID retry-mapping checks, and the frame read-back cases. These checks exercise pure/injected logic; they do not replace a live GUI test.

Build command:

```bash
xcodebuild \
  -project WindowManager.xcodeproj \
  -scheme WindowManager \
  -configuration Debug \
  -destination 'platform=macOS' \
  build
```

## Possible future improvements

- Explicit per-layout durable opt-in for imported layout Auto-apply (not available in v2.8).
- More robust matching for dynamic window titles.
- Launching missing applications.
- User-configurable exclusions and keyboard shortcuts.
- A visual layout preview.
- A verified composite display fingerprint, if a stable cross-version API becomes available.
