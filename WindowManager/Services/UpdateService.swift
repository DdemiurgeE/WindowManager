import AppKit
import Combine
import Sparkle

@MainActor
final class UpdateService: NSObject, ObservableObject {
    static let shared = UpdateService()

    private var updaterController: SPUStandardUpdaterController?

    private override init() {
        super.init()
    }

    func start() {
        guard updaterController == nil else { return }
        updaterController = SPUStandardUpdaterController(
            startingUpdater: true,
            updaterDelegate: nil,
            userDriverDelegate: nil
        )
    }

    func checkForUpdates() {
        updaterController?.checkForUpdates(nil)
    }
}