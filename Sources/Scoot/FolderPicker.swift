import AppKit

/// Presents a folder-picking NSOpenPanel and returns the chosen URL.
///
/// In LSUIElement mode the open panel steals key window status and does not
/// return it to the MenuBarExtra panel on close, leaving the panel rendered
/// inactive (greyed out). This helper activates the app before presenting and
/// restores key focus to the MenuBarExtra window afterwards.
@MainActor
func pickFolder(prompt: String) -> URL? {
    let panel = NSOpenPanel()
    panel.canChooseDirectories = true
    panel.canChooseFiles = false
    panel.allowsMultipleSelection = false
    panel.prompt = prompt

    NSApp.activate(ignoringOtherApps: true)

    let url = panel.runModal() == .OK ? panel.url : nil

    // The open panel is already dismissed, so the first visible non-NSPanel
    // window is the MenuBarExtra window; className contains "MenuBarExtra" on macOS 13+.
    let menuBarWindow =
        NSApp.windows.first { $0.isVisible && $0.className.contains("MenuBarExtra") }
        ?? NSApp.windows.first { $0.isVisible && !($0 is NSPanel) }
    menuBarWindow?.makeKeyAndOrderFront(nil)

    return url
}
