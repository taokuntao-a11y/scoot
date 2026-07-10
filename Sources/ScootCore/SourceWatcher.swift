import Combine
import Foundation

@MainActor
public final class SourceWatcher: ObservableObject {
    @Published public var files: [FileItem] = []
    @Published public var sourcePath: String {
        didSet {
            UserDefaults.standard.set(sourcePath, forKey: "sourcePath")
            rebuildWatcher()
            reload()
        }
    }

    private var dispatchSource: DispatchSourceFileSystemObject?
    private var watchedFD: Int32 = -1
    private var debounceTask: Task<Void, Never>?

    private static let incompleteExtensions: Set<String> = [
        ".download", ".crdownload", ".part", ".aria2"
    ]

    public var sourceURL: URL {
        URL(fileURLWithPath: sourcePath, isDirectory: true)
    }

    public init() {
        let defaultPath = FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent("Downloads").path
        sourcePath = UserDefaults.standard.string(forKey: "sourcePath") ?? defaultPath
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

        let src = DispatchSource.makeFileSystemObjectSource(
            fileDescriptor: fd,
            eventMask: .write,
            queue: .global()
        )

        src.setEventHandler { [weak self] in
            Task { @MainActor [weak self] in
                self?.scheduleReload()
            }
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

    // MARK: Scanning

    public func reload() {
        let url = URL(fileURLWithPath: sourcePath, isDirectory: true)
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
            files = []
            return
        }

        var result: [FileItem] = []
        for entry in entries {
            let name = entry.lastPathComponent
            guard !name.hasPrefix(".") else { continue }
            let lower = name.lowercased()
            if Self.incompleteExtensions.contains(where: { lower.hasSuffix($0) }) { continue }

            let rv = try? entry.resourceValues(forKeys: keys)
            let addedAt = rv?.addedToDirectoryDate ?? rv?.contentModificationDate ?? .distantPast
            let size = Int64(rv?.fileSize ?? 0)
            let isDir = rv?.isDirectory ?? false

            result.append(FileItem(url: entry, name: name, addedAt: addedAt, size: size, isDirectory: isDir))
        }

        result.sort { $0.addedAt > $1.addedAt }
        files = Array(result.prefix(50))
    }
}
