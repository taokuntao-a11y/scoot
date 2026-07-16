@preconcurrency import KeyboardShortcuts
import MenuBarExtraAccess
import ScootCore
import SwiftUI

@main
struct ScootApp: App {
    @StateObject private var sourceStore: SourceStore
    @StateObject private var sourceWatcher: SourceWatcher
    @StateObject private var destinationStore = DestinationStore()
    @StateObject private var appModel = AppModel()
    @StateObject private var selectionStore = SelectionStore()

    // Observed (not @State) so the hotkey callback can flip panel visibility
    // from outside the view hierarchy and still invalidate the scene.
    @ObservedObject private var hotkeyController = AppHotkeyController.shared

    init() {
        // Build SourceStore first so we can seed SourceWatcher with the active path.
        let store = SourceStore()
        _sourceStore = StateObject(wrappedValue: store)
        _sourceWatcher = StateObject(wrappedValue: SourceWatcher(path: store.activeSource.path))

        // Register hotkey handler once at app launch (not inside body to avoid repeat registration).
        KeyboardShortcuts.onKeyUp(for: .togglePanel) {
            AppHotkeyController.shared.toggle()
        }
    }

    var body: some Scene {
        // ── MenuBar panel ────────────────────────────────────────────────
        MenuBarExtra("Scoot", systemImage: "arrow.right.doc.on.clipboard") {
            panelContent
                .frame(width: 640, height: 520)
        }
        .menuBarExtraAccess(isPresented: $hotkeyController.isPanelPresented)
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
            .environmentObject(sourceStore)
            .environmentObject(sourceWatcher)
            .environmentObject(destinationStore)
            .environmentObject(appModel)
            .environmentObject(selectionStore)
            .environmentObject(appModel.moveLog)
    }
}

// MARK: - AppHotkeyController

/// Holds MenuBarExtra panel visibility. The hotkey callback lives outside the
/// view hierarchy, so the state must be on an ObservableObject the App observes;
/// MenuBarExtraAccess writes back through the binding on click-open/close.
@MainActor
final class AppHotkeyController: ObservableObject {
    static let shared = AppHotkeyController()

    @Published var isPanelPresented = false

    private init() {}

    func toggle() {
        if isPanelPresented {
            isPanelPresented = false
        } else {
            NSApp.activate(ignoringOtherApps: true)
            isPanelPresented = true
        }
    }
}
