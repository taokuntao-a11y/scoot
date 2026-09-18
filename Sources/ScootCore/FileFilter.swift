import Foundation

/// Single-select filter backing the capsule chips row above the file list.
/// Time and type share one row: exactly one filter is active at a time.
public enum FileFilter: String, CaseIterable, Identifiable, Sendable {
    case all = "全部"
    case today = "今天"
    case images = "图片"
    case docs = "文档"
    case archives = "压缩包"
    case other = "其他"

    public var id: String { rawValue }

    private static let imageExts: Set<String> = [
        "png", "jpg", "jpeg", "gif", "heic", "heif", "webp",
        "tiff", "tif", "bmp", "svg", "dng", "raw", "ico"
    ]

    private static let docExts: Set<String> = [
        "pdf", "doc", "docx", "ppt", "pptx", "key",
        "xls", "xlsx", "csv", "numbers", "pages",
        "txt", "md", "rtf", "epub"
    ]

    private static let archiveExts: Set<String> = [
        "zip", "rar", "7z", "tar", "gz", "bz2", "xz", "tgz"
    ]

    public func matches(_ item: FileItem) -> Bool {
        let ext = item.url.pathExtension.lowercased()
        switch self {
        case .all:
            return true
        case .today:
            return Calendar.current.isDateInToday(item.addedAt)
        case .images:
            return !item.isDirectory && Self.imageExts.contains(ext)
        case .docs:
            return !item.isDirectory && Self.docExts.contains(ext)
        case .archives:
            return !item.isDirectory && Self.archiveExts.contains(ext)
        case .other:
            return item.isDirectory
                || (!Self.imageExts.contains(ext)
                    && !Self.docExts.contains(ext)
                    && !Self.archiveExts.contains(ext))
        }
    }

    public func apply(to items: [FileItem]) -> [FileItem] {
        self == .all ? items : items.filter { matches($0) }
    }
}
