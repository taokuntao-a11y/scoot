import AppKit
import ScootCore
import SwiftUI

struct ContentView: View {
    @EnvironmentObject private var sourceWatcher: SourceWatcher
    @EnvironmentObject private var destinationStore: DestinationStore
    @EnvironmentObject private var appModel: AppModel

    var body: some View {
        VStack(spacing: 0) {
            HStack(spacing: 0) {
                FileListView()
                    .frame(width: 340)
                Divider()
                DestinationGridView()
            }
            Divider()
            BottomBarView()
                .frame(height: 36)
        }
    }
}

struct BottomBarView: View {
    @EnvironmentObject private var sourceWatcher: SourceWatcher
    @EnvironmentObject private var appModel: AppModel

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

            // Error message
            if let msg = appModel.errorMessage {
                Text(msg)
                    .foregroundStyle(.red)
                    .font(.caption)
                    .lineLimit(1)
            }

            Spacer()

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
    }

    private func chooseSourceFolder() {
        let panel = NSOpenPanel()
        panel.canChooseDirectories = true
        panel.canChooseFiles = false
        panel.allowsMultipleSelection = false
        panel.prompt = "选择源文件夹"
        if panel.runModal() == .OK, let url = panel.url {
            sourceWatcher.sourcePath = url.path
        }
    }
}
