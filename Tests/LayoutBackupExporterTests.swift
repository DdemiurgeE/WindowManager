import Foundation
import Darwin

@main
struct LayoutBackupExporterTests {
    static func main() throws {
        let fileManager = FileManager.default
        let directory = fileManager.temporaryDirectory.appendingPathComponent("layout-export-\(UUID().uuidString)", isDirectory: true)
        try fileManager.createDirectory(at: directory, withIntermediateDirectories: true)
        // Deliberately traversable: privacy must not depend on parent permissions.
        try fileManager.setAttributes([.posixPermissions: 0o755], ofItemAtPath: directory.path)
        defer { try? fileManager.removeItem(at: directory) }
        let destination = directory.appendingPathComponent("backup.json")
        func assertPrivateBackup() throws {
            let attributes = try fileManager.attributesOfItem(atPath: destination.path)
            precondition((attributes[.posixPermissions] as? NSNumber)?.intValue == 0o600)
        }
        func assertNoTemporaryFiles() throws {
            let names = try fileManager.contentsOfDirectory(atPath: directory.path)
            precondition(names.allSatisfy { !$0.hasPrefix(".layout-backup-") })
        }

        let screen = ScreenConfiguration.Screen(
            id: "synthetic-screen", frame: CGRect(x: -800, y: 0, width: 800, height: 600),
            visibleFrame: CGRect(x: -800, y: 20, width: 800, height: 580), scale: 2)
        let window = WindowInfo(
            appName: "Synthetic App", windowTitle: "Synthetic title",
            frame: CGRect(x: -500, y: 50, width: 600, height: 400), screenIndex: 0,
            relativeFrame: CGRect(x: 0.2, y: 0.1, width: 0.6, height: 0.7),
            screenID: screen.id, bundleIdentifier: "example.synthetic", axRole: "AXWindow",
            axSubrole: "AXStandardWindow", savedDisplayFrame: screen.frame,
            savedVisibleFrame: screen.visibleFrame, preservePresentation: false, savedScale: 2)
        var layout = Layout(name: "Synthetic layout", windows: [window], screenConfiguration: ScreenConfiguration(screens: [screen]))
        layout.lastUsed = Date(timeIntervalSince1970: 1_700_000_000)
        let legacyStyle = Layout(name: "Second synthetic layout", windows: [WindowInfo(
            appName: "Legacy synthetic", windowTitle: "Older fields", frame: CGRect(x: 0, y: 0, width: 200, height: 150), screenIndex: 0)])
        let originals = [layout, legacyStyle]


        try LayoutBackupExporter.export(originals, to: destination)
        try assertPrivateBackup()
        try assertNoTemporaryFiles()
        let data = try Data(contentsOf: destination)
        let decoded = try LayoutImportCodec.decode(data)
        precondition(decoded.count == 2 && decoded[0].id == layout.id)
        precondition(decoded[0].name == layout.name && decoded[0].createdAt.timeIntervalSince1970.rounded(.down) == layout.createdAt.timeIntervalSince1970.rounded(.down))
        precondition(decoded[0].lastUsed == layout.lastUsed)
        precondition(decoded[0].windows.count == 1)
        let restored = decoded[0].windows[0]
        precondition(restored.id == window.id && restored.appName == window.appName && restored.windowTitle == window.windowTitle)
        precondition(restored.bundleIdentifier == window.bundleIdentifier && restored.axRole == window.axRole && restored.axSubrole == window.axSubrole)
        precondition(restored.frame == window.frame && restored.relativeFrame == window.relativeFrame)
        precondition(restored.screenIndex == window.screenIndex && restored.screenID == window.screenID)
        precondition(restored.savedDisplayFrame == window.savedDisplayFrame && restored.savedVisibleFrame == window.savedVisibleFrame)
        precondition(restored.savedScale == window.savedScale && restored.preservePresentation == window.preservePresentation)
        precondition(restored.timestamp.timeIntervalSince1970.rounded(.down) == window.timestamp.timeIntervalSince1970.rounded(.down))
        precondition(decoded[0].screenConfiguration == layout.screenConfiguration)
        precondition(decoded[1].id == legacyStyle.id && decoded[1].lastUsed == nil)
        precondition(decoded[1].screenConfiguration == nil && decoded[1].windows[0].screenID == nil)
        precondition(originals[0].id == layout.id && originals[0].lastUsed == layout.lastUsed)

        // An encoding error cannot truncate or replace an existing backup.
        let bad = Layout(name: "Invalid geometry", windows: [WindowInfo(
            appName: "Synthetic", windowTitle: "Invalid", frame: CGRect(x: CGFloat.infinity, y: 0, width: 100, height: 100), screenIndex: 0)])
        do {
            try LayoutBackupExporter.export([bad], to: destination)
            preconditionFailure("Non-finite geometry must fail encoding")
        } catch {
            let existing = try Data(contentsOf: destination)
            precondition(existing == data)
            try assertPrivateBackup()
            try assertNoTemporaryFiles()
        }
        // A partial write fails without exposing the temporary payload, changing
        // the old backup, or leaving private staging files behind.
        var writes = 0
        do {
            try LayoutBackupExporter.export(originals, to: destination, writeChunk: { fd, bytes, length in
                writes += 1
                let staged = try! fileManager.contentsOfDirectory(atPath: directory.path)
                    .filter { $0.hasPrefix(".layout-backup-") }
                precondition(staged.count == 1)
                let path = directory.appendingPathComponent(staged[0]).path
                let mode = try! fileManager.attributesOfItem(atPath: path)[.posixPermissions] as! NSNumber
                precondition(mode.intValue == 0o600)
                if writes == 1 { return Darwin.write(fd, bytes, min(length, 5)) }
                errno = EIO
                return -1
            })
            preconditionFailure("Simulated partial write must fail")
        } catch {
            precondition(writes == 2)
            let existing = try Data(contentsOf: destination)
            precondition(existing == data)
            try assertPrivateBackup()
            try assertNoTemporaryFiles()
        }
        // A destination error after staging also leaves the existing backup intact.
        do {
            try LayoutBackupExporter.export(originals, to: directory)
            preconditionFailure("Writing over a directory must fail")
        } catch {
            let existing = try Data(contentsOf: destination)
            precondition(existing == data)
            try assertNoTemporaryFiles()
        }
        let link = directory.appendingPathComponent("link.json")
        try fileManager.createSymbolicLink(at: link, withDestinationURL: destination)
        do {
            try LayoutBackupExporter.export([], to: link)
            preconditionFailure("Writing over a symlink must fail")
        } catch {
            let existing = try Data(contentsOf: destination)
            precondition(existing == data)
            try assertNoTemporaryFiles()
        }
        // No layouts is a valid legacy [Layout] payload.
        try LayoutBackupExporter.export([], to: destination)
        try assertPrivateBackup()
        try assertNoTemporaryFiles()
        let emptyData = try Data(contentsOf: destination)
        let emptyLayouts = try LayoutImportCodec.decode(emptyData)
        precondition(emptyLayouts.isEmpty)
        print("LayoutBackupExporterTests: versioned roundtrip, private new/replaced backup, partial/encode/destination failure safety, empty backup passed")
    }
}
