import AppKit
import Foundation

// MARK: - FileIconCache

/// @MainActor icon cache keyed by file type rather than full path.
/// Key rules: directories → "folder", files without extension → "file",
/// files with extension → lowercased extension (e.g. "pdf").
/// Cache is capped at 200 entries; on overflow it is cleared and rebuilt.
@MainActor
enum FileIconCache {
    private static var cache: [String: NSImage] = [:]
    private static let maxEntries = 200

    // MARK: Lookup

    static func icon(for url: URL, isDirectory: Bool) -> NSImage {
        let key = cacheKey(for: url, isDirectory: isDirectory)
        if let cached = cache[key] { return cached }

        let image = NSWorkspace.shared.icon(forFile: url.path)
        if cache.count >= maxEntries { cache.removeAll() }
        cache[key] = image
        return image
    }

    // MARK: Private

    private static func cacheKey(for url: URL, isDirectory: Bool) -> String {
        if isDirectory { return "folder" }
        let ext = url.pathExtension
        return ext.isEmpty ? "file" : ext.lowercased()
    }
}
