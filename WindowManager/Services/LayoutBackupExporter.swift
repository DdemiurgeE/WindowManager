import Foundation
import Darwin

/// Explicit, local-only snapshot export. Never reads or writes SavedLayouts.
enum LayoutBackupExporter {
    static func encode(_ layouts: [Layout]) throws -> Data {
        return try LayoutImportCodec.export(layouts)
    }

    static func export(
        _ layouts: [Layout], to url: URL,
        writeChunk: (Int32, UnsafeRawPointer, Int) -> Int = { Darwin.write($0, $1, $2) }
    ) throws {
        // Complete encoding before creating any file or changing the destination.
        let data = try encode(layouts)
        guard url.isFileURL else { throw CocoaError(.fileWriteUnsupportedScheme) }
        let destination = url.path
        let template = url.deletingLastPathComponent().appendingPathComponent(".layout-backup-XXXXXX").path
        var name = Array(template.utf8CString)
        let fd = name.withUnsafeMutableBufferPointer { mkstemp($0.baseAddress!) }
        guard fd >= 0 else { throw posixError() }
        let temporary = String(cString: name)
        var open = true
        defer {
            if open { _ = Darwin.close(fd) }
            _ = temporary.withCString { Darwin.unlink($0) }
        }

        // mkstemp creates 0600, and fchmod enforces that invariant even if the
        // platform's defaults change. No sensitive bytes precede this check.
        guard fchmod(fd, 0o600) == 0 else { throw posixError() }
        try data.withUnsafeBytes { bytes in
            var offset = 0
            while offset < bytes.count {
                let count = writeChunk(fd, bytes.baseAddress!.advanced(by: offset), bytes.count - offset)
                if count < 0 && errno == EINTR { continue }
                guard count > 0 && count <= bytes.count - offset else {
                    throw count == 0 ? NSError(domain: NSPOSIXErrorDomain, code: Int(EIO)) : posixError()
                }
                offset += count
            }
        }
        while fsync(fd) != 0 {
            if errno != EINTR { throw posixError() }
        }
        guard Darwin.close(fd) == 0 else {
            open = false
            throw posixError()
        }
        open = false

        // Never follow or replace a symlink, directory, or other special file.
        var info = stat()
        if destination.withCString({ lstat($0, &info) }) == 0 {
            guard info.st_mode & mode_t(S_IFMT) == mode_t(S_IFREG) else {
                throw CocoaError(.fileWriteInvalidFileName)
            }
        } else if errno != ENOENT {
            throw posixError()
        }
        guard temporary.withCString({ source in destination.withCString { target in rename(source, target) } }) == 0 else {
            throw posixError()
        }
    }

    private static func posixError() -> NSError {
        NSError(domain: NSPOSIXErrorDomain, code: Int(errno))
    }
}
