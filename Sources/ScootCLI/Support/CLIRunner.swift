import Foundation
import ScootCore

/// Business logic layer for the CLI. Every function here builds the needed
/// `@MainActor` store(s) fresh for this invocation (a CLI run is short-lived —
/// there's no long-running app to share stores with) and returns a plain
/// Codable/Sendable result. JSON encoding stays in the command layer.
@MainActor
enum CLIRunner {

    // MARK: - dest

    static func destList() -> [DestInfo] {
        DestinationStore().destinations.map { DestInfo(name: $0.name, path: $0.path) }
    }

    static func destAdd(path: String, cwd: String) throws -> DestInfo {
        let url = try resolveExistingDirectory(path, cwd: cwd)
        let store = DestinationStore()
        store.add(url: url)
        guard let added = store.destinations.last(where: { $0.path == url.path }) else {
            throw CLIError("添加失败")
        }
        return DestInfo(name: added.name, path: added.path)
    }

    static func destRemove(nameOrPath: String, cwd: String) throws -> DestInfo {
        let store = DestinationStore()
        guard let match = matchDestination(nameOrPath, in: store.destinations, cwd: cwd) else {
            throw CLIError("找不到目标: \(nameOrPath)")
        }
        store.remove(match)
        return DestInfo(name: match.name, path: match.path)
    }

    // MARK: - src

    static func srcList() -> SrcListOutput {
        let store = SourceStore()
        let list = store.sources.map {
            SrcInfo(name: $0.name, path: $0.path, active: $0.id == store.activeSource.id)
        }
        return SrcListOutput(active: store.activeSource.path, sources: list)
    }

    static func srcAdd(path: String, cwd: String) throws -> SrcAddOutput {
        let url = try resolveExistingDirectory(path, cwd: cwd)
        let store = SourceStore()
        store.add(url: url)
        let added = DestInfo(name: store.activeSource.name, path: store.activeSource.path)
        return SrcAddOutput(added: added, active: store.activeSource.path)
    }

    static func srcUse(nameOrPath: String, cwd: String) throws -> SrcUseOutput {
        let store = SourceStore()
        guard let match = matchSource(nameOrPath, in: store.sources, cwd: cwd) else {
            throw CLIError("找不到来源: \(nameOrPath)（需先用 `scoot src add` 添加）")
        }
        store.activeSource = match
        return SrcUseOutput(active: store.activeSource.path)
    }

    // MARK: - list

    static func list(sourceArg: String?, cwd: String) throws -> ListOutput {
        let url: URL
        if let arg = sourceArg {
            let sourceStore = SourceStore()
            if let matched = matchSource(arg, in: sourceStore.sources, cwd: cwd) {
                url = matched.url
            } else {
                url = try resolveExistingDirectory(arg, cwd: cwd)
            }
        } else {
            url = SourceStore().activeSource.url
        }

        let keys: Set<URLResourceKey> = [.contentModificationDateKey, .fileSizeKey, .isDirectoryKey]
        let entries: [URL]
        do {
            entries = try FileManager.default.contentsOfDirectory(
                at: url,
                includingPropertiesForKeys: Array(keys),
                options: [.skipsHiddenFiles]
            )
        } catch {
            throw CLIError("无法读取目录: \(url.path) (\(error.localizedDescription))")
        }

        var files: [FileEntry] = []
        for entry in entries {
            let rv = try? entry.resourceValues(forKeys: keys)
            let size = Int64(rv?.fileSize ?? 0)
            let isDir = rv?.isDirectory ?? false
            let modified = rv?.contentModificationDate ?? .distantPast
            files.append(FileEntry(name: entry.lastPathComponent, size: size, isDirectory: isDir, modified: modified))
        }
        files.sort { $0.name.localizedStandardCompare($1.name) == .orderedAscending }

        return ListOutput(source: url.path, count: files.count, files: files)
    }

    // MARK: - move

    static func move(files: [String], to: String, cwd: String) throws -> MoveOutput {
        let destStore = DestinationStore()
        guard let target = resolveMoveTarget(to, destinations: destStore.destinations, cwd: cwd) else {
            throw CLIError("找不到目标: \(to)")
        }

        let urls = files.map { URL(fileURLWithPath: PathResolver.resolve($0, relativeTo: cwd)) }
        let engine = MoveEngine()
        let result = engine.move(urls, to: target.url)

        if !result.moved.isEmpty {
            let batchID = UUID()
            let logEntries = result.moved.map { pair in
                LogEntry(fileName: pair.from.lastPathComponent, destName: target.name, batchID: batchID, isUndo: false)
            }
            MoveLog().record(batch: logEntries)
        }

        let moved = result.moved.map { MovedPair(from: $0.from.path, to: $0.to.path) }
        let errors = result.errors.map { MoveErrorEntry(file: $0.url.path, error: $0.error.localizedDescription) }
        return MoveOutput(moved: moved, errors: errors, destination: target.name)
    }

    // MARK: - rename

    static func rename(file: String, newName: String, cwd: String) throws -> RenameOutput {
        let safeName = try validatedBasename(newName)
        let url = URL(fileURLWithPath: PathResolver.resolve(file, relativeTo: cwd))
        let engine = MoveEngine()
        let result = engine.rename([(url: url, newName: safeName)])

        if let failure = result.errors.first {
            throw CLIError("重命名失败: \(failure.error.localizedDescription)")
        }
        guard let moved = result.moved.first else {
            throw CLIError("重命名失败: 未知错误")
        }

        let batchID = UUID()
        MoveLog().record(LogEntry(fileName: moved.from.lastPathComponent, destName: "重命名", batchID: batchID, isUndo: false))

        return RenameOutput(renamed: RenamedPair(from: moved.from.path, to: moved.to.path))
    }

    // MARK: - slim

    static func slim(files: [String], quality: String, cwd: String) async throws -> SlimOutput {
        guard ["high", "balanced", "extreme"].contains(quality) else {
            throw CLIError("压缩质量必须是 high | balanced | extreme，收到：\(quality)")
        }

        let urls = files.map { URL(fileURLWithPath: PathResolver.resolve($0, relativeTo: cwd)) }

        // Partition into slimmable targets and unsupported files. Unsupported files
        // are NOT silently dropped — they're reported as errors so the caller sees
        // exactly which inputs were skipped and why.
        var targets: [URL] = []
        var failures: [(url: URL, error: String)] = []
        for url in urls {
            if SlimService.canSlim(url) {
                targets.append(url)
            } else {
                let ext = url.pathExtension.isEmpty ? "(无扩展名)" : ".\(url.pathExtension.lowercased())"
                failures.append((url: url, error: "不支持的文件类型: \(ext)"))
            }
        }

        let service = SlimService()
        var successes: [(url: URL, result: SlimResult)] = []

        for item in targets {
            let ext = item.pathExtension
            let stem = item.deletingPathExtension().lastPathComponent
            let dir = item.deletingLastPathComponent()
            let outputName = ext.isEmpty ? "\(stem)_slim" : "\(stem)_slim.\(ext)"
            let output = uniqueDestinationURL(for: outputName, in: dir)

            do {
                let result = try await service.compress(item, to: output, quality: quality)
                successes.append((url: item, result: result))
            } catch {
                failures.append((url: item, error: error.localizedDescription))
            }
        }

        if !successes.isEmpty {
            let batchID = UUID()
            let logEntries = successes.map { pair in
                LogEntry(fileName: pair.url.lastPathComponent, destName: "压缩", batchID: batchID, isUndo: false)
            }
            MoveLog().record(batch: logEntries)
        }

        let compressed = successes.map { pair in
            CompressedEntry(
                input: pair.url.path,
                output: pair.result.outputPath.path,
                input_mb: pair.result.inputSizeMB,
                output_mb: pair.result.outputSizeMB,
                reduction_pct: pair.result.reductionPct
            )
        }
        let errors = failures.map { SlimErrorEntry(file: $0.url.path, error: $0.error) }
        let savedMB = successes.reduce(0.0) { $0 + max(0, $1.result.inputSizeMB - $1.result.outputSizeMB) }

        return SlimOutput(compressed: compressed, errors: errors, saved_mb: savedMB)
    }

    // MARK: - log

    static func log(limit: Int) -> LogOutput {
        let entries = MoveLog().entries.prefix(max(0, limit)).map { e in
            LogEntryOutput(date: e.date, file: e.fileName, dest: e.destName, undo: e.isUndo)
        }
        return LogOutput(entries: Array(entries))
    }

    // MARK: - Shared helpers

    private static func resolveExistingDirectory(_ path: String, cwd: String) throws -> URL {
        let resolvedPath = PathResolver.resolve(path, relativeTo: cwd)
        var isDir: ObjCBool = false
        guard FileManager.default.fileExists(atPath: resolvedPath, isDirectory: &isDir), isDir.boolValue else {
            throw CLIError("路径不存在或不是文件夹: \(path)")
        }
        return URL(fileURLWithPath: resolvedPath).standardizedFileURL
    }
}
