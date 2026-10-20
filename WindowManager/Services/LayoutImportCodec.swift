import Foundation
import CoreFoundation

/// Portable v1 backups and unversioned v2.7 arrays. No disk or UI side effects.
enum LayoutImportCodec {
    static let maxBytes = 16 * 1024 * 1024
    static let maxLayouts = 1000
    static let maxWindows = 10_000
    static let dateFormatter: ISO8601DateFormatter = {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        formatter.timeZone = TimeZone(secondsFromGMT: 0)
        return formatter
    }()
    private static let secondsFormatter = ISO8601DateFormatter()

    struct Backup: Encodable {
        let format = "com.windowmanager.layouts"
        let schemaVersion = 1
        let exportedAt: Date
        let layouts: [Layout]
    }

    static func encoder() -> JSONEncoder {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        encoder.dateEncodingStrategy = .custom { date, encoder in
            var value = encoder.singleValueContainer()
            try value.encode(dateFormatter.string(from: date))
        }
        return encoder
    }

    static func decoder() -> JSONDecoder {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .custom { decoder in
            let value = try decoder.singleValueContainer().decode(String.self)
            guard let date = dateFormatter.date(from: value) ?? secondsFormatter.date(from: value) else {
                throw ImportError.invalid
            }
            return date
        }
        return decoder
    }

    static func export(_ layouts: [Layout]) throws -> Data {
        try encoder().encode(Backup(exportedAt: Date(), layouts: layouts))
    }

    static func decode(_ data: Data) throws -> [Layout] {
        guard data.count <= maxBytes else { throw ImportError.invalid }
        // JSONSerialization otherwise silently accepts duplicate keys, which can make
        // a human preview disagree with a different parser's later interpretation.
        var scanner = JSONKeyScanner(data)
        try scanner.check()
        let root = try JSONSerialization.jsonObject(with: data, options: [.fragmentsAllowed])
        let raw: [Any]
        if let array = root as? [Any] {
            raw = array
        } else if let object = root as? [String: Any] {
            try keys(object, required: ["format", "schemaVersion", "exportedAt", "layouts"])
            guard object["format"] as? String == "com.windowmanager.layouts",
                  exactInteger(object["schemaVersion"]) == 1,
                  let timestamp = object["exportedAt"] as? String,
                  dateFormatter.date(from: timestamp) != nil || secondsFormatter.date(from: timestamp) != nil,
                  let array = object["layouts"] as? [Any] else { throw ImportError.invalid }
            raw = array
        } else { throw ImportError.invalid }
        guard raw.count <= maxLayouts else { throw ImportError.invalid }
        var total = 0
        for value in raw {
            guard let layout = value as? [String: Any] else { throw ImportError.invalid }
            try keys(layout, required: ["id", "name", "windows", "createdAt"], optional: ["lastUsed", "screenConfiguration"])
            try uuid(layout["id"])
            try text(layout["name"], max: 256, nonempty: true)
            try date(layout["createdAt"])
            if let last = layout["lastUsed"], !(last is NSNull) { try date(last) }
            guard let windows = layout["windows"] as? [Any], windows.count <= 1000 else { throw ImportError.invalid }
            total += windows.count
            guard total <= maxWindows else { throw ImportError.invalid }
            var screenCount: Int?
            if let config = layout["screenConfiguration"], !(config is NSNull) {
                try screenConfiguration(config)
                screenCount = exactInteger((config as? [String: Any])?["screenCount"])
            }
            for item in windows { try window(item, screenCount: screenCount) }
        }
        let layouts = try decoder().decode([Layout].self, from: dataForLayouts(raw))
        try validateCollisions(layouts, against: [])
        return layouts
    }

    static func validateCollisions(_ incoming: [Layout], against existing: [Layout]) throws {
        var ids = Set<UUID>()
        var names = Set<String>()
        var windows = Set<UUID>()
        for layout in existing + incoming {
            guard ids.insert(layout.id).inserted,
                  names.insert(layout.name.precomposedStringWithCanonicalMapping.trimmingCharacters(in: .whitespacesAndNewlines).folding(options: [.caseInsensitive, .diacriticInsensitive], locale: Locale(identifier: "en_US_POSIX"))).inserted else { throw ImportError.collision }
            for window in layout.windows {
                guard windows.insert(window.id).inserted else { throw ImportError.collision }
            }
        }
    }

    private static func dataForLayouts(_ value: [Any]) throws -> Data {
        try JSONSerialization.data(withJSONObject: value)
    }

    private static func keys(_ object: [String: Any], required: Set<String>, optional: Set<String> = []) throws {
        guard required.isSubset(of: Set(object.keys)), Set(object.keys).isSubset(of: required.union(optional)) else { throw ImportError.invalid }
    }

    private static func exactInteger(_ value: Any?) -> Int? {
        guard let number = value as? NSNumber, CFGetTypeID(number) != CFBooleanGetTypeID(),
              let parsed = Int(number.stringValue) else { return nil }
        return parsed
    }

    private static func number(_ value: Any?, positive: Bool = false) throws -> Double {
        guard let value = value as? NSNumber, CFGetTypeID(value) != CFBooleanGetTypeID() else { throw ImportError.invalid }
        let number = value.doubleValue
        guard number.isFinite, abs(number) <= 10_000_000, !positive || number > 0 else { throw ImportError.invalid }
        return number
    }

    private static func text(_ value: Any?, max: Int, nonempty: Bool = false) throws {
        guard let text = value as? String, text.utf8.count <= max,
              !nonempty || !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { throw ImportError.invalid }
    }

    private static func uuid(_ value: Any?) throws {
        guard let raw = value as? String, UUID(uuidString: raw) != nil else { throw ImportError.invalid }
    }

    private static func date(_ value: Any?) throws {
        guard let raw = value as? String,
              dateFormatter.date(from: raw) != nil || secondsFormatter.date(from: raw) != nil else { throw ImportError.invalid }
    }

    private static func rectangle(_ value: Any?, sized: Bool = false) throws {
        guard let pair = value as? [Any], pair.count == 2,
              let origin = pair[0] as? [Any], origin.count == 2,
              let size = pair[1] as? [Any], size.count == 2 else { throw ImportError.invalid }
        _ = try number(origin[0]); _ = try number(origin[1])
        let width = try number(size[0]); let height = try number(size[1])
        guard sized ? (width > 0 && height > 0) : (width >= 0 && height >= 0) else { throw ImportError.invalid }
    }

    private static func optionalText(_ object: [String: Any], _ key: String, max: Int = 512) throws {
        if let value = object[key], !(value is NSNull) { try text(value, max: max) }
    }

    private static func screenConfiguration(_ value: Any) throws {
        guard let config = value as? [String: Any] else { throw ImportError.invalid }
        try keys(config, required: ["screenCount", "screenIDs"], optional: ["screens"])
        guard let ids = config["screenIDs"] as? [Any], ids.count <= 64,
              exactInteger(config["screenCount"]) == ids.count else { throw ImportError.invalid }
        for id in ids { try text(id, max: 512) }
        if let screens = config["screens"], !(screens is NSNull) {
            guard let screens = screens as? [[String: Any]], screens.count == ids.count else { throw ImportError.invalid }
            for screen in screens {
                try keys(screen, required: ["id", "frame", "visibleFrame"], optional: ["scale"])
                try text(screen["id"], max: 512)
                try rectangle(screen["frame"], sized: true)
                try rectangle(screen["visibleFrame"], sized: true)
                if let scale = screen["scale"], !(scale is NSNull) { _ = try number(scale, positive: true) }
            }
            guard screens.enumerated().allSatisfy({ (index, screen) in (screen["id"] as? String) == (ids[index] as? String) }) else { throw ImportError.invalid }
        }
    }

    private static func window(_ value: Any, screenCount: Int?) throws {
        guard let window = value as? [String: Any] else { throw ImportError.invalid }
        try keys(window, required: ["id", "appName", "windowTitle", "frame", "screenIndex", "timestamp"], optional: ["bundleIdentifier", "axRole", "axSubrole", "relativeFrame", "screenID", "savedDisplayFrame", "savedVisibleFrame", "preservePresentation", "savedScale"])
        try uuid(window["id"]); try text(window["appName"], max: 512)
        try text(window["windowTitle"], max: 4096)
        try date(window["timestamp"])
        try rectangle(window["frame"])
        guard let index = exactInteger(window["screenIndex"]), index >= 0,
              index < (screenCount ?? 64) else { throw ImportError.invalid }
        for key in ["bundleIdentifier", "axRole", "axSubrole", "screenID"] { try optionalText(window, key) }
        for key in ["relativeFrame", "savedDisplayFrame", "savedVisibleFrame"] {
            if let frame = window[key], !(frame is NSNull) {
                try rectangle(frame, sized: key != "relativeFrame")
                if key == "relativeFrame", let pair = frame as? [[NSNumber]], pair.count == 2,
                   (pair[1][0].doubleValue > 10 || pair[1][1].doubleValue > 10) { throw ImportError.invalid }
            }
        }
        if let scale = window["savedScale"], !(scale is NSNull) { _ = try number(scale, positive: true) }
        if let presentation = window["preservePresentation"], !(presentation is NSNull) {
            guard let bool = presentation as? NSNumber, CFGetTypeID(bool) == CFBooleanGetTypeID() else { throw ImportError.invalid }
        }
    }

    enum ImportError: Error { case invalid, collision }
}

/// Strict JSON structural scan before Foundation decoding (including escaped duplicate keys).
private struct JSONKeyScanner {
    let bytes: [UInt8]
    var offset = 0
    init(_ data: Data) { bytes = Array(data) }
    mutating func check() throws {
        try value(depth: 0)
        space()
        guard offset == bytes.count else { throw LayoutImportCodec.ImportError.invalid }
    }
    private mutating func space() {
        while offset < bytes.count && [UInt8(32), 9, 10, 13].contains(bytes[offset]) { offset += 1 }
    }
    private mutating func eat(_ character: UInt8) throws {
        space()
        guard offset < bytes.count, bytes[offset] == character else { throw LayoutImportCodec.ImportError.invalid }
        offset += 1
    }
    private mutating func string() throws -> String {
        try eat(34)
        let start = offset - 1
        var escape = false
        while offset < bytes.count {
            let c = bytes[offset]; offset += 1
            if !escape && c == 34 {
                let data = Data(bytes[start..<offset])
                guard let decoded = try? JSONSerialization.jsonObject(with: data, options: [.fragmentsAllowed]) as? String else { throw LayoutImportCodec.ImportError.invalid }
                return decoded
            }
            if !escape && c == 92 { escape = true } else { escape = false }
        }
        throw LayoutImportCodec.ImportError.invalid
    }
    private mutating func value(depth: Int) throws {
        space()
        guard depth <= 64, offset < bytes.count else { throw LayoutImportCodec.ImportError.invalid }
        let c = bytes[offset]
        if c == 34 { _ = try string(); return }
        if c == 123 {
            offset += 1; space()
            if offset < bytes.count && bytes[offset] == 125 { offset += 1; return }
            var keys = Set<String>()
            while true {
                let key = try string()
                guard keys.insert(key).inserted else { throw LayoutImportCodec.ImportError.invalid }
                try eat(58); try value(depth: depth + 1)
                space()
                if offset < bytes.count && bytes[offset] == 125 { offset += 1; return }
                try eat(44)
            }
        }
        if c == 91 {
            offset += 1; space()
            if offset < bytes.count && bytes[offset] == 93 { offset += 1; return }
            while true {
                try value(depth: depth + 1); space()
                if offset < bytes.count && bytes[offset] == 93 { offset += 1; return }
                try eat(44)
            }
        }
        let start = offset
        while offset < bytes.count && ![UInt8(32), 9, 10, 13, 44, 93, 125].contains(bytes[offset]) { offset += 1 }
        guard offset > start,
              (try? JSONSerialization.jsonObject(with: Data(bytes[start..<offset]), options: [.fragmentsAllowed])) != nil else { throw LayoutImportCodec.ImportError.invalid }
    }
}
