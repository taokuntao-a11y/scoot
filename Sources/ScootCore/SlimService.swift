import Foundation

// MARK: - SlimError

public enum SlimError: Error, LocalizedError, Sendable {
    /// The `slim` binary could not be located (bundle Resources, env override, dev fallback).
    case binaryNotFound(String)
    /// File extension is not one `slim` supports.
    case unsupportedType(String)
    /// `slim` ran and reported a handled error (its `{"error": "..."}` JSON shape).
    case compressionFailed(String)
    /// `Process` failed to launch or was interrupted at the OS level.
    case launchFailed(any Error)
    /// stdout did not parse as the expected JSON shape.
    case badOutput(String)
}

extension SlimError: CustomStringConvertible {
    public var description: String { errorDescription ?? "未知错误" }
}

extension SlimError {
    public var errorDescription: String? {
        switch self {
        case .binaryNotFound(let detail):
            return "找不到压缩工具 (slim): \(detail)"
        case .unsupportedType(let ext):
            return "不支持的文件类型: \(ext)"
        case .compressionFailed(let message):
            return "压缩失败: \(message)"
        case .launchFailed(let err):
            return "无法启动压缩进程: \(err.localizedDescription)"
        case .badOutput(let detail):
            return "压缩工具输出异常: \(detail)"
        }
    }
}

// MARK: - SlimResult

public struct SlimResult: Sendable {
    public let inputSizeMB: Double
    public let outputSizeMB: Double
    public let reductionPct: Double
    public let outputPath: URL
    public let format: String

    public init(inputSizeMB: Double, outputSizeMB: Double, reductionPct: Double, outputPath: URL, format: String) {
        self.inputSizeMB = inputSizeMB
        self.outputSizeMB = outputSizeMB
        self.reductionPct = reductionPct
        self.outputPath = outputPath
        self.format = format
    }
}

// MARK: - SlimService

/// Out-of-process bridge to the frozen `slim` CLI (PDF/PPTX/image compressor).
/// Mirrors LLMService's style: typed errors with Chinese descriptions, async API,
/// cancellation normalized to `CancellationError`.
public struct SlimService: Sendable {

    public init() {}

    // MARK: Supported extensions

    /// Lowercased, no leading dot — matches slim's `--json` "Supported:" list exactly.
    public static let slimmableExtensions: Set<String> = [
        "pdf", "pptx", "jpg", "jpeg", "jpe", "png", "webp", "tif", "tiff", "bmp", "gif"
    ]

    public static func canSlim(_ url: URL) -> Bool {
        slimmableExtensions.contains(url.pathExtension.lowercased())
    }

    // MARK: Binary discovery

    /// Search order: (1) app bundle Resources/slim, (2) SCOOT_SLIM_BIN env override,
    /// (3) `slim` found on PATH (so a Mac that installed slim via its own install.sh
    /// — e.g. pipx — works even without a bundle-embedded copy), (4) dev fallback at
    /// the slim repo's frozen build output.
    /// Exposed with an injectable candidate list so tests don't depend on a real app bundle.
    public static func locateBinary(
        bundle: Bundle = .main,
        environment: [String: String] = ProcessInfo.processInfo.environment,
        devFallback: String = "/Users/kun/Projects/slim/dist/slim"
    ) -> URL? {
        if let bundled = bundle.url(forResource: "slim", withExtension: nil),
           FileManager.default.isExecutableFile(atPath: bundled.path) {
            return bundled
        }
        if let override = environment["SCOOT_SLIM_BIN"], !override.isEmpty {
            let url = URL(fileURLWithPath: override)
            if FileManager.default.isExecutableFile(atPath: url.path) {
                return url
            }
        }
        if let onPath = locateOnPath(named: "slim", environment: environment) {
            return onPath
        }
        let fallback = URL(fileURLWithPath: devFallback)
        if FileManager.default.isExecutableFile(atPath: fallback.path) {
            return fallback
        }
        return nil
    }

    /// Scans `PATH` entries for an executable file named `name`. Deliberately does
    /// NOT shell out to `which` — enumerating `PATH` directly keeps this synchronous,
    /// dependency-free, and deterministic for tests.
    private static func locateOnPath(named name: String, environment: [String: String]) -> URL? {
        guard let pathVar = environment["PATH"], !pathVar.isEmpty else { return nil }
        for dir in pathVar.split(separator: ":") {
            guard !dir.isEmpty else { continue }
            let candidate = URL(fileURLWithPath: String(dir)).appendingPathComponent(name)
            if FileManager.default.isExecutableFile(atPath: candidate.path) {
                return candidate
            }
        }
        return nil
    }

    // MARK: Pure JSON parsing (directly unit-testable, no process spawn)

    /// Decodes slim's single-JSON-object `--json` stdout. All slim JSON logic lives here.
    public static func parseResult(stdout: Data, exitCode: Int32) throws -> SlimResult {
        guard let json = try? JSONSerialization.jsonObject(with: stdout) as? [String: Any] else {
            let raw = String(data: stdout, encoding: .utf8) ?? "<binary>"
            throw SlimError.badOutput("非 JSON 输出: \(raw.prefix(200))")
        }

        // slim reports handled errors as {"error": "..."} with exit code 1.
        if let errorMessage = json["error"] as? String {
            throw SlimError.compressionFailed(errorMessage)
        }
        guard exitCode == 0 else {
            let raw = String(data: stdout, encoding: .utf8) ?? "<binary>"
            throw SlimError.compressionFailed("退出码 \(exitCode): \(raw.prefix(200))")
        }

        guard let inputSizeMB = json["input_size_mb"] as? Double else {
            throw SlimError.badOutput("缺少 input_size_mb 字段")
        }
        guard let outputSizeMB = json["output_size_mb"] as? Double else {
            throw SlimError.badOutput("缺少 output_size_mb 字段")
        }
        guard let reductionPct = json["reduction_pct"] as? Double else {
            throw SlimError.badOutput("缺少 reduction_pct 字段")
        }
        guard let outputPathStr = json["output_path"] as? String else {
            throw SlimError.badOutput("缺少 output_path 字段")
        }
        guard let format = json["format"] as? String else {
            throw SlimError.badOutput("缺少 format 字段")
        }

        return SlimResult(
            inputSizeMB: inputSizeMB,
            outputSizeMB: outputSizeMB,
            reductionPct: reductionPct,
            outputPath: URL(fileURLWithPath: outputPathStr),
            format: format
        )
    }

    // MARK: Compress

    /// Spawns the located `slim` binary as a subprocess and parses its `--json` stdout.
    /// Runs off the main thread; honors Task cancellation by terminating the process.
    public func compress(_ input: URL, to output: URL, quality: String) async throws -> SlimResult {
        guard SlimService.canSlim(input) else {
            throw SlimError.unsupportedType(input.pathExtension)
        }
        guard let binary = SlimService.locateBinary() else {
            throw SlimError.binaryNotFound("未找到 slim 可执行文件")
        }

        let stdout = try await Self.runProcess(
            binary: binary,
            arguments: [input.path, "-o", output.path, "-q", quality, "--json"]
        )

        // If we were cancelled, the subprocess was terminated mid-flight and its
        // exit status / stdout are meaningless — surface cancellation, not a parse error.
        try Task.checkCancellation()

        return try SlimService.parseResult(stdout: stdout.data, exitCode: stdout.exitCode)
    }

    /// Runs `binary` with `arguments`, capturing stdout. Not actor-isolated: the Process
    /// and its termination handler must be free to run on a background thread under
    /// Swift 6 strict concurrency (a MainActor-inferred closure dispatched off-main
    /// previously crashed this app with SIGTRAP — see SourceWatcher.swift).
    private static func runProcess(
        binary: URL,
        arguments: [String]
    ) async throws -> (data: Data, exitCode: Int32) {
        // Scoped to this call (not shared/global) so concurrent compress() calls
        // each cancel only their own subprocess.
        let processBox = ProcessBox()

        return try await withTaskCancellationHandler {
            try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<(Data, Int32), any Error>) in
                let process = Process()
                process.executableURL = binary
                process.arguments = arguments

                let outPipe = Pipe()
                process.standardOutput = outPipe
                // Discard slim's stderr progress. Use nullDevice, NOT an unread Pipe:
                // an undrained stderr pipe would deadlock the child if it ever wrote
                // more than the ~64KB pipe buffer.
                process.standardError = FileHandle.nullDevice

                // Read stdout incrementally to avoid deadlock on large output filling the pipe buffer.
                let outHandle = outPipe.fileHandleForReading
                let bufferBox = LockedBox(Data())

                outHandle.readabilityHandler = { handle in
                    let chunk = handle.availableData
                    if chunk.isEmpty {
                        handle.readabilityHandler = nil
                    } else {
                        bufferBox.append(chunk)
                    }
                }

                process.terminationHandler = { proc in
                    // Drain any remaining bytes synchronously once the process has exited.
                    let trailing = outHandle.readDataToEndOfFile()
                    if !trailing.isEmpty { bufferBox.append(trailing) }
                    outHandle.readabilityHandler = nil
                    continuation.resume(returning: (bufferBox.value, proc.terminationStatus))
                }

                do {
                    try process.run()
                } catch {
                    outHandle.readabilityHandler = nil
                    continuation.resume(throwing: SlimError.launchFailed(error))
                    return
                }

                processBox.store(process)
            }
        } onCancel: {
            processBox.terminate()
        }
    }
}

// MARK: - Cancellation plumbing

/// Holds the in-flight Process so `onCancel` (which may run on any thread) can terminate it.
private final class ProcessBox: @unchecked Sendable {
    private let lock = NSLock()
    private var process: Process?

    func store(_ process: Process) {
        lock.lock()
        self.process = process
        lock.unlock()
    }

    func terminate() {
        lock.lock()
        let proc = process
        lock.unlock()
        if proc?.isRunning == true {
            proc?.terminate()
        }
    }
}

/// Thread-safe accumulator for stdout bytes read from a Pipe's readabilityHandler,
/// which fires on a background queue outside any actor.
private final class LockedBox: @unchecked Sendable {
    private let lock = NSLock()
    private var _value: Data

    init(_ initial: Data) { self._value = initial }

    var value: Data {
        lock.lock()
        defer { lock.unlock() }
        return _value
    }

    func append(_ chunk: Data) {
        lock.lock()
        _value.append(chunk)
        lock.unlock()
    }
}
