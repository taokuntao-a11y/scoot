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

    private let columns = [GridItem(.flexible()), GridItem(.flexible())]

    var body: some View {
        ScrollView {
            LazyVGrid(columns: columns, spacing: 12) {
                ForEach(destinationStore.destinations) { dest in
                    DestinationTileView(
                        destination: dest,
                        isHighlighted: highlightedID == dest.id,
                        movedCount: highlightedID == dest.id ? movedCount : 0
                    )
                    .onTapGesture {
                        moveSelected(to: dest)
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

    // MARK: - Actions

    private func moveSelected(to dest: Destination) {
        let selectedURLs = sourceWatcher.files
            .map(\.url)
            .filter { selectionStore.selection.contains($0) }
        guard !selectedURLs.isEmpty else { return }
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
        sourceWatcher.reload()
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

    private func addDestination() {
        let panel = NSOpenPanel()
        panel.canChooseDirectories = true
        panel.canChooseFiles = false
        panel.allowsMultipleSelection = false
        panel.prompt = "添加目标文件夹"
        if panel.runModal() == .OK, let url = panel.url {
            destinationStore.add(url: url)
        }
    }
}

// MARK: - Tile

struct DestinationTileView: View {
    let destination: Destination
    let isHighlighted: Bool
    let movedCount: Int

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
        .background(
            isHighlighted
                ? AnyShapeStyle(Color.green.opacity(0.2))
                : AnyShapeStyle(.quaternary),
            in: RoundedRectangle(cornerRadius: 8)
        )
        .animation(.easeInOut(duration: 0.2), value: isHighlighted)
    }
}
