# WindowManager Architecture

This document describes the current WindowManager application structure, its main services, data models, and user-scenario execution flow.

> Russian version: [`ARCHITECTURE.ru.md`](ARCHITECTURE.ru.md)

## Purpose

WindowManager automates restoring workspace window layouts on macOS. Its primary goal is to quickly return application windows to the right displays and positions after reconnecting monitors, switching workstations, or manually rearranging windows.

The application is built as a SwiftUI + AppKit macOS app:

- SwiftUI handles the main window, saved-layout list, and permissions screen.
- AppKit is used for Menu Bar integration, application-window handling, and system display access.
- Accessibility API (`ApplicationServices`) is used to read and change positions of windows belonging to other applications.
- `UserDefaults` is used as the local storage for saved layouts.

## High-level structure

```text
WindowManagerApp
├── ContentView
│   ├── Display Configuration
│   ├── Quick Actions
│   └── LayoutListView
├── Settings → PermissionsView
├── StatusBarService
├── ScreenMonitorService
├── WindowService
├── LayoutStorageService
└── PermissionsService
```

Data flows:

```text
Save Current Layout
    ↓
WindowService.captureCurrentLayout()
    ↓
[WindowInfo]
    ↓
Layout(name, windows, screenConfiguration)
    ↓
LayoutStorageService.saveLayout()
    ↓
UserDefaults["SavedLayouts"]
```

```text
Restore Layout
    ↓
LayoutListView / StatusBarService
    ↓
WindowService.restoreLayout(layout)
    ↓
AXUIElementSetAttributeValue(kAXPositionAttribute / kAXSizeAttribute)
```

```text
Screen configuration changed
    ↓
ScreenMonitorService
    ↓
Find matching Layout.screenConfiguration
    ↓
Restore most recently used matching layout
    ↓
User notification
```

## Entry point

File: `WindowManager/WindowManagerApp.swift`

`WindowManagerApp` creates three main `@StateObject` instances:

- `WindowService`
- `PermissionsService`
- `LayoutStorageService`

They are injected into the SwiftUI hierarchy via `environmentObject`.

When the main window appears, `setupServices()` runs:

1. `StatusBarService.shared.setup(...)` creates the Menu Bar item and menu.
2. `ScreenMonitorService.shared.setup(...)` provides the services required for automatic layout application.

`AppDelegate`:

- checks permissions on launch;
- keeps a reference to the main window;
- prevents the app from terminating when the last window is closed, so it can keep running from the Menu Bar;
- can show the main window again when the app is reopened.

## Data models

### `WindowInfo`

File: `WindowManager/Models/WindowInfo.swift`

Describes one saved window:

| Field | Purpose |
| --- | --- |
| `id` | Window record UUID |
| `appName` | Application `localizedName` |
| `windowTitle` | Window title from Accessibility API |
| `frame` | Absolute `CGRect` in `NSScreen` coordinates |
| `relativeFrame` | Normalized frame relative to the display |
| `screenIndex` | Index of the display where the window was captured |
| `timestamp` | Capture time |

`relativeFrame` is the key mechanism that makes layouts resilient to monitor reconnection. Instead of relying only on absolute coordinates, the app stores the window position and size as fractions of the corresponding display:

```text
x      = (window.x - screen.x) / screen.width
y      = (window.y - screen.y) / screen.height
width  = window.width / screen.width
height = window.height / screen.height
```

During restore, these values are converted back into the current display frame.

### `Layout`

File: `WindowManager/Models/Layout.swift`

Describes a saved layout:

| Field | Purpose |
| --- | --- |
| `id` | Layout UUID |
| `name` | User-provided name |
| `windows` | List of saved windows |
| `createdAt` | Creation date |
| `lastUsed` | Last time the layout was applied |
| `screenConfiguration` | Display configuration at save time |

### `ScreenConfiguration`

Stores a sorted list of display identifiers and the display count. It is used to find layouts matching the currently connected displays.

A display identifier is built as follows:

1. If `NSScreenNumber` is available, `screen_<number>` is used.
2. Otherwise the fallback is `screen_<width>x<height>_<x>_<y>`.

## Services

### `PermissionsService`

File: `WindowManager/Services/PermissionsService.swift`

Handles checking and requesting macOS permissions:

- Accessibility: `AXIsProcessTrustedWithOptions`.
- Screen Recording: attempts to read window information via `CGWindowListCopyWindowInfo`.

It also opens the relevant System Settings pages via `x-apple.systempreferences` URL schemes.

### `WindowService`

File: `WindowManager/Services/WindowService.swift`

The main service for working with external application windows.

#### Capturing a layout

`captureCurrentLayout()`:

1. Checks the Accessibility permission.
2. Gets `NSWorkspace.shared.runningApplications`.
3. Filters regular applications with `activationPolicy == .regular`.
4. Creates `AXUIElementCreateApplication(pid)` for each application.
5. Reads `kAXWindowsAttribute`.
6. For each window, reads:
   - `kAXTitleAttribute`;
   - `kAXPositionAttribute`;
   - `kAXSizeAttribute`.
7. Skips windows that are too small or completely outside all displays.
8. Determines the display by the largest intersection area between the window and each screen.
9. Stores both the absolute `frame` and the normalized `relativeFrame`.

#### AX and NSScreen coordinates

Accessibility/Quartz and `NSScreen` use different Y axes:

- `NSScreen`: origin is the bottom-left corner of the main display; Y grows upward.
- AX/Quartz: origin is the top-left corner of the main display; Y grows downward.

Because of this, the service contains coordinate converters:

- `screenFrameToAXOrigin(_:)`
- `axOriginToScreenFrame(axOrigin:size:)`

Formula for converting an `NSScreen` frame to an AX origin:

```text
axY = mainScreenHeight - screenY - windowHeight
```

#### Restoring a layout

`restoreLayout(_:)`:

1. Checks the Accessibility permission.
2. Gets currently running applications and the list of displays.
3. Computes `targetFrame` for each `WindowInfo`.
4. Finds the application by `localizedName == appName`.
5. Finds the window by title. If the application has exactly one window, that window is used as a fallback.
6. Sets position and size via the AX API.

`setWindowFrame(...)` applies position and size in several steps:

1. Position.
2. Short delay.
3. Size.
4. Short delay.
5. Position again.
6. Deferred drift check after 0.5 seconds and an additional correction if needed.

The second position update is necessary because some applications clip the requested window size, which can shift the window position.

### `LayoutStorageService`

File: `WindowManager/Services/LayoutStorageService.swift`

Stores the `[Layout]` array in `UserDefaults`:

- key: `SavedLayouts`;
- encoder: `JSONEncoder`;
- date strategy: `.iso8601`.

Methods:

- `saveLayout(_:)`
- `deleteLayout(_:)`
- `updateLayout(_:)`
- `markLayoutAsUsed(_:)`

### `ScreenMonitorService`

File: `WindowManager/Services/ScreenMonitorService.swift`

Monitors `NSApplication.didChangeScreenParametersNotification` with a 0.5-second debounce.

When displays change:

1. Builds a new `ScreenConfiguration`.
2. Compares it with the current one.
3. If the configuration changed and Auto-apply is enabled, searches for saved layouts with the same configuration.
4. Sorts matching layouts by `lastUsed`.
5. Applies the most recent layout after 1 second.
6. Sends a `Window Manager — Layout '<name>' applied automatically` notification.

Auto-apply is stored in `UserDefaults` under the `autoApplyEnabled` key. The default value is `true`.

### `StatusBarService`

File: `WindowManager/Services/StatusBarService.swift`

Creates an `NSStatusItem` with the `macwindow.on.rectangle` system symbol and a dynamic menu.

The menu is refreshed before each opening and contains:

1. the list of saved layouts;
2. `Save Current Layout...`;
3. `Auto-apply Layouts`;
4. `Open Window`;
5. `Quit`.

To start saving from the Menu Bar, the service opens the main window and posts the `ShowSaveLayoutAlert` notification, which is observed by `ContentView`.

## UI components

### `ContentView`

File: `WindowManager/Views/ContentView.swift`

The main application window. It consists of a left panel and a main content area.

Left panel:

- app icon and name;
- short description;
- Active status;
- Auto-apply toggle.

Main area:

- `Display Configuration` — current displays;
- `Quick Actions` — saving the current layout and refreshing display info;
- `Saved Layouts` — saved layouts list.

Saving a layout opens `SaveLayoutSheet`, which shows:

- layout name;
- display configuration;
- detected windows list.

### `LayoutListView`

File: `WindowManager/Views/LayoutListView.swift`

Shows saved layouts. For each layout it displays:

- name;
- number of windows;
- creation date;
- last-used date, if available;
- Restore button.

The context menu allows restoring or deleting a layout.

### `PermissionsView`

File: `WindowManager/Views/PermissionsView.swift`

Settings screen for checking and granting Accessibility and Screen Recording permissions.

## Limitations and edge behavior

1. **The app does not launch missing applications.** If an application from the layout is not running, the corresponding window is skipped.
2. **Windows are matched by title.** Dynamic titles can prevent exact restore matching.
3. **Some windows cannot be moved.** Certain applications reject Accessibility frame changes or immediately adjust the frame back.
4. **macOS permissions are critical.** Without Accessibility, capturing and restoring layouts do not work.
5. **Screen Recording is detected heuristically.** The service checks whether it can read window names via `CGWindowListCopyWindowInfo`.
6. **No layout export yet.** Layouts currently live only in local `UserDefaults`.
7. **Auto-apply is tied to `ScreenConfiguration`.** If display identifiers change unpredictably, a matching layout may not be found.

## Build verification

Local verification command:

```bash
xcodebuild \
  -project WindowManager.xcodeproj \
  -scheme WindowManager \
  -configuration Debug \
  -destination 'platform=macOS' \
  build
```

If Xcode chooses between multiple destinations for Apple Silicon and Intel, that is normal; specify `arch=arm64` or `arch=x86_64` explicitly if needed.

## Possible future improvements

- Export/import layouts as JSON.
- Edit a saved layout without recapturing it.
- More robust window matching: bundle identifier, process identifier, AXRole, AXSubrole.
- Automatically launch applications that are missing during restore.
- Keyboard shortcuts for saving and applying layouts.
- Exclusion support: do not save/restore specific applications or windows.
- Visual screen/window layout preview before saving.
