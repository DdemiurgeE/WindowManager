//
//  LayoutListView.swift
//  WindowManager
//
//  Created by Pavel Palnikov on 03.02.2026.
//


import SwiftUI

struct LayoutListView: View {
    @EnvironmentObject var layoutStorage: LayoutStorageService
    @EnvironmentObject var windowService: WindowService
    @EnvironmentObject var permissionsService: PermissionsService
    
    @State private var selectedLayout: Layout?
    @State private var showingDeleteConfirmation = false
    @State private var layoutToDelete: Layout?
    
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
                        LayoutRow(layout: layout)
                            .contentShape(Rectangle())
                            .contextMenu {
                                Button(action: { restoreLayout(layout) }) {
                                    Label("Restore", systemImage: "arrow.clockwise")
                                }
                                .disabled(!permissionsService.hasAccessibilityPermission)
                                
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
    }
    
    private func restoreLayout(_ layout: Layout) {
        windowService.restoreLayout(layout)
        layoutStorage.markLayoutAsUsed(layout)
    }
}

struct LayoutRow: View {
    let layout: Layout
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
                        Text("• Last used: \(lastUsed, style: .relative)")
                    }
                }
                .font(.caption)
                .foregroundColor(.secondary)
            }
            
            Spacer()
            
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
        }
        .padding(.vertical, 8)
    }
}
