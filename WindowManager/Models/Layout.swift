import Foundation

struct ScreenConfiguration: Codable, Equatable {
    let screenIDs: [String]
    let screenCount: Int
    
    init(screenIDs: [String]) {
        self.screenIDs = screenIDs.sorted()
        self.screenCount = screenIDs.count
    }
}

struct Layout: Codable, Identifiable {
    let id: UUID
    var name: String
    let windows: [WindowInfo]
    let createdAt: Date
    var lastUsed: Date?
    var screenConfiguration: ScreenConfiguration?
    
    init(name: String, windows: [WindowInfo], screenConfiguration: ScreenConfiguration? = nil) {
        self.id = UUID()
        self.name = name
        self.windows = windows
        self.createdAt = Date()
        self.lastUsed = nil
        self.screenConfiguration = screenConfiguration
    }
}
