import SwiftUI

struct ScreenDetailInfo: Identifiable {
    let id = UUID()
    let index: Int
    let frame: CGRect
    let isPrimary: Bool
    let scale: CGFloat

    var resolution: String {
        "\(Int(frame.width))×\(Int(frame.height))"
    }

    var position: String {
        "(\(Int(frame.origin.x)), \(Int(frame.origin.y)))"
    }

    var displayName: String {
        isPrimary ? "Primary Display" : "Display \(index + 1)"
    }
}

struct ContentView: View {
    @EnvironmentObject var windowService: WindowService
    @EnvironmentObject var layoutStorage: LayoutStorageService
    @StateObject private var screenMonitor = ScreenMonitorService.shared
    @AppStorage("autoApplyEnabled") private var autoApplyEnabled = true
    @State private var layoutName = ""
    @State private var showingSaveAlert = false
    @State private var screenDetails: [ScreenDetailInfo] = []
    @State private var currentWindows: [WindowInfo] = []
    @State private var showingSaveSheet = false

    var body: some View {
        HStack(spacing: 0) {
            // Left Panel - App Info
            leftPanel
                .frame(width: 280)
                .background(Color(NSColor.controlBackgroundColor))

            Divider()

            // Right Panel - Main Content
            rightPanel
                .frame(maxWidth: .infinity)
        }
        .frame(minWidth: 900, minHeight: 600)
        .sheet(isPresented: $showingSaveSheet) {
            SaveLayoutSheet(
                layoutName: $layoutName,
                windows: currentWindows,
                screenDetails: screenDetails,
                onSave: { name in
                    saveLayout(name: name)
                },
                onCancel: {
                    showingSaveSheet = false
                    layoutName = ""
                }
            )
        }
        .onAppear {
            updateScreenDetails()
            // Подписываемся на уведомление от статус-бара
            NotificationCenter.default.addObserver(
                forName: NSNotification.Name("ShowSaveLayoutAlert"),
                object: nil,
                queue: .main
            ) { _ in
                prepareToSaveLayout()
            }
        }
        .onReceive(screenMonitor.$currentScreenConfiguration) { newConfig in
            guard newConfig != nil else { return }
            print("[ContentView] Screen configuration changed; refreshing display details")
            updateScreenDetails()
        }
    }

    // MARK: - Left Panel

    private var leftPanel: some View {
        VStack(alignment: .leading, spacing: 20) {
            // App Icon
            HStack {
                Spacer()
                Image(systemName: "macwindow.on.rectangle")
                    .font(.system(size: 64))
                    .foregroundColor(.blue)
                Spacer()
            }
            .padding(.top, 30)

            // App Name
            VStack(alignment: .center, spacing: 8) {
                Text("Window Manager")
                    .font(.title2)
                    .fontWeight(.bold)
                    .multilineTextAlignment(.center)
                    .frame(maxWidth: .infinity)
            }

            // Description
            Text("Manage and restore window layouts across multiple displays")
                .font(.subheadline)
                .foregroundColor(.secondary)
                .multilineTextAlignment(.center)
                .frame(maxWidth: .infinity)
                .padding(.horizontal)

            Divider()
                .padding(.vertical, 10)

            // Status
            VStack(spacing: 12) {
                Label("Status", systemImage: "info.circle")
                    .font(.headline)
                    .frame(maxWidth: .infinity, alignment: .center)

                HStack(spacing: 8) {
                    Circle()
                        .fill(Color.green)
                        .frame(width: 10, height: 10)

                    Text("Active")
                        .font(.subheadline)
                        .foregroundColor(.secondary)
                }
                .frame(maxWidth: .infinity, alignment: .center)

                // Auto-apply toggle
                Toggle(isOn: $autoApplyEnabled) {
                    HStack(spacing: 8) {
                        Image(systemName: "arrow.triangle.2.circlepath")
                            .font(.subheadline)
                            .foregroundColor(autoApplyEnabled ? .green : .gray)
                        Text("Auto-apply")
                            .font(.subheadline)
                            .foregroundColor(.secondary)
                    }
                }
                .toggleStyle(.switch)
                .frame(maxWidth: .infinity, alignment: .center)
                .padding(.horizontal, 40)
            }

            Spacer()
        }
        .padding(.vertical)
    }

    // MARK: - Right Panel

    private var rightPanel: some View {
        ScrollView {
            VStack(spacing: 24) {
                // Display Configuration Section
                displayConfigurationSection

                Divider()
                    .padding(.horizontal)

                // Quick Actions Section
                quickActionsSection

                Divider()
                    .padding(.horizontal)

                // Saved Layouts Section
                savedLayoutsSection
            }
            .padding(24)
        }
    }

    // MARK: - Display Configuration Section

    private var displayConfigurationSection: some View {
        VStack(alignment: .leading, spacing: 16) {
            Label("Display Configuration", systemImage: "display.2")
                .font(.headline)

            // Display icons
            HStack(spacing: 16) {
                ForEach(screenDetails) { screen in
                    VStack(spacing: 8) {
                        ZStack {
                            RoundedRectangle(cornerRadius: 8)
                                .fill(screen.isPrimary ? Color.blue.opacity(0.15) : Color.gray.opacity(0.1))
                                .frame(width: 60, height: 60)

                            Image(systemName: "display")
                                .font(.system(size: 28))
                                .foregroundColor(screen.isPrimary ? .blue : .gray)
                        }

                        if screen.isPrimary {
                            Text("Primary")
                                .font(.caption2)
                                .foregroundColor(.blue)
                                .fontWeight(.medium)
                        }
                    }
                }
            }
            .padding(.vertical, 8)

            // Text configuration details
            VStack(alignment: .leading, spacing: 6) {
                ForEach(screenDetails) { screen in
                    HStack {
                        Text(screen.displayName)
                            .font(.subheadline)
                            .fontWeight(.medium)
                        Text("•")
                            .foregroundColor(.secondary)
                        Text(screen.resolution)
                            .font(.subheadline)
                            .foregroundColor(.secondary)
                    }
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding()
        .background(Color(NSColor.controlBackgroundColor).opacity(0.5))
        .cornerRadius(12)
    }

    // MARK: - Quick Actions Section

    private var quickActionsSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            Label("Quick Actions", systemImage: "bolt.fill")
                .font(.headline)

            HStack(spacing: 12) {
                Button(action: prepareToSaveLayout) {
                    Label("Save Current Layout", systemImage: "square.and.arrow.down")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.borderedProminent)
                .controlSize(.large)

                Button(action: refreshScreenInfo) {
                    Label("Refresh", systemImage: "arrow.clockwise")
                }
                .buttonStyle(.bordered)
                .controlSize(.large)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    // MARK: - Saved Layouts Section

    private var savedLayoutsSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Label("Saved Layouts", systemImage: "rectangle.stack")
                    .font(.headline)

                Spacer()

                Text("\(layoutStorage.layouts.count) layout(s)")
                    .font(.caption)
                    .foregroundColor(.secondary)
            }

            LayoutListView()
                .environmentObject(windowService)
                .environmentObject(layoutStorage)
                .frame(minHeight: 200)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    // MARK: - Helper Methods

    private func updateScreenDetails() {
        let screens = NSScreen.screens
        screenDetails = screens.enumerated().map { index, screen in
            ScreenDetailInfo(
                index: index,
                frame: screen.frame,
                isPrimary: index == 0,
                scale: screen.backingScaleFactor
            )
        }
    }

    private func prepareToSaveLayout() {
        currentWindows = windowService.captureCurrentLayout()
        updateScreenDetails()
        showingSaveSheet = true
    }

    private func saveLayout(name: String) {
        let screenConfig = windowService.getCurrentScreenConfiguration()
        let layout = Layout(name: name, windows: currentWindows, screenConfiguration: screenConfig)
        layoutStorage.saveLayout(layout)

        // Обновляем меню в статус-баре
        StatusBarService.shared.updateMenu()

        showingSaveSheet = false
        layoutName = ""
    }

    private func refreshScreenInfo() {
        updateScreenDetails()
        screenMonitor.updateCurrentScreenConfiguration()
    }
}



// MARK: - Save Layout Sheet

struct SaveLayoutSheet: View {
    @Binding var layoutName: String
    let windows: [WindowInfo]
    let screenDetails: [ScreenDetailInfo]
    let onSave: (String) -> Void
    let onCancel: () -> Void

    @State private var selectedWindows: Set<UUID> = []

    var body: some View {
        VStack(spacing: 20) {
            // Header
            HStack {
                VStack(alignment: .leading, spacing: 4) {
                    Text("Save Window Layout")
                        .font(.title2)
                        .fontWeight(.bold)

                    Text("Review and save the current window positions")
                        .font(.subheadline)
                        .foregroundColor(.secondary)
                }

                Spacer()
            }
            .padding()

            Divider()

            // Content
            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    // Layout name
                    VStack(alignment: .leading, spacing: 8) {
                        Label("Layout Name", systemImage: "textformat")
                            .font(.headline)

                        TextField("Enter layout name", text: $layoutName)
                            .textFieldStyle(.roundedBorder)
                    }

                    // Screen configuration
                    VStack(alignment: .leading, spacing: 8) {
                        Label("Display Configuration", systemImage: "display.2")
                            .font(.headline)

                        HStack {
                            ForEach(screenDetails) { screen in
                                VStack(spacing: 4) {
                                    Image(systemName: "display")
                                        .foregroundColor(screen.isPrimary ? .blue : .gray)
                                    Text(screen.resolution)
                                        .font(.caption2)
                                }
                                .padding(8)
                                .background(Color.gray.opacity(0.1))
                                .cornerRadius(6)
                            }
                        }
                    }

                    // Windows preview
                    VStack(alignment: .leading, spacing: 8) {
                        Label("Windows to Save (\(windows.count))", systemImage: "macwindow.on.rectangle")
                            .font(.headline)

                        if windows.isEmpty {
                            Text("No windows detected")
                                .foregroundColor(.secondary)
                                .frame(maxWidth: .infinity, alignment: .center)
                                .padding()
                        } else {
                            VStack(spacing: 8) {
                                ForEach(windows) { window in
                                    WindowPreviewRow(window: window)
                                }
                            }
                        }
                    }
                }
                .padding()
            }

            Divider()

            // Actions
            HStack {
                Button("Cancel") {
                    onCancel()
                }
                .keyboardShortcut(.cancelAction)

                Spacer()

                Button("Save Layout") {
                    if !layoutName.isEmpty {
                        onSave(layoutName)
                    }
                }
                .buttonStyle(.borderedProminent)
                .disabled(layoutName.isEmpty)
                .keyboardShortcut(.defaultAction)
            }
            .padding()
        }
        .frame(width: 600, height: 500)
        .onAppear {
            selectedWindows = Set(windows.map { $0.id })
        }
    }
}

// MARK: - Window Preview Row

struct WindowPreviewRow: View {
    let window: WindowInfo

    var body: some View {
        HStack(spacing: 12) {
            // App icon placeholder
            ZStack {
                RoundedRectangle(cornerRadius: 6)
                    .fill(Color.blue.opacity(0.1))
                    .frame(width: 40, height: 40)

                Text(String(window.appName.prefix(1)))
                    .font(.title3)
                    .fontWeight(.bold)
                    .foregroundColor(.blue)
            }

            VStack(alignment: .leading, spacing: 4) {
                Text(window.appName)
                    .font(.subheadline)
                    .fontWeight(.semibold)

                Text(window.windowTitle.isEmpty ? "Untitled" : window.windowTitle)
                    .font(.caption)
                    .foregroundColor(.secondary)
                    .lineLimit(1)
            }

            Spacer()

            VStack(alignment: .trailing, spacing: 2) {
                Text("Screen \(window.screenIndex + 1)")
                    .font(.caption2)
                    .foregroundColor(.secondary)

                Text("\(Int(window.frame.width))×\(Int(window.frame.height))")
                    .font(.caption2)
                    .foregroundColor(.secondary)
            }
        }
        .padding(10)
        .background(Color(NSColor.controlBackgroundColor))
        .cornerRadius(8)
    }
}

struct ContentView_Previews: PreviewProvider {
    static var previews: some View {
        ContentView()
            .environmentObject(WindowService())
            .environmentObject(LayoutStorageService())
    }
}
