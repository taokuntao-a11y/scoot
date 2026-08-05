import Foundation

// MARK: - dest

struct DestInfo: Codable, Sendable {
    let name: String
    let path: String
}

struct DestListOutput: Codable { let destinations: [DestInfo] }
struct DestAddOutput: Codable { let added: DestInfo }
struct DestRemoveOutput: Codable { let removed: DestInfo }

// MARK: - src

struct SrcInfo: Codable, Sendable {
    let name: String
    let path: String
    let active: Bool
}

struct SrcListOutput: Codable {
    let active: String
    let sources: [SrcInfo]
}

struct SrcAddOutput: Codable {
    let added: DestInfo
    let active: String
}

struct SrcUseOutput: Codable { let active: String }

// MARK: - list

struct FileEntry: Codable, Sendable {
    let name: String
    let size: Int64
    let isDirectory: Bool
    let modified: Date
}

struct ListOutput: Codable {
    let source: String
    let count: Int
    let files: [FileEntry]
}

// MARK: - move

struct MovedPair: Codable, Sendable {
    let from: String
    let to: String
}

struct MoveErrorEntry: Codable, Sendable {
    let file: String
    let error: String
}

struct MoveOutput: Codable {
    let moved: [MovedPair]
    let errors: [MoveErrorEntry]
    let destination: String
}

// MARK: - rename

struct RenamedPair: Codable {
    let from: String
    let to: String
}

struct RenameOutput: Codable { let renamed: RenamedPair }

// MARK: - slim

struct CompressedEntry: Codable, Sendable {
    let input: String
    let output: String
    let input_mb: Double
    let output_mb: Double
    let reduction_pct: Double
}

struct SlimErrorEntry: Codable, Sendable {
    let file: String
    let error: String
}

struct SlimOutput: Codable {
    let compressed: [CompressedEntry]
    let errors: [SlimErrorEntry]
    let saved_mb: Double
}

// MARK: - log

struct LogEntryOutput: Codable, Sendable {
    let date: Date
    let file: String
    let dest: String
    let undo: Bool
}

struct LogOutput: Codable { let entries: [LogEntryOutput] }

// MARK: - capabilities

struct JSONContract: Codable {
    let flag: String
    let stdout: String
    let stderr: String
    let exit_codes: [String: String]
}

struct CapabilitiesOutput: Codable {
    let name: String
    let version: String
    let description: String
    let commands: [String]
    let qualities: [String]
    let slimmable_extensions: [String]
    let json_contract: JSONContract
    let state_dir: String
}
