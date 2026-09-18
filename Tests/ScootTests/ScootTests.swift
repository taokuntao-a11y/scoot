import Foundation
import Testing

@testable import ScootCore

// MARK: - uniqueDestinationURL unit tests

@Suite("Rename logic")
struct RenameTests {
    /// Folder for isolated test runs
    private func tempDir() throws -> URL {
        let dir = FileManager.default.temporaryDirectory
            .appendingPathComponent("ScootTests-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir
    }

    @Test func noConflict() throws {
        let dir = try tempDir()
        defer { try? FileManager.default.removeItem(at: dir) }
        let result = uniqueDestinationURL(for: "report.pdf", in: dir)
        #expect(result.lastPathComponent == "report.pdf")
    }

    @Test func conflictAdds2() throws {
        let dir = try tempDir()
        defer { try? FileManager.default.removeItem(at: dir) }
        FileManager.default.createFile(atPath: dir.appendingPathComponent("report.pdf").path, contents: nil)
        let result = uniqueDestinationURL(for: "report.pdf", in: dir)
        #expect(result.lastPathComponent == "report 2.pdf")
    }

    @Test func conflictAdds3() throws {
        let dir = try tempDir()
        defer { try? FileManager.default.removeItem(at: dir) }
        FileManager.default.createFile(atPath: dir.appendingPathComponent("report.pdf").path, contents: nil)
        FileManager.default.createFile(atPath: dir.appendingPathComponent("report 2.pdf").path, contents: nil)
        let result = uniqueDestinationURL(for: "report.pdf", in: dir)
        #expect(result.lastPathComponent == "report 3.pdf")
    }

    @Test func noExtension() throws {
        let dir = try tempDir()
        defer { try? FileManager.default.removeItem(at: dir) }
        FileManager.default.createFile(atPath: dir.appendingPathComponent("Makefile").path, contents: nil)
        let result = uniqueDestinationURL(for: "Makefile", in: dir)
        #expect(result.lastPathComponent == "Makefile 2")
    }

    @Test func directoryConflict() throws {
        let dir = try tempDir()
        defer { try? FileManager.default.removeItem(at: dir) }
        try FileManager.default.createDirectory(
            at: dir.appendingPathComponent("MyFolder"),
            withIntermediateDirectories: false
        )
        let result = uniqueDestinationURL(for: "MyFolder", in: dir)
        #expect(result.lastPathComponent == "MyFolder 2")
    }

    @Test func dotGzTreatedAsSingleExt() throws {
        // Spec: .tar.gz → treat last extension (.gz)
        let dir = try tempDir()
        defer { try? FileManager.default.removeItem(at: dir) }
        FileManager.default.createFile(
            atPath: dir.appendingPathComponent("archive.tar.gz").path, contents: nil
        )
        let result = uniqueDestinationURL(for: "archive.tar.gz", in: dir)
        #expect(result.lastPathComponent == "archive.tar 2.gz")
    }
}

// MARK: - FileFilter tests

@Suite("FileFilter")
struct FileFilterTests {
    private func item(_ name: String, isDir: Bool = false, addedAt: Date = .distantPast) -> FileItem {
        FileItem(
            url: URL(fileURLWithPath: "/tmp/\(name)", isDirectory: isDir),
            name: name,
            addedAt: addedAt,
            size: 1,
            isDirectory: isDir
        )
    }

    @Test func typeBuckets() {
        #expect(FileFilter.images.matches(item("photo.PNG")))
        #expect(FileFilter.docs.matches(item("发票.pdf")))
        #expect(FileFilter.archives.matches(item("bundle.tar.gz")))
        #expect(FileFilter.other.matches(item("setup.dmg")))
        #expect(!FileFilter.images.matches(item("发票.pdf")))
        #expect(!FileFilter.other.matches(item("photo.png")))
    }

    @Test func directoriesAreOtherOnly() {
        let folder = item("pics.png", isDir: true)
        #expect(FileFilter.other.matches(folder))
        #expect(!FileFilter.images.matches(folder))
        #expect(FileFilter.all.matches(folder))
    }

    @Test func todayMatchesOnlyToday() {
        #expect(FileFilter.today.matches(item("new.txt", addedAt: Date())))
        #expect(!FileFilter.today.matches(item("old.txt", addedAt: .distantPast)))
    }

    @Test func applyFiltersAndKeepsOrder() {
        let items = [item("a.png"), item("b.pdf"), item("c.zip"), item("d.png")]
        #expect(FileFilter.all.apply(to: items).count == 4)
        #expect(FileFilter.images.apply(to: items).map(\.name) == ["a.png", "d.png"])
    }
}

// MARK: - MoveEngine tests

@Suite("MoveEngine")
struct MoveEngineTests {
    private func tempDir() throws -> URL {
        let dir = FileManager.default.temporaryDirectory
            .appendingPathComponent("ScootEngineTests-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir
    }

    private func makeFile(name: String, in dir: URL) throws -> URL {
        let url = dir.appendingPathComponent(name)
        FileManager.default.createFile(atPath: url.path, contents: Data("hello".utf8))
        return url
    }

    @Test func normalMove() throws {
        let src = try tempDir()
        let dst = try tempDir()
        defer {
            try? FileManager.default.removeItem(at: src)
            try? FileManager.default.removeItem(at: dst)
        }

        let file = try makeFile(name: "test.txt", in: src)
        let engine = MoveEngine()
        let result = engine.move([file], to: dst)

        #expect(result.errors.isEmpty)
        #expect(result.moved.count == 1)
        #expect(FileManager.default.fileExists(atPath: dst.appendingPathComponent("test.txt").path))
        #expect(!FileManager.default.fileExists(atPath: file.path))
    }

    @Test func autoRename() throws {
        let src = try tempDir()
        let dst = try tempDir()
        defer {
            try? FileManager.default.removeItem(at: src)
            try? FileManager.default.removeItem(at: dst)
        }

        // Pre-populate destination with same name
        try makeFile(name: "file.zip", in: dst)
        let srcFile = try makeFile(name: "file.zip", in: src)

        let engine = MoveEngine()
        let result = engine.move([srcFile], to: dst)

        #expect(result.errors.isEmpty)
        let movedName = result.moved.first?.to.lastPathComponent
        #expect(movedName == "file 2.zip")
    }

    @Test func autoRenameSequential() throws {
        let src = try tempDir()
        let dst = try tempDir()
        defer {
            try? FileManager.default.removeItem(at: src)
            try? FileManager.default.removeItem(at: dst)
        }

        try makeFile(name: "file.zip", in: dst)
        try makeFile(name: "file 2.zip", in: dst)
        let srcFile = try makeFile(name: "file.zip", in: src)

        let engine = MoveEngine()
        let result = engine.move([srcFile], to: dst)

        #expect(result.errors.isEmpty)
        #expect(result.moved.first?.to.lastPathComponent == "file 3.zip")
    }

    @Test func undoRestores() throws {
        let src = try tempDir()
        let dst = try tempDir()
        defer {
            try? FileManager.default.removeItem(at: src)
            try? FileManager.default.removeItem(at: dst)
        }

        let file = try makeFile(name: "undo-me.txt", in: src)
        let engine = MoveEngine()
        let moveResult = engine.move([file], to: dst)
        #expect(moveResult.errors.isEmpty)

        let movedURL = moveResult.moved[0].to
        #expect(FileManager.default.fileExists(atPath: movedURL.path))

        let undoResult = engine.undo()
        #expect(undoResult != nil)
        #expect(undoResult?.errors.isEmpty == true)

        // File should be back in src
        #expect(FileManager.default.fileExists(atPath: file.path))
        #expect(!FileManager.default.fileExists(atPath: movedURL.path))
    }

    @Test func undoWithConflict() throws {
        let src = try tempDir()
        let dst = try tempDir()
        defer {
            try? FileManager.default.removeItem(at: src)
            try? FileManager.default.removeItem(at: dst)
        }

        let file = try makeFile(name: "clash.txt", in: src)
        let engine = MoveEngine()
        let moveResult = engine.move([file], to: dst)
        #expect(moveResult.errors.isEmpty)

        // Simulate: original src location is now occupied
        FileManager.default.createFile(atPath: file.path, contents: Data("blocker".utf8))

        let undoResult = engine.undo()
        #expect(undoResult != nil)
        #expect(undoResult?.errors.isEmpty == true)

        // Should have been renamed to avoid clash
        let returnedName = undoResult?.moved.first?.to.lastPathComponent
        #expect(returnedName == "clash 2.txt")
    }

    @Test func partialFailureDoesNotAbort() throws {
        let src = try tempDir()
        let dst = try tempDir()
        defer {
            try? FileManager.default.removeItem(at: src)
            try? FileManager.default.removeItem(at: dst)
        }

        let goodFile = try makeFile(name: "good.txt", in: src)
        // Non-existent file simulates a failure
        let badFile = src.appendingPathComponent("nonexistent.txt")

        let engine = MoveEngine()
        let result = engine.move([badFile, goodFile], to: dst)

        // good.txt should have moved
        #expect(FileManager.default.fileExists(atPath: dst.appendingPathComponent("good.txt").path))
        // One error for the bad file
        #expect(result.errors.count == 1)
        #expect(result.moved.count == 1)
    }

    @Test func trashThenUndoRestores() throws {
        let src = try tempDir()
        defer { try? FileManager.default.removeItem(at: src) }

        let file = try makeFile(name: "junk.txt", in: src)
        let engine = MoveEngine()
        let result = engine.trash([file])

        #expect(result.errors.isEmpty)
        #expect(result.moved.count == 1)
        #expect(!FileManager.default.fileExists(atPath: file.path))
        // Landed in the Trash at the reported URL
        let trashed = try #require(result.moved.first?.to)
        #expect(FileManager.default.fileExists(atPath: trashed.path))
        #expect(engine.canUndo)

        // Undo pulls it back out of the Trash to the original folder
        let undone = try #require(engine.undo())
        #expect(undone.errors.isEmpty)
        #expect(FileManager.default.fileExists(atPath: file.path))
        #expect(!FileManager.default.fileExists(atPath: trashed.path))
    }

    @Test func trashDirectoryThenUndoKeepsChildren() throws {
        let src = try tempDir()
        defer { try? FileManager.default.removeItem(at: src) }

        let folder = src.appendingPathComponent("bundle")
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        _ = try makeFile(name: "inner.txt", in: folder)

        let engine = MoveEngine()
        let result = engine.trash([folder])

        #expect(result.errors.isEmpty)
        #expect(!FileManager.default.fileExists(atPath: folder.path))

        let undone = try #require(engine.undo())
        #expect(undone.errors.isEmpty)
        #expect(FileManager.default.fileExists(atPath: folder.appendingPathComponent("inner.txt").path))
    }

    @Test func trashPartialFailureDoesNotAbort() throws {
        let src = try tempDir()
        defer { try? FileManager.default.removeItem(at: src) }

        let real = try makeFile(name: "real.txt", in: src)
        let ghost = src.appendingPathComponent("ghost.txt")

        let engine = MoveEngine()
        let result = engine.trash([ghost, real])

        #expect(result.errors.count == 1)
        #expect(result.moved.count == 1)
        #expect(!FileManager.default.fileExists(atPath: real.path))

        // Clean the real file back out of the Trash
        _ = engine.undo()
    }

    @Test func undoNilWhenEmpty() {
        let engine = MoveEngine()
        #expect(engine.undo() == nil)
        #expect(!engine.canUndo)
    }
}

// MARK: - MoveLog tests

@Suite("MoveLog") @MainActor
struct MoveLogTests {

    /// Temporary JSONL file URL for an isolated test run.
    private func tempFileURL() -> URL {
        FileManager.default.temporaryDirectory
            .appendingPathComponent("ScootLogTests-\(UUID().uuidString).jsonl")
    }

    @Test func recordsEntry() {
        let url = tempFileURL()
        defer { try? FileManager.default.removeItem(at: url) }

        let log = MoveLog(fileURL: url)
        let entry = LogEntry(fileName: "report.pdf", destName: "合同")
        log.record(entry)

        #expect(log.entries.count == 1)
        #expect(log.entries[0].fileName == "report.pdf")
        #expect(log.entries[0].destName == "合同")
        #expect(!log.entries[0].isUndo)
    }

    @Test func newestFirst() {
        let url = tempFileURL()
        defer { try? FileManager.default.removeItem(at: url) }

        let log = MoveLog(fileURL: url)
        log.record(LogEntry(fileName: "a.pdf", destName: "A"))
        log.record(LogEntry(fileName: "b.pdf", destName: "B"))

        #expect(log.entries[0].fileName == "b.pdf")
        #expect(log.entries[1].fileName == "a.pdf")
    }

    @Test func truncatesTo500() {
        let url = tempFileURL()
        defer { try? FileManager.default.removeItem(at: url) }

        let log = MoveLog(fileURL: url)
        for i in 0..<510 {
            log.record(LogEntry(fileName: "file\(i).txt", destName: "dst"))
        }

        #expect(log.entries.count == MoveLog.maxEntries)
        // Newest entry should be file509
        #expect(log.entries[0].fileName == "file509.txt")
    }

    @Test func undoDirectionFlagIsSet() {
        let url = tempFileURL()
        defer { try? FileManager.default.removeItem(at: url) }

        let log = MoveLog(fileURL: url)
        let undoEntry = LogEntry(fileName: "report.pdf", destName: "合同", isUndo: true)
        log.record(undoEntry)

        #expect(log.entries[0].isUndo == true)
    }

    @Test func jsonlPersistenceRoundTrip() {
        let url = tempFileURL()
        defer { try? FileManager.default.removeItem(at: url) }

        // Write via first instance
        do {
            let log = MoveLog(fileURL: url)
            log.record(LogEntry(fileName: "alpha.zip", destName: "存档"))
            log.record(LogEntry(fileName: "beta.zip", destName: "备份", isUndo: true))
        }

        // Read via second instance (simulates app restart)
        let log2 = MoveLog(fileURL: url)
        #expect(log2.entries.count == 2)
        // Newest is beta.zip (last recorded)
        #expect(log2.entries[0].fileName == "beta.zip")
        #expect(log2.entries[0].isUndo == true)
        #expect(log2.entries[1].fileName == "alpha.zip")
    }

    @Test func jsonlTruncationPreservesNewest() {
        let url = tempFileURL()
        defer { try? FileManager.default.removeItem(at: url) }

        // Write 505 entries
        do {
            let log = MoveLog(fileURL: url)
            for i in 0..<505 {
                log.record(LogEntry(fileName: "f\(i).txt", destName: "d"))
            }
        }

        // Reload — should load exactly maxEntries (500) and keep newest
        let log2 = MoveLog(fileURL: url)
        #expect(log2.entries.count == MoveLog.maxEntries)
        #expect(log2.entries[0].fileName == "f504.txt")
    }
}
