import Foundation

// MARK: - Result types

public struct MoveResult: Sendable {
    public let moved: [(from: URL, to: URL)]
    public let errors: [(url: URL, error: any Error)]

    public var errorSummary: String? {
        guard !errors.isEmpty else { return nil }
        let names = errors.map { $0.url.lastPathComponent }.joined(separator: ", ")
        return "移动失败: \(names)"
    }

    public init(moved: [(from: URL, to: URL)], errors: [(url: URL, error: any Error)]) {
        self.moved = moved
        self.errors = errors
    }
}

// MARK: - Rename logic (public for unit testing)

/// Returns a unique destination URL by appending " 2", " 3", etc. before the extension.
public func uniqueDestinationURL(for name: String, in dir: URL) -> URL {
    let dest = dir.appendingPathComponent(name)
    guard FileManager.default.fileExists(atPath: dest.path) else { return dest }

    let ext = (name as NSString).pathExtension
    let base = ext.isEmpty ? name : (name as NSString).deletingPathExtension

    var counter = 2
    while true {
        let newName = ext.isEmpty ? "\(base) \(counter)" : "\(base) \(counter).\(ext)"
        let candidate = dir.appendingPathComponent(newName)
        if !FileManager.default.fileExists(atPath: candidate.path) {
            return candidate
        }
        counter += 1
    }
}

// MARK: - MoveEngine

/// Pure move + undo logic. No UI dependencies.
/// Not isolated to any actor; callers are responsible for thread safety.
public final class MoveEngine: @unchecked Sendable {

    private var undoStack: [[(from: URL, to: URL)]] = []
    private let maxUndoDepth = 10

    public init() {}

    // MARK: Public interface

    public var canUndo: Bool { !undoStack.isEmpty }

    /// Description of the last batch for the undo button label.
    public var lastBatchDescription: String? {
        guard let last = undoStack.last else { return nil }
        let names = last.map { $0.from.lastPathComponent }
        if names.count == 1 { return names[0] }
        return "\(names[0]) 等 \(names.count) 项"
    }

    /// Move items to dir, skip on error, push successful moves to undo stack.
    public func move(_ items: [URL], to dir: URL) -> MoveResult {
        var moved: [(from: URL, to: URL)] = []
        var errors: [(url: URL, error: any Error)] = []

        for item in items {
            let dest = uniqueDestinationURL(for: item.lastPathComponent, in: dir)
            do {
                try FileManager.default.moveItem(at: item, to: dest)
                moved.append((from: item, to: dest))
            } catch {
                errors.append((url: item, error: error))
            }
        }

        if !moved.isEmpty {
            undoStack.append(moved)
            if undoStack.count > maxUndoDepth {
                undoStack.removeFirst()
            }
        }

        return MoveResult(moved: moved, errors: errors)
    }

    /// Rename files in-place (same directory). Pushes onto the shared undo stack.
    /// - Parameter pairs: Each tuple contains the current URL and the desired new name (basename only).
    /// - Returns: MoveResult where `moved.from` = original URL, `moved.to` = renamed URL.
    public func rename(_ pairs: [(url: URL, newName: String)]) -> MoveResult {
        var moved: [(from: URL, to: URL)] = []
        var errors: [(url: URL, error: any Error)] = []

        for pair in pairs {
            let dir = pair.url.deletingLastPathComponent()
            let dest = uniqueDestinationURL(for: pair.newName, in: dir)
            do {
                try FileManager.default.moveItem(at: pair.url, to: dest)
                moved.append((from: pair.url, to: dest))
            } catch {
                errors.append((url: pair.url, error: error))
            }
        }

        if !moved.isEmpty {
            undoStack.append(moved)
            if undoStack.count > maxUndoDepth {
                undoStack.removeFirst()
            }
        }

        return MoveResult(moved: moved, errors: errors)
    }

    /// Reverse the last batch. Returns nil if nothing to undo.
    @discardableResult
    public func undo() -> MoveResult? {
        guard !undoStack.isEmpty else { return nil }
        let batch = undoStack.removeLast()

        var moved: [(from: URL, to: URL)] = []
        var errors: [(url: URL, error: any Error)] = []

        for pair in batch.reversed() {
            // Restore to the original name and directory (pair.from).
            // Using pair.from.lastPathComponent (original name) ensures rename undo
            // restores the original filename, not the post-rename filename.
            let dest = uniqueDestinationURL(
                for: pair.from.lastPathComponent,
                in: pair.from.deletingLastPathComponent()
            )
            do {
                try FileManager.default.moveItem(at: pair.to, to: dest)
                moved.append((from: pair.to, to: dest))
            } catch {
                errors.append((url: pair.to, error: error))
            }
        }

        return MoveResult(moved: moved, errors: errors)
    }
}
