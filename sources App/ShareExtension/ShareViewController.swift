import Social
import UniformTypeIdentifiers

final class ShareViewController: SLComposeServiceViewController {
    private let inboxStore = SharedClipboardInboxStore.shared

    override func isContentValid() -> Bool {
        true
    }

    override func didSelectPost() {
        Task {
            await handleInputItems()
            extensionContext?.completeRequest(returningItems: nil)
        }
    }

    override func configurationItems() -> [Any]! {
        []
    }

    private func handleInputItems() async {
        guard let extensionItems = extensionContext?.inputItems as? [NSExtensionItem] else {
            return
        }

        for item in extensionItems {
            for provider in item.attachments ?? [] {
                if provider.hasItemConformingToTypeIdentifier(UTType.plainText.identifier),
                   let text = try? await provider.loadItem(forTypeIdentifier: UTType.plainText.identifier) as? String {
                    let entry = ClipboardEntry(
                        type: .text,
                        title: String(text.prefix(40)),
                        previewText: text,
                        sourceDevice: "iPhone"
                    )
                    try? await inboxStore.append(entry)
                    continue
                }

                if let fileEntry = try? await makeFileEntry(from: provider) {
                    try? await inboxStore.append(fileEntry)
                }
            }
        }
    }

    private func makeFileEntry(from provider: NSItemProvider) async throws -> ClipboardEntry? {
        let supportedTypes: [ClipboardEntryType: UTType] = [
            .image: .image,
            .pdf: .pdf,
            .doc: .data,
            .audio: .audio,
            .video: .movie,
            .file: .item
        ]

        for (entryType, type) in supportedTypes where provider.hasItemConformingToTypeIdentifier(type.identifier) {
            guard let url = try await provider.loadFileRepresentation(for: type) else {
                continue
            }

            let fileName = url.lastPathComponent
            let destinationURL = AppGroupStore.localFilesDirectory()?.appendingPathComponent(fileName, isDirectory: false)
            if let destinationURL {
                try? FileManager.default.removeItem(at: destinationURL)
                try FileManager.default.copyItem(at: url, to: destinationURL)
            }

            return ClipboardEntry(
                type: entryType,
                title: fileName,
                previewText: "来自分享扩展的文件",
                fileName: fileName,
                mimeType: type.preferredMIMEType,
                localRelativePath: fileName,
                sourceDevice: "iPhone"
            )
        }

        return nil
    }
}

private extension NSItemProvider {
    func loadFileRepresentation(for type: UTType) async throws -> URL? {
        try await withCheckedThrowingContinuation { continuation in
            loadFileRepresentation(forTypeIdentifier: type.identifier) { url, error in
                if let error {
                    continuation.resume(throwing: error)
                } else {
                    continuation.resume(returning: url)
                }
            }
        }
    }

    func loadItem(forTypeIdentifier typeIdentifier: String) async throws -> NSSecureCoding? {
        try await withCheckedThrowingContinuation { continuation in
            loadItem(forTypeIdentifier: typeIdentifier, options: nil) { item, error in
                if let error {
                    continuation.resume(throwing: error)
                } else {
                    continuation.resume(returning: item as? NSSecureCoding)
                }
            }
        }
    }
}
