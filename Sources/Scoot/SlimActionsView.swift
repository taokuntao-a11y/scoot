import ScootCore
import SwiftUI

// MARK: - SlimActionsView

/// Bottom-bar "瘦身" (Slim) action: a Menu button offering three quality levels.
/// Compresses the current selection via the bundled `slim` CLI subprocess.
struct SlimActionsView: View {
    @EnvironmentObject private var appModel: AppModel
    @EnvironmentObject private var selectionStore: SelectionStore

    private var slimmableSelection: [URL] {
        selectionStore.selection.filter { SlimService.canSlim($0) }
    }

    private var hasSlimmableSelection: Bool { !slimmableSelection.isEmpty }

    var body: some View {
        Menu {
            Button("高质量 (high)") { runSlim(quality: "high") }
            Button("均衡 (balanced)") { runSlim(quality: "balanced") }
            Button("极限压缩 (extreme)") { runSlim(quality: "extreme") }
        } label: {
            if appModel.slimIsBusy {
                ProgressView().scaleEffect(0.6).frame(width: 14, height: 14)
            } else {
                Text("🗜 瘦身")
            }
        }
        .disabled(appModel.slimIsBusy || !hasSlimmableSelection)
        .help(helpText)
        .fixedSize()
    }

    private var helpText: String {
        if selectionStore.selection.isEmpty {
            return "请先选择文件 (支持 PDF / PPTX / 图片)"
        }
        if !hasSlimmableSelection {
            return "所选文件不支持压缩 (支持 PDF / PPTX / 图片)"
        }
        return "压缩所选文件，生成 _slim 副本"
    }

    private func runSlim(quality: String) {
        appModel.slim(slimmableSelection, quality: quality)
    }
}
