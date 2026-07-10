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

    @Test func undoNilWhenEmpty() {
        let engine = MoveEngine()
        #expect(engine.undo() == nil)
        #expect(!engine.canUndo)
    }
}
