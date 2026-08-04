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

    /// True while a Slim (compression) batch is running; separate from aiIsBusy
    /// since the two features are independent and shouldn't block each other's UI.
    @Published var slimIsBusy: Bool = false

    /// Action to cancel the current Slim task.
    var slimCancelAction: (() -> Void)?

    /// Non-nil for 1.6 s after a successful move/rename/undo; shown as bottom toast.
    @Published var toastMessage: String? = nil

    // MARK: - Watcher (weak; injected by ScootApp)

    weak var watcher: SourceWatcher?

    // MARK: - Private tasks

    private var completionTask: Task<Void, Never>?
    private var flashTask: Task<Void, Never>?
    private var toastTask: Task<Void, Never>?
    private var aiTimerTask: Task<Void, Never>?
    private var slimTask: Task<Void, Never>?

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

    // MARK: - Slim (compress)

    /// Compresses each slimmable file to a sibling "<stem>_slim<ext>" file via the
    /// bundled `slim` CLI. Runs sequentially and aggregates results into one toast +
    /// one moveLog batch. Slim never deletes/replaces the original, so no optimistic
    /// removal — the FS watcher will pick up the new "_slim" file on its own.
    func slim(_ items: [URL], quality: String = "balanced") {
        let targets = items.filter { SlimService.canSlim($0) }
        guard !targets.isEmpty else {
            errorMessage = "所选文件均不支持压缩"
            return
        }

        let service = SlimService()
        slimIsBusy = true
        errorMessage = nil

        let task = Task { @MainActor in
            defer {
                slimIsBusy = false
                slimCancelAction = nil
            }

            var successes: [(url: URL, result: SlimResult)] = []
            var failures: [(url: URL, error: any Error)] = []

            for item in targets {
                guard !Task.isCancelled else { return }
                let ext = item.pathExtension
                let stem = item.deletingPathExtension().lastPathComponent
                let dir = item.deletingLastPathComponent()
                let outputName = ext.isEmpty ? "\(stem)_slim" : "\(stem)_slim.\(ext)"
                let output = uniqueDestinationURL(for: outputName, in: dir)

                do {
                    let result = try await service.compress(item, to: output, quality: quality)
                    successes.append((url: item, result: result))
                } catch is CancellationError {
                    return
                } catch {
                    failures.append((url: item, error: error))
                }
            }

            guard !Task.isCancelled else { return }

            if !successes.isEmpty {
                let batchID = UUID()
                let logEntries = successes.map { pair in
                    LogEntry(
                        fileName: pair.url.lastPathComponent,
                        destName: "压缩",
                        batchID: batchID,
                        isUndo: false
                    )
                }
                moveLog.record(batch: logEntries)

                let savedMB = successes.reduce(0.0) { $0 + max(0, $1.result.inputSizeMB - $1.result.outputSizeMB) }
                showToast(String(format: "已压缩 %d 项，共省 %.1f MB", successes.count, savedMB))
                showCompletion(count: successes.count)
            }

            if !failures.isEmpty {
                let names = failures.map { $0.url.lastPathComponent }.joined(separator: ", ")
                errorMessage = "压缩失败: \(names)"
            }
        }
        slimTask = task
        slimCancelAction = { task.cancel() }
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
