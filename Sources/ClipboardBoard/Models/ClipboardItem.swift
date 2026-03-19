import AppKit
import CryptoKit
import UniformTypeIdentifiers

enum ClipboardContentKind: String, Codable {
    case text
    case image
    case pdf
    case doc
    case audio
    case video
    case file
    case files

    var symbolName: String {
        switch self {
        case .text:
            return "doc.text"
        case .image:
            return "photo"
        case .pdf:
            return "doc.richtext"
        case .doc:
            return "doc.text.image"
        case .audio:
            return "music.note"
        case .video:
            return "film"
        case .file, .files:
            return "doc"
        }
    }

    var label: String {
        switch self {
        case .text:
            return "文字"
        case .image:
            return "图片"
        case .pdf:
            return "PDF"
        case .doc:
            return "DOC"
        case .audio:
            return "音频"
        case .video:
            return "视频"
        case .file:
            return "文件"
        case .files:
            return "文件组"
        }
    }
}

struct ClipboardCapture {
    let item: ClipboardItem
    let payloadData: Data?
}

@MainActor
struct ClipboardItem: Identifiable, Equatable, Codable {
    let id: UUID
    let timestamp: Date
    let title: String
    let subtitle: String
    let contentKind: ClipboardContentKind
    let previewText: String?
    let previewImageData: Data?
    let pasteboardTypeIdentifier: String?
    let fileURLs: [URL]
    let payloadFileName: String?
    let fingerprint: String

    private static let previewCache = NSCache<NSString, NSImage>()
    private static let fileIconCache = NSCache<NSString, NSImage>()

    init(
        id: UUID = UUID(),
        timestamp: Date = Date(),
        title: String,
        subtitle: String,
        contentKind: ClipboardContentKind,
        previewText: String?,
        previewImageData: Data?,
        pasteboardTypeIdentifier: String?,
        fileURLs: [URL],
        payloadFileName: String?,
        fingerprint: String
    ) {
        self.id = id
        self.timestamp = timestamp
        self.title = title
        self.subtitle = subtitle
        self.contentKind = contentKind
        self.previewText = previewText
        self.previewImageData = previewImageData
        self.pasteboardTypeIdentifier = pasteboardTypeIdentifier
        self.fileURLs = fileURLs
        self.payloadFileName = payloadFileName
        self.fingerprint = fingerprint
    }

    static func capture(from pasteboard: NSPasteboard) -> ClipboardCapture? {
        if let urls = pasteboard.readObjects(
            forClasses: [NSURL.self],
            options: [.urlReadingFileURLsOnly: true]
        ) as? [URL], !urls.isEmpty {
            return makeFileItem(urls)
        }

        if let text = pasteboard.string(forType: .string), !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            let normalized = text.replacingOccurrences(of: #"\s+"#, with: " ", options: .regularExpression)
            let item = ClipboardItem(
                title: normalized.prefix(48).description,
                subtitle: "文字 · \(text.count) 字符",
                contentKind: .text,
                previewText: text,
                previewImageData: nil,
                pasteboardTypeIdentifier: NSPasteboard.PasteboardType.string.rawValue,
                fileURLs: [],
                payloadFileName: nil,
                fingerprint: Self.sha256(text)
            )
            return ClipboardCapture(item: item, payloadData: nil)
        }

        if let image = NSImage(pasteboard: pasteboard),
           let data = image.tiffRepresentation {
            let size = image.size
            let item = ClipboardItem(
                title: "图片",
                subtitle: "图片 · \(Int(size.width))×\(Int(size.height))",
                contentKind: .image,
                previewText: nil,
                previewImageData: Self.thumbnailData(for: image),
                pasteboardTypeIdentifier: NSPasteboard.PasteboardType.tiff.rawValue,
                fileURLs: [],
                payloadFileName: nil,
                fingerprint: Self.sha256(data)
            )
            return ClipboardCapture(item: item, payloadData: data)
        }

        if let pdfData = pasteboard.data(forType: .pdf) {
            let item = ClipboardItem(
                title: "PDF",
                subtitle: "PDF · \(Self.byteCount(pdfData.count))",
                contentKind: .pdf,
                previewText: nil,
                previewImageData: nil,
                pasteboardTypeIdentifier: NSPasteboard.PasteboardType.pdf.rawValue,
                fileURLs: [],
                payloadFileName: nil,
                fingerprint: Self.sha256(pdfData)
            )
            return ClipboardCapture(item: item, payloadData: pdfData)
        }

        for type in pasteboard.types ?? [] {
            if let data = pasteboard.data(forType: type), !data.isEmpty {
                let item = ClipboardItem(
                    title: type.rawValue,
                    subtitle: "原始数据 · \(Self.byteCount(data.count))",
                    contentKind: .file,
                    previewText: nil,
                    previewImageData: nil,
                    pasteboardTypeIdentifier: type.rawValue,
                    fileURLs: [],
                    payloadFileName: nil,
                    fingerprint: Self.sha256(data)
                )
                return ClipboardCapture(item: item, payloadData: data)
            }
        }

        return nil
    }

    func withPayloadFileName(_ payloadFileName: String?) -> ClipboardItem {
        ClipboardItem(
            id: id,
            timestamp: timestamp,
            title: title,
            subtitle: subtitle,
            contentKind: contentKind,
            previewText: previewText,
            previewImageData: previewImageData,
            pasteboardTypeIdentifier: pasteboardTypeIdentifier,
            fileURLs: fileURLs,
            payloadFileName: payloadFileName,
            fingerprint: fingerprint
        )
    }

    func restore(to pasteboard: NSPasteboard, payloadDataProvider: (String) -> Data?) {
        pasteboard.clearContents()

        switch contentKind {
        case .text:
            pasteboard.setString(previewText ?? title, forType: .string)

        case .image:
            if !fileURLs.isEmpty {
                pasteboard.writeObjects(fileURLs as [NSURL])
            } else if let payloadFileName,
                      let data = payloadDataProvider(payloadFileName),
                      let image = NSImage(data: data) {
                pasteboard.writeObjects([image])
            }

        case .pdf:
            if !fileURLs.isEmpty {
                pasteboard.writeObjects(fileURLs as [NSURL])
            } else if let payloadFileName,
                      let data = payloadDataProvider(payloadFileName) {
                pasteboard.setData(data, forType: .pdf)
            }

        case .doc, .audio, .video, .file, .files:
            if !fileURLs.isEmpty {
                pasteboard.writeObjects(fileURLs as [NSURL])
            } else if let payloadFileName,
                      let pasteboardTypeIdentifier,
                      let data = payloadDataProvider(payloadFileName) {
                pasteboard.setData(data, forType: NSPasteboard.PasteboardType(pasteboardTypeIdentifier))
            }
        }
    }

    func previewImage() -> NSImage? {
        if let cached = Self.previewCache.object(forKey: fingerprint as NSString) {
            return cached
        }

        if let previewImageData, let image = NSImage(data: previewImageData) {
            Self.previewCache.setObject(image, forKey: fingerprint as NSString)
            return image
        }

        if let firstURL = fileURLs.first {
            let cacheKey = firstURL.path as NSString
            if let cached = Self.fileIconCache.object(forKey: cacheKey) {
                return cached
            }

            let image: NSImage?
            switch contentKind {
            case .image:
                image = NSImage(contentsOf: firstURL) ?? NSWorkspace.shared.icon(forFile: firstURL.path)
            default:
                image = NSWorkspace.shared.icon(forFile: firstURL.path)
            }

            if let image {
                Self.fileIconCache.setObject(image, forKey: cacheKey)
            }
            return image
        }

        return nil
    }

    private static func makeFileItem(_ urls: [URL]) -> ClipboardCapture {
        let kind = inferKind(from: urls)
        let title = urls.count == 1 ? urls[0].lastPathComponent : "\(urls.count) 个文件"
        let extensions = Set(urls.compactMap { url -> String? in
            let ext = url.pathExtension.uppercased()
            return ext.isEmpty ? nil : ext
        })
        let extSummary = extensions.sorted().joined(separator: " / ")
        let subtitleCore = kind.label
        let subtitle = extSummary.isEmpty ? subtitleCore : "\(subtitleCore) · \(extSummary)"
        let fingerprintSource = urls.map { url in
            let resource = try? url.resourceValues(forKeys: [.contentModificationDateKey, .fileSizeKey])
            let modified = resource?.contentModificationDate?.timeIntervalSince1970 ?? 0
            let size = resource?.fileSize ?? 0
            return "\(url.path)|\(modified)|\(size)"
        }.joined(separator: "\n")

        let previewData: Data?
        if kind == .image, let firstURL = urls.first, let image = NSImage(contentsOf: firstURL) {
            previewData = thumbnailData(for: image)
        } else {
            previewData = nil
        }

        let item = ClipboardItem(
            title: title,
            subtitle: subtitle,
            contentKind: kind,
            previewText: urls.count == 1 ? urls[0].path : urls.map(\.lastPathComponent).joined(separator: "\n"),
            previewImageData: previewData,
            pasteboardTypeIdentifier: nil,
            fileURLs: urls,
            payloadFileName: nil,
            fingerprint: sha256(fingerprintSource)
        )
        return ClipboardCapture(item: item, payloadData: nil)
    }

    private static func inferKind(from urls: [URL]) -> ClipboardContentKind {
        guard urls.count == 1, let url = urls.first else {
            return .files
        }

        let ext = url.pathExtension.lowercased()
        if ["png", "jpg", "jpeg", "gif", "heic", "webp", "bmp", "tiff"].contains(ext) {
            return .image
        }
        if ext == "pdf" {
            return .pdf
        }
        if ["doc", "docx", "pages", "rtf", "rtfd"].contains(ext) {
            return .doc
        }
        if ["mp3", "m4a", "aac", "wav", "flac", "aiff"].contains(ext) {
            return .audio
        }
        if ["mp4", "mov", "m4v", "avi", "mkv", "webm"].contains(ext) {
            return .video
        }

        if let type = UTType(filenameExtension: ext) {
            if type.conforms(to: .image) {
                return .image
            }
            if type.conforms(to: .audio) {
                return .audio
            }
            if type.conforms(to: .text) || type.conforms(to: .rtf) || type.conforms(to: .compositeContent) {
                return .doc
            }
            if type.conforms(to: .movie) || type.conforms(to: .audiovisualContent) {
                return .video
            }
            if type.conforms(to: .pdf) {
                return .pdf
            }
        }

        return .file
    }

    private static func thumbnailData(for image: NSImage, maxDimension: CGFloat = 240) -> Data? {
        let maxSourceDimension = max(image.size.width, image.size.height)
        let scale = min(1, maxDimension / maxSourceDimension)
        let targetSize = NSSize(width: max(1, image.size.width * scale), height: max(1, image.size.height * scale))
        let thumbnail = NSImage(size: targetSize)

        thumbnail.lockFocus()
        defer { thumbnail.unlockFocus() }

        NSGraphicsContext.current?.imageInterpolation = .high
        image.draw(in: NSRect(origin: .zero, size: targetSize), from: .zero, operation: .copy, fraction: 1)

        guard let tiffData = thumbnail.tiffRepresentation,
              let bitmap = NSBitmapImageRep(data: tiffData) else {
            return nil
        }

        return bitmap.representation(using: .png, properties: [:])
    }

    private static func byteCount(_ count: Int) -> String {
        let formatter = ByteCountFormatter()
        formatter.countStyle = .file
        return formatter.string(fromByteCount: Int64(count))
    }

    private static func sha256(_ text: String) -> String {
        sha256(Data(text.utf8))
    }

    private static func sha256(_ data: Data) -> String {
        let digest = SHA256.hash(data: data)
        return digest.map { String(format: "%02x", $0) }.joined()
    }
}
