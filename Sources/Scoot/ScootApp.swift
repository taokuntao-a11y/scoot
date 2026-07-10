import ScootCore
import SwiftUI

@main
struct ScootApp: App {
    @StateObject private var sourceWatcher = SourceWatcher()
    @StateObject private var destinationStore = DestinationStore()
    @StateObject private var appModel = AppModel()
    @StateObject private var selectionStore = SelectionStore()

    var body: some Scene {
        // ── MenuBar panel ────────────────────────────────────────────────
        MenuBarExtra("Scoot", systemImage: "arrow.right.doc.on.clipboard") {
            panelContent
                .frame(width: 640, height: 520)
        }
        .menuBarExtraStyle(.window)

        // ── Main window (openWindow id: "main") ──────────────────────────
        Window("Scoot", id: "main") {
            panelContent
                .background(MainWindowObserverView())
                .frame(minWidth: 640, minHeight: 420)
        }
        .defaultSize(width: 720, height: 480)
        .windowResizability(.contentMinSize)
    }

    @ViewBuilder
    private var panelContent: some View {
        ContentView()
            .environmentObject(sourceWatcher)
            .environmentObject(destinationStore)
            .environmentObject(appModel)
            .environmentObject(selectionStore)
            .environmentObject(appModel.moveLog)
    }
}
