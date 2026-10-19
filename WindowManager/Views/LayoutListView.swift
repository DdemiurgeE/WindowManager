//
//  LayoutListView.swift
//  WindowManager
//
//  Created by Pavel Palnikov on 03.02.2026.
//


import SwiftUI
import AppKit

struct LayoutListView: View {
    @EnvironmentObject var layoutStorage: LayoutStorageService
    @EnvironmentObject var windowService: WindowService
    @EnvironmentObject var permissionsService: PermissionsService
    
    @State private var selectedLayout: Layout?
    @State private var previewLayout: Layout?
    @State private var showingDeleteConfirmation = false
    @State private var layoutToDelete: Layout?
    @AppStorage("includeDetailedRestoreDiagnostics") private var includeDetailedDiagnostics = false
    
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
            }
            if let result = windowService.lastRestoreResult,
               layoutStorage.layouts.contains(where: { $0.id == result.layoutID }) {
                RestoreDiagnosticsView(result: result, includeDetails: $includeDetailedDiagnostics,
                    onRetry: { retryLayout(result.layoutID) })
                    .padding(.horizontal)
                    .padding(.bottom, 8)
            }
        }
        .navigationTitle("Saved Layouts")
        .toolbar {
            ToolbarItem(placement: .automatic) {
                Text("\(layoutStorage.layouts.count) layouts")
                    .foregroundColor(.secondary)
                    .font(.caption)
            }
        }
        .alert("Delete Layout", isPresented: $showingDeleteConfirmation, presenting: layoutToDelete) { layout in
            Button("Delete", role: .destructive) {
                layoutStorage.deleteLayout(layout)
                // Обновляем меню в статус-баре
                StatusBarService.shared.updateMenu()
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
        layoutStorage.markLayoutAsUsed(layout)
    }

    private func retryLayout(_ layoutID: UUID?) {
        guard let layoutID, let layout = layoutStorage.layouts.first(where: { $0.id == layoutID }) else { return }
        guard windowService.retryMissingOrFailed(layout) != nil else { return }
        layoutStorage.markLayoutAsUsed(layout)
    }

    private func applyLayout(_ layout: Layout) {
        restoreLayout(layout)
        previewLayout = nil
    }
}

struct RestoreDiagnosticsView: View {
    let result: RestoreResult
    @Binding var includeDetails: Bool
    let onRetry: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Label("Last restore: \(result.layoutName)", systemImage: "checkmark.circle")
                    .font(.headline)
                Spacer()
                Button("Copy diagnostics") {
                    NSPasteboard.general.clearContents()
                    NSPasteboard.general.setString(
                        RestoreResultMapping.redactedDiagnostics(for: result, includeWindowDetails: includeDetails),
                        forType: .string)
                }
                .buttonStyle(.borderless)
            }
            Text("Verified restored: \(result.windowsRestored) • Missing/skipped: \(result.skippedCount) • AX failures: \(result.accessibilityFailureCount) • App clamps: \(result.clampCount)")
                .font(.caption)
                .foregroundColor(.secondary)
            Toggle("Include app and window names in copied details (explicit consent)", isOn: $includeDetails)
                .font(.caption)
            HStack {
                Text(RestoreResult.lastUsedPolicyDescription)
                    .font(.caption2)
                    .foregroundColor(.secondary)
                Spacer()
                Button("Retry only missing / failed", action: onRetry)
                    .disabled(RestoreResultMapping.retryableIDs(in: result.windowsResults).isEmpty)
            }
            if includeDetails {
                ForEach(result.windowsResults) { item in
                    Text("\(item.appName) — \(item.windowTitle): \(item.status.rawValue)")
                        .font(.caption2)
                }
            }
        }
        .padding(10)
        .background(Color(NSColor.controlBackgroundColor))
        .cornerRadius(8)
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
                layoutStorage.markLayoutAsUsed(layout)
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
