import AppKit
import ScootCore
import SwiftUI
import UniformTypeIdentifiers

struct DestinationGridView: View {
    @EnvironmentObject private var sourceWatcher: SourceWatcher
    @EnvironmentObject private var destinationStore: DestinationStore
    @EnvironmentObject private var appModel: AppModel
    @EnvironmentObject private var selectionStore: SelectionStore

    @State private var highlightedID: UUID? = nil
    @State private var movedCount: Int = 0
    @State private var shakingID: UUID? = nil
    @State private var shakeOffset: CGFloat = 0
    @State private var hoveredID: UUID? = nil

    private let columns = [GridItem(.flexible()), GridItem(.flexible())]

    var body: some View {
        if destinationStore.destinations.isEmpty {
            // 2a: Guide card when no destinations exist
            EmptyDestinationsGuideView {
                addDestination()
            }
        } else {
            ScrollView {
                LazyVGrid(columns: columns, spacing: 12) {
                    ForEach(destinationStore.destinations) { dest in
                        DestinationTileView(
                            destination: dest,
                            isHighlighted: highlightedID == dest.id,
                            movedCount: highlightedID == dest.id ? movedCount : 0,
                            isHovered: hoveredID == dest.id
                        )
                        // 2b: Shake when no selection
                        .modifier(ShakeEffect(
                            shakes: 3,
                            animatableData: shakingID == dest.id ? shakeOffset : 0
                        ))
                        .onTapGesture {
                            moveSelected(to: dest)
                        }
                        // 2d: Hover — deepen background + pointing hand cursor
                        .onHover { inside in
                            if inside {
                                hoveredID = dest.id
                                NSCursor.pointingHand.push()
                            } else {
                                if hoveredID == dest.id { hoveredID = nil }
                                NSCursor.pop()
                            }
                        }
                        .onDrop(of: [UTType.fileURL], isTargeted: nil) { providers in
                            handleDrop(providers: providers, to: dest)
                        }
                        .contextMenu {
                            Button("移除目标", role: .destructive) {
                                destinationStore.remove(dest)
                            }
                        }
                    }

                    // Add destination "+" tile
                    Button {
                        addDestination()
                    } label: {
                        VStack(spacing: 4) {
                            Image(systemName: "plus.circle.dashed")
                                .font(.system(size: 28))
                                .foregroundStyle(.secondary)
                            Text("添加目标")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                        .frame(maxWidth: .infinity)
                        .frame(height: 80)
                        .background(.quaternary, in: RoundedRectangle(cornerRadius: 8))
                    }
                    .buttonStyle(.plain)
                }
                .padding(12)
            }
        }
    }

    // MARK: - Actions

    private func moveSelected(to dest: Destination) {
        let selectedURLs = sourceWatcher.files
            .map(\.url)
            .filter { selectionStore.selection.contains($0) }

        guard !selectedURLs.isEmpty else {
            // 2b: Shake tile + show bottom-bar hint
            let targetID = dest.id
            shakingID = targetID
            shakeOffset = 0
            withAnimation(.easeInOut(duration: 0.3)) {
                shakeOffset = 1
            }
            Task {
                try? await Task.sleep(nanoseconds: 350_000_000)
                if shakingID == targetID {
                    shakeOffset = 0
                    shakingID = nil
                }
            }
            appModel.showHint("先在左侧选中要移动的文件")
            return
        }

        performMove(urls: selectedURLs, to: dest)
    }

    private func handleDrop(providers: [NSItemProvider], to dest: Destination) -> Bool {
        Task { @MainActor in
            var resolved: [URL] = []
            for provider in providers {
                if let url = await loadURL(from: provider) {
                    resolved.append(url)
                }
            }
            guard !resolved.isEmpty else { return }
            let allInSelection = resolved.allSatisfy { selectionStore.selection.contains($0) }
            let urlsToMove: [URL]
            if allInSelection && !selectionStore.selection.isEmpty {
                urlsToMove = sourceWatcher.files
                    .map(\.url)
                    .filter { selectionStore.selection.contains($0) }
            } else {
                urlsToMove = resolved
            }
            performMove(urls: urlsToMove, to: dest)
        }
        return true
    }

    private func loadURL(from provider: NSItemProvider) async -> URL? {
        await withCheckedContinuation { continuation in
            provider.loadItem(
                forTypeIdentifier: UTType.fileURL.identifier,
                options: nil
            ) { item, _ in
                if let data = item as? Data,
                   let url = URL(dataRepresentation: data, relativeTo: nil) {
                    continuation.resume(returning: url)
                } else if let url = item as? URL {
                    continuation.resume(returning: url)
                } else {
                    continuation.resume(returning: nil)
                }
            }
        }
    }

    private func performMove(urls: [URL], to dest: Destination) {
        appModel.move(urls, to: dest)
        selectionStore.selection = []
        movedCount = urls.count
        flashHighlight(for: dest)
        // 2c: Animate list changes (row removal) naturally
        withAnimation {
            sourceWatcher.reload()
        }
    }

    private func flashHighlight(for dest: Destination) {
        highlightedID = dest.id
        Task {
            try? await Task.sleep(nanoseconds: 1_500_000_000)
            if highlightedID == dest.id {
                highlightedID = nil
                movedCount = 0
            }
        }
    }

    // MARK: - Bug 1 fix: NSOpenPanel key-window restoration

    private func addDestination() {
        let panel = NSOpenPanel()
        panel.canChooseDirectories = true
        panel.canChooseFiles = false
        panel.allowsMultipleSelection = false
        panel.prompt = "添加目标文件夹"

        // Ensure the app is key so the panel can receive input in LSUIElement mode.
        NSApp.activate(ignoringOtherApps: true)

        if panel.runModal() == .OK, let url = panel.url {
            destinationStore.add(url: url)
        }

        // Return key focus to the MenuBarExtra panel window after the NSOpenPanel closes.
        // The panel itself is already dismissed, so the first visible non-NSPanel window is
        // the MenuBarExtra window; className contains "MenuBarExtra" on macOS 13+.
        let menuBarWindow =
            NSApp.windows.first { $0.isVisible && $0.className.contains("MenuBarExtra") }
            ?? NSApp.windows.first { $0.isVisible && !($0 is NSPanel) }
        menuBarWindow?.makeKeyAndOrderFront(nil)
    }
}

// MARK: - Empty Guide Card (2a)

private struct EmptyDestinationsGuideView: View {
    let onAdd: () -> Void
    @State private var breathingOpacity: Double = 0.65

    var body: some View {
        Button(action: onAdd) {
            VStack(spacing: 14) {
                Image(systemName: "folder.badge.plus")
                    .font(.system(size: 44))
                    .foregroundStyle(.secondary)
                    .opacity(breathingOpacity)

                VStack(spacing: 6) {
                    Text("1. 点这里添加常用目标文件夹")
                        .font(.subheadline)
                        .foregroundStyle(.primary)
                    Text("2. 选中左侧文件，点击目标即完成移动")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .onAppear {
            withAnimation(.easeInOut(duration: 1.5).repeatForever(autoreverses: true)) {
                breathingOpacity = 1.0
            }
        }
    }
}

// MARK: - Shake GeometryEffect (2b)

private struct ShakeEffect: GeometryEffect {
    var shakes: Int = 3
    var amount: CGFloat = 6
    var animatableData: CGFloat

    func effectValue(size: CGSize) -> ProjectionTransform {
        let translation = amount * sin(animatableData * .pi * CGFloat(shakes))
        return ProjectionTransform(CGAffineTransform(translationX: translation, y: 0))
    }
}

// MARK: - Tile

struct DestinationTileView: View {
    let destination: Destination
    let isHighlighted: Bool
    let movedCount: Int
    let isHovered: Bool

    // 2c: Scale bounce on move success
    @State private var bounceScale: CGFloat = 1.0

    var body: some View {
        VStack(spacing: 4) {
            Image(nsImage: NSWorkspace.shared.icon(forFile: destination.path))
                .resizable()
                .frame(width: 32, height: 32)

            Text(destination.name)
                .font(.caption)
                .lineLimit(2)
                .multilineTextAlignment(.center)

            if isHighlighted && movedCount > 0 {
                Text("已移入 \(movedCount) 项")
                    .font(.caption2)
                    .foregroundStyle(.green)
            }
        }
        .frame(maxWidth: .infinity)
        .frame(height: 80)
        .scaleEffect(bounceScale)
        .background(
            isHighlighted
                ? AnyShapeStyle(Color.green.opacity(0.2))
                : isHovered
                    ? AnyShapeStyle(.tertiary)
                    : AnyShapeStyle(.quaternary),
            in: RoundedRectangle(cornerRadius: 8)
        )
        .animation(.easeInOut(duration: 0.2), value: isHighlighted)
        .animation(.easeInOut(duration: 0.15), value: isHovered)
        .onChange(of: isHighlighted) { newVal in
            if newVal {
                // Spring bounce: 1.0 → 1.06 → 1.0
                withAnimation(.spring(response: 0.15, dampingFraction: 0.45)) {
                    bounceScale = 1.06
                }
                Task {
                    try? await Task.sleep(nanoseconds: 160_000_000)
                    withAnimation(.spring(response: 0.2, dampingFraction: 0.7)) {
                        bounceScale = 1.0
                    }
                }
            }
        }
    }
}
