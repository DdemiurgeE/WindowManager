import Foundation
import Combine
final class PermissionsService: ObservableObject {
 static let shared = PermissionsService()
 @Published var hasAccessibilityPermission = true
 @Published var hasScreenRecordingPermission = true
 func checkAccessibilityPermission() -> Bool { hasAccessibilityPermission }
 func checkAllPermissions() {}
 func requestAccessibilityPermission() { fatalError("Synthetic tests forbid permission requests") }
 func requestScreenRecordingPermission() { fatalError("Synthetic tests forbid permission requests") }
}
