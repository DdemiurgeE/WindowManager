import Foundation
import Combine

final class LayoutStorageService: ObservableObject {
    @Published private(set) var layouts: [Layout] = []
    @Published private(set) var storageAvailable = true

    private let store: TransactionalLayoutStore
    private var current: TransactionalLayoutStore.Snapshot?
    private var generation = 0

    struct ImportPreview {
        let layouts: [Layout]
        let generation: Int
        let snapshot: TransactionalLayoutStore.Snapshot
    }

    init(store: TransactionalLayoutStore = TransactionalLayoutStore()) {
        self.store = store
        do {
            current = try store.snapshot()
            layouts = current!.layouts
        } catch {
            storageAvailable = false // Corrupt authoritative store must not fall back.
        }
    }

    func prepareImport(_ data: Data) throws -> ImportPreview {
        guard storageAvailable, let current else { throw TransactionalLayoutStore.StoreError.unavailable }
        let incoming = try LayoutImportCodec.decode(data)
        try LayoutImportCodec.validateCollisions(incoming, against: current.layouts)
        return ImportPreview(layouts: incoming, generation: generation, snapshot: current)
    }

    func confirmImport(_ preview: ImportPreview) throws {
        guard storageAvailable, let current,
              preview.generation == generation,
              current.bytes == preview.snapshot.bytes,
              current.legacyBytes == preview.snapshot.legacyBytes else { throw TransactionalLayoutStore.StoreError.changed }
        guard !preview.layouts.isEmpty else { return }
        try LayoutImportCodec.validateCollisions(preview.layouts, against: current.layouts)
        let combined = current.layouts + preview.layouts
        let ids = current.quarantined.union(preview.layouts.map(\.id))
        try commit(combined, quarantined: ids, install: true)
    }

    func saveLayout(_ layout: Layout) throws {
        guard let current, storageAvailable else { throw TransactionalLayoutStore.StoreError.unavailable }
        try commit(current.layouts + [layout], quarantined: current.quarantined)
    }

    func deleteLayout(_ layout: Layout) throws {
        guard let current, storageAvailable else { throw TransactionalLayoutStore.StoreError.unavailable }
        try commit(current.layouts.filter { $0.id != layout.id }, quarantined: current.quarantined.subtracting([layout.id]))
    }

    func updateLayout(_ layout: Layout) throws {
        guard let current, storageAvailable, let index = current.layouts.firstIndex(where: { $0.id == layout.id }) else { throw TransactionalLayoutStore.StoreError.unavailable }
        var candidate = current.layouts
        candidate[index] = layout
        try commit(candidate, quarantined: current.quarantined)
    }

    func markLayoutAsUsed(_ layout: Layout) throws {
        var updated = layout
        updated.lastUsed = Date()
        try updateLayout(updated) // Never clears quarantine.
    }

    func eligibleForAutoApply(_ id: UUID) -> Bool {
        guard storageAvailable, let current else { return false }
        // Re-read canonical state so another cooperating process or an external
        // corrupt/unsupported store cannot make stale published layouts eligible.
        guard let latest = try? store.snapshot(), latest.bytes == current.bytes,
              latest.legacyBytes == current.legacyBytes else { return false }
        return latest.layouts.contains(where: { $0.id == id }) && !latest.quarantined.contains(id)
    }

    func exportLayouts() throws -> [Layout] {
        guard storageAvailable, let current,
              let latest = try? store.snapshot(), latest.bytes == current.bytes,
              latest.legacyBytes == current.legacyBytes else { throw TransactionalLayoutStore.StoreError.changed }
        return latest.layouts
    }

    /// Explicit recovery after an ambiguous post-rename outcome; never replay the import.
    func reconcileStorage() throws {
        let resolved = try store.reconcile()
        current = resolved
        layouts = resolved.layouts
        generation += 1
        storageAvailable = true
    }

    private func commit(_ layouts: [Layout], quarantined: Set<UUID>, install: Bool = false) throws {
        guard let current, storageAvailable else { throw TransactionalLayoutStore.StoreError.unavailable }
        do {
            let next = try store.commit(layouts, quarantined: quarantined, expected: current, install: install)
            self.current = next
            self.layouts = next.layouts
            generation += 1
        } catch {
            if case TransactionalLayoutStore.StoreError.ambiguous = error { storageAvailable = false }
            throw error
        }
    }
}
