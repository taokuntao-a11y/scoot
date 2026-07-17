import Foundation
import Testing

@testable import ScootCore

// MARK: - Mock LLMService

/// Configurable mock: returns a fixed string or throws.
struct MockLLM: LLMService {
    let response: Result<String, any Error>

    init(returning text: String) {
        self.response = .success(text)
    }

    init(throwing error: any Error) {
        self.response = .failure(error)
    }

    func complete(system: String, user: String) async throws -> String {
        switch response {
        case .success(let text): return text
        case .failure(let err): throw err
        }
    }
}

// MARK: - stripFence tests

@Suite("stripFence")
struct StripFenceTests {
    @Test func plainJSONPassesThrough() {
        let input = #"[{"a":1}]"#
        #expect(stripFence(input) == input)
    }

    @Test func stripsJsonFence() {
        let input = "```json\n[{\"a\":1}]\n```"
        #expect(stripFence(input) == #"[{"a":1}]"#)
    }

    @Test func stripsPlainFence() {
        let input = "```\n[{\"a\":1}]\n```"
        #expect(stripFence(input) == #"[{"a":1}]"#)
    }

    @Test func stripsLeadingWhitespace() {
        let input = "  \n```json\n[]\n```\n  "
        #expect(stripFence(input) == "[]")
    }
}

// MARK: - ArchiveSuggester tests

@Suite("ArchiveSuggester")
struct ArchiveSuggesterTests {

    // MARK: Prompt construction

    @Test func promptContainsAllFileNames() async throws {
        // Capture what the LLM receives via a recording mock
        actor Recorder: LLMService {
            var capturedUser: String = ""
            func complete(system: String, user: String) async throws -> String {
                capturedUser = user
                // Return minimal valid JSON so parsing doesn't crash
                return "[]"
            }
        }

        let recorder = Recorder()
        let suggester = ArchiveSuggester(llm: recorder)
        _ = try await suggester.suggest(
            fileNames: ["invoice_2024.pdf", "photo.jpg"],
            destinations: ["合同", "图片"]
        )

        let user = await recorder.capturedUser
        #expect(user.contains("invoice_2024.pdf"))
        #expect(user.contains("photo.jpg"))
        #expect(user.contains("合同"))
        #expect(user.contains("图片"))
    }

    // MARK: Normal JSON parsing

    @Test func parsesValidJSON() async throws {
        let json = #"[{"file":"a.pdf","dest":"合同"},{"file":"b.jpg","dest":null}]"#
        let llm = MockLLM(returning: json)
        let suggester = ArchiveSuggester(llm: llm)
        let results = try await suggester.suggest(
            fileNames: ["a.pdf", "b.jpg"],
            destinations: ["合同"]
        )
        #expect(results.count == 2)
        let first = results.first { $0.file == "a.pdf" }
        #expect(first?.dest == "合同")
        let second = results.first { $0.file == "b.jpg" }
        #expect(second?.dest == nil)
    }

    // MARK: Fence stripping

    @Test func parsesJSONWrappedInFence() async throws {
        let fenced = "```json\n[{\"file\":\"x.zip\",\"dest\":\"存档\"}]\n```"
        let llm = MockLLM(returning: fenced)
        let suggester = ArchiveSuggester(llm: llm)
        let results = try await suggester.suggest(
            fileNames: ["x.zip"],
            destinations: ["存档"]
        )
        #expect(results.count == 1)
        #expect(results[0].dest == "存档")
    }

    // MARK: Invalid dest filtering

    @Test func dropsDestNotInList() async throws {
        // LLM returns a dest that isn't in the provided list
        let json = #"[{"file":"a.pdf","dest":"非法目标"}]"#
        let llm = MockLLM(returning: json)
        let suggester = ArchiveSuggester(llm: llm)
        let results = try await suggester.suggest(
            fileNames: ["a.pdf"],
            destinations: ["合同", "图片"]
        )
        #expect(results.count == 1)
        #expect(results[0].dest == nil)  // filtered → nil (uncertain)
    }

    // MARK: Empty input

    @Test func emptyFileNamesReturnsEmpty() async throws {
        let llm = MockLLM(returning: "[]")
        let suggester = ArchiveSuggester(llm: llm)
        let results = try await suggester.suggest(fileNames: [], destinations: ["合同"])
        #expect(results.isEmpty)
    }

    // MARK: LLM error propagates

    @Test func propagatesLLMError() async {
        let llm = MockLLM(throwing: LLMError.httpError(statusCode: 401, body: "unauthorized"))
        let suggester = ArchiveSuggester(llm: llm)
        do {
            _ = try await suggester.suggest(fileNames: ["a.pdf"], destinations: ["合同"])
            #expect(Bool(false), "Expected throw")
        } catch let e as LLMError {
            if case .httpError(let code, _) = e {
                #expect(code == 401)
            } else {
                #expect(Bool(false), "Wrong LLMError case: \(e)")
            }
        } catch {
            #expect(Bool(false), "Wrong error type: \(error)")
        }
    }
}

// MARK: - RenameSuggester tests

@Suite("RenameSuggester")
struct RenameSuggesterTests {

    // MARK: Prompt construction

    @Test func promptContainsAllFileNames() async throws {
        actor Recorder: LLMService {
            var capturedUser: String = ""
            func complete(system: String, user: String) async throws -> String {
                capturedUser = user
                return "[]"
            }
        }

        let recorder = Recorder()
        let suggester = RenameSuggester(llm: recorder)
        _ = try await suggester.suggest(fileNames: ["IMG_0001.jpg", "doc_final_v3.docx"])

        let user = await recorder.capturedUser
        #expect(user.contains("IMG_0001.jpg"))
        #expect(user.contains("doc_final_v3.docx"))
    }

    // MARK: Normal parsing

    @Test func parsesValidJSON() async throws {
        let json = """
        [
          {"file": "IMG_0001.jpg", "new_name": "海边日落.jpg"},
          {"file": "doc_final_v3.docx", "new_name": "项目合同草稿.docx"}
        ]
        """
        let llm = MockLLM(returning: json)
        let suggester = RenameSuggester(llm: llm)
        let results = try await suggester.suggest(fileNames: ["IMG_0001.jpg", "doc_final_v3.docx"])
        #expect(results.count == 2)
        #expect(results[0].newName == "海边日落.jpg")
        #expect(results[1].newName == "项目合同草稿.docx")
    }

    // MARK: Extension enforcement

    @Test func extensionMismatchUsesOriginal() async throws {
        // LLM returned .png but original is .jpg
        let json = #"[{"file":"photo.jpg","new_name":"美丽风景.png"}]"#
        let llm = MockLLM(returning: json)
        let suggester = RenameSuggester(llm: llm)
        let results = try await suggester.suggest(fileNames: ["photo.jpg"])
        #expect(results.count == 1)
        #expect(results[0].newName == "美丽风景.jpg")
    }

    @Test func noExtensionFileKeptWithoutExt() async throws {
        // Original has no extension; new name should also have none
        let json = #"[{"file":"Makefile","new_name":"主构建文件.sh"}]"#
        let llm = MockLLM(returning: json)
        let suggester = RenameSuggester(llm: llm)
        let results = try await suggester.suggest(fileNames: ["Makefile"])
        // Original has no extension → strip any extension from new name
        #expect(results.count == 1)
        #expect(results[0].newName == "主构建文件")
    }

    // MARK: Fence stripping

    @Test func parsesJSONWrappedInFence() async throws {
        let fenced = "```json\n[{\"file\":\"a.zip\",\"new_name\":\"备份存档.zip\"}]\n```"
        let llm = MockLLM(returning: fenced)
        let suggester = RenameSuggester(llm: llm)
        let results = try await suggester.suggest(fileNames: ["a.zip"])
        #expect(results.count == 1)
        #expect(results[0].newName == "备份存档.zip")
    }

    // MARK: Illegal character filtering

    @Test func dropsNamesWithPathSeparator() async throws {
        let json = #"[{"file":"a.pdf","new_name":"a/b.pdf"}]"#
        let llm = MockLLM(returning: json)
        let suggester = RenameSuggester(llm: llm)
        let results = try await suggester.suggest(fileNames: ["a.pdf"])
        #expect(results.isEmpty)
    }

    @Test func dropsNamesWithColon() async throws {
        let json = #"[{"file":"a.pdf","new_name":"合同:草稿.pdf"}]"#
        let llm = MockLLM(returning: json)
        let suggester = RenameSuggester(llm: llm)
        let results = try await suggester.suggest(fileNames: ["a.pdf"])
        #expect(results.isEmpty)
    }

    @Test func dropsEmptyNewName() async throws {
        let json = #"[{"file":"a.pdf","new_name":""}]"#
        let llm = MockLLM(returning: json)
        let suggester = RenameSuggester(llm: llm)
        let results = try await suggester.suggest(fileNames: ["a.pdf"])
        #expect(results.isEmpty)
    }

    @Test func dropsNamesOver80Chars() async throws {
        let longName = String(repeating: "a", count: 75) + ".pdf"  // 79 chars OK
        let tooLong = String(repeating: "b", count: 77) + ".pdf"   // 81 chars dropped
        let json = """
        [
          {"file":"a.pdf","new_name":"\(longName)"},
          {"file":"b.pdf","new_name":"\(tooLong)"}
        ]
        """
        let llm = MockLLM(returning: json)
        let suggester = RenameSuggester(llm: llm)
        let results = try await suggester.suggest(fileNames: ["a.pdf", "b.pdf"])
        #expect(results.count == 1)
        #expect(results[0].newName == longName)
    }

    // MARK: Duplicate new name filtering

    @Test func dropsDuplicateNewNames() async throws {
        let json = """
        [
          {"file":"a.pdf","new_name":"报告.pdf"},
          {"file":"b.pdf","new_name":"报告.pdf"}
        ]
        """
        let llm = MockLLM(returning: json)
        let suggester = RenameSuggester(llm: llm)
        let results = try await suggester.suggest(fileNames: ["a.pdf", "b.pdf"])
        // Only the first occurrence should be kept
        #expect(results.count == 1)
        #expect(results[0].file == "a.pdf")
    }

    // MARK: Empty input

    @Test func emptyFileNamesReturnsEmpty() async throws {
        let llm = MockLLM(returning: "[]")
        let suggester = RenameSuggester(llm: llm)
        let results = try await suggester.suggest(fileNames: [])
        #expect(results.isEmpty)
    }
}

// MARK: - MoveEngine rename tests

@Suite("MoveEngine.rename")
struct MoveEngineRenameTests {

    private func tempDir() throws -> URL {
        let dir = FileManager.default.temporaryDirectory
            .appendingPathComponent("ScootRenameTests-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir
    }

    private func makeFile(name: String, in dir: URL) throws -> URL {
        let url = dir.appendingPathComponent(name)
        FileManager.default.createFile(atPath: url.path, contents: Data("content".utf8))
        return url
    }

    // MARK: Basic rename

    @Test func basicRename() throws {
        let dir = try tempDir()
        defer { try? FileManager.default.removeItem(at: dir) }

        let file = try makeFile(name: "IMG_0001.jpg", in: dir)
        let engine = MoveEngine()
        let result = engine.rename([(url: file, newName: "海边日落.jpg")])

        #expect(result.errors.isEmpty)
        #expect(result.moved.count == 1)
        #expect(result.moved[0].to.lastPathComponent == "海边日落.jpg")
        #expect(FileManager.default.fileExists(atPath: dir.appendingPathComponent("海边日落.jpg").path))
        #expect(!FileManager.default.fileExists(atPath: file.path))
    }

    // MARK: Conflict gets sequence number

    @Test func renameConflictGetsSequenceNumber() throws {
        let dir = try tempDir()
        defer { try? FileManager.default.removeItem(at: dir) }

        // Pre-populate target name
        try makeFile(name: "报告.pdf", in: dir)
        let file = try makeFile(name: "old.pdf", in: dir)

        let engine = MoveEngine()
        let result = engine.rename([(url: file, newName: "报告.pdf")])

        #expect(result.errors.isEmpty)
        #expect(result.moved[0].to.lastPathComponent == "报告 2.pdf")
    }

    // MARK: Undo restores original name

    @Test func undoRestoresOriginalName() throws {
        let dir = try tempDir()
        defer { try? FileManager.default.removeItem(at: dir) }

        let file = try makeFile(name: "original.txt", in: dir)
        let engine = MoveEngine()
        let result = engine.rename([(url: file, newName: "renamed.txt")])
        #expect(result.errors.isEmpty)
        #expect(FileManager.default.fileExists(atPath: dir.appendingPathComponent("renamed.txt").path))

        // Undo should move renamed.txt back to original.txt
        let undoResult = engine.undo()
        #expect(undoResult != nil)
        #expect(undoResult?.errors.isEmpty == true)
        #expect(FileManager.default.fileExists(atPath: file.path))
        #expect(!FileManager.default.fileExists(atPath: dir.appendingPathComponent("renamed.txt").path))
    }

    // MARK: Mixed move + rename undo order

    @Test func mixedMoveAndRenameUndoOrder() throws {
        let src = try tempDir()
        let dst = try tempDir()
        defer {
            try? FileManager.default.removeItem(at: src)
            try? FileManager.default.removeItem(at: dst)
        }

        let file1 = try makeFile(name: "move_me.txt", in: src)
        let file2 = try makeFile(name: "rename_me.txt", in: src)

        let engine = MoveEngine()

        // First: move file1 to dst
        let moveResult = engine.move([file1], to: dst)
        #expect(moveResult.errors.isEmpty)

        // Second: rename file2 in-place
        let renameResult = engine.rename([(url: file2, newName: "renamed.txt")])
        #expect(renameResult.errors.isEmpty)

        // Undo should reverse rename first (LIFO)
        let undo1 = engine.undo()
        #expect(undo1 != nil)
        #expect(FileManager.default.fileExists(atPath: file2.path))

        // Undo should reverse move second
        let undo2 = engine.undo()
        #expect(undo2 != nil)
        #expect(FileManager.default.fileExists(atPath: file1.path))

        // Nothing left to undo
        #expect(engine.undo() == nil)
    }

    // MARK: canUndo reflects rename batches

    @Test func canUndoAfterRename() throws {
        let dir = try tempDir()
        defer { try? FileManager.default.removeItem(at: dir) }

        let file = try makeFile(name: "a.txt", in: dir)
        let engine = MoveEngine()
        #expect(!engine.canUndo)

        engine.rename([(url: file, newName: "b.txt")])
        #expect(engine.canUndo)
    }
}
