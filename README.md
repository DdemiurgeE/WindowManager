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
- Stores user layouts as ISO-8601 JSON in local `UserDefaults` under the `SavedLayouts` key. There is no export, import, sync, or remote storage.
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

For each saved target, the app first matches a running application by bundle identifier when both sides have one, then falls back to localized name. It reads the app's current Accessibility windows and assigns targets using title, role, subrole, and frame metadata. Dynamic titles or changing window sets can prevent a match.

The display resolver prefers a unique usable observed display ID, then the saved frame's center, the saved display index, and finally a deterministic first display. An unchanged absolute frame is used only when saved and current display geometry, visible frame, and scale all match. Otherwise the finite normalized `relativeFrame` is projected onto the selected display; older layouts can fall back to their saved absolute frame. Normal frames are clamped so a useful title-bar strip remains reachable, without silently shrinking the saved window. Fullscreen/maximized-style presentations can opt out of this clamp.

Restore results are based on Accessibility writes and read-back. A window can be reported as `positionSet`, `appImposedClamp`, `axFailure`, `restoreSuperseded`, `coordinateUnavailable`, `appNotFound`, or `windowSkipped`, among other matching statuses. Only `positionSet` contributes to the restored-window count.

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
- the final notification is emitted at most once after the initial attempt and retries finish (or cancellation), subject to macOS notification authorization.

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
- Marketing version: `2.5`
- Build: `3`
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
│   ├── LayoutStorageService.swift  # Persists layouts in UserDefaults
│   ├── PermissionsService.swift    # Checks/requests macOS permissions
│   ├── ScreenMonitorService.swift  # Stable-topology Auto-apply lifecycle
│   └── StatusBarService.swift      # Menu Bar integration
└── Views/
    ├── ContentView.swift           # Main window
    ├── LayoutListView.swift        # Saved layouts list
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
- Saved layouts are local `UserDefaults` JSON only; there is no sync or export mechanism.
- The automated verification does not mutate live windows or displays. The WindowManager scheme has no test action, so `xcodebuild test` is not available for this target.

## Repository

https://github.com/DdemiurgeE/WindowManager
