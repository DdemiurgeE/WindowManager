import Foundation

struct Layout: Codable, Identifiable {
    let id: UUID
    var name: String
    let windows: [WindowInfo]
    let createdAt: Date
    var lastUsed: Date?
    
    init(name: String, windows: [WindowInfo]) {
        self.id = UUID()
        self.name = name
        self.windows = windows
        self.createdAt = Date()
        self.lastUsed = nil
    }
}
