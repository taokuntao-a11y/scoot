import Combine
import Foundation

// MARK: - SourceFolder

public struct SourceFolder: Codable, Identifiable, Sendable, Hashable {
    public let id: UUID
    public var name: String   // defaults to lastPathComponent
    public var path: String

    public init(id: UUID = UUID(), name: String, path: String) {
        self.id = id
        self.name = name
        self.path = path
    }

    public var url: URL { URL(fileURLWithPath: path, isDirectory: true) }
}

// MARK: - Persistence payload

private struct SourcePayload: Codable {
    var sources: [SourceFolder]
    var activeID: UUID
}

// MARK: - SourceStore

@MainActor
public final class SourceStore: ObservableObject {
    @Published public var sources: [SourceFolder] = []
    @Published public var activeSource: SourceFolder {
        didSet { persistActiveID() }
    }

    private let storageURL: URL
    private let defaults: UserDefaults

    // MARK: Init

    /// Production init — uses Application Support/Scoot and UserDefaults.standard.
    public convenience init() {
        let appSupport = FileManager.default.urls(
            for: .applicationSupportDirectory, in: .userDomainMask
        ).first!
        let dir = appSupport.appendingPathComponent("Scoot")
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        self.init(storageDir: dir, defaults: .standard)
    }

    /// Injectable init for tests.
    public init(storageDir: URL, defaults: UserDefaults) {
        self.defaults = defaults

        let storageURL = storageDir.appendingPathComponent("sources.json")
        self.storageURL = storageURL

        // Temporary placeholder — replaced below after migration/load.
        let downloadsPath = FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent("Downloads").path
        let placeholder = SourceFolder(name: "Downloads", path: downloadsPath)
        activeSource = placeholder

        // Load persisted state, with migration from old "sourcePath" UserDefault.
        let loaded = Self.loadOrDefault(
            from: storageURL,
            defaults: defaults,
            downloadsPath: downloadsPath
        )
        sources = loaded.sources
        // Resolve activeID → fall back to first if ID no longer in list
        if let active = loaded.sources.first(where: { $0.id == loaded.activeID }) {
            activeSource = active
        } else {
            activeSource = loaded.sources[0]
        }
    }

    // MARK: - Load / migration

    private static func loadOrDefault(
        from url: URL,
        defaults: UserDefaults,
        downloadsPath: String
    ) -> SourcePayload {
        // --- Migration: consume legacy "sourcePath" UserDefaults key ---
        let legacyKey = "sourcePath"
        let legacyPath = defaults.string(forKey: legacyKey)
        if let legacy = legacyPath {
            defaults.removeObject(forKey: legacyKey)

            // Build sources list with Downloads always present
            let downloadsFolder = SourceFolder(name: "Downloads", path: downloadsPath)
            var sources: [SourceFolder] = [downloadsFolder]
            var activeID = downloadsFolder.id

            if legacy != downloadsPath {
                // Add legacy path as second item and make it active
                let legacyName = URL(fileURLWithPath: legacy).lastPathComponent
                let legacyFolder = SourceFolder(name: legacyName, path: legacy)
                sources.append(legacyFolder)
                activeID = legacyFolder.id
            }

            let payload = SourcePayload(sources: sources, activeID: activeID)
            save(payload, to: url)
            return payload
        }

        // --- Normal load ---
        if let data = try? Data(contentsOf: url),
           let payload = try? JSONDecoder().decode(SourcePayload.self, from: data),
           !payload.sources.isEmpty {
            return payload
        }

        // --- First launch defaults ---
        let downloadsFolder = SourceFolder(name: "Downloads", path: downloadsPath)
        let payload = SourcePayload(sources: [downloadsFolder], activeID: downloadsFolder.id)
        save(payload, to: url)
        return payload
    }

    // MARK: - Mutations

    public func add(url: URL) {
        let path = url.path
        // Duplicate path → activate existing item instead
        if let existing = sources.first(where: { $0.path == path }) {
            activeSource = existing
            return
        }
        let folder = SourceFolder(name: url.lastPathComponent, path: path)
        sources.append(folder)
        activeSource = folder
        persist()
    }

    public func remove(_ folder: SourceFolder) {
        // Last source cannot be removed
        guard sources.count > 1 else { return }
        let wasActive = (folder.id == activeSource.id)
        sources.removeAll { $0.id == folder.id }
        if wasActive {
            activeSource = sources[0]
        }
        persist()
    }

    // MARK: - Persistence helpers

    private func persist() {
        let payload = SourcePayload(sources: sources, activeID: activeSource.id)
        Self.save(payload, to: storageURL)
    }

    private func persistActiveID() {
        // Re-use persist() so sources + activeID stay in sync
        persist()
    }

    @discardableResult
    private static func save(_ payload: SourcePayload, to url: URL) -> Bool {
        guard let data = try? JSONEncoder().encode(payload) else { return false }
        try? data.write(to: url, options: .atomic)
        return true
    }
}
