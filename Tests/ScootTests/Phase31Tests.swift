import Foundation
import Testing

@testable import ScootCore

// MARK: - MoveLog batch tests

@Suite("MoveLog batch") @MainActor
struct MoveLogBatchTests {

    private func tempFileURL() -> URL {
        FileManager.default.temporaryDirectory
            .appendingPathComponent("ScootBatchTests-\(UUID().uuidString).jsonl")
    }

    @Test func batchRecordsInOrder() {
        let url = tempFileURL()
        defer { try? FileManager.default.removeItem(at: url) }

        let log = MoveLog(fileURL: url)
        let entries = [
            LogEntry(fileName: "a.pdf", destName: "A"),
            LogEntry(fileName: "b.pdf", destName: "B"),
            LogEntry(fileName: "c.pdf", destName: "C"),
        ]
        log.record(batch: entries)

        // Newest-first: c is index 0
        #expect(log.entries.count == 3)
        #expect(log.entries[0].fileName == "c.pdf")
        #expect(log.entries[1].fileName == "b.pdf")
        #expect(log.entries[2].fileName == "a.pdf")
    }

    @Test func batchSingleDiskWrite_roundTrip() {
        let url = tempFileURL()
        defer { try? FileManager.default.removeItem(at: url) }

        do {
            let log = MoveLog(fileURL: url)
            log.record(batch: [
                LogEntry(fileName: "x.zip", destName: "存档"),
                LogEntry(fileName: "y.zip", destName: "备份"),
            ])
        }

        // Reload — both entries should survive the round-trip
        let log2 = MoveLog(fileURL: url)
        #expect(log2.entries.count == 2)
        #expect(log2.entries[0].fileName == "y.zip")
        #expect(log2.entries[1].fileName == "x.zip")
    }

    @Test func batchTruncatesAt500() {
        let url = tempFileURL()
        defer { try? FileManager.default.removeItem(at: url) }

        let log = MoveLog(fileURL: url)
        // Write 510 entries in one batch
        let batch = (0..<510).map { i in
            LogEntry(fileName: "file\(i).txt", destName: "dst")
        }
        log.record(batch: batch)

        #expect(log.entries.count == MoveLog.maxEntries)
        // Newest (file509) should be index 0
        #expect(log.entries[0].fileName == "file509.txt")
    }
}

// MARK: - SourceWatcher.scan pure-function tests

@Suite("SourceWatcher.scan")
struct SourceWatcherScanTests {

    private func tempDir() throws -> URL {
        let dir = FileManager.default.temporaryDirectory
            .appendingPathComponent("ScootScanTests-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir
    }

    private func touch(_ name: String, in dir: URL, date: Date = Date()) throws {
        let url = dir.appendingPathComponent(name)
        try Data().write(to: url)
        // Set addedToDirectoryDate via xattr simulation — fall back to setting modificationDate
        try FileManager.default.setAttributes(
            [.modificationDate: date],
            ofItemAtPath: url.path
        )
    }

    @Test func hiddenFilesAreFiltered() throws {
        let dir = try tempDir()
        defer { try? FileManager.default.removeItem(at: dir) }

        try touch("visible.txt", in: dir)
        try touch(".hidden", in: dir)

        let result = SourceWatcher.scan(path: dir.path)
        #expect(result.count == 1)
        #expect(result[0].name == "visible.txt")
    }

    @Test func incompleteDownloadSuffixesAreFiltered() throws {
        let dir = try tempDir()
        defer { try? FileManager.default.removeItem(at: dir) }

        try touch("done.pdf", in: dir)
        try touch("partial.pdf.download", in: dir)
        try touch("chrome.crdownload", in: dir)
        try touch("aria.part", in: dir)
        try touch("aria2file.aria2", in: dir)

        let result = SourceWatcher.scan(path: dir.path)
        #expect(result.count == 1)
        #expect(result[0].name == "done.pdf")
    }

    @Test func resultsAreNewestFirst() throws {
        let dir = try tempDir()
        defer { try? FileManager.default.removeItem(at: dir) }

        let base = Date(timeIntervalSinceNow: -100)
        try touch("old.txt", in: dir, date: base)
        try touch("new.txt", in: dir, date: base.addingTimeInterval(60))

        let result = SourceWatcher.scan(path: dir.path)
        #expect(result.count == 2)
        #expect(result[0].name == "new.txt")
        #expect(result[1].name == "old.txt")
    }
}

// MARK: - CredentialsFile tests

@Suite("CredentialsFile")
struct CredentialsFileTests {

    private func tempDir() throws -> URL {
        let dir = FileManager.default.temporaryDirectory
            .appendingPathComponent("ScootCredTests-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir
    }

    @Test func roundTrip() throws {
        let dir = try tempDir()
        defer { try? FileManager.default.removeItem(at: dir) }

        let creds = CredentialsFile(storageDir: dir)
        #expect(creds.hasKey() == false)
        #expect(creds.read() == nil)

        creds.save(apiKey: "test-api-key-123")
        #expect(creds.hasKey() == true)
        #expect(creds.read() == "test-api-key-123")
    }

    @Test func permissions0600() throws {
        let dir = try tempDir()
        defer { try? FileManager.default.removeItem(at: dir) }

        let creds = CredentialsFile(storageDir: dir)
        creds.save(apiKey: "secret")

        let credFile = dir.appendingPathComponent("credentials.json")
        let attrs = try FileManager.default.attributesOfItem(atPath: credFile.path)
        let perms = attrs[.posixPermissions] as? Int
        #expect(perms == 0o600)
    }

    @Test func deleteRemovesKey() throws {
        let dir = try tempDir()
        defer { try? FileManager.default.removeItem(at: dir) }

        let creds = CredentialsFile(storageDir: dir)
        creds.save(apiKey: "key-to-delete")
        #expect(creds.hasKey() == true)

        creds.delete()
        #expect(creds.hasKey() == false)
        #expect(creds.read() == nil)
    }
}
