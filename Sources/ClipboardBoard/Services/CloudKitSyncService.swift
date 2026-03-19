import CloudKit
import Foundation
import UniformTypeIdentifiers

private enum ClipboardCloudRecordKey {
    static let id = "id"
    static let createdAt = "createdAt"
    static let type = "type"
    static let title = "title"
    static let previewText = "previewText"
    static let fileName = "fileName"
    static let mimeType = "mimeType"
    static let localRelativePath = "localRelativePath"
    static let cloudAssetKey = "cloudAssetKey"
    static let thumbnailRelativePath = "thumbnailRelativePath"
    static let sourceDevice = "sourceDevice"
    static let isPinned = "isPinned"
    static let asset = "asset"
}

@MainActor
final class ClipboardCloudSyncService {
    private let container: CKContainer
    private let database: CKDatabase
    private let persistence: ClipboardPersistenceController
    private let recordType = "ClipboardEntry"
    private let sourceDevice: String
    private var uploadTask: Task<Void, Never>?

    init(
        containerIdentifier: String = "iCloud.com.liangweibin.clipboardboard",
        persistence: ClipboardPersistenceController = .shared
    ) {
        self.container = CKContainer(identifier: containerIdentifier)
        self.database = container.privateCloudDatabase
        self.persistence = persistence
        self.sourceDevice = Host.current().localizedName ?? "Mac"
    }

    func scheduleUpload(items: [ClipboardItem]) {
        uploadTask?.cancel()
        let snapshot = Array(items.prefix(50))

        uploadTask = Task { [weak self] in
            do {
                try await Task.sleep(for: .seconds(1.2))
                guard !Task.isCancelled else {
                    return
                }
                await self?.upload(snapshot)
            } catch {
                return
            }
        }
    }

    func syncNow(items: [ClipboardItem]) {
        scheduleUpload(items: items)
    }

    private func upload(_ items: [ClipboardItem]) async {
        let records = items.map(makeRecord)

        do {
            _ = try await database.modifyRecords(saving: records, deleting: [])
        } catch {
            NSLog("CloudKit sync failed: %@", error.localizedDescription)
        }
    }

    private func makeRecord(for item: ClipboardItem) -> CKRecord {
        let recordID = CKRecord.ID(recordName: item.id.uuidString)
        let record = CKRecord(recordType: recordType, recordID: recordID)

        record[ClipboardCloudRecordKey.id] = item.id.uuidString as CKRecordValue
        record[ClipboardCloudRecordKey.createdAt] = item.timestamp as CKRecordValue
        record[ClipboardCloudRecordKey.type] = syncType(for: item).rawValue as CKRecordValue
        record[ClipboardCloudRecordKey.title] = item.title as CKRecordValue
        record[ClipboardCloudRecordKey.previewText] = (item.previewText ?? item.title) as CKRecordValue
        record[ClipboardCloudRecordKey.fileName] = fileName(for: item) as CKRecordValue?
        record[ClipboardCloudRecordKey.mimeType] = mimeType(for: item) as CKRecordValue?
        record[ClipboardCloudRecordKey.localRelativePath] = nil
        record[ClipboardCloudRecordKey.cloudAssetKey] = cloudAssetKey(for: item) as CKRecordValue?
        record[ClipboardCloudRecordKey.thumbnailRelativePath] = nil
        record[ClipboardCloudRecordKey.sourceDevice] = sourceDevice as CKRecordValue
        record[ClipboardCloudRecordKey.isPinned] = 0 as CKRecordValue

        if let assetURL = assetURL(for: item) {
            record[ClipboardCloudRecordKey.asset] = CKAsset(fileURL: assetURL)
        }

        return record
    }

    private func syncType(for item: ClipboardItem) -> SyncedClipboardEntryType {
        switch item.contentKind {
        case .text:
            return .text
        case .image:
            return .image
        case .pdf:
            return .pdf
        case .doc:
            return .doc
        case .audio:
            return .audio
        case .video:
            return .video
        case .files:
            return .file
        case .file:
            return .file
        }
    }

    private func fileName(for item: ClipboardItem) -> String? {
        if let firstURL = item.fileURLs.first {
            return firstURL.lastPathComponent
        }
        if let payloadFileName = item.payloadFileName {
            return payloadFileName
        }
        return nil
    }

    private func cloudAssetKey(for item: ClipboardItem) -> String? {
        assetURL(for: item)?.lastPathComponent
    }

    private func assetURL(for item: ClipboardItem) -> URL? {
        if let firstURL = item.fileURLs.first, FileManager.default.fileExists(atPath: firstURL.path) {
            return firstURL
        }

        if let payloadFileName = item.payloadFileName {
            let url = persistence.payloadURL(for: payloadFileName)
            if FileManager.default.fileExists(atPath: url.path) {
                return url
            }
        }

        return nil
    }

    private func mimeType(for item: ClipboardItem) -> String? {
        if let firstURL = item.fileURLs.first,
           let type = UTType(filenameExtension: firstURL.pathExtension) {
            return type.preferredMIMEType
        }

        if let pasteboardTypeIdentifier = item.pasteboardTypeIdentifier,
           let type = UTType(pasteboardTypeIdentifier) {
            return type.preferredMIMEType
        }

        switch item.contentKind {
        case .text:
            return "text/plain"
        case .image:
            return "image/tiff"
        case .pdf:
            return "application/pdf"
        case .doc:
            return "application/msword"
        case .audio:
            return "audio/mpeg"
        case .video:
            return "video/mp4"
        case .file, .files:
            return "application/octet-stream"
        }
    }
}

enum SyncedClipboardEntryType: String {
    case text
    case image
    case pdf
    case doc
    case audio
    case video
    case file
}
