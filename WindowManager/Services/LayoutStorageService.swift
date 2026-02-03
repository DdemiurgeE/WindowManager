import Foundation
import Combine

class LayoutStorageService: ObservableObject {
    @Published var layouts: [Layout] = []
    
    private let storageKey = "SavedLayouts"
    private let userDefaults = UserDefaults.standard
    
    init() {
        loadLayouts()
    }
    
    func saveLayout(_ layout: Layout) {
        layouts.append(layout)
        persistLayouts()
    }
    
    func deleteLayout(_ layout: Layout) {
        layouts.removeAll { $0.id == layout.id }
        persistLayouts()
    }
    
    func updateLayout(_ layout: Layout) {
        if let index = layouts.firstIndex(where: { $0.id == layout.id }) {
            layouts[index] = layout
            persistLayouts()
        }
    }
    
    func markLayoutAsUsed(_ layout: Layout) {
        var updatedLayout = layout
        updatedLayout.lastUsed = Date()
        updateLayout(updatedLayout)
    }
    
    private func persistLayouts() {
        do {
            let encoder = JSONEncoder()
            encoder.dateEncodingStrategy = .iso8601
            let data = try encoder.encode(layouts)
            userDefaults.set(data, forKey: storageKey)
        } catch {
            print("Failed to save layouts: \(error)")
        }
    }
    
    private func loadLayouts() {
        guard let data = userDefaults.data(forKey: storageKey) else {
            return
        }
        
        do {
            let decoder = JSONDecoder()
            decoder.dateDecodingStrategy = .iso8601
            layouts = try decoder.decode([Layout].self, from: data)
        } catch {
            print("Failed to load layouts: \(error)")
        }
    }
}
