import Foundation
import Darwin

@main struct LayoutImportTests {
    static func main() throws {
        let fm = FileManager.default
        let base = fm.temporaryDirectory.appendingPathComponent("stage-c-synthetic-\(UUID())")
        try fm.createDirectory(at: base, withIntermediateDirectories: true)
        defer { try? fm.removeItem(at: base) }
        let suite = "stage-c-test-\(UUID())"
        let defaults = UserDefaults(suiteName: suite)!
        defer { defaults.removePersistentDomain(forName: suite) }
        let legacyEncoder = JSONEncoder(); legacyEncoder.dateEncodingStrategy = .iso8601
        let screen = ScreenConfiguration.Screen(id: "display", frame: CGRect(x: -1920, y: 0, width: 1920, height: 1080), visibleFrame: CGRect(x: -1920, y: 24, width: 1920, height: 1056), scale: 2)
        let win = WindowInfo(appName: "Synthetic", windowTitle: "Private title", frame: CGRect(x: -900, y: 50, width: 600, height: 400), screenIndex: 0, relativeFrame: CGRect(x: 0.1, y: 0.2, width: 0.5, height: 0.4), screenID: "display", bundleIdentifier: "test.app", axRole: "AXWindow", axSubrole: "AXStandardWindow", savedDisplayFrame: screen.frame, savedVisibleFrame: screen.visibleFrame, preservePresentation: false, savedScale: 2)
        let old = Layout(name: "Original", windows: [win], screenConfiguration: ScreenConfiguration(screens: [screen]))
        let oldBytes = try legacyEncoder.encode([old])
        defaults.set(oldBytes, forKey: "SavedLayouts")
        let new = Layout(name: "Imported", windows: [WindowInfo(appName: "New", windowTitle: "Another title", frame: CGRect(x: -100, y: 0, width: 200, height: 150), screenIndex: 0)], screenConfiguration: ScreenConfiguration(screens: [screen]))
        let source = try LayoutImportCodec.export([new])
        let json = try JSONSerialization.jsonObject(with: source) as! [String: Any]
        precondition((json["schemaVersion"] as? Int) == 1 && (json["format"] as? String) == "com.windowmanager.layouts")
        let precision = Date(timeIntervalSince1970: 1_700_000_000.123)
        let fractionData = try LayoutImportCodec.encoder().encode([precision])
        let fractionDecoded = try LayoutImportCodec.decoder().decode([Date].self, from: fractionData)
        precondition(abs(fractionDecoded[0].timeIntervalSince1970 - precision.timeIntervalSince1970) < 0.001)
        let decoded = try LayoutImportCodec.decode(source)
        precondition(decoded.count == 1 && decoded[0].id == new.id && decoded[0].windows[0].id == new.windows[0].id)
        precondition(decoded[0].windows[0].frame == new.windows[0].frame)
        let legacy = try LayoutImportCodec.decode(oldBytes)
        precondition(legacy[0].id == old.id && legacy[0].windows[0].relativeFrame == win.relativeFrame)
        let serviceStore = TransactionalLayoutStore(directory: base.appendingPathComponent("private"), defaults: defaults)
        let service = LayoutStorageService(store: serviceStore)
        let preview = try service.prepareImport(source)
        precondition(!fm.fileExists(atPath: serviceStore.directory.path) && service.layouts.count == 1)
        precondition(service.eligibleForAutoApply(old.id))
        for bad in [
            Data("{\"format\":\"com.windowmanager.layouts\",\"schemaVersion\":999,\"exportedAt\":\"2024-01-01T00:00:00Z\",\"layouts\":[]}".utf8),
            Data("[{\"id\":\"x\",\"id\":\"y\"}]".utf8), Data(source.dropLast()),
            Data(repeating: 65, count: LayoutImportCodec.maxBytes + 1)
        ] {
            do { _ = try service.prepareImport(bad); preconditionFailure("Bad backup accepted") } catch {}
        }
        do { _ = try service.prepareImport(try LayoutImportCodec.export([old])); preconditionFailure("Collision accepted") } catch {}
        let duplicateNames = try LayoutImportCodec.export([new, new])
        do { _ = try service.prepareImport(duplicateNames); preconditionFailure("Duplicate accepted") } catch {}
        var invalid = json
        var entries = invalid["layouts"] as! [[String: Any]]
        var windows = entries[0]["windows"] as! [[String: Any]]
        windows[0]["frame"] = [[-100, 0], [-200, 150]]
        entries[0]["windows"] = windows
        invalid["layouts"] = entries
        let invalidGeometry = try JSONSerialization.data(withJSONObject: invalid)
        do { _ = try service.prepareImport(invalidGeometry); preconditionFailure("Negative width accepted") } catch {}
        precondition(defaults.data(forKey: "SavedLayouts") == oldBytes && service.layouts.count == 1)
        serviceStore.fault = .beforeRename
        do { try service.confirmImport(preview); preconditionFailure("Fault accepted") } catch {}
        precondition(service.layouts.count == 1 && defaults.data(forKey: "SavedLayouts") == oldBytes)
        precondition(!fm.fileExists(atPath: serviceStore.directory.appendingPathComponent("SavedLayouts-v1.json").path))
        serviceStore.fault = .none
        try service.confirmImport(preview)
        precondition(service.layouts.count == 2 && defaults.data(forKey: "SavedLayouts") == oldBytes)
        precondition(service.eligibleForAutoApply(old.id) && !service.eligibleForAutoApply(new.id))
        let target = serviceStore.directory.appendingPathComponent("SavedLayouts-v1.json")
        let stored = try Data(contentsOf: target)
        let fileMode = try fm.attributesOfItem(atPath: target.path)[.posixPermissions] as? NSNumber
        let directoryMode = try fm.attributesOfItem(atPath: serviceStore.directory.path)[.posixPermissions] as? NSNumber
        precondition(fileMode?.intValue == 0o600 && directoryMode?.intValue == 0o700)
        try service.markLayoutAsUsed(new)
        precondition(!service.eligibleForAutoApply(new.id) && defaults.data(forKey: "SavedLayouts") == oldBytes)
        do { try service.confirmImport(preview); preconditionFailure("Stale preview accepted") } catch {}
        let restarted = LayoutStorageService(store: TransactionalLayoutStore(directory: serviceStore.directory, defaults: defaults))
        precondition(restarted.layouts.count == 2 && !restarted.eligibleForAutoApply(new.id))
        let postPreview = try restarted.prepareImport(try LayoutImportCodec.export([Layout(name: "Second import", windows: [])]))
        // Post-cutover pre-rename failure leaves the precise canonical bytes unchanged.
        let postStore = TransactionalLayoutStore(directory: serviceStore.directory, defaults: defaults)
        let postService = LayoutStorageService(store: postStore)
        let postCandidate = try postService.prepareImport(try LayoutImportCodec.export([Layout(name: "Another import", windows: [])]))
        let preFailureBytes = try Data(contentsOf: target)
        postStore.fault = .beforeWrite
        do { try postService.confirmImport(postCandidate); preconditionFailure("Pre-write fault accepted") } catch {}
        precondition(postService.layouts.count == 2 && (try? Data(contentsOf: target)) == preFailureBytes)
        postStore.fault = .beforeRename
        do { try postService.confirmImport(postCandidate); preconditionFailure("Pre-rename fault accepted") } catch {}
        precondition(postService.layouts.count == 2 && (try? Data(contentsOf: target)) == preFailureBytes)
        precondition(postPreview.layouts.count == 1)
        let adversary = LayoutStorageService(store: TransactionalLayoutStore(directory: serviceStore.directory, defaults: defaults))
        try restarted.deleteLayout(old)
        do { try adversary.saveLayout(old); preconditionFailure("Stale writer accepted") } catch {}
        precondition(adversary.layouts.count == 2 && defaults.data(forKey: "SavedLayouts") == oldBytes)
        let updatedBytes = try Data(contentsOf: target)
        precondition(updatedBytes != stored)
        let ambiguousStore = TransactionalLayoutStore(directory: serviceStore.directory, defaults: defaults)
        let ambiguous = LayoutStorageService(store: ambiguousStore)
        let before = ambiguous.layouts.map(\.id)
        ambiguousStore.fault = .afterRename
        do { try ambiguous.saveLayout(Layout(name: "Uncertain", windows: [])); preconditionFailure("Ambiguous accepted") } catch {}
        precondition(!ambiguous.storageAvailable && ambiguous.layouts.map(\.id) == before && defaults.data(forKey: "SavedLayouts") == oldBytes)
        let reconciled = try ambiguousStore.reconcile()
        precondition(reconciled.layouts.count == before.count + 1)
        let afterRestart = LayoutStorageService(store: TransactionalLayoutStore(directory: serviceStore.directory, defaults: defaults))
        precondition(afterRestart.layouts.count == before.count + 1)
        for (name, content) in [
            ("corrupt", Data("{broken".utf8)),
            ("future", Data("{\"version\":99,\"layouts\":[],\"quarantinedImportedLayoutIDs\":[]}".utf8))
        ] {
            let dir = base.appendingPathComponent(name)
            try fm.createDirectory(at: dir, withIntermediateDirectories: true)
            try fm.setAttributes([.posixPermissions: 0o700], ofItemAtPath: dir.path)
            let file = dir.appendingPathComponent("SavedLayouts-v1.json")
            try content.write(to: file)
            try fm.setAttributes([.posixPermissions: 0o600], ofItemAtPath: file.path)
            let blocked = LayoutStorageService(store: TransactionalLayoutStore(directory: dir, defaults: defaults))
            precondition(!blocked.storageAvailable && blocked.layouts.isEmpty && !blocked.eligibleForAutoApply(old.id))
            do { try blocked.saveLayout(new); preconditionFailure("Corrupt store accepted mutation") } catch {}
        }
        let linkDir = base.appendingPathComponent("symlink")
        try fm.createDirectory(at: linkDir, withIntermediateDirectories: true)
        try fm.setAttributes([.posixPermissions: 0o700], ofItemAtPath: linkDir.path)
        try fm.createSymbolicLink(at: linkDir.appendingPathComponent("SavedLayouts-v1.json"), withDestinationURL: target)
        let linkStore = LayoutStorageService(store: TransactionalLayoutStore(directory: linkDir, defaults: defaults))
        precondition(!linkStore.storageAvailable && linkStore.layouts.isEmpty)
        print("LayoutImportTests: legacy/versioned, privacy, preview, pre/post rename faults, stale writer, quarantine and restart passed")
    }
}
