import Foundation

/// Shared stdout/stderr plumbing for every subcommand, implementing the JSON
/// contract mirrored from slim's CLI: with `--json`, stdout carries exactly one
/// JSON object and nothing else; without it, friendly text goes to stdout.
enum CLIOutput {
    static func printJSON<T: Encodable>(_ value: T) {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        encoder.outputFormatting = [.sortedKeys]
        guard let data = try? encoder.encode(value), let str = String(data: data, encoding: .utf8) else {
            print("{\"error\":\"JSON 编码失败\"}")
            return
        }
        print(str)
    }

    /// Reports a handled error and exits 1. In `--json` mode, prints a single
    /// `{"error": "..."}` object to stdout (per the JSON contract — errors are
    /// still "the" JSON object on stdout, not a second one). In human mode,
    /// prints "Error: ..." to stderr.
    static func fail(_ message: String, json: Bool) -> Never {
        if json {
            printJSON(["error": message])
        } else {
            FileHandle.standardError.write(Data("Error: \(message)\n".utf8))
        }
        exit(1)
    }
}
