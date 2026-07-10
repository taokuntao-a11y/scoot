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
}
