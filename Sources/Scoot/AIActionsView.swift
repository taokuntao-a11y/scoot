import ScootCore
import SwiftUI

// MARK: - AIActionsView

/// Bottom-bar AI action buttons: "AI 分拣" and "AI 重命名".
struct AIActionsView: View {
    @EnvironmentObject private var appModel: AppModel
    @EnvironmentObject private var aiConfig: AIConfigStore
    @EnvironmentObject private var destinationStore: DestinationStore
    @EnvironmentObject private var sourceWatcher: SourceWatcher
    @EnvironmentObject private var selectionStore: SelectionStore

    @State private var showArchiveSheet = false
    @State private var showRenameSheet = false
    @State private var showSettingsPopover = false

    @State private var archiveSuggestions: [(file: String, dest: String?)] = []
    @State private var renameSuggestions: [(file: String, newName: String)] = []

    @State private var aiTask: Task<Void, Never>?

    var body: some View {
        HStack(spacing: 6) {
            // AI 分拣
            Button {
                handleArchive()
            } label: {
                if appModel.aiIsBusy {
                    ProgressView().scaleEffect(0.6).frame(width: 14, height: 14)
                } else {
                    Text("✨ AI 分拣")
                }
            }
            .disabled(appModel.aiIsBusy || destinationStore.destinations.isEmpty)
            .help(destinationStore.destinations.isEmpty ? "请先添加目标文件夹" : "AI 归档建议")
            .sheet(isPresented: $showArchiveSheet) {
                ArchivePreviewSheet(suggestions: $archiveSuggestions)
            }

            // AI 重命名
            Button {
                handleRename()
            } label: {
                if appModel.aiIsBusy {
                    ProgressView().scaleEffect(0.6).frame(width: 14, height: 14)
                } else {
                    Text("✎ AI 重命名")
                }
            }
            .disabled(appModel.aiIsBusy || selectionStore.selection.isEmpty)
            .help(selectionStore.selection.isEmpty ? "请先选择文件" : "AI 智能重命名")
            .sheet(isPresented: $showRenameSheet) {
                RenamePreviewSheet(suggestions: $renameSuggestions)
            }
        }
        // Settings popover when no API key is configured
        .popover(isPresented: $showSettingsPopover, arrowEdge: .top) {
            SettingsView()
        }
    }

    // MARK: - Archive action

    private func handleArchive() {
        guard aiConfig.hasKey else {
            showSettingsPopover = true
            return
        }
        guard let llm = aiConfig.makeLLMService() else {
            appModel.errorMessage = "AI 未配置，请在设置中填写 API Key"
            return
        }

        let targets: [String] = destinationStore.destinations.map { $0.name }
        guard !targets.isEmpty else {
            appModel.errorMessage = "请先添加目标文件夹"
            return
        }

        // Collect files: selected or all (capped at 30)
        let files: [URL]
        if !selectionStore.selection.isEmpty {
            files = Array(selectionStore.selection.prefix(30))
        } else {
            files = Array(sourceWatcher.files.map { $0.url }.prefix(30))
        }
        guard !files.isEmpty else { return }

        let fileNames = files.map { $0.lastPathComponent }
        let suggester = ArchiveSuggester(llm: llm)

        appModel.startAIBusy()
        appModel.errorMessage = nil

        let task = Task { @MainActor in
            defer { appModel.stopAIBusy() }
            do {
                let raw = try await suggester.suggest(fileNames: fileNames, destinations: targets)
                guard !Task.isCancelled else { return }
                archiveSuggestions = raw
                showArchiveSheet = true
            } catch is CancellationError {
                // Silent — user cancelled intentionally
            } catch {
                appModel.errorMessage = error.localizedDescription
            }
        }
        aiTask = task
        appModel.aiCancelAction = { task.cancel() }
    }

    // MARK: - Rename action

    private func handleRename() {
        guard aiConfig.hasKey else {
            showSettingsPopover = true
            return
        }
        guard let llm = aiConfig.makeLLMService() else {
            appModel.errorMessage = "AI 未配置，请在设置中填写 API Key"
            return
        }

        let files = Array(selectionStore.selection.prefix(30))
        guard !files.isEmpty else { return }

        let fileNames = files.map { $0.lastPathComponent }
        let suggester = RenameSuggester(llm: llm)

        appModel.startAIBusy()
        appModel.errorMessage = nil

        let task = Task { @MainActor in
            defer { appModel.stopAIBusy() }
            do {
                let raw = try await suggester.suggest(fileNames: fileNames)
                guard !Task.isCancelled else { return }
                renameSuggestions = raw
                showRenameSheet = true
            } catch is CancellationError {
                // Silent — user cancelled intentionally
            } catch {
                appModel.errorMessage = error.localizedDescription
            }
        }
        aiTask = task
        appModel.aiCancelAction = { task.cancel() }
    }
}

// MARK: - ArchivePreviewSheet

/// Shows LLM archive suggestions; user can adjust dest and toggle inclusion before confirming.
struct ArchivePreviewSheet: View {
    @Binding var suggestions: [(file: String, dest: String?)]
    @EnvironmentObject private var appModel: AppModel
    @EnvironmentObject private var destinationStore: DestinationStore
    @EnvironmentObject private var sourceWatcher: SourceWatcher
    @EnvironmentObject private var selectionStore: SelectionStore
    @Environment(\.dismiss) private var dismiss

    // Local editable state: (fileName, chosenDest, isChecked)
    @State private var rows: [ArchiveRow] = []

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            // Header
            HStack {
                Text("AI 分拣建议")
                    .font(.headline)
                Spacer()
                Button("取消") { dismiss() }
            }
            .padding()

            Divider()

            // Row list
            ScrollView {
                VStack(spacing: 0) {
                    ForEach($rows) { $row in
                        HStack(spacing: 10) {
                            Toggle("", isOn: $row.isChecked)
                                .toggleStyle(.checkbox)
                                .labelsHidden()

                            Text(row.fileName)
                                .lineLimit(1)
                                .truncationMode(.middle)
                                .frame(maxWidth: .infinity, alignment: .leading)

                            Image(systemName: "arrow.right")
                                .foregroundStyle(.secondary)
                                .font(.caption)

                            Picker("", selection: $row.chosenDest) {
                                ForEach(destinationStore.destinations) { dest in
                                    Text(dest.name).tag(dest.name as String?)
                                }
                                Text("— 跳过 —").tag(nil as String?)
                            }
                            .labelsHidden()
                            .frame(width: 150)
                        }
                        .padding(.horizontal)
                        .padding(.vertical, 6)
                        Divider().padding(.horizontal)
                    }
                }
            }

            Divider()

            // Footer
            HStack {
                Text("AI 只根据文件名推断，不读取文件内容")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Spacer()
                Button("取消") { dismiss() }
                Button("移动 \(checkedCount) 项") {
                    executeArchive()
                }
                .disabled(checkedCount == 0)
                .keyboardShortcut(.return, modifiers: [])
            }
            .padding()
        }
        .frame(width: 520, height: 400)
        .onAppear { buildRows() }
    }

    private var checkedCount: Int { rows.filter { $0.isChecked }.count }

    private func buildRows() {
        // Build a lookup: fileName → URL
        let allFiles: [URL]
        if !selectionStore.selection.isEmpty {
            allFiles = Array(selectionStore.selection)
        } else {
            allFiles = sourceWatcher.files.map { $0.url }
        }
        let fileMap: [String: URL] = Dictionary(
            allFiles.map { ($0.lastPathComponent, $0) },
            uniquingKeysWith: { first, _ in first }
        )

        rows = suggestions.compactMap { suggestion in
            guard fileMap[suggestion.file] != nil else { return nil }
            // Default checked only when LLM is confident (dest != nil)
            return ArchiveRow(
                fileName: suggestion.file,
                chosenDest: suggestion.dest ?? destinationStore.destinations.first?.name,
                isChecked: suggestion.dest != nil
            )
        }
    }

    private func executeArchive() {
        // Build: dest name → [URL]
        let allFiles: [URL]
        if !selectionStore.selection.isEmpty {
            allFiles = Array(selectionStore.selection)
        } else {
            allFiles = sourceWatcher.files.map { $0.url }
        }
        let fileMap: [String: URL] = Dictionary(
            allFiles.map { ($0.lastPathComponent, $0) },
            uniquingKeysWith: { first, _ in first }
        )

        // Group by destination
        var groups: [String: [URL]] = [:]
        for row in rows where row.isChecked {
            guard let destName = row.chosenDest,
                  let fileURL = fileMap[row.fileName] else { continue }
            groups[destName, default: []].append(fileURL)
        }

        // Execute per-destination (each is its own undo batch, per spec)
        for destName in groups.keys {
            guard let dest = destinationStore.destinations.first(where: { $0.name == destName }) else { continue }
            let items = groups[destName]!
            appModel.move(items, to: dest)
        }

        dismiss()
    }
}

// MARK: ArchiveRow

private struct ArchiveRow: Identifiable {
    let id = UUID()
    let fileName: String
    var chosenDest: String?
    var isChecked: Bool
}

// MARK: - RenamePreviewSheet

/// Shows LLM rename suggestions; user can edit new names and toggle inclusion.
struct RenamePreviewSheet: View {
    @Binding var suggestions: [(file: String, newName: String)]
    @EnvironmentObject private var appModel: AppModel
    @EnvironmentObject private var sourceWatcher: SourceWatcher
    @EnvironmentObject private var selectionStore: SelectionStore
    @Environment(\.dismiss) private var dismiss

    @State private var rows: [RenameRow] = []

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            // Header
            HStack {
                Text("AI 重命名建议")
                    .font(.headline)
                Spacer()
                Button("取消") { dismiss() }
            }
            .padding()

            Divider()

            // Row list
            ScrollView {
                VStack(spacing: 0) {
                    ForEach($rows) { $row in
                        HStack(spacing: 10) {
                            Toggle("", isOn: $row.isChecked)
                                .toggleStyle(.checkbox)
                                .labelsHidden()

                            Text(row.originalName)
                                .lineLimit(1)
                                .truncationMode(.middle)
                                .frame(maxWidth: .infinity, alignment: .leading)

                            Image(systemName: "arrow.right")
                                .foregroundStyle(.secondary)
                                .font(.caption)

                            TextField("新文件名", text: $row.newName)
                                .textFieldStyle(.roundedBorder)
                                .frame(width: 200)
                        }
                        .padding(.horizontal)
                        .padding(.vertical, 6)
                        Divider().padding(.horizontal)
                    }
                }
            }

            Divider()

            // Footer
            HStack {
                Text("AI 只根据文件名推断，不读取文件内容")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Spacer()
                Button("取消") { dismiss() }
                Button("重命名 \(checkedCount) 项") {
                    executeRename()
                }
                .disabled(checkedCount == 0)
                .keyboardShortcut(.return, modifiers: [])
            }
            .padding()
        }
        .frame(width: 560, height: 400)
        .onAppear { buildRows() }
    }

    private var checkedCount: Int { rows.filter { $0.isChecked }.count }

    private func buildRows() {
        let selectedURLs = Array(selectionStore.selection)
        let fileMap: [String: URL] = Dictionary(
            selectedURLs.map { ($0.lastPathComponent, $0) },
            uniquingKeysWith: { first, _ in first }
        )

        rows = suggestions.compactMap { s in
            guard fileMap[s.file] != nil else { return nil }
            return RenameRow(originalName: s.file, newName: s.newName, isChecked: true)
        }
    }

    private func executeRename() {
        let selectedURLs = Array(selectionStore.selection)
        let fileMap: [String: URL] = Dictionary(
            selectedURLs.map { ($0.lastPathComponent, $0) },
            uniquingKeysWith: { first, _ in first }
        )

        // Collect checked rows and validate again before executing
        var pairs: [(url: URL, newName: String)] = []
        var seenNames: Set<String> = Set(
            // Names of files NOT being renamed (collision check); lowercased to
            // match the case-insensitive lookups below
            selectedURLs
                .map { $0.lastPathComponent }
                .filter { name in !rows.contains { $0.isChecked && $0.originalName == name } }
                .map { $0.lowercased() }
        )

        for row in rows where row.isChecked {
            guard let url = fileMap[row.originalName] else { continue }
            let trimmed = row.newName.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !trimmed.isEmpty,
                  !trimmed.contains("/"),
                  !trimmed.contains("\\"),
                  !trimmed.contains(":") else { continue }
            guard trimmed.count <= 80 else { continue }
            // Collision with non-selected files or earlier rows
            guard !seenNames.contains(trimmed.lowercased()) else { continue }
            seenNames.insert(trimmed.lowercased())
            pairs.append((url: url, newName: trimmed))
        }

        if !pairs.isEmpty {
            appModel.rename(pairs)
        }

        dismiss()
    }
}

// MARK: RenameRow

private struct RenameRow: Identifiable {
    let id = UUID()
    let originalName: String
    var newName: String
    var isChecked: Bool
}
