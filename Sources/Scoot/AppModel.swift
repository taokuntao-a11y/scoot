import Combine
import Foundation
import ScootCore
import SwiftUI

/// Observable wrapper around MoveEngine that publishes undo state.
@MainActor
final class AppModel: ObservableObject {
    let engine = MoveEngine()

    @Published var canUndo: Bool = false
    @Published var lastBatchDescription: String? = nil
    @Published var errorMessage: String? = nil
    @Published var hintMessage: String? = nil

    private var hintTask: Task<Void, Never>? = nil

    func move(_ items: [URL], to destination: Destination) {
        let result = engine.move(items, to: destination.url)
        canUndo = engine.canUndo
        lastBatchDescription = engine.lastBatchDescription
        errorMessage = result.errorSummary
    }

    func undo() {
        let result = engine.undo()
        canUndo = engine.canUndo
        lastBatchDescription = engine.lastBatchDescription
        errorMessage = result?.errorSummary
    }

    /// Shows a transient hint message that auto-clears after 2 seconds.
    func showHint(_ message: String) {
        hintMessage = message
        hintTask?.cancel()
        hintTask = Task { @MainActor in
            try? await Task.sleep(nanoseconds: 2_000_000_000)
            guard !Task.isCancelled else { return }
            hintMessage = nil
        }
    }
}
