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

            // Open main window
            Button {
                openWindow(id: "main")
            } label: {
                Image(systemName: "arrow.up.left.and.arrow.down.right")
                    .help("在独立窗口打开")
            }
            .buttonStyle(.plain)

            // Settings (gear) → quick shortcut recorder popover
            Button {
                showSettingsPopover.toggle()
            } label: {
                Image(systemName: "gearshape")
                    .help("设置")
            }
            .buttonStyle(.plain)
            .popover(isPresented: $showSettingsPopover, arrowEdge: .top) {
                ShortcutSettingsView()
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

// MARK: - ShortcutSettingsView

struct ShortcutSettingsView: View {
    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("快捷键设置")
                .font(.headline)
            Divider()
            KeyboardShortcuts.Recorder("呼出面板", name: .togglePanel)
            Text("在任意应用前台按下快捷键即可呼出/收起 Scoot 面板")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .padding()
        .frame(width: 300)
    }
}
