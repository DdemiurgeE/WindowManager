//
//  LayoutListView.swift
//  WindowManager
//
//  Created by Pavel Palnikov on 03.02.2026.
//


import SwiftUI
import AppKit
import Combine
import UniformTypeIdentifiers

struct LayoutListView: View {
    @EnvironmentObject var layoutStorage: LayoutStorageService
    @EnvironmentObject var windowService: WindowService
    @EnvironmentObject var permissionsService: PermissionsService
    
    @State private var selectedLayout: Layout?
    @State private var previewLayout: Layout?
    @State private var showingDeleteConfirmation = false
    @State private var layoutToDelete: Layout?
    @State private var showingExportWarning = false
    @State private var showingExportResult = false
    @State private var exportResult = ""
    @State private var importPreview: LayoutStorageService.ImportPreview?
    @State private var showingImportConfirmation = false
    @State private var showingImportResult = false
    @State private var importResult = ""
    
    var body: some View {
        VStack {
            if layoutStorage.layouts.isEmpty {
                VStack(spacing: 20) {
                    Image(systemName: "rectangle.stack")
                        .font(.system(size: 60))
                        .foregroundColor(.gray)
                    Text("No Saved Layouts")
                        .font(.title2)
                        .foregroundColor(.secondary)
                    Text("Capture and save your first layout to get started")
                        .font(.subheadline)
                        .foregroundColor(.secondary)
                        .multilineTextAlignment(.center)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                List {
                    ForEach(layoutStorage.layouts) { layout in
                        LayoutRow(layout: layout, onPreview: { previewLayout = layout })
                            .contentShape(Rectangle())
                            .contextMenu {
                                Button(action: { restoreLayout(layout) }) {
                                    Label("Restore", systemImage: "arrow.clockwise")
                                }
                                .disabled(!permissionsService.hasAccessibilityPermission)

                                Button(action: { previewLayout = layout }) {
                                    Label("Preview / Dry Run", systemImage: "eye")
                                }
                                
                                Button(role: .destructive, action: {
                                    layoutToDelete = layout
                                    showingDeleteConfirmation = true
                                }) {
                                    Label("Delete", systemImage: "trash")
                                }
                            }
                    }
                }
                .listStyle(.inset)
                .frame(height: 220)
            }
            if let result = windowService.lastRestoreResult,
               layoutStorage.layouts.contains(where: { $0.id == result.layoutID }) {
                RestoreDiagnosticsView(result: result, revision: windowService.restoreResultRevision,
                    isExpanded: windowService.restoreDiagnosticsExpanded,
                    onToggle: {
                        if windowService.restoreDiagnosticsExpanded {
                            windowService.hideRestoreDiagnostics()
                        } else {
                            windowService.showRestoreDiagnostics()
                        }
                    },
                    onRetry: { retryLayout(result.layoutID) })
                    .id(windowService.restoreResultRevision)
                    .padding(.horizontal)
                    .padding(.bottom, 8)
            }
        }
        .navigationTitle("Saved Layouts")
        .toolbar {
            ToolbarItem(placement: .automatic) {
                Button("Export Backup…", systemImage: "square.and.arrow.up") {
                    showingExportWarning = true
                }
                .accessibilityLabel("Export backup of all saved layouts")
                .help("Save all layouts as a local JSON backup")
            }
            ToolbarItem(placement: .automatic) {
                Button("Import Backup…", systemImage: "square.and.arrow.down") { importBackup() }
                    .accessibilityLabel("Choose a local JSON backup to preview for import")
            }
            ToolbarItem(placement: .automatic) {
                Text("\(layoutStorage.layouts.count) layouts")
                    .foregroundColor(.secondary)
                    .font(.caption)
            }
        }
        .confirmationDialog("Export all saved layouts?", isPresented: $showingExportWarning) {
            Button("Choose Backup Destination…") { exportBackup() }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("The JSON backup contains window titles, app names, window geometry, and display metadata. Keep it private. Nothing is uploaded; you choose where to save it.")
        }
        .alert("Backup Export", isPresented: $showingExportResult) {
            Button("OK", role: .cancel) {}
        } message: {
            Text(exportResult)
        }
        .confirmationDialog("Import backup?", isPresented: $showingImportConfirmation) {
            Button("Import \(importPreview?.layouts.count ?? 0) Layouts") { confirmImport() }
            Button("Cancel", role: .cancel) { importPreview = nil }
        } message: {
            Text("Add \(importPreview?.layouts.count ?? 0) layouts to \(layoutStorage.layouts.count) saved layouts? Existing layouts are never replaced. Imported layouts remain excluded from Auto-apply even if restored manually. The backup contains private window titles, app names, geometry and display metadata; keep the file and device backups private. Nothing is uploaded.")
        }
        .alert("Backup Import", isPresented: $showingImportResult) {
            Button("OK", role: .cancel) {}
        } message: { Text(importResult) }
        .alert("Delete Layout", isPresented: $showingDeleteConfirmation, presenting: layoutToDelete) { layout in
            Button("Delete", role: .destructive) {
                do {
                    try layoutStorage.deleteLayout(layout)
                    StatusBarService.shared.updateMenu()
                } catch { reportStorageFailure() }
            }
            Button("Cancel", role: .cancel) {}
        } message: { layout in
            Text("Are you sure you want to delete '\(layout.name)'?")
        }
        .sheet(item: $previewLayout) { layout in
            RestorePreviewView(
                layout: layout,
                planner: windowService,
                onApply: { applyLayout(layout) }
            )
        }
    }
    
    private func restoreLayout(_ layout: Layout) {
        windowService.restoreLayout(layout)
        do { try layoutStorage.markLayoutAsUsed(layout) } catch { reportStorageFailure() }
    }

    private func exportBackup() {
        let panel = NSSavePanel()
        panel.title = "Export Saved Layouts Backup"
        panel.nameFieldStringValue = "WindowManager-Layouts.json"
        panel.allowedContentTypes = [.json]
        panel.canCreateDirectories = true
        guard panel.runModal() == .OK, let url = panel.url else { return }

        do {
            try LayoutBackupExporter.export(layoutStorage.exportLayouts(), to: url)
            exportResult = "Backup exported to the chosen location. Keep this file private."
        } catch {
            // Do not expose encoding errors, file paths, or private layout content.
            exportResult = "Backup could not be exported. No layout data was changed. Check the destination and try again."
        }
        showingExportResult = true
    }

    private func importBackup() {
        let panel = NSOpenPanel()
        panel.title = "Choose Layout Backup"
        panel.allowedContentTypes = [.json]
        panel.canChooseDirectories = false
        panel.allowsMultipleSelection = false
        guard panel.runModal() == .OK, let url = panel.url else { return }
        let scoped = url.startAccessingSecurityScopedResource()
        defer { if scoped { url.stopAccessingSecurityScopedResource() } }
        do {
            let handle = try FileHandle(forReadingFrom: url)
            defer { try? handle.close() }
            let bytes = try handle.read(upToCount: LayoutImportCodec.maxBytes + 1) ?? Data()
            let preview = try layoutStorage.prepareImport(bytes)
            guard !preview.layouts.isEmpty else {
                importResult = "Backup is empty; no layouts were changed."
                showingImportResult = true
                return
            }
            importPreview = preview
            showingImportConfirmation = true
        } catch {
            importResult = "Backup cannot be imported. Check its format, size, or duplicate IDs/names. No layouts were changed."
            showingImportResult = true
        }
    }

    private func confirmImport() {
        guard let preview = importPreview else { return }
        importPreview = nil
        do {
            try layoutStorage.confirmImport(preview)
            StatusBarService.shared.updateMenu()
            importResult = "Layouts imported. They will not Auto-apply."
        } catch {
            importResult = layoutStorage.storageAvailable
                ? "Import was rejected or storage failed before commit. Inspect saved layouts before retrying."
                : "Commit outcome needs recovery. Auto-apply and changes are disabled; restart to re-read the private store. Do not retry blindly."
        }
        showingImportResult = true
    }

    private func reportStorageFailure() {
        importResult = layoutStorage.storageAvailable
            ? "Layout could not be saved. Check storage and retry."
            : "Private layout store needs recovery; changes and Auto-apply are disabled."
        showingImportResult = true
    }

    private func retryLayout(_ layoutID: UUID?) {
        guard let layoutID, let layout = layoutStorage.layouts.first(where: { $0.id == layoutID }) else { return }
        guard windowService.retryMissingOrFailed(layout) != nil else { return }
        do { try layoutStorage.markLayoutAsUsed(layout) } catch { reportStorageFailure() }
    }

    private func applyLayout(_ layout: Layout) {
        restoreLayout(layout)
        previewLayout = nil
    }
}

/// A confirmation belongs to one request and one result; it is never persisted.
enum RestoreDiagnosticsCopyOutcome: Equatable {
    case success, staleRequest, writeFailed

    var message: String {
        switch self {
        case .success: return ""
        case .staleRequest: return "Diagnostics changed or confirmation expired. No copy was attempted; request a new copy."
        case .writeFailed: return "Diagnostics could not be copied. Clipboard contents may have changed; try again."
        }
    }
}

@MainActor final class RestoreDiagnosticsCopyActions: ObservableObject {
    private let write: (String) -> Bool
    private var pendingDetails: (revision: Int, text: String)?

    init(write: @escaping (String) -> Bool) {
        self.write = write
    }

    convenience init() { self.init(write: Self.writeToPasteboard) }

    func copySummary(for result: RestoreResult) -> Bool {
        write(RestoreResultMapping.redactedDiagnostics(for: result, includeWindowDetails: false))
    }

    func request(for result: RestoreResult, revision: Int) {
        pendingDetails = (revision,
            RestoreResultMapping.redactedDiagnostics(for: result, includeWindowDetails: true))
    }

    func cancel() { pendingDetails = nil }

    func confirm(for result: RestoreResult, revision: Int) -> RestoreDiagnosticsCopyOutcome {
        guard let pendingDetails else { return .staleRequest }
        self.pendingDetails = nil
        guard pendingDetails.revision == revision else { return .staleRequest }
        let currentDetails = RestoreResultMapping.redactedDiagnostics(for: result, includeWindowDetails: true)
        guard currentDetails == pendingDetails.text else { return .staleRequest }
        return write(currentDetails) ? .success : .writeFailed
    }

    private static func writeToPasteboard(_ text: String) -> Bool {
        let pasteboard = NSPasteboard.general
        pasteboard.clearContents()
        return pasteboard.setString(text, forType: .string)
    }
}

@MainActor struct RestoreDiagnosticsView: View {
    let result: RestoreResult
    let revision: Int
    let isExpanded: Bool
    let onToggle: () -> Void
    let onRetry: () -> Void
    @StateObject var copyActions: RestoreDiagnosticsCopyActions
    private enum CopyAlert { case confirmation, staleRequest, failure }
    @State private var copyAlert: CopyAlert?
    @State private var showNamesOnScreen = false

    init(result: RestoreResult, revision: Int, isExpanded: Bool, onToggle: @escaping () -> Void,
         onRetry: @escaping () -> Void) {
        self.init(result: result, revision: revision, isExpanded: isExpanded, onToggle: onToggle,
                  onRetry: onRetry, copyActions: RestoreDiagnosticsCopyActions())
    }

    init(result: RestoreResult, revision: Int, isExpanded: Bool, onToggle: @escaping () -> Void,
         onRetry: @escaping () -> Void, copyActions: RestoreDiagnosticsCopyActions) {
        self.result = result
        self.revision = revision
        self.isExpanded = isExpanded
        self.onToggle = onToggle
        self.onRetry = onRetry
        _copyActions = StateObject(wrappedValue: copyActions)
    }

    func copySummary() -> Bool { copyActions.copySummary(for: result) }
    func requestDetailedCopy() { copyActions.request(for: result, revision: revision) }
    func cancelDetailedCopy() { copyActions.cancel() }
    func confirmDetailedCopy() -> RestoreDiagnosticsCopyOutcome { copyActions.confirm(for: result, revision: revision) }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Label("Last restore: \(result.layoutName)", systemImage: "checkmark.circle")
                    .font(.headline)
                    .lineLimit(1)
                Spacer()
                Button(isExpanded ? "Hide diagnostics" : "Show diagnostics", action: onToggle)
                    .buttonStyle(.borderless)
            }
            Text(result.compactDiagnosticsDescription)
                .font(.caption)
                .foregroundColor(.secondary)
            if isExpanded {
                Toggle("Show app and window names on screen (does not affect copied diagnostics)", isOn: $showNamesOnScreen)
                    .font(.caption)
                HStack {
                    Button("Copy summary") {
                        if !copySummary() { copyAlert = .failure }
                    }
                    Button("Copy with names…") {
                        requestDetailedCopy()
                        copyAlert = .confirmation
                    }
                    .help("Requires confirmation each time; includes layout, app and window names")
                }
                .buttonStyle(.borderless)
                HStack {
                    Text(RestoreResult.lastUsedPolicyDescription)
                        .font(.caption2)
                        .foregroundColor(.secondary)
                    Spacer()
                    Button("Retry only missing / failed", action: onRetry)
                        .disabled(RestoreResultMapping.retryableIDs(in: result.windowsResults).isEmpty)
                }
                if showNamesOnScreen {
                    ScrollView {
                        LazyVStack(alignment: .leading, spacing: 4) {
                            ForEach(result.windowsResults) { item in
                                Text("\(item.appName) — \(item.windowTitle): \(item.status.rawValue)")
                                    .font(.caption2)
                                    .lineLimit(1)
                                    .frame(maxWidth: .infinity, alignment: .leading)
                            }
                        }
                    }
                    .frame(maxHeight: 140)
                }
            }
        }
        .padding(10)
        .background(Color(NSColor.controlBackgroundColor))
        .cornerRadius(8)
        .alert(copyAlert == .confirmation ? "Copy diagnostics with names?" :
               copyAlert == .staleRequest ? "Copy request expired" : "Copy failed",
               isPresented: Binding(
                get: { copyAlert != nil },
                set: { presented in
                    if !presented {
                        cancelDetailedCopy()
                        copyAlert = nil
                    }
                })) {
            if copyAlert == .confirmation {
                Button("Cancel", role: .cancel) { cancelDetailedCopy() }
                    .keyboardShortcut(.defaultAction)
                Button("Copy with names") {
                    let outcome = confirmDetailedCopy()
                    if outcome != .success {
                        // Present after the confirmation has finished dismissing.
                        DispatchQueue.main.async {
                            copyAlert = outcome == .staleRequest ? .staleRequest : .failure
                        }
                    }
                }
            } else {
                Button("OK", role: .cancel) {}
            }
        } message: {
            Text(copyAlert == .confirmation
                ? "This copies layout, app and window names. They remain on the system clipboard until replaced. Confirm each time you copy with names."
                : copyAlert == .staleRequest
                    ? RestoreDiagnosticsCopyOutcome.staleRequest.message
                    : RestoreDiagnosticsCopyOutcome.writeFailed.message)
        }
        .onChange(of: revision) { _, _ in
            cancelDetailedCopy()
            copyAlert = nil
            showNamesOnScreen = false
        }
    }
}

struct LayoutRow: View {
    let layout: Layout
    let onPreview: () -> Void
    @EnvironmentObject var windowService: WindowService
    @EnvironmentObject var permissionsService: PermissionsService
    @EnvironmentObject var layoutStorage: LayoutStorageService
    
    var body: some View {
        HStack {
            VStack(alignment: .leading, spacing: 8) {
                Text(layout.name)
                    .font(.headline)
                
                Text("\(layout.windows.count) windows")
                    .font(.subheadline)
                    .foregroundColor(.secondary)
                
                HStack {
                    Text("Created: \(layout.createdAt, style: .date)")
                    if let lastUsed = layout.lastUsed {
                        Text("• Last attempted: \(lastUsed, style: .relative)")
                    }
                }
                .font(.caption)
                .foregroundColor(.secondary)
            }
            
            Spacer()
            
            Button(action: {
                onPreview()
            }) {
                Label("Preview / Dry Run", systemImage: "eye.circle.fill")
                    .font(.subheadline)
            }
            .buttonStyle(.borderless)
            .accessibilityLabel("Preview layout \(layout.name) without applying")

            Button(action: {
                windowService.restoreLayout(layout)
                try? layoutStorage.markLayoutAsUsed(layout)
            }) {
                Label("Restore", systemImage: "arrow.clockwise.circle.fill")
                    .labelStyle(.iconOnly)
                    .font(.title2)
            }
            .buttonStyle(.borderless)
            .disabled(!permissionsService.hasAccessibilityPermission)
            .accessibilityLabel("Apply layout \(layout.name)")
        }
        .padding(.vertical, 8)
    }
}
