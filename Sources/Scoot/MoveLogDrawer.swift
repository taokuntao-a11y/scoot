import ScootCore
import SwiftUI

// MARK: - MoveLogDrawer

/// Collapsible drawer above the bottom bar showing operation history.
struct MoveLogDrawer: View {
    @EnvironmentObject private var moveLog: MoveLog
    @State private var isExpanded: Bool = false

    private static let timeFormatter: DateFormatter = {
        let f = DateFormatter()
        f.dateFormat = "HH:mm"
        return f
    }()

    var body: some View {
        DisclosureGroup(isExpanded: $isExpanded) {
            ScrollView {
                LazyVStack(alignment: .leading, spacing: 2) {
                    if moveLog.entries.isEmpty {
                        Text("暂无操作记录")
                            .foregroundStyle(.secondary)
                            .font(.caption)
                            .padding(.horizontal, 10)
                            .padding(.vertical, 4)
                    } else {
                        ForEach(moveLog.entries) { entry in
                            EntryRowView(entry: entry)
                        }
                    }
                }
                .padding(.vertical, 4)
            }
            .frame(height: 120)
        } label: {
            HStack(spacing: 4) {
                Text("操作日志")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                if let latest = moveLog.entries.first {
                    Text(summarize(latest))
                        .font(.caption)
                        .foregroundStyle(.tertiary)
                        .lineLimit(1)
                }
                Spacer()
            }
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 4)
    }

    private func summarize(_ entry: LogEntry) -> String {
        if entry.isUndo {
            return "最近：↩ \(entry.fileName) ← \(entry.destName)"
        }
        return "最近：\(entry.fileName) → \(entry.destName)"
    }
}

// MARK: - Entry row

private struct EntryRowView: View {
    let entry: LogEntry

    private static let timeFormatter: DateFormatter = {
        let f = DateFormatter()
        f.dateFormat = "HH:mm"
        return f
    }()

    var body: some View {
        HStack(spacing: 8) {
            Text(Self.timeFormatter.string(from: entry.date))
                .font(.caption2.monospacedDigit())
                .foregroundStyle(.secondary)
                .frame(width: 34, alignment: .leading)

            if entry.isUndo {
                Text("↩ \(entry.fileName) ← \(entry.destName)")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            } else {
                Text("\(entry.fileName) → \(entry.destName)")
                    .font(.caption)
                    .foregroundStyle(.primary)
                    .lineLimit(1)
            }

            Spacer()
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 1)
    }
}
