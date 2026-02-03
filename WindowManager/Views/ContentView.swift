//
//  ContentView.swift
//  WindowManager
//
//  Created by Pavel Palnikov on 03.02.2026.
//


import SwiftUI

struct ContentView: View {
    @EnvironmentObject var windowService: WindowService
    @EnvironmentObject var permissionsService: PermissionsService
    @EnvironmentObject var layoutStorage: LayoutStorageService
    
    @State private var showingSaveDialog = false
    @State private var newLayoutName = ""
    @State private var showingPermissionsAlert = false
    
    var body: some View {
        NavigationView {
            VStack(spacing: 20) {
                // Статус разрешений
                if !permissionsService.hasAccessibilityPermission {
                    PermissionWarningView()
                }
                
                // Информация об экранах
                VStack(alignment: .leading, spacing: 10) {
                    Text("Screens Information")
                        .font(.headline)
                    
                    Text(windowService.getScreensInfo())
                        .font(.system(.body, design: .monospaced))
                        .padding()
                        .background(Color.gray.opacity(0.1))
                        .cornerRadius(8)
                }
                .padding()
                
                // Кнопки управления
                VStack(spacing: 15) {
                    Button(action: captureLayout) {
                        Label("Capture Current Layout", systemImage: "camera.fill")
                            .frame(maxWidth: .infinity)
                            .padding()
                            .background(Color.blue)
                            .foregroundColor(.white)
                            .cornerRadius(10)
                    }
                    .disabled(!permissionsService.hasAccessibilityPermission)
                    
                    if !windowService.currentWindows.isEmpty {
                        Button(action: { showingSaveDialog = true }) {
                            Label("Save Layout", systemImage: "square.and.arrow.down")
                                .frame(maxWidth: .infinity)
                                .padding()
                                .background(Color.green)
                                .foregroundColor(.white)
                                .cornerRadius(10)
                        }
                    }
                }
                .padding(.horizontal)
                
                // Список окон
                if !windowService.currentWindows.isEmpty {
                    VStack(alignment: .leading) {
                        Text("Captured Windows (\(windowService.currentWindows.count))")
                            .font(.headline)
                            .padding(.horizontal)
                        
                        List(windowService.currentWindows) { window in
                            VStack(alignment: .leading, spacing: 5) {
                                Text(window.appName)
                                    .font(.headline)
                                Text(window.windowTitle)
                                    .font(.subheadline)
                                    .foregroundColor(.secondary)
                                Text("Screen \(window.screenIndex) • \(Int(window.frame.width))×\(Int(window.frame.height))")
                                    .font(.caption)
                                    .foregroundColor(.secondary)
                            }
                            .padding(.vertical, 5)
                        }
                    }
                }
                
                Spacer()
            }
            .navigationTitle("Window Manager")
            
            // Список сохраненных layouts
            LayoutListView()
        }
        .sheet(isPresented: $showingSaveDialog) {
            SaveLayoutDialog(layoutName: $newLayoutName, onSave: saveCurrentLayout)
        }
        .alert("Permissions Required", isPresented: $showingPermissionsAlert) {
            Button("Open Settings") {
                permissionsService.requestAccessibilityPermission()
            }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("This app requires Accessibility permissions to manage windows. Please grant access in System Preferences.")
        }
    }
    
    private func captureLayout() {
        guard permissionsService.hasAccessibilityPermission else {
            showingPermissionsAlert = true
            return
        }
        
        windowService.captureCurrentLayout()
    }
    
    private func saveCurrentLayout() {
        guard !newLayoutName.isEmpty else { return }
        
        let layout = Layout(name: newLayoutName, windows: windowService.currentWindows)
        layoutStorage.saveLayout(layout)
        
        newLayoutName = ""
        showingSaveDialog = false
    }
}

struct PermissionWarningView: View {
    @EnvironmentObject var permissionsService: PermissionsService
    
    var body: some View {
        VStack(spacing: 10) {
            HStack {
                Image(systemName: "exclamationmark.triangle.fill")
                    .foregroundColor(.orange)
                Text("Accessibility Permission Required")
                    .font(.headline)
            }
            
            Button("Grant Permission") {
                permissionsService.requestAccessibilityPermission()
            }
            .buttonStyle(.borderedProminent)
        }
        .padding()
        .background(Color.orange.opacity(0.1))
        .cornerRadius(10)
        .padding()
    }
}

struct SaveLayoutDialog: View {
    @Binding var layoutName: String
    let onSave: () -> Void
    @Environment(\.dismiss) var dismiss
    
    var body: some View {
        VStack(spacing: 20) {
            Text("Save Layout")
                .font(.title2)
                .bold()
            
            TextField("Layout Name", text: $layoutName)
                .textFieldStyle(.roundedBorder)
                .padding()
            
            HStack(spacing: 15) {
                Button("Cancel") {
                    dismiss()
                }
                .buttonStyle(.bordered)
                
                Button("Save") {
                    onSave()
                    dismiss()
                }
                .buttonStyle(.borderedProminent)
                .disabled(layoutName.isEmpty)
            }
        }
        .padding()
        .frame(width: 400, height: 200)
    }
}