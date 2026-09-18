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

    /// Stable identity for the built-in Trash tile (shares the UUID-keyed
    /// hover/highlight/shake state with real destination tiles).
    private static let trashTileID = UUID()

    var body: some View {
        if destinationStore.destinations.isEmpty {
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
                        .modifier(ShakeEffect(
                            shakes: 3,
                            animatableData: shakingID == dest.id ? shakeOffset : 0
                        ))
                        .onTapGesture {
                            moveSelected(to: dest)
                        }
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

                    // Built-in Trash tile — always last, cannot be removed.
                    TrashTileView(
                        isHighlighted: highlightedID == Self.trashTileID,
                        movedCount: highlightedID == Self.trashTileID ? movedCount : 0,
                        isHovered: hoveredID == Self.trashTileID
                    )
                    .modifier(ShakeEffect(
                        shakes: 3,
                        animatableData: shakingID == Self.trashTileID ? shakeOffset : 0
                    ))
                    .onTapGesture {
                        trashSelected()
                    }
                    .onHover { inside in
                        if inside {
                            hoveredID = Self.trashTileID
                            NSCursor.pointingHand.push()
                        } else {
                            if hoveredID == Self.trashTileID { hoveredID = nil }
                            NSCursor.pop()
                        }
                    }
                    .onDrop(of: [UTType.fileURL], isTargeted: nil) { providers in
                        handleTrashDrop(providers: providers)
                    }
                    .help("移入系统回收站，可撤销")
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
            // Shake tile + flash StepperBar step ①
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
            appModel.flashStepOne()
            return
        }

        performMove(urls: selectedURLs, to: dest)
    }

    private func trashSelected() {
        let selectedURLs = sourceWatcher.files
            .map(\.url)
            .filter { selectionStore.selection.contains($0) }

        guard !selectedURLs.isEmpty else {
            let targetID = Self.trashTileID
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
            appModel.flashStepOne()
            return
        }

        performTrash(urls: selectedURLs)
    }

    private func handleTrashDrop(providers: [NSItemProvider]) -> Bool {
        Task { @MainActor in
            var resolved: [URL] = []
            for provider in providers {
                if let url = await loadURL(from: provider) {
                    resolved.append(url)
                }
            }
            guard !resolved.isEmpty else { return }
            let allInSelection = resolved.allSatisfy { selectionStore.selection.contains($0) }
            let urlsToTrash: [URL]
            if allInSelection && !selectionStore.selection.isEmpty {
                urlsToTrash = sourceWatcher.files
                    .map(\.url)
                    .filter { selectionStore.selection.contains($0) }
            } else {
                urlsToTrash = resolved
            }
            performTrash(urls: urlsToTrash)
        }
        return true
    }

    private func performTrash(urls: [URL]) {
        appModel.trash(urls)
        selectionStore.selection = []
        movedCount = urls.count
        flashHighlight(id: Self.trashTileID)
        withAnimation {
            sourceWatcher.reload()
        }
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
        flashHighlight(id: dest.id)
        withAnimation {
            sourceWatcher.reload()
        }
    }

    private func flashHighlight(id: UUID) {
        highlightedID = id
        Task {
            try? await Task.sleep(nanoseconds: 1_500_000_000)
            if highlightedID == id {
                highlightedID = nil
                movedCount = 0
            }
        }
    }

    private func addDestination() {
        if let url = pickFolder(prompt: "添加目标文件夹") {
            destinationStore.add(url: url)
        }
    }
}

// MARK: - Empty Guide Card

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

// MARK: - Shake GeometryEffect

private struct ShakeEffect: GeometryEffect {
    var shakes: Int = 3
    var amount: CGFloat = 6
    var animatableData: CGFloat

    func effectValue(size: CGSize) -> ProjectionTransform {
        let translation = amount * sin(animatableData * .pi * CGFloat(shakes))
        return ProjectionTransform(CGAffineTransform(translationX: translation, y: 0))
    }
}

// MARK: - Trash tile

/// Built-in "回收站" tile: same footprint as a destination tile, red accent on
/// hover, files land in the system Trash (recoverable via 撤销).
struct TrashTileView: View {
    let isHighlighted: Bool
    let movedCount: Int
    let isHovered: Bool

    @State private var bounceScale: CGFloat = 1.0

    var body: some View {
        VStack(spacing: 4) {
            Image(systemName: isHovered ? "trash.fill" : "trash")
                .font(.system(size: 24))
                .frame(width: 32, height: 32)
                .foregroundStyle(isHovered ? AnyShapeStyle(Color.red) : AnyShapeStyle(.secondary))

            Text("回收站")
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
                    ? AnyShapeStyle(Color.red.opacity(0.12))
                    : AnyShapeStyle(.quaternary),
            in: RoundedRectangle(cornerRadius: 8)
        )
        .animation(.easeInOut(duration: 0.2), value: isHighlighted)
        .animation(.easeInOut(duration: 0.15), value: isHovered)
        .onChange(of: isHighlighted) { newVal in
            if newVal {
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

// MARK: - Tile

struct DestinationTileView: View {
    let destination: Destination
    let isHighlighted: Bool
    let movedCount: Int
    let isHovered: Bool

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
