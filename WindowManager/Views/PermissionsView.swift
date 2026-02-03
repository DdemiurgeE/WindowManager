//
//  PermissionsView.swift
//  WindowManager
//
//  Created by Pavel Palnikov on 03.02.2026.
//


import SwiftUI

struct PermissionsView: View {
    @EnvironmentObject var permissionsService: PermissionsService
    
    var body: some View {
        VStack(spacing: 20) {
            Text("Permissions")
                .font(.title)
                .bold()
            
            VStack(alignment: .leading, spacing: 15) {
                PermissionRow(
                    title: "Accessibility",
                    description: "Required to read and control window positions",
                    isGranted: permissionsService.hasAccessibilityPermission,
                    action: permissionsService.requestAccessibilityPermission
                )
                
                Divider()
                
                PermissionRow(
                    title: "Screen Recording",
                    description: "Required to capture window information",
                    isGranted: permissionsService.hasScreenRecordingPermission,
                    action: permissionsService.requestScreenRecordingPermission
                )
            }
            .padding()
            
            Button("Refresh Permissions") {
                permissionsService.checkAllPermissions()
            }
            .buttonStyle(.bordered)
            
            Spacer()
        }
        .padding()
        .frame(width: 500, height: 400)
    }
}

struct PermissionRow: View {
    let title: String
    let description: String
    let isGranted: Bool
    let action: () -> Void
    
    var body: some View {
        HStack {
            VStack(alignment: .leading, spacing: 5) {
                Text(title)
                    .font(.headline)
                Text(description)
                    .font(.caption)
                    .foregroundColor(.secondary)
            }
            
            Spacer()
            
            if isGranted {
                Image(systemName: "checkmark.circle.fill")
                    .foregroundColor(.green)
                    .font(.title2)
            } else {
                Button("Grant") {
                    action()
                }
                .buttonStyle(.borderedProminent)
            }
        }
    }
}