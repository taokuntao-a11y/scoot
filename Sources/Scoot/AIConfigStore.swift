import Foundation
import ScootCore
import SwiftUI

// MARK: - AIConfigStore

/// Persists AI configuration.
/// API Key → local credentials file (Application Support/Scoot/credentials.json, mode 0600).
/// Base URL + model name → UserDefaults.
@MainActor
final class AIConfigStore: ObservableObject {
    private static let baseURLDefaultsKey = "ai.baseURL"
    private static let modelDefaultsKey = "ai.model"

    static let defaultBaseURL = "https://api.anthropic.com"
    static let defaultModel = "claude-haiku-4-5"

    // MARK: Published properties

    @Published private(set) var hasKey: Bool = false
    @Published var baseURL: String {
        didSet { UserDefaults.standard.set(baseURL, forKey: Self.baseURLDefaultsKey) }
    }
    @Published var model: String {
        didSet { UserDefaults.standard.set(model, forKey: Self.modelDefaultsKey) }
    }

    // MARK: Storage

    private let credentials: CredentialsFile

    // MARK: Init

    /// Designated init — storageDir is injectable for tests.
    init(storageDir: URL? = nil) {
        let dir: URL
        if let provided = storageDir {
            dir = provided
        } else {
            let appSupport = FileManager.default.urls(
                for: .applicationSupportDirectory, in: .userDomainMask
            ).first!
            dir = appSupport.appendingPathComponent("Scoot")
        }
        credentials = CredentialsFile(storageDir: dir)
        hasKey = credentials.hasKey()
        baseURL = UserDefaults.standard.string(forKey: Self.baseURLDefaultsKey) ?? Self.defaultBaseURL
        model = UserDefaults.standard.string(forKey: Self.modelDefaultsKey) ?? Self.defaultModel
    }

    // MARK: Key management

    func setKey(_ key: String) {
        let trimmed = key.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        credentials.save(apiKey: trimmed)
        hasKey = true
    }

    func clearKey() {
        credentials.delete()
        hasKey = false
    }

    // MARK: Build LLMService

    /// Returns a configured AnthropicClient, or nil if no API key is stored.
    func makeLLMService() -> (any LLMService)? {
        guard let key = credentials.read() else { return nil }
        let url = baseURL.trimmingCharacters(in: .whitespacesAndNewlines)
        let effectiveURL = url.isEmpty ? Self.defaultBaseURL : url
        let effectiveModel = model.trimmingCharacters(in: .whitespacesAndNewlines)
        let modelName = effectiveModel.isEmpty ? Self.defaultModel : effectiveModel
        return AnthropicClient(apiKey: key, baseURL: effectiveURL, model: modelName)
    }
}
