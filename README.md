# WindowManager

WindowManager is a SwiftUI + AppKit macOS menu-bar application for saving and restoring window layouts across one or more displays. Use it when you want to reposition already-running applications after changing your display setup, either manually or through Auto-apply.

> Russian version: [`README.ru.md`](README.ru.md)

## What the app does

- Shows the current display configuration, including display count, primary display, geometry, and scale.
- Captures windows from running regular applications through the Accessibility API. Windows smaller than 50×50 points or outside the union of current displays are skipped.
- Stores window metadata used for later restoration:
  - application name and optional bundle identifier;
  - title, Accessibility role, and subrole;
  - absolute `CGRect`;
  - normalized `relativeFrame`;
  - observed display ID, display geometry, visible frame, scale, and legacy display index;
  - capture timestamp.
- Stores layouts in local `SavedLayouts` until an explicitly confirmed import installs a private transactional Application Support file. The original defaults value remains a pre-import fallback snapshot; there is no sync or remote storage.
- Restores window frames through `AXUIElementSetAttributeValue`, then reads position and size back to report the effective result.
- Provides Menu Bar actions to apply a saved layout, save the current layout, toggle Auto-apply, open the main window, and quit.
- Monitors display-configuration changes and can automatically apply the most recently used matching layout.

## Main usage scenarios

### 1. Initial permission setup

The app needs macOS permissions to capture and restore windows:

1. **Accessibility** — required to read and control window positions.
2. **Screen Recording** — checked heuristically through access to the on-screen window list.

Open:

- `System Settings → Privacy & Security → Accessibility`
- `System Settings → Privacy & Security → Screen Recording`

Add WindowManager to both lists and restart the app if macOS asks you to do so.

### 2. Saving a layout

1. Arrange already-running windows.
2. Click **Save Current Layout** in the main window or choose **Save Current Layout...** from the Menu Bar.
3. Review the detected windows; small or off-display windows may be omitted.
4. Enter a layout name.
5. Click **Save Layout**.

### 3. Restoring a layout

- In the main window, click the restore button for the desired layout.
- Or choose the layout name from the Menu Bar menu.

For each saved target, the app matches a running application by bundle identifier when the saved target has one; targets without a saved bundle identifier use localized-name fallback. A bundle-ID target therefore requires a current bundle-ID match. It reads the app's current Accessibility windows and assigns targets using title, role, subrole, and frame metadata. Dynamic titles or changing window sets can prevent a match.

The display resolver prefers a unique usable observed display ID, then the saved frame's center, the saved display index, and finally a deterministic first display. An unchanged absolute frame is used only when saved and current display geometry, visible frame, and scale all match. Otherwise the finite normalized `relativeFrame` is projected onto the selected display; older layouts can fall back to their saved absolute frame. Normal frames are clamped so a useful title-bar strip remains reachable, without silently shrinking the saved window. Fullscreen/maximized-style presentations can opt out of this clamp.

Restore results are based on Accessibility writes and read-back. A window can be reported as `positionSet`, `appImposedClamp`, `axFailure`, `restoreSuperseded`, `coordinateUnavailable`, `appNotFound`, or `windowSkipped`, among other matching statuses. Only `positionSet` contributes to the restored-window count.

### Exporting a backup

In **Saved Layouts**, select **Export Backup…**, read the privacy warning, and choose a local destination. The versioned JSON envelope contains all saved layouts, including private window titles, app names, geometry, display metadata, IDs and ISO-8601 dates. Treat it as private; WindowManager does not upload it. An empty list exports `"layouts": []`. Cancel leaves the destination untouched; a failed export does not change saved layouts. Keep a separate copy of any backup you overwrite.

### Importing a backup (v2.8)

Choose **Import Backup…** and select a local JSON file. The non-writing preview validates the whole backup before explicit confirmation. Both v2.7 unversioned `[Layout]` and v2.8 `{ "format":"com.windowmanager.layouts", "schemaVersion":1, "exportedAt":..., "layouts":[...] }` are supported. Duplicate IDs/names, existing collisions, invalid/future schemas, malformed geometry and files over 16 MiB are rejected as a whole; there is no overwrite, silent rename, AX restore or cloud action. Empty imports are no-ops. Imported layouts retain `lastUsed` but are excluded from Auto-apply even after manual restore; v2.8 has no opt-in to change this.

The first confirmed import writes a 0600 file in a 0700 `obelisk.WindowManager` folder under the user Application Support directory. There is no launch-time migration. The original `SavedLayouts` defaults value is never deleted or rewritten by import and remains a fallback *only while the private file is absent*. Once present, the private file takes precedence for loads and edits. A corrupt or unsupported file disables edits and Auto-apply instead of silently falling back. After upgrade, older binaries see only the stale defaults snapshot; do not edit in an older version concurrently with v2.8. Export before downgrading. This file is included in normal system backups and contains sensitive metadata; consider encrypted backups. Durability relies on local filesystem rename/fsync semantics and cooperative writers, not universal hardware failure guarantees.

New exports use UTC ISO-8601 millisecond precision; v2.7 second-precision exports cannot recover lost fractions. UUIDs, ordering, optional metadata and geometry are preserved within the supported date precision. A post-rename failure can have an uncertain outcome: edits and Auto-apply are disabled until a restart/re-read; do not blindly retry import.

### 4. Automatic application

When macOS reports a display-configuration change, Auto-apply waits for a stable topology before writing window frames:

- the notification is debounced by 0.5 seconds;
- display snapshots are polled every 0.25 seconds;
- three consecutive equal snapshots are required, including geometry and scale;
- if stability is not reached within 10 seconds, the attempt is skipped;
- matching uses display IDs and, when geometry is available on both sides, complete `ScreenConfiguration` equality;
- the most recently used matching layout is selected; unused layouts sort after used layouts;
- missing applications/windows are retried at most three times, one second apart;
- a topology change or disabling Auto-apply invalidates pending retries and prevents further writes;
- the final notification is emitted at most once after the initial attempt and any active retries finish (or an active retry is cancelled by disabling Auto-apply), subject to macOS notification authorization; topology cancellation discards pending notification state.

Auto-apply is enabled by default (`autoApplyEnabled` in `UserDefaults`) and can be toggled in the main window or through **Auto-apply Layouts** in the Menu Bar.

## Requirements

- macOS with SwiftUI/AppKit and Accessibility API support.
- Xcode.
- Accessibility and Screen Recording permissions.

Current project settings:

- Target: `WindowManager`
- Scheme: `WindowManager`
- Bundle ID: `obelisk.WindowManager`
- Swift: `5.0`
- Marketing version: `2.8`
- Build: `6`
- macOS deployment target: `26.2`

## Building from source

```bash
xcodebuild \
  -project WindowManager.xcodeproj \
  -scheme WindowManager \
  -configuration Debug \
  -destination 'platform=macOS' \
  build
```

Release build:

```bash
xcodebuild \
  -project WindowManager.xcodeproj \
  -scheme WindowManager \
  -configuration Release \
  -destination 'platform=macOS' \
  build
```

## Project structure

```text
WindowManager/
├── WindowManagerApp.swift          # Entry point, AppDelegate, service initialization
├── Info.plist                      # App icon configuration
├── Models/
│   ├── Layout.swift                # Layout and display configuration model
│   ├── WindowInfo.swift            # Saved window model
│   └── RestoreResult.swift         # Restore statuses and result counts
├── Services/
│   ├── WindowService.swift         # Captures and restores windows via AX API
│   ├── FrameRestoreEngine.swift    # AX write, timing, drift correction, read-back
│   ├── ScreenResolver.swift        # Display selection and frame resolution
│   ├── WindowAssignment.swift       # Current-window matching
│   ├── LayoutStorageService.swift  # Coordinates legacy and transactional layouts
│   ├── TransactionalLayoutStore.swift # Private post-import authoritative file
│   ├── LayoutImportCodec.swift     # Bounded legacy/versioned JSON validation
│   ├── PermissionsService.swift    # Checks/requests macOS permissions
│   ├── ScreenMonitorService.swift  # Stable-topology Auto-apply lifecycle
│   └── StatusBarService.swift      # Menu Bar integration
└── Views/
    ├── ContentView.swift           # Main window
    ├── LayoutListView.swift        # Saved layouts list
    ├── RestorePreviewView.swift    # Safe restore preview
    └── PermissionsView.swift       # Permissions screen
```

## Documentation

Detailed architecture, model, service, restore-status, and limitation documentation is available in [`docs/ARCHITECTURE.md`](docs/ARCHITECTURE.md).

Russian documentation is available in [`docs/ARCHITECTURE.ru.md`](docs/ARCHITECTURE.ru.md).

## Known limitations

- Applications must already be running; WindowManager does not launch missing applications.
- Bundle IDs, localized names, titles, roles, subroles, and frames improve matching but do not guarantee it. Dynamic titles and changing application window sets can prevent assignment.
- Some applications reject Accessibility changes, clamp frames, or change them after read-back; the result reports that outcome instead of claiming success.
- Display IDs are observation keys and can change after reconnect. Normalized coordinates adapt to geometry but do not prove that two IDs refer to the same physical monitor; vendor/model/serial fingerprints are not stored.
- Older layouts remain decodable, but layouts without newer display metadata rely on resolver fallbacks and cannot claim exact display identity.
- Accessibility is required for capture and restore. Screen Recording status is checked heuristically through window-list access.
- Import/export are manual and local only; there is no sync mechanism. Concurrent old binaries and hardware/power failures are outside the private store's cooperative-writer guarantee.
- The automated verification does not mutate live windows or displays. The WindowManager scheme has no test action, so `xcodebuild test` is not available for this target.

## Repository

https://github.com/DdemiurgeE/WindowManager
