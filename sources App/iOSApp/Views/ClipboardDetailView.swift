import QuickLook
import SwiftUI

struct ClipboardDetailView: View {
    let item: ClipboardEntry
    let copyAction: () -> Void
    let shareAction: () -> Void

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                if item.type.isFileLike {
                    HStack(spacing: 16) {
                        ClipboardEntryPreviewView(entry: item, size: 72)

                        VStack(alignment: .leading, spacing: 6) {
                            Text(item.fileName ?? item.title)
                                .font(.headline)
                            Text(ClipboardFileLocator.isAvailableLocally(item) ? "已同步到本机，可直接分享至微信" : "文件尚未落地到本机，请先下拉刷新")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                    }
                }

                VStack(alignment: .leading, spacing: 8) {
                    Text(item.title)
                        .font(.title2.bold())
                    Text(item.type.displayName)
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }

                Text(item.previewText)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding()
                    .background(Color.secondary.opacity(0.08), in: RoundedRectangle(cornerRadius: 16, style: .continuous))

                HStack {
                    if item.type == .text {
                        Button("复制内容", action: copyAction)
                            .buttonStyle(.borderedProminent)
                    } else {
                        Button("分享文件", action: shareAction)
                            .buttonStyle(.borderedProminent)
                            .disabled(!ClipboardFileLocator.isAvailableLocally(item))
                    }
                }
            }
            .padding()
        }
        .navigationTitle("详情")
        .navigationBarTitleDisplayMode(.inline)
    }
}
