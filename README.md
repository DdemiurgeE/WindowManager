# WindowManager

WindowManager is a SwiftUI macOS application for saving and restoring window layouts across one or more displays. The app lives in the Menu Bar, can remember current window positions and sizes, lets you apply saved layouts manually, and can automatically restore a matching layout when the display configuration changes.

> Russian version: [`README.ru.md`](README.ru.md)

## What the app does

- Shows the current display configuration: number of displays, primary display, and resolutions.
- Captures the list of open windows from regular macOS applications via the Accessibility API.
- Stores the following for each window:
  - application name;
  - window title;
  - absolute `CGRect`;
  - display index;
  - normalized `relativeFrame` relative to the display;
  - capture timestamp.
- Stores user layouts in `UserDefaults` under the `SavedLayouts` key.
- Restores window positions and sizes via `AXUIElementSetAttributeValue`.
- Provides a Menu Bar menu with quick actions:
  - apply a saved layout;
  - save the current layout;
  - enable/disable Auto-apply;
  - open the main window;
  - quit the app.
- Monitors display configuration changes and, when Auto-apply is enabled, applies the most recently used layout that matches the current configuration.
- Shows a system notification after automatically applying a layout.

## Main usage scenarios

### 1. Initial permission setup

The app needs macOS system permissions to work:

1. **Accessibility** — required to read and control window positions.
2. **Screen Recording** — required to access window information.

Open the app settings or macOS System Settings:

- `System Settings → Privacy & Security → Accessibility`
- `System Settings → Privacy & Security → Screen Recording`

Add WindowManager to both lists and restart the app if macOS asks you to do so.

### 2. Saving a layout

1. Arrange your windows the way you want.
2. Click **Save Current Layout** in the main window or choose **Save Current Layout...** from the Menu Bar.
3. Review the detected windows.
4. Enter a layout name.
5. Click **Save Layout**.

### 3. Restoring a layout

- In the main window, click the restore button for the desired layout.
- Or choose the layout name from the Menu Bar menu.

The app finds running applications by `localizedName`, then tries to match windows by title. If an application has only one window, that window is used even without an exact title match.

### 4. Automatic application

When the display configuration changes, for example when a monitor is connected or disconnected, `ScreenMonitorService` looks for saved layouts with the same `ScreenConfiguration`. If Auto-apply is enabled, the most recently used matching layout is applied.

Auto-apply can be toggled:

- in the main window via the **Auto-apply** switch;
- in the Menu Bar via **Auto-apply Layouts**.

## Requirements

- macOS with SwiftUI/AppKit and Accessibility API support.
- Xcode.
- Accessibility and Screen Recording permissions.

Current project settings:

- Target: `WindowManager`
- Scheme: `WindowManager`
- Bundle ID: `obelisk.WindowManager`
- Swift: `5.0`
- Marketing version: `2.3`
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
│   └── WindowInfo.swift            # Saved window model
├── Services/
│   ├── WindowService.swift         # Captures and restores windows via AX API
│   ├── LayoutStorageService.swift  # Persists layouts in UserDefaults
│   ├── PermissionsService.swift    # Checks/requests macOS permissions
│   ├── ScreenMonitorService.swift  # Display monitoring and Auto-apply
│   └── StatusBarService.swift      # Menu Bar integration
└── Views/
    ├── ContentView.swift           # Main window
    ├── LayoutListView.swift        # Saved layouts list
    └── PermissionsView.swift       # Permissions screen
```

## Documentation

Detailed architecture, model, service, and limitation documentation is available in [`docs/ARCHITECTURE.md`](docs/ARCHITECTURE.md).

Russian documentation is available in [`docs/ARCHITECTURE.ru.md`](docs/ARCHITECTURE.ru.md).

## Known limitations

- Applications must already be running: WindowManager does not launch missing applications when restoring a layout.
- Window matching depends on the application name and window title. Dynamic titles can reduce restore accuracy.
- Some applications may restrict changing their window size or position via the Accessibility API.
- The app may need to be restarted after macOS permission changes.
- Saved layouts are stored locally in `UserDefaults`; there is no sync or export mechanism yet.

## Repository

https://github.com/DdemiurgeE/WindowManager
