import AppKit
import SwiftUI

// MARK: - MainWindowObserverView

/// Hidden zero-size NSView embedded in the main Window's ContentView.
/// On window attach: switches NSApp to .regular (Dock icon, Cmd-Tab).
/// On window close: restores .accessory when no other main windows remain.
struct MainWindowObserverView: NSViewRepresentable {

    @MainActor
    final class Coordinator: NSObject {
        nonisolated(unsafe) var observerToken: NSObjectProtocol?

        func attachToWindow(_ window: NSWindow) {
            guard observerToken == nil else { return }

            NSApp.setActivationPolicy(.regular)
            NSApp.activate(ignoringOtherApps: true)

            observerToken = NotificationCenter.default.addObserver(
                forName: NSWindow.willCloseNotification,
                object: window,
                queue: .main
            ) { [weak self, weak window] _ in
                MainActor.assumeIsolated {
                    let hasOtherMainWindow = NSApp.windows.contains {
                        $0 !== window && $0.isVisible && !$0.className.contains("MenuBarExtra")
                    }
                    if !hasOtherMainWindow {
                        NSApp.setActivationPolicy(.accessory)
                    }
                    self?.observerToken = nil
                }
            }
        }

        deinit {
            if let token = observerToken {
                NotificationCenter.default.removeObserver(token)
            }
        }
    }

    func makeCoordinator() -> Coordinator { Coordinator() }

    func makeNSView(context: Context) -> LifecycleView {
        let view = LifecycleView()
        view.coordinator = context.coordinator
        return view
    }

    func updateNSView(_ nsView: LifecycleView, context: Context) {}

    // MARK: - LifecycleView

    @MainActor
    final class LifecycleView: NSView {
        weak var coordinator: Coordinator?

        override func viewDidMoveToWindow() {
            super.viewDidMoveToWindow()
            guard let window = self.window else { return }
            coordinator?.attachToWindow(window)
        }
    }
}
