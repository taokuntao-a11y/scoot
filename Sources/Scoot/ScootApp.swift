@preconcurrency import KeyboardShortcuts
import MenuBarExtraAccess
import ScootCore
import SwiftUI

@main
struct ScootApp: App {
    @StateObject private var sourceStore: SourceStore
    @StateObject private var sourceWatcher: SourceWatcher
    @StateObject private var destinationStore = DestinationStore()
    @StateObject private var appModel: AppModel
    @StateObject private var selectionStore = SelectionStore()
    @StateObject private var aiConfig = AIConfigStore()

    // Observed (not @State) so the hotkey callback can flip panel visibility
    // from outside the view hierarchy and still invalidate the scene.
    @ObservedObject private var hotkeyController = AppHotkeyController.shared

    init() {
        // Build SourceStore first so we can seed SourceWatcher with the active path.
        let store = SourceStore()
        let watcher = SourceWatcher(path: store.activeSource.path)
        let model = AppModel()
        model.watcher = watcher
        _sourceStore = StateObject(wrappedValue: store)
        _sourceWatcher = StateObject(wrappedValue: watcher)
        _appModel = StateObject(wrappedValue: model)

        // Register hotkey handler once at app launch (not inside body to avoid repeat registration).
        KeyboardShortcuts.onKeyUp(for: .togglePanel) {
            AppHotkeyController.shared.toggle()
        }
    }

    var body: some Scene {
        // ── MenuBar panel ────────────────────────────────────────────────
        MenuBarExtra {
            panelContent
                .frame(width: 640, height: 520)
        } label: {
            // Custom label (instead of the `systemImage:` initializer) so we can
            // hang a launch-time `.task` on it: the menu-bar label renders at app
            // launch, so it's a reliable place to open the main window once. That
            // gives users a real native window + Dock icon (via MainWindowObserverView)
            // instead of a menu-bar-only app that looks like nothing launched.
            MenuBarLabel()
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
            .environmentObject(aiConfig)
    }
}

// MARK: - MenuBarLabel

/// The menu-bar icon. Opens the main window once at launch so the app presents a
/// real, interactive native window on first run rather than a hidden menu-bar-only
/// process. A single `Window` scene is single-instance, so re-opening it just
/// focuses the existing window — safe if it were ever called twice.
private struct MenuBarLabel: View {
    @Environment(\.openWindow) private var openWindow
    @State private var didOpenAtLaunch = false

    var body: some View {
        Image(systemName: "arrow.right.doc.on.clipboard")
            .task {
                guard !didOpenAtLaunch else { return }
                didOpenAtLaunch = true
                openWindow(id: "main")
            }
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
