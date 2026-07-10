import Foundation

public struct FileItem: Identifiable, Hashable, Sendable {
    public let id: URL
    public let url: URL
    public let name: String
    public let addedAt: Date
    public let size: Int64
    public let isDirectory: Bool

    public init(url: URL, name: String, addedAt: Date, size: Int64, isDirectory: Bool) {
        self.id = url
        self.url = url
        self.name = name
        self.addedAt = addedAt
        self.size = size
        self.isDirectory = isDirectory
    }
}
