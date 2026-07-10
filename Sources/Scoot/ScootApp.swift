import ScootCore
import SwiftUI

@main
struct ScootApp: App {
    @StateObject private var sourceWatcher = SourceWatcher()
    @StateObject private var destinationStore = DestinationStore()
    @StateObject private var appModel = AppModel()
    @StateObject private var selectionStore = SelectionStore()

    var body: some Scene {
        MenuBarExtra("Scoot", systemImage: "arrow.right.doc.on.clipboard") {
            ContentView()
                .environmentObject(sourceWatcher)
                .environmentObject(destinationStore)
                .environmentObject(appModel)
                .environmentObject(selectionStore)
                .frame(width: 640, height: 420)
        }
        .menuBarExtraStyle(.window)
    }
}
