import Foundation
import Testing

@testable import ScootCLI
@testable import ScootCore

// MARK: - PathResolver (pure — no filesystem access)

@Suite("PathResolver")
struct PathResolverTests {

    @Test func absolutePathPassesThrough() {
        #expect(PathResolver.resolve("/tmp/foo", relativeTo: "/Users/kun") == "/tmp/foo")
    }

    @Test func relativePathJoinsWithCwd() {
        #expect(PathResolver.resolve("foo/bar.txt", relativeTo: "/Users/kun/Projects") == "/Users/kun/Projects/foo/bar.txt")
    }

    @Test func tildeExpandsToHome() {
        let home = FileManager.default.homeDirectoryForCurrentUser.path
        #expect(PathResolver.resolve("~/Downloads", relativeTo: "/irrelevant") == "\(home)/Downloads")
    }

    @Test func dotResolvesRelativeToCwd() {
        // PathResolver does plain string-joining, not full standardization — "."
        // stays as a literal trailing path component. Callers that need a
        // canonical path standardize afterward via URL.standardizedFileURL
        // (see matchDestination / resolveMoveTarget).
        #expect(PathResolver.resolve(".", relativeTo: "/Users/kun/Projects") == "/Users/kun/Projects/.")
    }
}

// MARK: - matchDestination / matchSource (pure name-or-path matching)

@Suite("matchDestination / matchSource")
struct MatcherTests {

    private let destinations = [
        Destination(name: "Invoices", path: "/Users/kun/Documents/Invoices"),
        Destination(name: "Photos", path: "/Users/kun/Pictures"),
    ]

    private let sources = [
        SourceFolder(name: "Downloads", path: "/Users/kun/Downloads"),
        SourceFolder(name: "Desktop", path: "/Users/kun/Desktop"),
    ]

    @Test func matchesDestinationByExactName() {
        let found = matchDestination("Invoices", in: destinations, cwd: "/tmp")
        #expect(found?.path == "/Users/kun/Documents/Invoices")
    }

    @Test func matchesDestinationByAbsolutePath() {
        let found = matchDestination("/Users/kun/Pictures", in: destinations, cwd: "/tmp")
        #expect(found?.name == "Photos")
    }

    @Test func matchesDestinationByRelativePathAgainstCwd() {
        // cwd = /Users/kun/Documents, so "Invoices" (bare, not a stored name match
        // here since the stored name IS "Invoices" too) — use a distinct relative form.
        let found = matchDestination("./Invoices", in: destinations, cwd: "/Users/kun/Documents")
        #expect(found?.name == "Invoices")
    }

    @Test func returnsNilWhenNoMatch() {
        #expect(matchDestination("Nope", in: destinations, cwd: "/tmp") == nil)
        #expect(matchDestination("/nowhere", in: destinations, cwd: "/tmp") == nil)
    }

    @Test func matchesSourceByExactName() {
        let found = matchSource("Desktop", in: sources, cwd: "/tmp")
        #expect(found?.path == "/Users/kun/Desktop")
    }

    @Test func matchesSourceByAbsolutePath() {
        let found = matchSource("/Users/kun/Downloads", in: sources, cwd: "/tmp")
        #expect(found?.name == "Downloads")
    }
}

// MARK: - resolveMoveTarget (store match, falls back to a real existing directory)

@Suite("resolveMoveTarget")
struct ResolveMoveTargetTests {

    private let destinations = [
        Destination(name: "Invoices", path: "/Users/kun/Documents/Invoices"),
    ]

    @Test func resolvesStoredDestinationByName() {
        let result = resolveMoveTarget("Invoices", destinations: destinations, cwd: "/tmp")
        #expect(result?.name == "Invoices")
        if case .destination = result {
            // expected
        } else {
            Issue.record("expected .destination case")
        }
    }

    @Test func fallsBackToRawExistingDirectory() throws {
        let dir = FileManager.default.temporaryDirectory
            .appendingPathComponent("ScootCLIResolveMoveTarget-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: dir) }

        let result = resolveMoveTarget(dir.path, destinations: destinations, cwd: "/tmp")
        guard case .rawDirectory(let name, let url) = result else {
            Issue.record("expected .rawDirectory case, got \(String(describing: result))")
            return
        }
        #expect(name == dir.lastPathComponent)
        #expect(url.path == dir.standardizedFileURL.path)
    }

    @Test func returnsNilWhenNeitherStoreNorDirectoryMatches() {
        let result = resolveMoveTarget("/nonexistent/nope", destinations: destinations, cwd: "/tmp")
        #expect(result == nil)
    }

    @Test func returnsNilWhenPathExistsButIsAFile() throws {
        let dir = FileManager.default.temporaryDirectory
            .appendingPathComponent("ScootCLIResolveMoveTargetFile-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: dir) }
        let file = dir.appendingPathComponent("not-a-dir.txt")
        FileManager.default.createFile(atPath: file.path, contents: nil)

        let result = resolveMoveTarget(file.path, destinations: destinations, cwd: "/tmp")
        #expect(result == nil)
    }
}
