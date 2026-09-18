import Foundation

// MARK: - LLMError

public enum LLMError: Error, Sendable {
    /// HTTP non-2xx response.
    case httpError(statusCode: Int, body: String)
    /// Response JSON doesn't contain expected content field.
    case unexpectedResponse(String)
    /// Network or URLSession level error.
    case networkError(any Error)
}

extension LLMError: LocalizedError {
    public var errorDescription: String? {
        switch self {
        case .httpError(let code, let body):
            let preview = body.prefix(120)
            return "LLM 请求失败 (\(code)): \(preview)"
        case .unexpectedResponse(let detail):
            return "LLM 响应格式异常: \(detail)"
        case .networkError(let err):
            return "网络错误: \(err.localizedDescription)"
        }
    }
}

// MARK: - LLMService protocol

/// Minimal text-completion abstraction. Sendable so it can cross actor boundaries.
public protocol LLMService: Sendable {
    /// Sends a single-turn request and returns the assistant's text response.
    func complete(system: String, user: String) async throws -> String
}

// MARK: - AnthropicClient

/// Thin URLSession adapter for Anthropic Messages API.
/// Sendable: all stored properties are value types or thread-safe types.
public struct AnthropicClient: LLMService {
    private let apiKey: String
    private let baseURL: String
    private let model: String

    public init(
        apiKey: String,
        baseURL: String = "https://api.anthropic.com",
        model: String = "claude-haiku-4-5"
    ) {
        self.apiKey = apiKey
        self.baseURL = baseURL.hasSuffix("/") ? String(baseURL.dropLast()) : baseURL
        self.model = model
    }

    public func complete(system: String, user: String) async throws -> String {
        guard let url = URL(string: "\(baseURL)/v1/messages") else {
            throw LLMError.unexpectedResponse("Invalid base URL: \(baseURL)")
        }

        // Build request body
        let body: [String: Any] = [
            "model": model,
            "max_tokens": 2048,
            "temperature": 0,
            "system": system,
            "messages": [
                ["role": "user", "content": user]
            ]
        ]
        let bodyData = try JSONSerialization.data(withJSONObject: body)

        var request = URLRequest(url: url, timeoutInterval: 60)
        request.httpMethod = "POST"
        request.httpBody = bodyData
        request.setValue(apiKey, forHTTPHeaderField: "x-api-key")
        request.setValue("2023-06-01", forHTTPHeaderField: "anthropic-version")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")

        let (data, response): (Data, URLResponse)
        do {
            (data, response) = try await URLSession.shared.data(for: request)
        } catch {
            // Normalize cancellation so callers can silently ignore user-initiated
            // cancels; URLSession surfaces Task cancellation as URLError.cancelled.
            if error is CancellationError || (error as? URLError)?.code == .cancelled {
                throw CancellationError()
            }
            throw LLMError.networkError(error)
        }

        // Check HTTP status
        if let httpResponse = response as? HTTPURLResponse,
           !(200...299).contains(httpResponse.statusCode) {
            let bodyStr = String(data: data, encoding: .utf8) ?? "<binary>"
            throw LLMError.httpError(statusCode: httpResponse.statusCode, body: bodyStr)
        }

        // Parse response: { "content": [...] } — take the first "text" block.
        // Reasoning models (e.g. deepseek-flash) prepend a "thinking" block,
        // so content[0] is not necessarily the text block.
        guard let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let content = json["content"] as? [[String: Any]],
              let text = content.first(where: { $0["type"] as? String == "text" })?["text"] as? String
        else {
            let raw = String(data: data, encoding: .utf8) ?? "<binary>"
            throw LLMError.unexpectedResponse("no text content block; raw: \(raw.prefix(200))")
        }

        return text
    }
}
