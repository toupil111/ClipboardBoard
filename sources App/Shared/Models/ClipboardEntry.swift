import Foundation

public enum ClipboardEntryType: String, Codable, CaseIterable, Identifiable {
    case text
    case image
    case pdf
    case doc
    case audio
    case video
    case file

    public var id: String { rawValue }

    public var displayName: String {
        switch self {
        case .text: return "文本"
        case .image: return "图片"
        case .pdf: return "PDF"
        case .doc: return "DOC"
        case .audio: return "音频"
        case .video: return "视频"
        case .file: return "文件"
        }
    }

    public var isFileLike: Bool {
        switch self {
        case .text:
            return false
        case .image, .pdf, .doc, .audio, .video, .file:
            return true
        }
    }
}

public struct ClipboardEntry: Identifiable, Codable, Hashable {
    public let id: UUID
    public let createdAt: Date
    public let type: ClipboardEntryType
    public var title: String
    public var previewText: String
    public var fileName: String?
    public var mimeType: String?
    public var localRelativePath: String?
    public var cloudAssetKey: String?
    public var thumbnailRelativePath: String?
    public var sourceDevice: String
    public var isPinned: Bool

    public init(
        id: UUID = UUID(),
        createdAt: Date = Date(),
        type: ClipboardEntryType,
        title: String,
        previewText: String,
        fileName: String? = nil,
        mimeType: String? = nil,
        localRelativePath: String? = nil,
        cloudAssetKey: String? = nil,
        thumbnailRelativePath: String? = nil,
        sourceDevice: String,
        isPinned: Bool = false
    ) {
        self.id = id
        self.createdAt = createdAt
        self.type = type
        self.title = title
        self.previewText = previewText
        self.fileName = fileName
        self.mimeType = mimeType
        self.localRelativePath = localRelativePath
        self.cloudAssetKey = cloudAssetKey
        self.thumbnailRelativePath = thumbnailRelativePath
        self.sourceDevice = sourceDevice
        self.isPinned = isPinned
    }

    public var shortPreview: String {
        String(previewText.prefix(80))
    }

    public var copyText: String? {
        type == .text ? previewText : nil
    }
}

public extension ClipboardEntry {
    static let mockItems: [ClipboardEntry] = [
        ClipboardEntry(type: .text, title: "会议纪要", previewText: "今天的目标是完成 iOS 同步与小组件。", sourceDevice: "Mac"),
        ClipboardEntry(type: .pdf, title: "报价单.pdf", previewText: "PDF 文件已从 Mac 同步", fileName: "报价单.pdf", mimeType: "application/pdf", sourceDevice: "Mac"),
        ClipboardEntry(type: .image, title: "设计稿.png", previewText: "图片文件", fileName: "设计稿.png", mimeType: "image/png", sourceDevice: "Mac")
    ]
}
