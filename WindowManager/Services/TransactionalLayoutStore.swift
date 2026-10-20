import Foundation
import Darwin

/// Authoritative only when its canonical file exists. The legacy defaults blob is
/// never removed or rewritten by installation or subsequent file transactions.
final class TransactionalLayoutStore {
    struct Snapshot {
        var layouts: [Layout]
        var quarantined: Set<UUID>
        var bytes: Data?
        var legacyBytes: Data?
        var fileExists: Bool
    }
    private struct Payload: Codable {
        let version: Int
        let layouts: [Layout]
        let quarantinedImportedLayoutIDs: [UUID]
    }
    enum StoreError: Error { case invalid, changed, ambiguous, unavailable }
    enum Fault: Equatable { case none, beforeWrite, beforeRename, afterRename, afterSync, beforeReadback }

    let directory: URL
    private let defaults: UserDefaults
    private let key = "SavedLayouts"
    var fault: Fault = .none // Synthetic test injection only; production stays .none.
    private var frozen = false

    init(directory: URL? = nil, defaults: UserDefaults = .standard) {
        self.directory = directory ?? FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("obelisk.WindowManager", isDirectory: true)
        self.defaults = defaults
    }

    private var target: URL { directory.appendingPathComponent("SavedLayouts-v1.json") }
    private var lockURL: URL { directory.appendingPathComponent(".SavedLayouts.lock") }
    private var legacyBytes: Data? { defaults.data(forKey: key) }

    func snapshot() throws -> Snapshot {
        guard !frozen else { throw StoreError.ambiguous }
        let data = try readCanonical()
        if let data {
            let payload = try decode(data)
            return Snapshot(layouts: payload.layouts, quarantined: Set(payload.quarantinedImportedLayoutIDs), bytes: data, legacyBytes: nil, fileExists: true)
        }
        let legacy = legacyBytes
        guard defaults.object(forKey: key) == nil || legacy != nil,
              (legacy?.count ?? 0) <= LayoutImportCodec.maxBytes else { throw StoreError.invalid }
        let layouts: [Layout]
        if let legacy {
            let decoder = JSONDecoder(); decoder.dateDecodingStrategy = .iso8601
            guard let decoded = try? decoder.decode([Layout].self, from: legacy) else { throw StoreError.invalid }
            layouts = decoded
        } else { layouts = [] }
        return Snapshot(layouts: layouts, quarantined: [], bytes: nil, legacyBytes: legacy, fileExists: false)
    }

    func commit(_ layouts: [Layout], quarantined: Set<UUID>, expected: Snapshot, install: Bool = false) throws -> Snapshot {
        guard !frozen else { throw StoreError.ambiguous }
        let observed = try readCanonical()
        guard expected.fileExists == (observed != nil) else { throw StoreError.changed }
        if !expected.fileExists && !install { // Keep pre-import saves on the historical key.
            guard legacyBytes == expected.legacyBytes else { throw StoreError.changed }
            let encoder = JSONEncoder(); encoder.dateEncodingStrategy = .iso8601
            let data = try encoder.encode(layouts)
            defaults.set(data, forKey: key)
            return try snapshot()
        }
        guard install || expected.fileExists else { throw StoreError.invalid }
        guard Set(layouts.map(\.id)).isSuperset(of: quarantined) else { throw StoreError.invalid }
        let payload = Payload(version: 1, layouts: layouts, quarantinedImportedLayoutIDs: quarantined.sorted { $0.uuidString < $1.uuidString })
        let bytes = try LayoutImportCodec.encoder().encode(payload)
        guard bytes.count <= LayoutImportCodec.maxBytes else { throw StoreError.invalid }
        _ = try decode(bytes)
        try ensureDirectory()
        let lock = lockURL.path.withCString { Darwin.open($0, O_CREAT | O_RDWR | O_NOFOLLOW | O_CLOEXEC, 0o600) }
        guard lock >= 0 else { throw posixError() }
        defer { _ = Darwin.lockf(lock, F_ULOCK, 0); _ = Darwin.close(lock) }
        guard Darwin.lockf(lock, F_LOCK, 0) == 0 else { throw posixError() }
        let current = try readCanonical()
        guard current == expected.bytes,
              expected.fileExists == (current != nil),
              (expected.fileExists || legacyBytes == expected.legacyBytes) else { throw StoreError.changed }
        var lockInfo = stat()
        guard fstat(lock, &lockInfo) == 0, lockInfo.st_uid == getuid(),
              lockInfo.st_mode & mode_t(S_IFMT) == mode_t(S_IFREG),
              lockInfo.st_nlink == 1, lockInfo.st_mode & 0o077 == 0 else { throw StoreError.unavailable }
        let template = directory.appendingPathComponent(".SavedLayouts-XXXXXX").path
        var path = Array(template.utf8CString)
        let fd = path.withUnsafeMutableBufferPointer { mkstemp($0.baseAddress!) }
        guard fd >= 0 else { throw posixError() }
        let temporary = String(cString: path)
        var open = true
        defer {
            if open { _ = Darwin.close(fd) }
            _ = temporary.withCString { Darwin.unlink($0) }
        }
        guard fchmod(fd, 0o600) == 0 else { throw posixError() }
        if fault == .beforeWrite { throw StoreError.unavailable }
        try bytes.withUnsafeBytes { data in
            var offset = 0
            while offset < data.count {
                let count = Darwin.write(fd, data.baseAddress!.advanced(by: offset), data.count - offset)
                if count < 0 && errno == EINTR { continue }
                guard count > 0 else { throw posixError() }
                offset += count
            }
        }
        try sync(fd)
        guard Darwin.close(fd) == 0 else { open = false; throw posixError() }
        open = false
        guard try readFile(temporary) == bytes else { throw StoreError.invalid }
        if fault == .beforeRename { throw StoreError.unavailable }
        // Recheck under the stable lock (a non-cooperating writer remains outside
        // our contract; this guards against opportunistic replacement).
        guard try readCanonical() == expected.bytes else { throw StoreError.changed }
        guard temporary.withCString({ source in target.path.withCString { dest in Darwin.rename(source, dest) } }) == 0 else { throw posixError() }
        do {
            if fault == .afterRename { throw StoreError.ambiguous }
            try syncDirectory(directory)
            if fault == .afterSync || fault == .beforeReadback { throw StoreError.ambiguous }
            guard try readCanonical() == bytes else { throw StoreError.ambiguous }
        } catch {
            frozen = true
            throw StoreError.ambiguous
        }
        return Snapshot(layouts: layouts, quarantined: quarantined, bytes: bytes, legacyBytes: nil, fileExists: true)
    }

    /// Resolve a post-rename uncertainty from canonical bytes, never a compensating write.
    func reconcile() throws -> Snapshot {
        frozen = false
        do { return try snapshot() } catch { frozen = true; throw error }
    }

    private func decode(_ bytes: Data) throws -> Payload {
        guard bytes.count <= LayoutImportCodec.maxBytes else { throw StoreError.invalid }
        let decoder = LayoutImportCodec.decoder()
        guard let result = try? decoder.decode(Payload.self, from: bytes), result.version == 1,
              Set(result.quarantinedImportedLayoutIDs).count == result.quarantinedImportedLayoutIDs.count,
              Set(result.layouts.map(\.id)).isSuperset(of: result.quarantinedImportedLayoutIDs),
              (try? LayoutImportCodec.validateCollisions(result.layouts, against: [])) != nil else { throw StoreError.invalid }
        return result
    }

    private func ensureDirectory() throws {
        let parent = directory.deletingLastPathComponent()
        // FileManager resolves the user-domain Application Support location; do not
        // create arbitrary ancestors or follow a preexisting app subdirectory link.
        var info = stat()
        if directory.path.withCString({ lstat($0, &info) }) != 0 {
            guard errno == ENOENT, mkdir(directory.path, 0o700) == 0 else { throw posixError() }
            try syncDirectory(parent)
        }
        guard directory.path.withCString({ lstat($0, &info) }) == 0,
              info.st_mode & mode_t(S_IFMT) == mode_t(S_IFDIR), info.st_uid == getuid(),
              info.st_mode & 0o077 == 0 else { throw StoreError.unavailable }
    }

    private func readCanonical() throws -> Data? {
        var dir = stat()
        if directory.path.withCString({ lstat($0, &dir) }) == 0 {
            guard dir.st_mode & mode_t(S_IFMT) == mode_t(S_IFDIR), dir.st_uid == getuid(),
                  dir.st_mode & 0o077 == 0 else { throw StoreError.unavailable }
        } else if errno != ENOENT { throw posixError() }
        var info = stat()
        let result = target.path.withCString { lstat($0, &info) }
        if result != 0 {
            if errno == ENOENT {
                // An inaccessible directory must never appear as an absent file.
                return nil
            }
            throw posixError()
        }
        guard info.st_mode & mode_t(S_IFMT) == mode_t(S_IFREG), info.st_uid == getuid(),
              info.st_nlink == 1, info.st_mode & 0o077 == 0,
              info.st_size <= LayoutImportCodec.maxBytes else { throw StoreError.unavailable }
        return try readFile(target.path)
    }

    private func readFile(_ path: String) throws -> Data {
        let fd = path.withCString { Darwin.open($0, O_RDONLY | O_NOFOLLOW | O_CLOEXEC) }
        guard fd >= 0 else { throw posixError() }
        defer { _ = Darwin.close(fd) }
        var info = stat()
        guard fstat(fd, &info) == 0, info.st_mode & mode_t(S_IFMT) == mode_t(S_IFREG),
              info.st_uid == getuid(), info.st_nlink == 1, info.st_mode & 0o077 == 0,
              info.st_size <= LayoutImportCodec.maxBytes else { throw StoreError.unavailable }
        var data = Data()
        var buffer = [UInt8](repeating: 0, count: 8192)
        while true {
            let n = Darwin.read(fd, &buffer, buffer.count)
            if n < 0 && errno == EINTR { continue }
            guard n >= 0 else { throw posixError() }
            if n == 0 { break }
            guard data.count + n <= LayoutImportCodec.maxBytes else { throw StoreError.invalid }
            data.append(contentsOf: buffer.prefix(n))
        }
        return data
    }

    private func syncDirectory(_ url: URL) throws {
        let fd = url.path.withCString { Darwin.open($0, O_RDONLY | O_DIRECTORY | O_NOFOLLOW | O_CLOEXEC) }
        guard fd >= 0 else { throw posixError() }
        defer { _ = Darwin.close(fd) }
        try sync(fd)
    }

    private func sync(_ fd: Int32) throws {
        while Darwin.fsync(fd) != 0 {
            if errno != EINTR { throw posixError() }
        }
    }

    private func posixError() -> NSError { NSError(domain: NSPOSIXErrorDomain, code: Int(errno)) }
}
