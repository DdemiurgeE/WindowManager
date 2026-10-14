import CoreGraphics
import Foundation

@main
struct LegacyJSONFixtureTests {
    static func main() throws {
        let fixturePath = CommandLine.arguments[1]
        let data = try Data(contentsOf: URL(fileURLWithPath: fixturePath))
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        let window = try decoder.decode(WindowInfo.self, from: data)
        precondition(window.appName == "LegacyApp")
        precondition(window.windowTitle == "Legacy document")
        precondition(window.frame == CGRect(x: 42, y: 84, width: 640, height: 480))
        precondition(window.screenIndex == 0)
        precondition(window.bundleIdentifier == nil)
        precondition(window.relativeFrame == nil)
        precondition(window.screenID == nil)
        precondition(window.savedDisplayFrame == nil)
        precondition(window.savedVisibleFrame == nil)
        precondition(window.preservePresentation == nil)
        precondition(window.savedScale == nil)
        print("LegacyJSONFixtureTest: legacy WindowInfo decoded")
    }
}
