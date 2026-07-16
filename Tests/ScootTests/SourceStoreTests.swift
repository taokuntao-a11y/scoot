import Foundation
import Testing

@testable import ScootCore

// MARK: - SourceStore tests

@Suite("SourceStore") @MainActor
struct SourceStoreTests {

    // Isolated temp storage directory and UserDefaults suite for each test.
    private func makeStore(
        prePopulateDefaults: ((UserDefaults) -> Void)? = nil
    ) throws -> (SourceStore, URL, UserDefaults) {
        let dir = FileManager.default.temporaryDirectory
            .appendingPathComponent("ScootSourceStoreTests-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)

        let suite = "ScootSourceStoreTests-\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suite)!
        prePopulateDefaults?(defaults)

        let store = SourceStore(storageDir: dir, defaults: defaults)
        return (store, dir, defaults)
    }

    private func cleanup(_ dir: URL) {
        try? FileManager.default.removeItem(at: dir)
    }

    // MARK: 1. First launch — Downloads is the single default source

    @Test func firstLaunchHasDownloads() throws {
        let (store, dir, _) = try makeStore()
        defer { cleanup(dir) }

        #expect(store.sources.count == 1)
        let downloadsPath = FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent("Downloads").path
        #expect(store.sources[0].path == downloadsPath)
        #expect(store.activeSource.path == downloadsPath)
    }

    // MARK: 2. add() deduplication — duplicate path activates existing item

    @Test func addDuplicateActivatesExisting() throws {
        let (store, dir, _) = try makeStore()
        defer { cleanup(dir) }

        let tmpDir = FileManager.default.temporaryDirectory
            .appendingPathComponent("SourceStoreAddDup-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: tmpDir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: tmpDir) }

        store.add(url: tmpDir)
        let countAfterFirst = store.sources.count  // should be 2

        // Add same path again
        store.add(url: tmpDir)
        #expect(store.sources.count == countAfterFirst)  // no new entry
        #expect(store.activeSource.path == tmpDir.path)
    }

    // MARK: 3. remove() — last source cannot be removed

    @Test func removeLastSourceRejected() throws {
        let (store, dir, _) = try makeStore()
        defer { cleanup(dir) }

        #expect(store.sources.count == 1)
        let only = store.sources[0]
        store.remove(only)
        #expect(store.sources.count == 1)  // unchanged
    }

    // MARK: 4. remove() active source — auto-switches to first remaining item

    @Test func removeActiveSourceSwitchesToFirst() throws {
        let (store, dir, _) = try makeStore()
        defer { cleanup(dir) }

        let tmpDir = FileManager.default.temporaryDirectory
            .appendingPathComponent("SourceStoreRemoveActive-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: tmpDir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: tmpDir) }

        store.add(url: tmpDir)
        // Active is now tmpDir (second item)
        #expect(store.activeSource.path == tmpDir.path)

        store.remove(store.activeSource)
        // Should fall back to Downloads (first item)
        #expect(store.sources.count == 1)
        let downloadsPath = FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent("Downloads").path
        #expect(store.activeSource.path == downloadsPath)
    }

    // MARK: 5. Persistence round-trip

    @Test func persistenceRoundTrip() throws {
        let dir = FileManager.default.temporaryDirectory
            .appendingPathComponent("ScootSourceStoreRoundTrip-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        defer { cleanup(dir) }

        let suite = "ScootSourceStoreRoundTrip-\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suite)!

        let tmpDir = FileManager.default.temporaryDirectory
            .appendingPathComponent("SourceStoreRT-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: tmpDir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: tmpDir) }

        // Write via first instance
        do {
            let store = SourceStore(storageDir: dir, defaults: defaults)
            store.add(url: tmpDir)
            #expect(store.sources.count == 2)
        }

        // Read via second instance
        let store2 = SourceStore(storageDir: dir, defaults: defaults)
        #expect(store2.sources.count == 2)
        #expect(store2.activeSource.path == tmpDir.path)
    }

    // MARK: 6a. Migration: legacy sourcePath == Downloads → not duplicated

    @Test func migrationLegacyEqualsDownloads() throws {
        let downloadsPath = FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent("Downloads").path

        let (store, dir, defaults) = try makeStore { d in
            d.set(downloadsPath, forKey: "sourcePath")
        }
        defer { cleanup(dir) }

        // After migration key must be gone
        #expect(defaults.string(forKey: "sourcePath") == nil)
        // Only one source (Downloads, not duplicated)
        #expect(store.sources.count == 1)
        #expect(store.activeSource.path == downloadsPath)
    }

    // MARK: 6b. Migration: legacy sourcePath != Downloads → added and activated

    @Test func migrationLegacyDifferentFromDownloads() throws {
        let tmpDir = FileManager.default.temporaryDirectory
            .appendingPathComponent("SourceStoreMigration-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: tmpDir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: tmpDir) }

        let (store, dir, defaults) = try makeStore { d in
            d.set(tmpDir.path, forKey: "sourcePath")
        }
        defer { cleanup(dir) }

        // After migration key must be gone
        #expect(defaults.string(forKey: "sourcePath") == nil)
        // Two sources: Downloads first, legacy second
        #expect(store.sources.count == 2)
        let downloadsPath = FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent("Downloads").path
        #expect(store.sources[0].path == downloadsPath)
        #expect(store.sources[1].path == tmpDir.path)
        // Legacy path is active
        #expect(store.activeSource.path == tmpDir.path)
    }
}
