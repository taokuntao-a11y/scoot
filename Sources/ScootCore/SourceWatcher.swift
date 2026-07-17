import Combine
import Foundation

@MainActor
public final class SourceWatcher: ObservableObject {
    @Published public var files: [FileItem] = []
    public var sourcePath: String {
        didSet {
            rebuildWatcher()
            reload()
        }
    }

    private var dispatchSource: DispatchSourceFileSystemObject?
    private var watchedFD: Int32 = -1
    private var debounceTask: Task<Void, Never>?

    /// Monotonically increasing counter; used to discard stale scan results.
    private var generation: Int = 0

    nonisolated static let incompleteExtensions: Set<String> = [
        ".download", ".crdownload", ".part", ".aria2"
    ]

    public var sourceURL: URL {
        URL(fileURLWithPath: sourcePath, isDirectory: true)
    }

    /// Designated init — path is supplied by App layer (SourceStore.activeSource.path).
    public init(path: String) {
        self.sourcePath = path
        rebuildWatcher()
        reload()
    }

    deinit {
        dispatchSource?.cancel()
        if watchedFD >= 0 { Darwin.close(watchedFD) }
    }

    // MARK: Watching

    private func rebuildWatcher() {
        dispatchSource?.cancel()
        dispatchSource = nil
        if watchedFD >= 0 {
            Darwin.close(watchedFD)
            watchedFD = -1
        }

        let path = sourcePath
        let fd = Darwin.open(path, O_EVTONLY)
        guard fd >= 0 else { return }
        watchedFD = fd

        // Handlers formed in this @MainActor context are MainActor-isolated under
        // Swift 6; dispatching them on a background queue trips the runtime
        // isolation assertion (SIGTRAP), so the source must run on the main queue.
        let src = DispatchSource.makeFileSystemObjectSource(
            fileDescriptor: fd,
            eventMask: .write,
            queue: .main
        )

        src.setEventHandler { [weak self] in
            self?.scheduleReload()
        }

        // fd is closed in the cancel handler; avoid closing it twice in deinit
        src.setCancelHandler { Darwin.close(fd) }

        src.resume()
        dispatchSource = src
        // Transfer fd ownership to cancel handler
        watchedFD = -1
    }

    private func scheduleReload() {
        debounceTask?.cancel()
        debounceTask = Task { @MainActor [weak self] in
            try? await Task.sleep(nanoseconds: 300_000_000)
            guard !Task.isCancelled else { return }
            self?.reload()
        }
    }

    // MARK: Immediate removal (optimistic update)

    /// Remove the given URLs from the in-memory list immediately without waiting
    /// for a filesystem event.  Produces the "fly away" animation when paired with
    /// a list .animation modifier.
    public func removeImmediately(_ urls: [URL]) {
        let set = Set(urls)
        files = files.filter { !set.contains($0.url) }
    }

    // MARK: Scanning

    /// Pure nonisolated scan — safe to call from any Task.
    public nonisolated static func scan(path: String) -> [FileItem] {
        let url = URL(fileURLWithPath: path, isDirectory: true)
        let keys: Set<URLResourceKey> = [
            .addedToDirectoryDateKey,
            .contentModificationDateKey,
            .fileSizeKey,
            .isDirectoryKey
        ]

        guard let entries = try? FileManager.default.contentsOfDirectory(
            at: url,
            includingPropertiesForKeys: Array(keys),
            options: .skipsHiddenFiles
        ) else {
            return []
        }

        var result: [FileItem] = []
        for entry in entries {
            let name = entry.lastPathComponent
            guard !name.hasPrefix(".") else { continue }
            let lower = name.lowercased()
            if incompleteExtensions.contains(where: { lower.hasSuffix($0) }) { continue }

            let rv = try? entry.resourceValues(forKeys: keys)
            let addedAt = rv?.addedToDirectoryDate ?? rv?.contentModificationDate ?? .distantPast
            let size = Int64(rv?.fileSize ?? 0)
            let isDir = rv?.isDirectory ?? false

            result.append(FileItem(url: entry, name: name, addedAt: addedAt, size: size, isDirectory: isDir))
        }

        result.sort { $0.addedAt > $1.addedAt }
        return Array(result.prefix(50))
    }

    /// Triggers a background scan; result is published on MainActor.
    /// Stale results (from cancelled/superseded scans) are discarded via generation counter.
    public func reload() {
        generation &+= 1
        let myGeneration = generation
        let path = sourcePath

        Task.detached {
            let result = SourceWatcher.scan(path: path)
            await MainActor.run { [weak self] in
                guard let self, self.generation == myGeneration else { return }
                self.files = result
            }
        }
    }
}
