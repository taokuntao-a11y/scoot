import Combine
import Foundation
import ScootCore
import SwiftUI

/// Observable wrapper around MoveEngine that publishes undo state and move log.
@MainActor
final class AppModel: ObservableObject {
    let engine = MoveEngine()
    let moveLog = MoveLog()

    @Published var canUndo: Bool = false
    @Published var lastBatchDescription: String? = nil
    @Published var errorMessage: String? = nil

    /// Non-nil for 2 s after a successful move; drives StepperBar step-3 completion state.
    @Published var completionMoveCount: Int? = nil

    /// Briefly true when a tile is tapped with no selection; StepperBar flashes step ①.
    @Published var stepOneFlash: Bool = false

    private var completionTask: Task<Void, Never>?
    private var flashTask: Task<Void, Never>?

    // MARK: - Move

    func move(_ items: [URL], to destination: Destination) {
        let result = engine.move(items, to: destination.url)
        canUndo = engine.canUndo
        lastBatchDescription = engine.lastBatchDescription
        errorMessage = result.errorSummary

        // Log each moved file
        let batchID = UUID()
        for pair in result.moved {
            moveLog.record(
                LogEntry(
                    fileName: pair.from.lastPathComponent,
                    destName: destination.name,
                    batchID: batchID,
                    isUndo: false
                )
            )
        }

        // Drive StepperBar step-3 completion state
        if !result.moved.isEmpty {
            showCompletion(count: result.moved.count)
        }
    }

    // MARK: - Undo

    func undo() {
        guard let result = engine.undo() else { return }
        canUndo = engine.canUndo
        lastBatchDescription = engine.lastBatchDescription
        errorMessage = result.errorSummary

        // Log undo entries (pair.from = file in dest folder; pair.to = restored location)
        let batchID = UUID()
        for pair in result.moved {
            moveLog.record(
                LogEntry(
                    fileName: pair.from.lastPathComponent,
                    destName: pair.from.deletingLastPathComponent().lastPathComponent,
                    batchID: batchID,
                    isUndo: true
                )
            )
        }
    }

    // MARK: - StepperBar helpers

    /// Triggers step-① flash for ~0.5 s (tile tapped with no selection).
    func flashStepOne() {
        stepOneFlash = true
        flashTask?.cancel()
        flashTask = Task { @MainActor in
            try? await Task.sleep(nanoseconds: 500_000_000)
            guard !Task.isCancelled else { return }
            stepOneFlash = false
        }
    }

    private func showCompletion(count: Int) {
        completionMoveCount = count
        completionTask?.cancel()
        completionTask = Task { @MainActor in
            try? await Task.sleep(nanoseconds: 2_000_000_000)
            guard !Task.isCancelled else { return }
            completionMoveCount = nil
        }
    }
}
