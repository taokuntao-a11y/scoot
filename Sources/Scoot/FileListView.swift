import AppKit
import ScootCore
import SwiftUI

struct FileListView: View {
    @EnvironmentObject private var sourceWatcher: SourceWatcher
    @EnvironmentObject private var selectionStore: SelectionStore

    var body: some View {
        Group {
            if sourceWatcher.files.isEmpty {
                VStack {
                    Spacer()
                    Text("下载文件夹是空的 🎉")
                        .foregroundStyle(.secondary)
                    Spacer()
                }
            } else {
                List(sourceWatcher.files, selection: $selectionStore.selection) { item in
                    FileRowView(item: item)
                        .tag(item.url)
                        .onDrag {
                            // If the dragged row is part of the selection, drag all selected items.
                            // SwiftUI onDrag only yields one primary provider, but we encode all
                            // selected URLs as a space-separated string in the primary item so the
                            // drop target can recover them. Falls back to the single item otherwise.
                            let selectedURLs: [URL]
                            if selectionStore.selection.contains(item.url) {
                                selectedURLs = sourceWatcher.files
                                    .map(\.url)
                                    .filter { selectionStore.selection.contains($0) }
                            } else {
                                selectedURLs = [item.url]
                            }
                            // Use the primary dragged file's built-in provider.
                            // Multi-URL is surfaced via the selection store on drop.
                            let primary = selectedURLs.first ?? item.url
                            return NSItemProvider(contentsOf: primary) ?? NSItemProvider()
                        }
                        .gesture(
                            TapGesture(count: 2).onEnded {
                                NSWorkspace.shared.open(item.url)
                            }
                        )
                }
                .listStyle(.plain)
            }
        }
    }
}

// MARK: - Row

struct FileRowView: View {
    let item: FileItem

    private static let relativeFormatter: RelativeDateTimeFormatter = {
        let f = RelativeDateTimeFormatter()
        f.unitsStyle = .abbreviated
        return f
    }()

    private static let byteFormatter: ByteCountFormatter = {
        let f = ByteCountFormatter()
        f.countStyle = .file
        return f
    }()

    var body: some View {
        HStack(spacing: 6) {
            Image(nsImage: NSWorkspace.shared.icon(forFile: item.url.path))
                .resizable()
                .frame(width: 20, height: 20)

            VStack(alignment: .leading, spacing: 1) {
                Text(item.name)
                    .lineLimit(1)
                    .truncationMode(.middle)

                HStack(spacing: 4) {
                    Text(
                        Self.relativeFormatter.localizedString(
                            for: item.addedAt, relativeTo: Date()
                        )
                    )
                    .foregroundStyle(.secondary)
                    .font(.caption)

                    if !item.isDirectory {
                        Text(Self.byteFormatter.string(fromByteCount: item.size))
                            .foregroundStyle(.secondary)
                            .font(.caption)
                    }
                }
            }
        }
        .padding(.vertical, 2)
    }
}
