import Foundation

// MARK: - LogEntry

public struct LogEntry: Codable, Identifiable, Sendable {
    public let id: UUID
    public let date: Date
    public let fileName: String
    public let destName: String
    public let batchID: UUID
    public let isUndo: Bool

    public init(
        id: UUID = UUID(),
        date: Date = Date(),
        fileName: String,
        destName: String,
        batchID: UUID = UUID(),
        isUndo: Bool = false
    ) {
        self.id = id
        self.date = date
        self.fileName = fileName
        self.destName = destName
        self.batchID = batchID
        self.isUndo = isUndo
    }
}

// MARK: - MoveLog

/// Persisted operation log. Stores entries in JSONL (one JSON object per line).
/// File format: oldest entry first. In-memory array: newest first.
/// Cap: 500 entries; excess rows are dropped from the oldest end.
@MainActor
public final class MoveLog: ObservableObject {
    @Published public private(set) var entries: [LogEntry] = []

    private let fileURL: URL
    public static let maxEntries = 500

    // MARK: Init

    public init(fileURL: URL? = nil) {
        if let url = fileURL {
            self.fileURL = url
        } else {
            let appSupport = FileManager.default.urls(
                for: .applicationSupportDirectory, in: .userDomainMask
            ).first!
            let dir = appSupport.appendingPathComponent("Scoot")
            try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
            self.fileURL = dir.appendingPathComponent("history.jsonl")
        }
        load()
    }

    // MARK: Public API

    /// Append a new entry (newest-first in memory; oldest-first on disk).
    public func record(_ entry: LogEntry) {
        record(batch: [entry])
    }

    /// Append multiple entries in a single disk write (newest-first in memory).
    /// The last element of `entries` is treated as the newest and lands at index 0.
    public func record(batch entries: [LogEntry]) {
        guard !entries.isEmpty else { return }
        // Iterate forward so each successive insert pushes older entries down;
        // the last entry ends up at index 0 (newest-first convention).
        for entry in entries {
            self.entries.insert(entry, at: 0)
        }
        appendLines(entries)
        if self.entries.count > Self.maxEntries {
            self.entries = Array(self.entries.prefix(Self.maxEntries))
            rewriteFile()
        }
    }

    // MARK: Persistence

    private static var encoder: JSONEncoder = {
        let e = JSONEncoder()
        e.dateEncodingStrategy = .iso8601
        return e
    }()

    private static var decoder: JSONDecoder = {
        let d = JSONDecoder()
        d.dateDecodingStrategy = .iso8601
        return d
    }()

    private func load() {
        guard let data = try? Data(contentsOf: fileURL) else { return }
        let text = String(decoding: data, as: UTF8.self)
        let lines = text.components(separatedBy: "\n").filter { !$0.isEmpty }
        // File stores oldest-first; reverse so newest is index 0
        var loaded: [LogEntry] = lines.reversed().compactMap { line in
            guard let d = line.data(using: .utf8) else { return nil }
            return try? Self.decoder.decode(LogEntry.self, from: d)
        }
        if loaded.count > Self.maxEntries {
            loaded = Array(loaded.prefix(Self.maxEntries))
            entries = loaded
            rewriteFile()
        } else {
            entries = loaded
        }
    }

    private func appendLine(_ entry: LogEntry) {
        appendLines([entry])
    }

    /// Appends multiple entries in a single FileHandle write (oldest-first ordering preserved).
    private func appendLines(_ newEntries: [LogEntry]) {
        let lines = newEntries.compactMap { e -> String? in
            guard let data = try? Self.encoder.encode(e),
                  let json = String(data: data, encoding: .utf8) else { return nil }
            return json
        }
        guard !lines.isEmpty else { return }
        let block = lines.joined(separator: "\n") + "\n"
        guard let blockData = block.data(using: .utf8) else { return }

        if FileManager.default.fileExists(atPath: fileURL.path) {
            guard let handle = try? FileHandle(forWritingTo: fileURL) else { return }
            handle.seekToEndOfFile()
            handle.write(blockData)
            try? handle.close()
        } else {
            try? blockData.write(to: fileURL, options: .atomic)
        }
    }

    private func rewriteFile() {
        // entries is newest-first; file wants oldest-first
        let lines = entries.reversed().compactMap { e -> String? in
            guard let data = try? Self.encoder.encode(e) else { return nil }
            return String(data: data, encoding: .utf8)
        }
        let content = lines.joined(separator: "\n") + (lines.isEmpty ? "" : "\n")
        try? content.data(using: .utf8).flatMap {
            try $0.write(to: fileURL, options: .atomic)
        }
    }
}
