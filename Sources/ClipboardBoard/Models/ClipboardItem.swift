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

enum ClipboardDetectedLabel: String, Codable {
    case email
    case phone
    case account

    var title: String {
        switch self {
        case .email:
            return "邮箱"
        case .phone:
            return "手机号"
        case .account:
            return "账号"
        }
    }

    var symbolName: String {
        switch self {
        case .email:
            return "envelope"
        case .phone:
            return "phone"
        case .account:
            return "person.crop.circle"
        }
    }
}

struct ClipboardCapture {
    let item: ClipboardItem
    let payloadData: Data?
}

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
    let isFavorite: Bool
    let isPinned: Bool
    let isSensitive: Bool
    let secondaryEncryptedPreviewText: Data?
    let sensitiveRevealTimeoutSeconds: Int?
    let blocksAutoPaste: Bool
    let estimatedSizeBytes: Int64
    let duplicateCount: Int
    let customTags: [String]

    @MainActor private static let previewCache = NSCache<NSString, NSImage>()
    @MainActor private static let fileIconCache = NSCache<NSString, NSImage>()
    private static let emailPattern = try! NSRegularExpression(pattern: #"[A-Z0-9._%+-]+@[A-Z0-9.-]+\.[A-Z]{2,}"#, options: [.caseInsensitive])
    private static let phonePattern = try! NSRegularExpression(pattern: #"(?<!\d)(?:\+?86[- ]?)?1[3-9]\d{9}(?!\d)"#, options: [])

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
        fingerprint: String,
        isFavorite: Bool = false,
        isPinned: Bool = false,
        isSensitive: Bool = false,
        secondaryEncryptedPreviewText: Data? = nil,
        sensitiveRevealTimeoutSeconds: Int? = nil,
        blocksAutoPaste: Bool = false,
        estimatedSizeBytes: Int64 = 0,
        duplicateCount: Int = 1,
        customTags: [String] = []
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
        self.isFavorite = isFavorite
        self.isPinned = isPinned
        self.isSensitive = isSensitive
        self.secondaryEncryptedPreviewText = secondaryEncryptedPreviewText
        self.sensitiveRevealTimeoutSeconds = sensitiveRevealTimeoutSeconds
        self.blocksAutoPaste = blocksAutoPaste
        self.estimatedSizeBytes = estimatedSizeBytes
        self.duplicateCount = max(duplicateCount, 1)
        self.customTags = Array(Set(customTags.map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }.filter { !$0.isEmpty })).sorted()
    }

    enum CodingKeys: String, CodingKey {
        case id
        case timestamp
        case title
        case subtitle
        case contentKind
        case previewText
        case previewImageData
        case pasteboardTypeIdentifier
        case fileURLs
        case payloadFileName
        case fingerprint
        case isFavorite
        case isPinned
        case isSensitive
        case secondaryEncryptedPreviewText
        case sensitiveRevealTimeoutSeconds
        case blocksAutoPaste
        case estimatedSizeBytes
        case duplicateCount
        case customTags
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decode(UUID.self, forKey: .id)
        timestamp = try container.decode(Date.self, forKey: .timestamp)
        title = try container.decode(String.self, forKey: .title)
        subtitle = try container.decode(String.self, forKey: .subtitle)
        contentKind = try container.decode(ClipboardContentKind.self, forKey: .contentKind)
        previewText = try container.decodeIfPresent(String.self, forKey: .previewText)
        previewImageData = try container.decodeIfPresent(Data.self, forKey: .previewImageData)
        pasteboardTypeIdentifier = try container.decodeIfPresent(String.self, forKey: .pasteboardTypeIdentifier)
        fileURLs = try container.decodeIfPresent([URL].self, forKey: .fileURLs) ?? []
        payloadFileName = try container.decodeIfPresent(String.self, forKey: .payloadFileName)
        fingerprint = try container.decode(String.self, forKey: .fingerprint)
        isFavorite = try container.decodeIfPresent(Bool.self, forKey: .isFavorite) ?? false
        isPinned = try container.decodeIfPresent(Bool.self, forKey: .isPinned) ?? false
        isSensitive = try container.decodeIfPresent(Bool.self, forKey: .isSensitive) ?? false
        secondaryEncryptedPreviewText = try container.decodeIfPresent(Data.self, forKey: .secondaryEncryptedPreviewText)
        sensitiveRevealTimeoutSeconds = try container.decodeIfPresent(Int.self, forKey: .sensitiveRevealTimeoutSeconds)
        blocksAutoPaste = try container.decodeIfPresent(Bool.self, forKey: .blocksAutoPaste) ?? false
        estimatedSizeBytes = try container.decodeIfPresent(Int64.self, forKey: .estimatedSizeBytes) ?? 0
        duplicateCount = try container.decodeIfPresent(Int.self, forKey: .duplicateCount) ?? 1
        customTags = try container.decodeIfPresent([String].self, forKey: .customTags) ?? []
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(id, forKey: .id)
        try container.encode(timestamp, forKey: .timestamp)
        try container.encode(title, forKey: .title)
        try container.encode(subtitle, forKey: .subtitle)
        try container.encode(contentKind, forKey: .contentKind)
        try container.encodeIfPresent(previewText, forKey: .previewText)
        try container.encodeIfPresent(previewImageData, forKey: .previewImageData)
        try container.encodeIfPresent(pasteboardTypeIdentifier, forKey: .pasteboardTypeIdentifier)
        try container.encode(fileURLs, forKey: .fileURLs)
        try container.encodeIfPresent(payloadFileName, forKey: .payloadFileName)
        try container.encode(fingerprint, forKey: .fingerprint)
        try container.encode(isFavorite, forKey: .isFavorite)
        try container.encode(isPinned, forKey: .isPinned)
        try container.encode(isSensitive, forKey: .isSensitive)
        try container.encodeIfPresent(secondaryEncryptedPreviewText, forKey: .secondaryEncryptedPreviewText)
        try container.encodeIfPresent(sensitiveRevealTimeoutSeconds, forKey: .sensitiveRevealTimeoutSeconds)
        try container.encode(blocksAutoPaste, forKey: .blocksAutoPaste)
        try container.encode(estimatedSizeBytes, forKey: .estimatedSizeBytes)
        try container.encode(duplicateCount, forKey: .duplicateCount)
        try container.encode(customTags, forKey: .customTags)
    }

    @MainActor
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
                fingerprint: Self.sha256(text),
                estimatedSizeBytes: Int64(Data(text.utf8).count)
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
                fingerprint: Self.sha256(data),
                estimatedSizeBytes: Int64(data.count)
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
                fingerprint: Self.sha256(pdfData),
                estimatedSizeBytes: Int64(pdfData.count)
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
                    fingerprint: Self.sha256(data),
                    estimatedSizeBytes: Int64(data.count)
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
            fingerprint: fingerprint,
            isFavorite: isFavorite,
            isPinned: isPinned,
            isSensitive: isSensitive,
            secondaryEncryptedPreviewText: secondaryEncryptedPreviewText,
            sensitiveRevealTimeoutSeconds: sensitiveRevealTimeoutSeconds,
            blocksAutoPaste: blocksAutoPaste,
            estimatedSizeBytes: estimatedSizeBytes,
            duplicateCount: duplicateCount,
            customTags: customTags
        )
    }

    func withFavorite(_ isFavorite: Bool) -> ClipboardItem {
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
            fingerprint: fingerprint,
            isFavorite: isFavorite,
            isPinned: isPinned,
            isSensitive: isSensitive,
            secondaryEncryptedPreviewText: secondaryEncryptedPreviewText,
            sensitiveRevealTimeoutSeconds: sensitiveRevealTimeoutSeconds,
            blocksAutoPaste: blocksAutoPaste,
            estimatedSizeBytes: estimatedSizeBytes,
            duplicateCount: duplicateCount,
            customTags: customTags
        )
    }

    func withPinned(_ isPinned: Bool) -> ClipboardItem {
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
            fingerprint: fingerprint,
            isFavorite: isFavorite,
            isPinned: isPinned,
            isSensitive: isSensitive,
            secondaryEncryptedPreviewText: secondaryEncryptedPreviewText,
            sensitiveRevealTimeoutSeconds: sensitiveRevealTimeoutSeconds,
            blocksAutoPaste: blocksAutoPaste,
            estimatedSizeBytes: estimatedSizeBytes,
            duplicateCount: duplicateCount,
            customTags: customTags
        )
    }

    func withSensitive(_ isSensitive: Bool) -> ClipboardItem {
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
            fingerprint: fingerprint,
            isFavorite: isFavorite,
            isPinned: isPinned,
            isSensitive: isSensitive,
            secondaryEncryptedPreviewText: isSensitive ? secondaryEncryptedPreviewText : nil,
            sensitiveRevealTimeoutSeconds: isSensitive ? sensitiveRevealTimeoutSeconds : nil,
            blocksAutoPaste: false,
            estimatedSizeBytes: estimatedSizeBytes,
            duplicateCount: duplicateCount,
            customTags: customTags
        )
    }

    func withSensitiveTimeout(_ timeout: Int?) -> ClipboardItem {
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
            fingerprint: fingerprint,
            isFavorite: isFavorite,
            isPinned: isPinned,
            isSensitive: isSensitive,
            secondaryEncryptedPreviewText: secondaryEncryptedPreviewText,
            sensitiveRevealTimeoutSeconds: timeout,
            blocksAutoPaste: blocksAutoPaste,
            estimatedSizeBytes: estimatedSizeBytes,
            duplicateCount: duplicateCount,
            customTags: customTags
        )
    }

    func withResolvedPreviewText(_ previewText: String?) -> ClipboardItem {
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
            fingerprint: fingerprint,
            isFavorite: isFavorite,
            isPinned: isPinned,
            isSensitive: isSensitive,
            secondaryEncryptedPreviewText: secondaryEncryptedPreviewText,
            sensitiveRevealTimeoutSeconds: sensitiveRevealTimeoutSeconds,
            blocksAutoPaste: blocksAutoPaste,
            estimatedSizeBytes: estimatedSizeBytes,
            duplicateCount: duplicateCount,
            customTags: customTags
        )
    }

    func withSecondaryEncryptedPreviewText(_ encryptedData: Data?, previewText: String?) -> ClipboardItem {
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
            fingerprint: fingerprint,
            isFavorite: isFavorite,
            isPinned: isPinned,
            isSensitive: isSensitive,
            secondaryEncryptedPreviewText: encryptedData,
            sensitiveRevealTimeoutSeconds: sensitiveRevealTimeoutSeconds,
            blocksAutoPaste: blocksAutoPaste,
            estimatedSizeBytes: estimatedSizeBytes,
            duplicateCount: duplicateCount,
            customTags: customTags
        )
    }

    func withDuplicateCount(_ duplicateCount: Int) -> ClipboardItem {
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
            fingerprint: fingerprint,
            isFavorite: isFavorite,
            isPinned: isPinned,
            isSensitive: isSensitive,
            secondaryEncryptedPreviewText: secondaryEncryptedPreviewText,
            sensitiveRevealTimeoutSeconds: sensitiveRevealTimeoutSeconds,
            blocksAutoPaste: blocksAutoPaste,
            estimatedSizeBytes: estimatedSizeBytes,
            duplicateCount: duplicateCount,
            customTags: customTags
        )
    }

    func mergingDuplicateMetadata(from existing: ClipboardItem) -> ClipboardItem {
        ClipboardItem(
            id: existing.id,
            timestamp: timestamp,
            title: title,
            subtitle: subtitle,
            contentKind: contentKind,
            previewText: previewText,
            previewImageData: previewImageData,
            pasteboardTypeIdentifier: pasteboardTypeIdentifier,
            fileURLs: fileURLs,
            payloadFileName: payloadFileName,
            fingerprint: fingerprint,
            isFavorite: existing.isFavorite,
            isPinned: existing.isPinned,
            isSensitive: existing.isSensitive,
            secondaryEncryptedPreviewText: existing.secondaryEncryptedPreviewText,
            sensitiveRevealTimeoutSeconds: existing.sensitiveRevealTimeoutSeconds,
            blocksAutoPaste: existing.blocksAutoPaste,
            estimatedSizeBytes: estimatedSizeBytes,
            duplicateCount: existing.duplicateCount + 1,
            customTags: existing.customTags
        )
    }

    func withCustomTags(_ customTags: [String], markFavorite: Bool? = nil) -> ClipboardItem {
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
            fingerprint: fingerprint,
            isFavorite: markFavorite ?? isFavorite,
            isPinned: isPinned,
            isSensitive: isSensitive,
            secondaryEncryptedPreviewText: secondaryEncryptedPreviewText,
            sensitiveRevealTimeoutSeconds: sensitiveRevealTimeoutSeconds,
            blocksAutoPaste: blocksAutoPaste,
            estimatedSizeBytes: estimatedSizeBytes,
            customTags: customTags
        )
    }

    var displayTags: [String] {
        var tags = customTags
        if isSensitive, !tags.contains("敏感") {
            tags.insert("敏感", at: 0)
        }
        if let quickTagTitle, !tags.contains(quickTagTitle) {
            tags.insert(quickTagTitle, at: 0)
        }
        return tags
    }

    var protectedPreviewText: String? {
        guard isSensitive else {
            return previewText
        }

        let count = max((previewText ?? title).count, 8)
        return String(repeating: "•", count: min(count, 24))
    }

    func partiallyRevealedPreviewText(visibleCount preferredVisibleCount: Int) -> String? {
        guard isSensitive else {
            return previewText
        }

        let source = previewText ?? title
        guard !source.isEmpty else {
            return nil
        }

        let visibleCount = min(max(preferredVisibleCount, 1), source.count)
        let prefixText = String(source.prefix(visibleCount))
        let maskedCount = min(max(source.count - visibleCount, 4), 20)
        return prefixText + String(repeating: "•", count: maskedCount)
    }

    var hasCustomSensitiveTimeout: Bool {
        sensitiveRevealTimeoutSeconds != nil
    }

    var duplicateBadgeTitle: String? {
        duplicateCount > 1 ? "合并 \(duplicateCount) 次" : nil
    }

    func isLargeAttachment(thresholdMB: Int) -> Bool {
        estimatedSizeBytes >= Int64(max(thresholdMB, 1)) * 1_048_576
    }

    func isSemanticallySimilar(to other: ClipboardItem) -> Bool {
        guard contentKind == other.contentKind else {
            return false
        }

        switch contentKind {
        case .text, .doc:
            return normalizedSearchBody == other.normalizedSearchBody
        case .image, .pdf:
            return fingerprint == other.fingerprint
        case .audio, .video, .file, .files:
            if !fileURLs.isEmpty || !other.fileURLs.isEmpty {
                return fileURLs.map(\.path).sorted() == other.fileURLs.map(\.path).sorted()
            }
            return fingerprint == other.fingerprint || (title == other.title && estimatedSizeBytes == other.estimatedSizeBytes)
        }
    }

    private var normalizedSearchBody: String {
        [title, subtitle, previewText ?? "", fileURLs.map(\.lastPathComponent).joined(separator: " ")]
            .joined(separator: " ")
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .replacingOccurrences(of: #"\s+"#, with: " ", options: .regularExpression)
            .lowercased()
    }

    var detectedLabel: ClipboardDetectedLabel? {
        guard contentKind == .text || contentKind == .doc else {
            return nil
        }

        let source = [title, previewText ?? ""].joined(separator: "\n")
        let sourceRange = NSRange(source.startIndex..<source.endIndex, in: source)

        if Self.emailPattern.firstMatch(in: source, range: sourceRange) != nil {
            return .email
        }

        if Self.phonePattern.firstMatch(in: source, range: sourceRange) != nil {
            return .phone
        }

        let normalized = source.lowercased()
        if normalized.contains("账号") || normalized.contains("account") || normalized.contains("login") || normalized.contains("user") || normalized.contains("用户名") || normalized.contains("id:") {
            return .account
        }

        return nil
    }

    var quickTagTitle: String? {
        detectedLabel?.title
    }

    @MainActor
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

    @MainActor
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

    @MainActor
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
            fingerprint: sha256(fingerprintSource),
            estimatedSizeBytes: urls.reduce(into: Int64(0)) { partialResult, url in
                let resource = try? url.resourceValues(forKeys: [.fileSizeKey])
                partialResult += Int64(resource?.fileSize ?? 0)
            }
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

    @MainActor
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
