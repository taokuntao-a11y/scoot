@preconcurrency import KeyboardShortcuts

// MARK: - Keyboard shortcut names

extension KeyboardShortcuts.Name {
    // nonisolated(unsafe): Name is not Sendable in v1.x; this static is only accessed
    // from KeyboardShortcuts callbacks which are dispatched on the main thread.
    nonisolated(unsafe) static let togglePanel = Self(
        "togglePanel",
        default: .init(.s, modifiers: [.option, .shift])
    )
}
