import SwiftUI

struct ClipboardRowView: View {
    let item: ClipboardEntry
    let copyAction: () -> Void
    let shareAction: () -> Void

    var body: some View {
        HStack(spacing: 12) {
            ClipboardEntryPreviewView(entry: item)

            VStack(alignment: .leading, spacing: 4) {
                Text(item.title)
                    .font(.headline)
                    .lineLimit(1)

                Text(item.shortPreview)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .lineLimit(2)
            }

            Spacer()

            if item.type == .text {
                Button("复制", action: copyAction)
                    .buttonStyle(.borderedProminent)
                    .controlSize(.small)
            } else {
                Button("分享", action: shareAction)
                    .buttonStyle(.bordered)
                    .controlSize(.small)
                    .disabled(!ClipboardFileLocator.isAvailableLocally(item))
            }
        }
        .padding(.vertical, 4)
    }
}
