import Foundation

// MARK: - CredentialsFile

/// Reads and writes the API key to a local credentials file (~/.ssh model).
/// File format: {"apiKey": "..."}.  Permissions are locked to 0600 on write
/// and tightened on read if found too permissive.
public struct CredentialsFile: Sendable {
    private let fileURL: URL

    // MARK: Init

    public init(storageDir: URL) {
        self.fileURL = storageDir.appendingPathComponent("credentials.json")
    }

    // MARK: Public API

    /// Returns true if the credentials file exists and contains a non-empty key.
    public func hasKey() -> Bool {
        return read() != nil
    }

    /// Persist the API key to disk (mode 0600).
    public func save(apiKey: String) {
        let trimmed = apiKey.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }

        let payload = ["apiKey": trimmed]
        guard let data = try? JSONEncoder().encode(payload) else { return }

        let fm = FileManager.default
        let dir = fileURL.deletingLastPathComponent()
        try? fm.createDirectory(at: dir, withIntermediateDirectories: true)

        do {
            try data.write(to: fileURL, options: .atomic)
            try fm.setAttributes([.posixPermissions: 0o600 as NSNumber], ofItemAtPath: fileURL.path)
        } catch {
            // Best-effort; failure silently drops
        }
    }

    /// Load the API key. Tightens permissions if they are too permissive before reading.
    public func read() -> String? {
        let fm = FileManager.default
        guard fm.fileExists(atPath: fileURL.path) else { return nil }

        // Tighten permissions if wider than 0600
        if let attrs = try? fm.attributesOfItem(atPath: fileURL.path),
           let perms = attrs[.posixPermissions] as? Int,
           perms & 0o177 != 0 {
            try? fm.setAttributes([.posixPermissions: 0o600 as NSNumber], ofItemAtPath: fileURL.path)
        }

        guard let data = try? Data(contentsOf: fileURL),
              let dict = try? JSONDecoder().decode([String: String].self, from: data),
              let key = dict["apiKey"],
              !key.isEmpty
        else { return nil }

        return key
    }

    /// Remove the credentials file.
    public func delete() {
        try? FileManager.default.removeItem(at: fileURL)
    }
}
