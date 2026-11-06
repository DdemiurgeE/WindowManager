import Foundation

@main struct SaveSelectionTests {
    static var checks = 0
    static func check(_ condition: Bool, _ label: String) {
        guard condition else { print("FAIL: \(label)"); exit(1) }
        checks += 1
        print("PASS: \(label)")
    }

    static func main() throws {
        let windows = (0..<3).map { index in
            WindowInfo(appName: "Synthetic", windowTitle: "Fixture", frame: CGRect(x: index, y: 0, width: 100, height: 100), screenIndex: 0)
        }
        let all = Set(windows.map(\.id))
        let subset: Set<UUID> = [windows[2].id, windows[0].id]
        let expected = [windows[0].id, windows[2].id]
        let host = SaveHost()
        host.currentWindows = windows
        let sheet = SheetHost()
        sheet.windows = windows
        sheet.appear()
        check(sheet.selectedWindows == all, "sheet appearance defaults to all captured windows")
        sheet.toggleWindow(windows[1], selected: false)
        check(sheet.selectedWindows == subset, "checkbox setter deselects only its window")
        sheet.toggleWindow(windows[1], selected: true)
        check(sheet.selectedWindows == all, "checkbox setter reselects its window")
        sheet.selectedWindows = subset
        sheet.onSave = { host.saveLayout(action: $0) }
        sheet.clickSave()
        check(host.layoutStorage.layouts.first?.windows.map(\.id) == expected, "new subset in captured order")
        let encoded = try JSONEncoder().encode(host.layoutStorage.layouts[0])
        check(try JSONDecoder().decode(Layout.self, from: encoded).windows.map(\.id) == expected, "selected windows survive model JSON round trip")

        let existing = Layout(id: UUID(), name: "Destination", windows: windows,
                              createdAt: Date(timeIntervalSince1970: 100), lastUsed: Date(timeIntervalSince1970: 200), screenConfiguration: nil)
        host.layoutStorage.layouts = [existing]
        host.layoutStorage.writes = 0
        sheet.existingLayouts = [existing]
        sheet.saveMode = .overwrite
        sheet.selectedLayoutID = existing.id
        sheet.clickSave()
        check(host.layoutStorage.writes == 0 && sheet.showingOverwriteConfirmation, "partial overwrite waits before mutation")
        check(sheet.overwriteMessage.contains("Destination") && sheet.overwriteMessage.contains("all 3 saved") && sheet.overwriteMessage.contains("2 of 3 captured"), "confirmation names destination and counts")
        sheet.cancelOverwrite()
        sheet.confirmOverwrite()
        check(host.layoutStorage.writes == 0, "cancel discards pending action")
        sheet.clickSave()
        sheet.confirmOverwrite()
        check(host.layoutStorage.layouts[0].windows.map(\.id) == expected, "confirmed overwrite replaces exactly, without merge")
        check(host.layoutStorage.layouts[0].id == existing.id && host.layoutStorage.layouts[0].createdAt == existing.createdAt && host.layoutStorage.layouts[0].lastUsed == existing.lastUsed, "overwrite preserves identity and dates")
        sheet.confirmOverwrite()
        check(host.layoutStorage.writes == 1, "confirmation consumed once")

        for ids: Set<UUID> in [[], [UUID()], [windows[0].id, UUID()]] {
            host.layoutStorage.writes = 0
            host.showingStorageError = false
            host.saveLayout(action: .newLayout(name: "Synthetic", selectedIDs: ids))
            check(host.layoutStorage.writes == 0 && host.showingStorageError, "new rejects empty/unknown/mixed IDs")
            host.showingStorageError = false
            host.saveLayout(action: .overwriteLayout(id: existing.id, name: existing.name, selectedIDs: ids, partialOverwriteConfirmed: true))
            check(host.layoutStorage.writes == 0 && host.showingStorageError, "overwrite rejects empty/unknown/mixed IDs")
            sheet.selectedWindows = ids
            check(!sheet.canSave, "invalid selection disables Save")
            sheet.clickSave()
            check(host.layoutStorage.writes == 0, "invalid sheet submission is no-op")
        }
        host.saveLayout(action: .overwriteLayout(id: existing.id, name: existing.name, selectedIDs: subset))
        check(host.layoutStorage.writes == 0, "unconfirmed partial action rejected")
        sheet.selectedWindows = all
        sheet.clickSave()
        check(host.layoutStorage.writes == 1 && !sheet.showingOverwriteConfirmation && host.layoutStorage.layouts[0].windows.map(\.id) == windows.map(\.id), "all-selected overwrite needs no partial confirmation")
        sheet.saveMode = .new
        sheet.clickSave()
        check(host.layoutStorage.layouts.last?.windows.map(\.id) == windows.map(\.id), "all-selected new preserves behavior")

        host.layoutStorage.writes = 0
        sheet.saveMode = .overwrite
        sheet.selectedLayoutID = UUID()
        check(!sheet.canSave, "missing destination disables Save")
        sheet.clickSave()
        check(host.layoutStorage.writes == 0, "missing destination never falls back to new")
        sheet.selectedLayoutID = nil
        sheet.clickSave()
        check(host.layoutStorage.writes == 0, "nil destination never falls back to new")
        host.saveLayout(action: .overwriteLayout(id: UUID(), name: "Missing", selectedIDs: all))
        check(host.layoutStorage.writes == 0, "save boundary rejects missing destination")

        sheet.selectedLayoutID = existing.id
        sheet.selectedWindows = subset
        sheet.clickSave()
        host.layoutStorage.layouts = []
        sheet.confirmOverwrite()
        check(host.layoutStorage.writes == 0, "destination removed during confirmation rejected")
        host.layoutStorage.layouts = [existing]
        sheet.clickSave()
        host.currentWindows = [WindowInfo(appName: "Synthetic", windowTitle: "New capture", frame: .zero, screenIndex: 0)]
        sheet.confirmOverwrite()
        check(host.layoutStorage.writes == 0, "stale capture rejected after confirmation")
        host.currentWindows = [windows[0], windows[0]]
        host.saveLayout(action: .newLayout(name: "Synthetic", selectedIDs: [windows[0].id]))
        check(host.layoutStorage.writes == 0, "duplicate capture IDs rejected")
        sheet.windows = []
        sheet.selectedWindows = []
        check(!sheet.canSave, "empty capture disables Save")
        sheet.windows = windows
        sheet.selectedWindows = all
        sheet.layoutName = ""
        check(!sheet.canSave, "empty name disables Save")
        print("SaveSelectionTests: \(checks) checks passed")
    }
}
