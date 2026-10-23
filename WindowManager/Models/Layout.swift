import Foundation

struct ScreenConfiguration: Codable, Equatable {
    struct Screen: Codable, Equatable {
        let id: String
        let frame: CGRect
        let visibleFrame: CGRect
        let scale: CGFloat?

        init(id: String, frame: CGRect, visibleFrame: CGRect, scale: CGFloat?) {
            self.id = id
            self.frame = frame
            self.visibleFrame = visibleFrame
            self.scale = scale
        }
    }

    let screenIDs: [String]
    let screenCount: Int
    let screens: [Screen]
    
    init(screenIDs: [String]) {
        self.screenIDs = screenIDs.sorted()
        self.screenCount = screenIDs.count
        self.screens = []
    }

    init(screens: [Screen]) {
        self.screens = screens.sorted { $0.id < $1.id }
        self.screenIDs = self.screens.map(\.id)
        self.screenCount = self.screens.count
    }

    /// Auto-apply may target physical displays only when every identity is
    /// unique and backed by hardware. Old `screen_` observation keys cannot
    /// distinguish monitors that macOS renumbered after reconnecting.
    var hasReliablePhysicalIdentity: Bool {
        !screenIDs.isEmpty && screenCount == screens.count &&
        Set(screenIDs).count == screenCount &&
        screenIDs.allSatisfy { $0.hasPrefix("display_") }
    }

    func matchesForAutoApply(_ current: ScreenConfiguration) -> Bool {
        hasReliablePhysicalIdentity && current.hasReliablePhysicalIdentity &&
        screenIDs == current.screenIDs
    }

    private enum CodingKeys: String, CodingKey {
        case screenIDs, screenCount, screens
    }

    init(from decoder: Decoder) throws {
        let values = try decoder.container(keyedBy: CodingKeys.self)
        let decodedIDs = try values.decodeIfPresent([String].self, forKey: .screenIDs) ?? []
        let decodedScreens = try values.decodeIfPresent([Screen].self, forKey: .screens) ?? []
        if decodedScreens.isEmpty {
            self.init(screenIDs: decodedIDs)
        } else {
            self.init(screens: decodedScreens)
        }
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
