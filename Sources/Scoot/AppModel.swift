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

    /// True while an AI request is in flight; disables AI action buttons.
    @Published var aiIsBusy: Bool = false

    /// Elapsed seconds since AI request started; incremented every second while busy.
    @Published var aiElapsedSeconds: Int = 0

    /// Action to cancel the current AI task (set by AIActionsView).
    var aiCancelAction: (() -> Void)?

    /// Non-nil for 1.6 s after a successful move/rename/undo; shown as bottom toast.
    @Published var toastMessage: String? = nil

    // MARK: - Watcher (weak; injected by ScootApp)

    weak var watcher: SourceWatcher?

    // MARK: - Private tasks

    private var completionTask: Task<Void, Never>?
    private var flashTask: Task<Void, Never>?
    private var toastTask: Task<Void, Never>?
    private var aiTimerTask: Task<Void, Never>?

    // MARK: - Move

    func move(_ items: [URL], to destination: Destination) {
        let result = engine.move(items, to: destination.url)
        canUndo = engine.canUndo
        lastBatchDescription = engine.lastBatchDescription
        errorMessage = result.errorSummary

        if !result.moved.isEmpty {
            // Optimistic removal from the file list
            watcher?.removeImmediately(result.moved.map(\.from))

            // Batch log
            let batchID = UUID()
            let logEntries = result.moved.map { pair in
                LogEntry(
                    fileName: pair.from.lastPathComponent,
                    destName: destination.name,
                    batchID: batchID,
                    isUndo: false
                )
            }
            moveLog.record(batch: logEntries)

            // Toast
            let destName = destination.name
            showToast("已移动 \(result.moved.count) 项 → \(destName)")

            showCompletion(count: result.moved.count)
        }
    }

    // MARK: - Undo

    func undo() {
        guard let result = engine.undo() else { return }
        canUndo = engine.canUndo
        lastBatchDescription = engine.lastBatchDescription
        errorMessage = result.errorSummary

        if !result.moved.isEmpty {
            // Undo restores files to original location — no optimistic removal.
            // FS event will trigger a reload; just show a toast.
            let batchID = UUID()
            let logEntries = result.moved.map { pair in
                LogEntry(
                    fileName: pair.from.lastPathComponent,
                    destName: pair.from.deletingLastPathComponent().lastPathComponent,
                    batchID: batchID,
                    isUndo: true
                )
            }
            moveLog.record(batch: logEntries)

            showToast("已撤销 \(result.moved.count) 项")
        }
    }

    // MARK: - Rename

    /// Rename files in-place via MoveEngine and record log entries.
    func rename(_ pairs: [(url: URL, newName: String)]) {
        let result = engine.rename(pairs)
        canUndo = engine.canUndo
        lastBatchDescription = engine.lastBatchDescription
        errorMessage = result.errorSummary

        if !result.moved.isEmpty {
            // Optimistic removal (renamed file stays in same folder but appears under new name;
            // removing it avoids a stale row until the FS event fires).
            watcher?.removeImmediately(result.moved.map(\.from))

            let batchID = UUID()
            let logEntries = result.moved.map { pair in
                LogEntry(
                    fileName: pair.from.lastPathComponent,
                    destName: "重命名",
                    batchID: batchID,
                    isUndo: false
                )
            }
            moveLog.record(batch: logEntries)

            showToast("已重命名 \(result.moved.count) 项")
            showCompletion(count: result.moved.count)
        }
    }

    // MARK: - AI busy timer

    func startAIBusy() {
        aiIsBusy = true
        aiElapsedSeconds = 0
        aiTimerTask?.cancel()
        aiTimerTask = Task { @MainActor in
            while !Task.isCancelled {
                try? await Task.sleep(nanoseconds: 1_000_000_000)
                guard !Task.isCancelled else { break }
                aiElapsedSeconds += 1
            }
        }
    }

    func stopAIBusy() {
        aiTimerTask?.cancel()
        aiTimerTask = nil
        aiIsBusy = false
        aiElapsedSeconds = 0
        aiCancelAction = nil
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

    private func showToast(_ message: String) {
        toastMessage = message
        toastTask?.cancel()
        toastTask = Task { @MainActor in
            try? await Task.sleep(nanoseconds: 1_600_000_000)
            guard !Task.isCancelled else { return }
            toastMessage = nil
        }
    }
}
