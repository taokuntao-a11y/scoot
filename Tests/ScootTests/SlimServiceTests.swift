import Foundation
import Testing

@testable import ScootCore

// MARK: - SlimService.parseResult (pure JSON logic — no process spawn)

@Suite("SlimService.parseResult")
struct SlimParseResultTests {

    @Test func successJSONParsesAllFields() throws {
        let json = """
        {"format":"pdf","input_path":"/abs/in.pdf","output_path":"/abs/out.pdf",
         "input_size_mb":10.02,"output_size_mb":1.22,"reduction_pct":87.8,
         "images_processed":1,"images_skipped":0,"quality":"balanced"}
        """
        let result = try SlimService.parseResult(stdout: Data(json.utf8), exitCode: 0)

        #expect(result.inputSizeMB == 10.02)
        #expect(result.outputSizeMB == 1.22)
        #expect(result.reductionPct == 87.8)
        #expect(result.outputPath.path == "/abs/out.pdf")
        #expect(result.format == "pdf")
    }

    @Test func successJSONIgnoresExtraImageFields() throws {
        // Image results carry extra fields (output_format, output_dimensions, ...) —
        // parseResult must ignore them and only rely on the documented shape.
        let json = """
        {"format":"image","input_path":"/a.png","output_path":"/a_slim.png",
         "input_size_mb":0.04,"output_size_mb":0.013,"reduction_pct":68.6,
         "images_processed":1,"images_skipped":0,"original_dimensions":[1200,1200],
         "output_dimensions":[1200,1200],"output_format":"png",
         "format_changed":false,"quality":"balanced"}
        """
        let result = try SlimService.parseResult(stdout: Data(json.utf8), exitCode: 0)
        #expect(result.format == "image")
        #expect(result.reductionPct == 68.6)
    }

    @Test func errorJSONWithExitCode1ThrowsCompressionFailed() {
        let json = #"{"error": "Unsupported file type '.xyz'. Supported: .pdf, .png"}"#
        #expect(throws: SlimError.self) {
            try SlimService.parseResult(stdout: Data(json.utf8), exitCode: 1)
        }
        do {
            _ = try SlimService.parseResult(stdout: Data(json.utf8), exitCode: 1)
            Issue.record("expected throw")
        } catch let SlimError.compressionFailed(message) {
            #expect(message.contains("Unsupported file type"))
        } catch {
            Issue.record("wrong error type: \(error)")
        }
    }

    @Test func errorJSONWithExitCode0StillThrows() {
        // Defensive: even if exit code were somehow 0, presence of "error" key wins.
        let json = #"{"error": "something went wrong"}"#
        #expect(throws: SlimError.self) {
            try SlimService.parseResult(stdout: Data(json.utf8), exitCode: 0)
        }
    }

    @Test func nonZeroExitWithNonJSONStdoutThrows() {
        let garbage = Data("not json at all".utf8)
        #expect(throws: SlimError.self) {
            try SlimService.parseResult(stdout: garbage, exitCode: 1)
        }
    }

    @Test func nonZeroExitWithValidJSONButNoErrorKeyThrowsCompressionFailed() {
        // e.g. a crash that happens to print unrelated JSON to stdout.
        let json = #"{"unexpected": true}"#
        do {
            _ = try SlimService.parseResult(stdout: Data(json.utf8), exitCode: 1)
            Issue.record("expected throw")
        } catch let SlimError.compressionFailed(message) {
            #expect(message.contains("退出码"))
        } catch {
            Issue.record("wrong error type: \(error)")
        }
    }

    @Test func missingExpectedFieldThrowsBadOutput() {
        let json = #"{"format":"pdf","input_size_mb":1.0}"#
        do {
            _ = try SlimService.parseResult(stdout: Data(json.utf8), exitCode: 0)
            Issue.record("expected throw")
        } catch SlimError.badOutput {
            // expected
        } catch {
            Issue.record("wrong error type: \(error)")
        }
    }
}

// MARK: - canSlim / extension gating

@Suite("SlimService.canSlim")
struct SlimCanSlimTests {

    @Test func supportedExtensionsReturnTrue() {
        #expect(SlimService.canSlim(URL(fileURLWithPath: "/x/report.pdf")))
        #expect(SlimService.canSlim(URL(fileURLWithPath: "/x/photo.png")))
        #expect(SlimService.canSlim(URL(fileURLWithPath: "/x/photo.webp")))
        // Case-insensitive
        #expect(SlimService.canSlim(URL(fileURLWithPath: "/x/REPORT.PDF")))
        #expect(SlimService.canSlim(URL(fileURLWithPath: "/x/deck.PPTX")))
    }

    @Test func unsupportedExtensionsReturnFalse() {
        #expect(!SlimService.canSlim(URL(fileURLWithPath: "/x/notes.txt")))
        #expect(!SlimService.canSlim(URL(fileURLWithPath: "/x/README.md")))
    }

    @Test func matchesDocumentedSupportedList() {
        let expected: Set<String> = [
            "pdf", "pptx", "jpg", "jpeg", "jpe", "png", "webp", "tif", "tiff", "bmp", "gif"
        ]
        #expect(SlimService.slimmableExtensions == expected)
    }
}

// MARK: - Binary discovery

@Suite("SlimService.locateBinary")
struct SlimLocateBinaryTests {

    private func tempExecutable() throws -> URL {
        let dir = FileManager.default.temporaryDirectory
            .appendingPathComponent("ScootSlimBinTests-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        let bin = dir.appendingPathComponent("fake-slim")
        let script = "#!/bin/sh\necho '{}'\n"
        try script.write(to: bin, atomically: true, encoding: .utf8)
        try FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: bin.path)
        return bin
    }

    @Test func honorsEnvOverride() throws {
        let bin = try tempExecutable()
        defer { try? FileManager.default.removeItem(at: bin.deletingLastPathComponent()) }

        let found = SlimService.locateBinary(
            bundle: Bundle(for: DummyClassForBundleLookup.self),
            environment: ["SCOOT_SLIM_BIN": bin.path],
            devFallback: "/nonexistent/dev/fallback/slim"
        )
        #expect(found == bin)
    }

    @Test func fallsBackToDevPathWhenNoOverride() throws {
        let bin = try tempExecutable()
        defer { try? FileManager.default.removeItem(at: bin.deletingLastPathComponent()) }

        let found = SlimService.locateBinary(
            bundle: Bundle(for: DummyClassForBundleLookup.self),
            environment: [:],
            devFallback: bin.path
        )
        #expect(found == bin)
    }

    @Test func findsBinaryOnPATH() throws {
        // Point PATH at a temp dir containing a dummy executable named "slim",
        // with no SCOOT_SLIM_BIN override and a nonexistent dev fallback — the
        // only way this can resolve is via the PATH scan branch.
        let dir = FileManager.default.temporaryDirectory
            .appendingPathComponent("ScootSlimPathTests-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: dir) }

        let bin = dir.appendingPathComponent("slim")
        let script = "#!/bin/sh\necho '{}'\n"
        try script.write(to: bin, atomically: true, encoding: .utf8)
        try FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: bin.path)

        let found = SlimService.locateBinary(
            bundle: Bundle(for: DummyClassForBundleLookup.self),
            environment: ["PATH": "\(dir.path):/usr/bin:/bin"],
            devFallback: "/nonexistent/dev/fallback/slim"
        )
        #expect(found == bin)
    }

    @Test func envOverrideWinsOverPATH() throws {
        // SCOOT_SLIM_BIN takes priority even when a "slim" also sits on PATH.
        let dir = FileManager.default.temporaryDirectory
            .appendingPathComponent("ScootSlimPathPriorityTests-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: dir) }

        let onPathBin = dir.appendingPathComponent("slim")
        try "#!/bin/sh\necho '{}'\n".write(to: onPathBin, atomically: true, encoding: .utf8)
        try FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: onPathBin.path)

        let overrideBin = dir.appendingPathComponent("override-slim")
        try "#!/bin/sh\necho '{}'\n".write(to: overrideBin, atomically: true, encoding: .utf8)
        try FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: overrideBin.path)

        let found = SlimService.locateBinary(
            bundle: Bundle(for: DummyClassForBundleLookup.self),
            environment: ["SCOOT_SLIM_BIN": overrideBin.path, "PATH": dir.path],
            devFallback: "/nonexistent/dev/fallback/slim"
        )
        #expect(found == overrideBin)
    }

    @Test func returnsNilWhenNothingFound() {
        let found = SlimService.locateBinary(
            bundle: Bundle(for: DummyClassForBundleLookup.self),
            environment: [:],
            devFallback: "/nonexistent/dev/fallback/slim"
        )
        #expect(found == nil)
    }

    @Test func ignoresEmptyEnvOverride() throws {
        let bin = try tempExecutable()
        defer { try? FileManager.default.removeItem(at: bin.deletingLastPathComponent()) }

        let found = SlimService.locateBinary(
            bundle: Bundle(for: DummyClassForBundleLookup.self),
            environment: ["SCOOT_SLIM_BIN": ""],
            devFallback: bin.path
        )
        // Empty override should be skipped and fall through to devFallback.
        #expect(found == bin)
    }
}

/// Anchor class purely so `Bundle(for:)` gives a non-main test bundle
/// (guarantees `bundle.url(forResource:withExtension:)` misses, exercising the
/// env-override / dev-fallback branches deterministically in CI).
private final class DummyClassForBundleLookup {}

// MARK: - Integration test against the real frozen binary (skips gracefully if absent)

@Suite("SlimService integration (real binary)")
struct SlimIntegrationTests {

    static let devBinaryPath = "/Users/kun/Projects/slim/dist/slim"

    @Test func compressesARealPNG() async throws {
        guard FileManager.default.isExecutableFile(atPath: Self.devBinaryPath) else {
            // Frozen binary not present on this machine — skip, don't fail.
            return
        }

        let dir = FileManager.default.temporaryDirectory
            .appendingPathComponent("ScootSlimIntegration-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: dir) }

        let input = dir.appendingPathComponent("test.png")
        try makeTestPNG(at: input)

        let output = dir.appendingPathComponent("test_slim.png")
        let service = SlimService()

        setenv("SCOOT_SLIM_BIN", Self.devBinaryPath, 1)
        defer { unsetenv("SCOOT_SLIM_BIN") }

        let result = try await service.compress(input, to: output, quality: "balanced")

        #expect(result.reductionPct >= 0)
        #expect(FileManager.default.fileExists(atPath: output.path))
    }

    /// Writes a minimal but real, decodable PNG (a solid-color 64x64 image) using
    /// hand-built chunks — no AppKit/ImageIO dependency needed in ScootTests.
    private func makeTestPNG(at url: URL) throws {
        var data = Data()
        // PNG signature
        data.append(contentsOf: [0x89, 0x50, 0x4E, 0x47, 0x0D, 0x0A, 0x1A, 0x0A])

        func chunk(_ type: String, _ payload: Data) -> Data {
            var c = Data()
            var lengthBE = UInt32(payload.count).bigEndian
            withUnsafeBytes(of: &lengthBE) { c.append(contentsOf: $0) }
            let typeBytes = Data(type.utf8)
            c.append(typeBytes)
            c.append(payload)
            var crcInput = typeBytes
            crcInput.append(payload)
            var crc = crc32(crcInput).bigEndian
            withUnsafeBytes(of: &crc) { c.append(contentsOf: $0) }
            return c
        }

        let width: UInt32 = 64
        let height: UInt32 = 64

        var ihdr = Data()
        var w = width.bigEndian
        var h = height.bigEndian
        withUnsafeBytes(of: &w) { ihdr.append(contentsOf: $0) }
        withUnsafeBytes(of: &h) { ihdr.append(contentsOf: $0) }
        ihdr.append(contentsOf: [8, 2, 0, 0, 0]) // bit depth 8, color type 2 (RGB), no interlace
        data.append(chunk("IHDR", ihdr))

        // Raw scanlines: each row prefixed with filter byte 0, followed by width*3 RGB bytes.
        var raw = Data()
        for _ in 0..<height {
            raw.append(0) // filter: none
            for _ in 0..<width {
                raw.append(contentsOf: [120, 80, 200]) // solid purple
            }
        }
        let compressed = zlibDeflate(raw)
        data.append(chunk("IDAT", compressed))
        data.append(chunk("IEND", Data()))

        try data.write(to: url)
    }

    /// Zlib-wrap raw bytes as "stored" (uncompressed) deflate blocks — valid zlib
    /// stream, no external compression library needed.
    private func zlibDeflate(_ raw: Data) -> Data {
        var out = Data([0x78, 0x01]) // zlib header (no compression / fastest)
        let bytes = [UInt8](raw)
        var offset = 0
        let maxBlock = 65535
        while offset < bytes.count {
            let remaining = bytes.count - offset
            let blockSize = min(maxBlock, remaining)
            let isFinal: UInt8 = (offset + blockSize >= bytes.count) ? 1 : 0
            out.append(isFinal) // BFINAL=isFinal, BTYPE=00 (stored)
            let len = UInt16(blockSize)
            let nlen = ~len
            out.append(UInt8(len & 0xFF))
            out.append(UInt8((len >> 8) & 0xFF))
            out.append(UInt8(nlen & 0xFF))
            out.append(UInt8((nlen >> 8) & 0xFF))
            out.append(contentsOf: bytes[offset..<(offset + blockSize)])
            offset += blockSize
        }
        var adler = adler32(raw).bigEndian
        withUnsafeBytes(of: &adler) { out.append(contentsOf: $0) }
        return out
    }

    private func adler32(_ data: Data) -> UInt32 {
        var a: UInt32 = 1
        var b: UInt32 = 0
        let modAdler: UInt32 = 65521
        for byte in data {
            a = (a + UInt32(byte)) % modAdler
            b = (b + a) % modAdler
        }
        return (b << 16) | a
    }

    private func crc32(_ data: Data) -> UInt32 {
        var crc: UInt32 = 0xFFFFFFFF
        for byte in data {
            crc ^= UInt32(byte)
            for _ in 0..<8 {
                if crc & 1 != 0 {
                    crc = (crc >> 1) ^ 0xEDB88320
                } else {
                    crc >>= 1
                }
            }
        }
        return crc ^ 0xFFFFFFFF
    }
}
