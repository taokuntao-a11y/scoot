import Foundation
import ScootCore

// MARK: - Path resolution (pure — no filesystem access)

/// Expands `~` and resolves a possibly-relative path against `cwd`. Pure string
/// manipulation only, so it's directly unit-testable without touching disk.
enum PathResolver {
    static func resolve(_ path: String, relativeTo cwd: String) -> String {
        let expanded = (path as NSString).expandingTildeInPath
        if expanded.hasPrefix("/") {
            return expanded
        }
        return (cwd as NSString).appendingPathComponent(expanded)
    }
}

// MARK: - Basename validation (for `rename --name`)

/// Validates that `rename --name <x>` is a plain filename, not a path. Rejects an
/// empty/whitespace name, anything containing a path separator, and the special
/// `.`/`..` entries — otherwise `MoveEngine.rename` would resolve it against the
/// file's directory and could write outside it (e.g. `--name ../evil`). Pure, no
/// disk access — directly unit-testable. Returns the trimmed, validated basename.
func validatedBasename(_ name: String) throws -> String {
    let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
    guard !trimmed.isEmpty else {
        throw CLIError("新文件名不能为空")
    }
    guard !trimmed.contains("/"), trimmed != ".", trimmed != ".." else {
        throw CLIError("新文件名必须是纯文件名，不能包含路径分隔符或为 . / ..：\(name)")
    }
    return trimmed
}

// MARK: - Name-or-path matching against stored Destination / SourceFolder lists

/// Matches a `<name-or-path>` CLI argument against stored destinations: exact name
/// match first, then a standardized-path comparison. Pure (only path string
/// standardization, no disk access) — safe to unit test directly.
func matchDestination(_ nameOrPath: String, in destinations: [Destination], cwd: String) -> Destination? {
    if let byName = destinations.first(where: { $0.name == nameOrPath }) {
        return byName
    }
    let resolved = URL(fileURLWithPath: PathResolver.resolve(nameOrPath, relativeTo: cwd)).standardizedFileURL.path
    return destinations.first { URL(fileURLWithPath: $0.path).standardizedFileURL.path == resolved }
}

/// Same matching rule as `matchDestination`, for `SourceFolder`.
func matchSource(_ nameOrPath: String, in sources: [SourceFolder], cwd: String) -> SourceFolder? {
    if let byName = sources.first(where: { $0.name == nameOrPath }) {
        return byName
    }
    let resolved = URL(fileURLWithPath: PathResolver.resolve(nameOrPath, relativeTo: cwd)).standardizedFileURL.path
    return sources.first { URL(fileURLWithPath: $0.path).standardizedFileURL.path == resolved }
}

// MARK: - `move --to` resolution

/// Result of resolving `move --to <dest-name-or-path>`: either a match against a
/// stored `Destination`, or a raw existing directory used directly (its name is
/// derived from the last path component).
enum ResolvedMoveTarget: Equatable {
    case destination(Destination)
    case rawDirectory(name: String, url: URL)

    var name: String {
        switch self {
        case .destination(let d): return d.name
        case .rawDirectory(let name, _): return name
        }
    }

    var url: URL {
        switch self {
        case .destination(let d): return d.url
        case .rawDirectory(_, let url): return url
        }
    }
}

/// Resolves `--to`: first match a stored destination by name, else by path; if
/// there's no store match but `to` is an existing directory path, use it directly.
/// `fileManager` is injectable so tests can point at real (throwaway) temp dirs
/// without needing a process spawn.
func resolveMoveTarget(
    _ to: String,
    destinations: [Destination],
    cwd: String,
    fileManager: FileManager = .default
) -> ResolvedMoveTarget? {
    if let match = matchDestination(to, in: destinations, cwd: cwd) {
        return .destination(match)
    }
    let resolvedPath = PathResolver.resolve(to, relativeTo: cwd)
    var isDir: ObjCBool = false
    if fileManager.fileExists(atPath: resolvedPath, isDirectory: &isDir), isDir.boolValue {
        let url = URL(fileURLWithPath: resolvedPath).standardizedFileURL
        return .rawDirectory(name: url.lastPathComponent, url: url)
    }
    return nil
}
