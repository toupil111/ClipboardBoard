import SwiftUI
import WidgetKit

struct ClipboardWidgetEntry: TimelineEntry {
    let date: Date
    let items: [ClipboardEntry]
}

struct ClipboardWidgetProvider: TimelineProvider {
    func placeholder(in context: Context) -> ClipboardWidgetEntry {
        ClipboardWidgetEntry(date: .now, items: Array(ClipboardEntry.mockItems.prefix(3)))
    }

    func getSnapshot(in context: Context, completion: @escaping (ClipboardWidgetEntry) -> Void) {
        completion(ClipboardWidgetEntry(date: .now, items: Array(ClipboardEntry.mockItems.prefix(3))))
    }

    func getTimeline(in context: Context, completion: @escaping (Timeline<ClipboardWidgetEntry>) -> Void) {
        Task {
            let items = await ClipboardCacheStore.shared.loadWidgetItems()
            let entry = ClipboardWidgetEntry(date: .now, items: Array(items.prefix(3)))
            let next = Calendar.current.date(byAdding: .minute, value: 15, to: .now) ?? .now.addingTimeInterval(900)
            completion(Timeline(entries: [entry], policy: .after(next)))
        }
    }
}

struct ClipboardWidgetEntryView: View {
    var entry: ClipboardWidgetProvider.Entry

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("粘贴板")
                .font(.headline)

            ForEach(entry.items.prefix(3)) { item in
                HStack(spacing: 8) {
                    VStack(alignment: .leading, spacing: 2) {
                        Text(item.title)
                            .font(.caption.bold())
                            .lineLimit(1)
                        Text(item.shortPreview)
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                            .lineLimit(1)
                    }

                    Spacer()

                    if item.type == .text {
                        Link(destination: URL(string: "clipboardboard://copy?id=\(item.id.uuidString)")!) {
                            Image(systemName: "doc.on.doc")
                        }
                    } else {
                        Link(destination: URL(string: "clipboardboard://open?id=\(item.id.uuidString)")!) {
                            Image(systemName: "square.and.arrow.up")
                        }
                    }
                }
            }
        }
        .padding()
    }
}

struct ClipboardWidget: Widget {
    let kind = "ClipboardWidget"

    var body: some WidgetConfiguration {
        StaticConfiguration(kind: kind, provider: ClipboardWidgetProvider()) { entry in
            ClipboardWidgetEntryView(entry: entry)
        }
        .configurationDisplayName("粘贴板列表")
        .description("快速查看最近同步到手机的剪贴板内容。")
        .supportedFamilies([.systemMedium, .systemLarge])
    }
}
