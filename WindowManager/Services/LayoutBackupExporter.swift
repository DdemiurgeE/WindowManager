import Foundation

/// Explicit, local-only snapshot export. Never reads or writes SavedLayouts.
enum LayoutBackupExporter {
    static func encode(_ layouts: [Layout]) throws -> Data {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601 // Same contract as LayoutStorageService.
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        return try encoder.encode(layouts)
    }

    static func export(_ layouts: [Layout], to url: URL) throws {
        // Encode completely before touching the destination; atomic writes stage
        // a temporary file and replace the destination only on success.
        let data = try encode(layouts)
        try data.write(to: url, options: .atomic)
    }
}
