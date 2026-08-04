import AppKit
import KeyboardShortcuts
import ScootCore
import SwiftUI

// MARK: - ContentView

struct ContentView: View {
    @EnvironmentObject private var sourceStore: SourceStore
    @EnvironmentObject private var sourceWatcher: SourceWatcher
    @EnvironmentObject private var destinationStore: DestinationStore
    @EnvironmentObject private var appModel: AppModel
    @EnvironmentObject private var selectionStore: SelectionStore

    var body: some View {
        ZStack(alignment: .bottom) {
            // MARK: Main panel content
            VStack(spacing: 0) {
                // ① StepperBar — top full-width strip
                StepperBar()
                Divider()

                // ② Split pane with headers
                HStack(spacing: 0) {
                    // Left pane — source switcher header
                    VStack(spacing: 0) {
                        SourceHeaderView(badge: selectionBadge)
                        Divider()
                        FileListView()
                    }
                    .frame(width: 320)

                    Divider()

                    // Right pane
                    VStack(spacing: 0) {
                        PaneHeaderView(title: "目标位置") {
                            Button {
                                addDestination()
                            } label: {
                                Image(systemName: "plus")
                                    .font(.caption)
                                    .padding(4)
                            }
                            .buttonStyle(.plain)
                            .help("添加目标文件夹")
                        }
                        Divider()
                        DestinationGridView()
                    }
                }

                Divider()

                // ③ MoveLog drawer
                MoveLogDrawer()

                Divider()

                // ④ Bottom bar
                BottomBarView()
                    .frame(height: 36)
            }
            // Sync activeSource → watcher + clear selection. Lives here (not on the
            // MenuBarExtra scene) so it also fires when the source is switched from
            // the main window; guarded so panel + main window don't double-apply.
            .onChange(of: sourceStore.activeSource) { newSource in
                guard sourceWatcher.sourcePath != newSource.path else { return }
                sourceWatcher.sourcePath = newSource.path
                selectionStore.selection = []
            }

            // MARK: AI busy overlay
            if appModel.aiIsBusy {
                ZStack {
                    Color.black.opacity(0.35)
                        .ignoresSafeArea()
                    VStack(spacing: 12) {
                        ProgressView()
                            .scaleEffect(1.2)
                        Text("AI 思考中… \(appModel.aiElapsedSeconds) 秒")
                            .foregroundStyle(.white)
                            .font(.subheadline)
                        Button("取消") {
                            appModel.aiCancelAction?()
                        }
                        .buttonStyle(.borderedProminent)
                        .tint(.white.opacity(0.25))
                        .foregroundStyle(.white)
                    }
                }
                .transition(.opacity)
            }

            // MARK: Toast
            if let msg = appModel.toastMessage {
                HStack(spacing: 6) {
                    Image(systemName: "checkmark.circle.fill")
                        .foregroundStyle(.green)
                    Text(msg)
                        .font(.subheadline)
                        .foregroundStyle(.primary)
                }
                .padding(.horizontal, 16)
                .padding(.vertical, 10)
                .background(.regularMaterial, in: Capsule())
                .shadow(radius: 4)
                .padding(.bottom, 44)
                .allowsHitTesting(false)
                .transition(.asymmetric(
                    insertion: .scale(scale: 0.85).combined(with: .opacity),
                    removal: .opacity
                ))
                .id(msg)
            }
        }
        .animation(.spring(response: 0.35, dampingFraction: 0.75), value: appModel.toastMessage)
        .animation(.easeInOut(duration: 0.2), value: appModel.aiIsBusy)
    }

    // MARK: - Helpers

    private var selectionBadge: String {
        let n = selectionStore.selection.count
        if n > 0 { return "已选 \(n)" }
        let total = sourceWatcher.files.count
        return total > 0 ? "共 \(total) 项" : ""
    }

    private func addDestination() {
        if let url = pickFolder(prompt: "添加目标文件夹") {
            destinationStore.add(url: url)
        }
    }
}

// MARK: - SourceHeaderView

/// Left-pane header: source folder switcher menu + badge.
struct SourceHeaderView: View {
    @EnvironmentObject private var sourceStore: SourceStore
    @EnvironmentObject private var selectionStore: SelectionStore

    var badge: String

    var body: some View {
        HStack(spacing: 6) {
            SourceMenuView()

            if !badge.isEmpty {
                Text(badge)
                    .font(.caption2)
                    .padding(.horizontal, 5)
                    .padding(.vertical, 2)
                    .background(Color.secondary.opacity(0.18), in: Capsule())
                    .foregroundStyle(.secondary)
            }

            Spacer()
        }
        .padding(.horizontal, 10)
        .frame(height: 28)
    }
}

// MARK: - SourceMenuView

/// Drop-down Menu that shows the current source and lets the user switch / add / remove.
struct SourceMenuView: View {
    @EnvironmentObject private var sourceStore: SourceStore
    @EnvironmentObject private var selectionStore: SelectionStore

    var body: some View {
        Menu {
            // Source items with checkmark on active
            ForEach(sourceStore.sources) { folder in
                Button {
                    sourceStore.activeSource = folder
                } label: {
                    if folder.id == sourceStore.activeSource.id {
                        Label(folder.name, systemImage: "checkmark")
                    } else {
                        Text(folder.name)
                    }
                }
            }

            Divider()

            Button("添加源文件夹…") {
                if let url = pickFolder(prompt: "选择源文件夹") {
                    sourceStore.add(url: url)
                }
            }

            if sourceStore.sources.count > 1 {
                Button("移除当前源") {
                    sourceStore.remove(sourceStore.activeSource)
                }
            }
        } label: {
            HStack(spacing: 3) {
                Text(sourceStore.activeSource.name)
                    .font(.subheadline)
                    .fontWeight(.medium)
                Image(systemName: "chevron.down")
                    .font(.caption2)
            }
        }
        .menuStyle(.borderlessButton)
        .fixedSize()
    }
}

// MARK: - PaneHeaderView

struct PaneHeaderView<Trailing: View>: View {
    let title: String
    var badge: String = ""
    @ViewBuilder var trailing: () -> Trailing

    init(
        title: String,
        badge: String = "",
        @ViewBuilder trailing: @escaping () -> Trailing
    ) {
        self.title = title
        self.badge = badge
        self.trailing = trailing
    }

    var body: some View {
        HStack(spacing: 6) {
            Text(title)
                .font(.subheadline)
                .fontWeight(.medium)

            if !badge.isEmpty {
                Text(badge)
                    .font(.caption2)
                    .padding(.horizontal, 5)
                    .padding(.vertical, 2)
                    .background(Color.secondary.opacity(0.18), in: Capsule())
                    .foregroundStyle(.secondary)
            }

            Spacer()

            trailing()
        }
        .padding(.horizontal, 10)
        .frame(height: 28)
    }
}

// Convenience init for header without trailing button
extension PaneHeaderView where Trailing == EmptyView {
    init(title: String, badge: String = "") {
        self.title = title
        self.badge = badge
        self.trailing = { EmptyView() }
    }
}

// MARK: - BottomBarView

struct BottomBarView: View {
    @EnvironmentObject private var appModel: AppModel
    @EnvironmentObject private var aiConfig: AIConfigStore
    @Environment(\.openWindow) private var openWindow

    @State private var showSettingsPopover = false

    var body: some View {
        HStack(spacing: 8) {
            // Undo button
            Button {
                appModel.undo()
            } label: {
                Label(
                    appModel.lastBatchDescription.map { "撤销 \($0)" } ?? "撤销",
                    systemImage: "arrow.uturn.backward"
                )
            }
            .disabled(!appModel.canUndo)

            // Error message (hint replaced by StepperBar)
            if let msg = appModel.errorMessage {
                Text(msg)
                    .foregroundStyle(.red)
                    .font(.caption)
                    .lineLimit(1)
            }

            Spacer()

            // AI action buttons
            AIActionsView()

            // Slim (compress) action
            SlimActionsView()

            Spacer()

            // Open main window
            Button {
                openWindow(id: "main")
            } label: {
                Image(systemName: "arrow.up.left.and.arrow.down.right")
                    .help("在独立窗口打开")
            }
            .buttonStyle(.plain)

            // Settings (gear) → two-section settings popover
            Button {
                showSettingsPopover.toggle()
            } label: {
                Image(systemName: "gearshape")
                    .help("设置")
            }
            .buttonStyle(.plain)
            .popover(isPresented: $showSettingsPopover, arrowEdge: .top) {
                SettingsView()
                    .environmentObject(aiConfig)
            }

            // Quit
            Button("退出") {
                NSApplication.shared.terminate(nil)
            }
        }
        .padding(.horizontal, 10)
        .buttonStyle(.plain)
        .animation(.easeInOut(duration: 0.2), value: appModel.errorMessage)
    }
}

// MARK: - SettingsView

/// Two-section settings popover: 快捷键 + AI 配置.
struct SettingsView: View {
    @EnvironmentObject private var aiConfig: AIConfigStore

    @State private var pendingKey: String = ""
    @State private var baseURLInput: String = ""
    @State private var modelInput: String = ""

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {

                // MARK: 快捷键
                Group {
                    Text("快捷键")
                        .font(.headline)
                    Divider()
                    KeyboardShortcuts.Recorder("呼出面板", name: .togglePanel)
                    Text("在任意应用前台按下快捷键即可呼出/收起 Scoot 面板")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }

                // MARK: AI 配置
                Group {
                    Text("AI 配置")
                        .font(.headline)
                    Divider()

                    // API Key row
                    if aiConfig.hasKey {
                        HStack {
                            Text("API Key")
                                .frame(width: 80, alignment: .leading)
                            Text("已配置 ●●●●●●●●")
                                .foregroundStyle(.secondary)
                            Spacer()
                            Button("清除") {
                                aiConfig.clearKey()
                                pendingKey = ""
                            }
                            .foregroundStyle(.red)
                        }
                    } else {
                        VStack(alignment: .leading, spacing: 4) {
                            Text("API Key")
                            SecureField("粘贴 Anthropic API Key", text: $pendingKey)
                                .textFieldStyle(.roundedBorder)
                            Button("保存") {
                                aiConfig.setKey(pendingKey)
                                pendingKey = ""
                            }
                            .disabled(pendingKey.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                        }
                    }

                    // Base URL
                    VStack(alignment: .leading, spacing: 4) {
                        Text("Base URL")
                        TextField(AIConfigStore.defaultBaseURL, text: $baseURLInput)
                            .textFieldStyle(.roundedBorder)
                            .onChange(of: baseURLInput) { val in
                                aiConfig.baseURL = val.isEmpty ? AIConfigStore.defaultBaseURL : val
                            }
                    }

                    // Model
                    VStack(alignment: .leading, spacing: 4) {
                        Text("模型名称")
                        TextField(AIConfigStore.defaultModel, text: $modelInput)
                            .textFieldStyle(.roundedBorder)
                            .onChange(of: modelInput) { val in
                                aiConfig.model = val.isEmpty ? AIConfigStore.defaultModel : val
                            }
                    }

                    Text("Key 保存在本机 Application Support，仅当前用户可读；不会上传")
                        .font(.caption)
                        .foregroundStyle(.secondary)

                    Text("AI 功能只发送文件名和目标文件夹名，不读取文件内容")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
            .padding()
        }
        .frame(width: 340)
        .onAppear {
            // Populate editable fields from current config
            baseURLInput = aiConfig.baseURL == AIConfigStore.defaultBaseURL ? "" : aiConfig.baseURL
            modelInput = aiConfig.model == AIConfigStore.defaultModel ? "" : aiConfig.model
        }
    }
}
