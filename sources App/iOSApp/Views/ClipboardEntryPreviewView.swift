import QuickLookThumbnailing
import SwiftUI

struct ClipboardEntryPreviewView: View {
    let entry: ClipboardEntry
    var size: CGFloat = 44
    @State private var image: UIImage?

    var body: some View {
        Group {
            if let image {
                Image(uiImage: image)
                    .resizable()
                    .scaledToFill()
            } else {
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .fill(Color.blue.opacity(0.12))
                    .overlay {
                        Image(systemName: iconName)
                            .foregroundStyle(.blue)
                    }
            }
        }
        .frame(width: size, height: size)
        .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
        .task(id: entry.id) {
            await loadThumbnailIfNeeded()
        }
    }

    private var iconName: String {
        switch entry.type {
        case .text: return "doc.text"
        case .image: return "photo"
        case .pdf: return "doc.richtext"
        case .doc: return "doc"
        case .audio: return "waveform"
        case .video: return "film"
        case .file: return "folder"
        }
    }

    private func loadThumbnailIfNeeded() async {
        guard entry.type.isFileLike,
              let fileURL = ClipboardFileLocator.localFileURL(for: entry) else {
            return
        }

        let request = QLThumbnailGenerator.Request(
            fileAt: fileURL,
            size: CGSize(width: size * 2, height: size * 2),
            scale: UIScreen.main.scale,
            representationTypes: .thumbnail
        )

        do {
            let thumbnail = try await QLThumbnailGenerator.shared.generateBestRepresentation(for: request)
            image = thumbnail.uiImage
        } catch {
            image = nil
        }
    }
}
