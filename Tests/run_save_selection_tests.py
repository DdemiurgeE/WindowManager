"""Execute extracted production save handlers with synthetic, in-memory services.
No SwiftUI lifecycle, application launch, UserDefaults or AX calls. Extraction is
structural scaffolding, not a replacement implementation of save behavior.
"""
from pathlib import Path
import subprocess

root = Path(__file__).resolve().parents[1]
source = (root / 'WindowManager/Views/ContentView.swift').read_text()

# Structural UI wiring checks only, not live accessibility/UI acceptance.
assert '.toggleStyle(.checkbox)' in source, 'FAIL: selectable window checkbox missing'
assert '.accessibilityLabel(' in source and 'window.appName' in source and 'window.windowTitle' in source
assert '.disabled(!canSave)' in source
assert 'Button("Cancel", role: .cancel) { cancelOverwrite() }' in source
assert 'Button("Replace Windows", role: .destructive) { confirmOverwrite() }' in source

def block(start, source=source):
    begin = source.index(start)
    brace = source.index('{', begin)
    depth = 1
    end = brace + 1
    while depth:
        depth += (source[end] == '{') - (source[end] == '}')
        end += 1
    return source[begin:end]

sheet_source = source[source.index('struct SaveLayoutSheet:'):]
appear = block('.onAppear', sheet_source).removeprefix('.onAppear ')
toggle = block('set: { selected in', sheet_source).replace('set: { selected in', '{', 1)
save = block('private func saveLayout(action:').replace('private func', 'func')
button = block('Button("Save Layout")')[len('Button("Save Layout") '):]
helpers = ''
if '// BEGIN SAVE SELECTION HANDLERS' in source:
    helpers = source.split('// BEGIN SAVE SELECTION HANDLERS')[1].split('// END SAVE SELECTION HANDLERS')[0].replace('private ', '')
enums = source[source.index('enum SaveMode:'):source.index('struct SaveLayoutSheet:')]
scaffold = '''
import Foundation
final class MemoryStorage {
    var layouts: [Layout] = []
    var writes = 0
    func saveLayout(_ layout: Layout) throws { layouts.append(layout); writes += 1 }
    func updateLayout(_ layout: Layout) throws {
        layouts[layouts.firstIndex(where: { $0.id == layout.id })!] = layout
        writes += 1
    }
}
final class SyntheticWindows {
    func getCurrentScreenConfiguration() -> ScreenConfiguration { .init(screenIDs: []) }
}
final class StatusBarService {
    static let shared = StatusBarService()
    func updateMenu() {}
}
final class SaveHost {
    var currentWindows: [WindowInfo] = []
    var layoutStorage = MemoryStorage()
    var windowService = SyntheticWindows()
    var showingStorageError = false
    var showingSaveSheet = true
    var layoutName = "Synthetic"
    SAVE
}
final class SheetHost {
    var windows: [WindowInfo] = []
    var existingLayouts: [Layout] = []
    var selectedWindows: Set<UUID> = []
    var layoutName = "Synthetic"
    var saveMode: SaveMode = .new
    var selectedLayoutID: UUID?
    var pendingOverwrite: SaveAction?
    var overwriteMessage = ""
    var showingOverwriteConfirmation = false
    var onSave: (SaveAction) -> Void = { _ in }
    HELPERS
    func clickSave() BUTTON
    func appear() APPEAR
    func toggleWindow(_ window: WindowInfo, selected: Bool) TOGGLE
}
'''.replace('SAVE', save).replace('HELPERS', helpers).replace('BUTTON', button).replace('APPEAR', appear).replace('TOGGLE', toggle)
build = root / '.build'
build.mkdir(exist_ok=True)
fixture = build / 'SaveSelectionExtracted.swift'
fixture.write_text(scaffold + enums)
subprocess.run(['xcrun', '--sdk', 'macosx', 'swiftc', str(root/'WindowManager/Models/Layout.swift'), str(root/'WindowManager/Models/WindowInfo.swift'), str(fixture), str(root/'Tests/SaveSelectionTests.swift'), '-o', str(build/'SaveSelectionTests')], check=True)
subprocess.run([str(build/'SaveSelectionTests')], check=True)
