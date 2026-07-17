import Foundation

// MARK: - ArchiveSuggester

/// Asks LLM to match each file to one of the provided destination folders.
/// Input: file names + candidate destination names.
/// Output: `[(file: String, dest: String?)]` where nil means LLM is uncertain.
public struct ArchiveSuggester: Sendable {
    private let llm: any LLMService

    public init(llm: any LLMService) {
        self.llm = llm
    }

    // MARK: Public interface

    /// - Parameters:
    ///   - fileNames: Display names of files to classify.
    ///   - destinations: Available target folder names.
    /// - Returns: Array matching fileNames order; dest is nil when LLM is uncertain.
    public func suggest(
        fileNames: [String],
        destinations: [String]
    ) async throws -> [(file: String, dest: String?)] {
        guard !fileNames.isEmpty else { return [] }

        let system = """
        你是一个文件自动分拣助手，帮助用户将下载文件夹中的文件归类到目标文件夹。
        请只根据文件名判断最合适的目标文件夹，不要读取文件内容。
        如果无法确定，返回 null。
        只输出严格的 JSON 数组，不要任何解释文字。
        """

        let filesJSON = fileNames.map { "  \"\($0.replacingOccurrences(of: "\"", with: "\\\""))\"" }
            .joined(separator: ",\n")
        let destsJSON = destinations.map { "  \"\($0.replacingOccurrences(of: "\"", with: "\\\""))\"" }
            .joined(separator: ",\n")

        let user = """
        待分拣文件列表：
        [
        \(filesJSON)
        ]

        可用目标文件夹：
        [
        \(destsJSON)
        ]

        请为每个文件选择最合适的目标文件夹，若不确定则填 null。
        返回严格 JSON 数组，格式如下（字段名用英文）：
        [{"file": "文件名", "dest": "目标文件夹名或null"}, ...]
        """

        let rawText = try await llm.complete(system: system, user: user)
        return parseArchiveSuggestions(rawText: rawText, validDests: Set(destinations))
    }

    // MARK: Parsing

    private func parseArchiveSuggestions(
        rawText: String,
        validDests: Set<String>
    ) -> [(file: String, dest: String?)] {
        let jsonStr = stripFence(rawText)
        guard let data = jsonStr.data(using: .utf8),
              let arr = try? JSONSerialization.jsonObject(with: data) as? [[String: Any]]
        else { return [] }

        return arr.compactMap { item -> (file: String, dest: String?)? in
            guard let file = item["file"] as? String, !file.isEmpty else { return nil }
            // "dest" can be a String or NSNull
            if let destStr = item["dest"] as? String {
                // Only accept dest if it's in the valid list
                let finalDest = validDests.contains(destStr) ? destStr : nil
                return (file: file, dest: finalDest)
            } else {
                // null or missing → uncertain
                return (file: file, dest: nil)
            }
        }
    }
}

// MARK: - RenameSuggester

/// Asks LLM to suggest semantic file names for a list of files.
/// Enforces: original extension preserved, no path separators, max 80 chars, no duplicates.
public struct RenameSuggester: Sendable {
    private let llm: any LLMService

    public init(llm: any LLMService) {
        self.llm = llm
    }

    // MARK: Public interface

    /// - Parameter fileNames: Current file names to rename.
    /// - Returns: Validated `(file: String, newName: String)` pairs; invalid items are dropped.
    public func suggest(fileNames: [String]) async throws -> [(file: String, newName: String)] {
        guard !fileNames.isEmpty else { return [] }

        let system = """
        你是一个文件重命名助手，帮助用户将下载文件夹中语义不清的文件名改成清晰易读的名称。
        命名要求：
        1. 语义清晰，能反映文件内容
        2. 保留原文件扩展名不变
        3. 名称不超过 80 个字符
        4. 不能包含 / : \\ * ? \" < > | 等非法字符
        5. 不能以空格或点开头或结尾
        6. 只根据文件名推断，不读取文件内容
        只输出严格的 JSON 数组，不要任何解释文字。
        """

        let filesJSON = fileNames.map { "  \"\($0.replacingOccurrences(of: "\"", with: "\\\""))\"" }
            .joined(separator: ",\n")

        let user = """
        请为以下文件提供更清晰的文件名：
        [
        \(filesJSON)
        ]

        返回严格 JSON 数组，格式如下（字段名用英文）：
        [{"file": "原文件名", "new_name": "新文件名（含扩展名）"}, ...]
        """

        let rawText = try await llm.complete(system: system, user: user)
        return parseRenameSuggestions(rawText: rawText, originalNames: fileNames)
    }

    // MARK: Parsing + validation

    private func parseRenameSuggestions(
        rawText: String,
        originalNames: [String]
    ) -> [(file: String, newName: String)] {
        let jsonStr = stripFence(rawText)
        guard let data = jsonStr.data(using: .utf8),
              let arr = try? JSONSerialization.jsonObject(with: data) as? [[String: Any]]
        else { return [] }

        var seenNewNames: Set<String> = []
        var results: [(file: String, newName: String)] = []

        for item in arr {
            guard let file = item["file"] as? String, !file.isEmpty,
                  var newName = item["new_name"] as? String, !newName.isEmpty
            else { continue }

            // Enforce original extension
            newName = enforceExtension(newName: newName, originalName: file)

            // Validate: no path separators, not empty, not too long
            guard isValidName(newName) else { continue }

            // Drop duplicates (case-insensitive match for safety)
            let key = newName.lowercased()
            guard !seenNewNames.contains(key) else { continue }

            seenNewNames.insert(key)
            results.append((file: file, newName: newName))
        }

        return results
    }

    /// Forces `newName` to carry the same extension as `originalName`.
    private func enforceExtension(newName: String, originalName: String) -> String {
        let origExt = (originalName as NSString).pathExtension
        let newExt = (newName as NSString).pathExtension
        if origExt.isEmpty { return (newName as NSString).deletingPathExtension }
        if newExt.lowercased() == origExt.lowercased() { return newName }
        // Extension mismatch: replace with original extension
        let nameWithoutExt = (newName as NSString).deletingPathExtension
        return "\(nameWithoutExt).\(origExt)"
    }

    /// Returns false for names with path separators, blank, overly long, or illegal chars.
    private func isValidName(_ name: String) -> Bool {
        guard !name.isEmpty, name.count <= 80 else { return false }
        // No path separators
        guard !name.contains("/"), !name.contains("\\") else { return false }
        // No other illegal chars
        let illegal: Set<Character> = [":", "*", "?", "\"", "<", ">", "|"]
        guard !name.contains(where: { illegal.contains($0) }) else { return false }
        // Must not be just whitespace
        guard !name.trimmingCharacters(in: .whitespaces).isEmpty else { return false }
        return true
    }
}

// MARK: - Shared helpers

/// Strips ```json ... ``` or ``` ... ``` markdown fences from LLM output.
func stripFence(_ text: String) -> String {
    var s = text.trimmingCharacters(in: .whitespacesAndNewlines)
    // Remove opening fence (with optional language tag)
    if s.hasPrefix("```") {
        if let newline = s.firstIndex(of: "\n") {
            s = String(s[s.index(after: newline)...])
        }
    }
    // Remove closing fence
    if s.hasSuffix("```") {
        s = String(s.dropLast(3)).trimmingCharacters(in: .whitespacesAndNewlines)
    }
    return s.trimmingCharacters(in: .whitespacesAndNewlines)
}
