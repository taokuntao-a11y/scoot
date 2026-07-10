import AppKit
import ScootCore
import SwiftUI

// MARK: - ContentView

struct ContentView: View {
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
                // Left pane
                VStack(spacing: 0) {
                    PaneHeaderView(
                        title: "选中文件",
                        badge: selectionBadge
                    )
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
    @EnvironmentObject private var sourceWatcher: SourceWatcher
    @EnvironmentObject private var appModel: AppModel
    @Environment(\.openWindow) private var openWindow

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

            // Source folder picker
            Button {
                chooseSourceFolder()
            } label: {
                Label(
                    URL(fileURLWithPath: sourceWatcher.sourcePath).lastPathComponent,
                    systemImage: "folder"
                )
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

    private func chooseSourceFolder() {
        if let url = pickFolder(prompt: "选择源文件夹") {
            sourceWatcher.sourcePath = url.path
        }
    }
}
