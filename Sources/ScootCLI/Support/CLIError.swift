import Foundation

/// A handled, user-facing CLI error. Carries a plain Chinese message (matching the
/// rest of ScootCore's error style) so `error.localizedDescription` reads cleanly
/// both on stderr (human mode) and inside `{"error": "..."}` (--json mode).
struct CLIError: Error, LocalizedError {
    let message: String

    init(_ message: String) {
        self.message = message
    }

    var errorDescription: String? { message }
}
