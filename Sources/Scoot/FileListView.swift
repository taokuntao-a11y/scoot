import AppKit
import ScootCore
import SwiftUI

struct FileListView: View {
    @EnvironmentObject private var sourceWatcher: SourceWatcher
    @EnvironmentObject private var selectionStore: SelectionStore

    @Binding var filter: FileFilter

    @AppStorage("hasSeenIntro") private var hasSeenIntro: Bool = false

    private var filteredFiles: [FileItem] {
        filter.apply(to: sourceWatcher.files)
    }

    var body: some View {
        VStack(spacing: 0) {
            // First-use banner — shown until user dismisses
            if !hasSeenIntro {
                IntroBannerView {
                    withAnimation(.easeInOut(duration: 0.2)) {
                        hasSeenIntro = true
                    }
                }
                Divider()
            }

            // Filter capsules — hidden when the folder itself is empty
            if !sourceWatcher.files.isEmpty {
                FilterChipsRow(filter: $filter)
                Divider()
            }

            Group {
                if sourceWatcher.files.isEmpty {
                    VStack {
                        Spacer()
                        Text("下载文件夹是空的 🎉")
                            .foregroundStyle(.secondary)
                        Spacer()
                    }
                } else if filteredFiles.isEmpty {
                    VStack {
                        Spacer()
                        Text("没有「\(filter.rawValue)」文件")
                            .foregroundStyle(.secondary)
                        Spacer()
                    }
                } else {
                    List(filteredFiles, selection: $selectionStore.selection) { item in
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
                    .animation(.easeInOut(duration: 0.25), value: sourceWatcher.files)
                }
            }
        }
        // A hidden-but-selected file would still be moved by tile clicks, so the
        // selection must not survive a filter switch.
        .onChange(of: filter) { _ in
            selectionStore.selection = []
        }
    }
}

// MARK: - Filter chips

private struct FilterChipsRow: View {
    @Binding var filter: FileFilter

    var body: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 5) {
                ForEach(FileFilter.allCases) { f in
                    Button {
                        filter = f
                    } label: {
                        Text(f.rawValue)
                            .font(.caption)
                            .padding(.horizontal, 9)
                            .padding(.vertical, 3)
                            .background(
                                filter == f
                                    ? AnyShapeStyle(Color.accentColor)
                                    : AnyShapeStyle(Color.secondary.opacity(0.15)),
                                in: Capsule()
                            )
                            .foregroundStyle(filter == f ? AnyShapeStyle(.white) : AnyShapeStyle(.primary))
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(.horizontal, 10)
        }
        .padding(.vertical, 5)
    }
}

// MARK: - Intro Banner

private struct IntroBannerView: View {
    let onDismiss: () -> Void

    var body: some View {
        HStack(spacing: 8) {
            Image(systemName: "info.circle")
                .foregroundStyle(.blue)
                .font(.caption)
            Text("Scoot 常驻菜单栏，下载完文件点这里快速分拣")
                .font(.caption)
                .foregroundStyle(.primary)
            Spacer()
            Button(action: onDismiss) {
                Image(systemName: "xmark")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }
            .buttonStyle(.plain)
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 6)
        .background(Color.blue.opacity(0.08))
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
            Image(nsImage: FileIconCache.icon(for: item.url, isDirectory: item.isDirectory))
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
