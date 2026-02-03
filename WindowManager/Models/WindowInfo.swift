import Foundation
import CoreGraphics

struct WindowInfo: Codable, Identifiable {
    let id: UUID
    let appName: String
    let windowTitle: String
    let frame: CGRect
    let screenIndex: Int
    let timestamp: Date
    
    init(appName: String, windowTitle: String, frame: CGRect, screenIndex: Int) {
        self.id = UUID()
        self.appName = appName
        self.windowTitle = windowTitle
        self.frame = frame
        self.screenIndex = screenIndex
        self.timestamp = Date()
    }
}

// Расширение для CGRect чтобы сделать его Codable
extension CGRect: Codable {
    enum CodingKeys: String, CodingKey {
        case x, y, width, height
    }
    
    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        let x = try container.decode(CGFloat.self, forKey: .x)
        let y = try container.decode(CGFloat.self, forKey: .y)
        let width = try container.decode(CGFloat.self, forKey: .width)
        let height = try container.decode(CGFloat.self, forKey: .height)
        self.init(x: x, y: y, width: width, height: height)
    }
    
    public func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(origin.x, forKey: .x)
        try container.encode(origin.y, forKey: .y)
        try container.encode(size.width, forKey: .width)
        try container.encode(size.height, forKey: .height)
    }
}