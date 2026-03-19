import CloudKit
import Foundation

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

public protocol ClipboardSyncServing {
    func fetchLatest(limit: Int) async throws -> [ClipboardEntry]
    func upload(_ entries: [ClipboardEntry]) async throws
}

public struct CloudKitClipboardSyncService: ClipboardSyncServing {
    private let container: CKContainer
    private let database: CKDatabase
    private let recordType = "ClipboardEntry"

    public init(containerIdentifier: String = "iCloud.com.liangweibin.clipboardboard") {
        let container = CKContainer(identifier: containerIdentifier)
        self.container = container
        self.database = container.privateCloudDatabase
    }

    public func fetchLatest(limit: Int) async throws -> [ClipboardEntry] {
        let query = CKQuery(recordType: recordType, predicate: NSPredicate(value: true))
        query.sortDescriptors = [NSSortDescriptor(key: "createdAt", ascending: false)]

        let results = try await database.records(matching: query, resultsLimit: limit)
        let records = results.matchResults.compactMap { _, result -> CKRecord? in
            try? result.get()
        }

        return records.compactMap { record in
            var entry = Self.mapRecord(record)
            if let asset = record["asset"] as? CKAsset,
               let fileURL = asset.fileURL,
               let relativePath = Self.persistAssetFile(from: fileURL, preferredName: entry?.fileName ?? fileURL.lastPathComponent) {
                entry?.localRelativePath = relativePath
            }
            return entry
        }
        .sorted { $0.createdAt > $1.createdAt }
    }

    public func upload(_ entries: [ClipboardEntry]) async throws {
        let records = entries.map(Self.makeRecord(_:))
        _ = try await database.modifyRecords(saving: records, deleting: [])
    }

    private static func mapRecord(_ record: CKRecord) -> ClipboardEntry? {
                guard let idString = record[ClipboardCloudRecordKey.id] as? String,
              let id = UUID(uuidString: idString),
                            let createdAt = record[ClipboardCloudRecordKey.createdAt] as? Date,
                            let typeRawValue = record[ClipboardCloudRecordKey.type] as? String,
              let type = ClipboardEntryType(rawValue: typeRawValue),
                            let title = record[ClipboardCloudRecordKey.title] as? String,
                            let previewText = record[ClipboardCloudRecordKey.previewText] as? String,
                            let sourceDevice = record[ClipboardCloudRecordKey.sourceDevice] as? String else {
            return nil
        }

        return ClipboardEntry(
            id: id,
            createdAt: createdAt,
            type: type,
            title: title,
            previewText: previewText,
            fileName: record[ClipboardCloudRecordKey.fileName] as? String,
            mimeType: record[ClipboardCloudRecordKey.mimeType] as? String,
            localRelativePath: record[ClipboardCloudRecordKey.localRelativePath] as? String,
            cloudAssetKey: record[ClipboardCloudRecordKey.cloudAssetKey] as? String,
            thumbnailRelativePath: record[ClipboardCloudRecordKey.thumbnailRelativePath] as? String,
            sourceDevice: sourceDevice,
            isPinned: record[ClipboardCloudRecordKey.isPinned] as? Int == 1
        )
    }

    private static func makeRecord(_ entry: ClipboardEntry) -> CKRecord {
        let record = CKRecord(recordType: "ClipboardEntry", recordID: CKRecord.ID(recordName: entry.id.uuidString))
        record[ClipboardCloudRecordKey.id] = entry.id.uuidString
        record[ClipboardCloudRecordKey.createdAt] = entry.createdAt
        record[ClipboardCloudRecordKey.type] = entry.type.rawValue
        record[ClipboardCloudRecordKey.title] = entry.title
        record[ClipboardCloudRecordKey.previewText] = entry.previewText
        record[ClipboardCloudRecordKey.fileName] = entry.fileName
        record[ClipboardCloudRecordKey.mimeType] = entry.mimeType
        record[ClipboardCloudRecordKey.localRelativePath] = entry.localRelativePath
        record[ClipboardCloudRecordKey.cloudAssetKey] = entry.cloudAssetKey
        record[ClipboardCloudRecordKey.thumbnailRelativePath] = entry.thumbnailRelativePath
        record[ClipboardCloudRecordKey.sourceDevice] = entry.sourceDevice
        record[ClipboardCloudRecordKey.isPinned] = entry.isPinned ? 1 : 0
        return record
    }

    private static func persistAssetFile(from sourceURL: URL, preferredName: String) -> String? {
        guard let directoryURL = AppGroupStore.localFilesDirectory() else {
            return nil
        }

        let targetFileName = preferredName.isEmpty ? sourceURL.lastPathComponent : preferredName
        let targetURL = directoryURL.appendingPathComponent(targetFileName, isDirectory: false)

        do {
            if FileManager.default.fileExists(atPath: targetURL.path) {
                try FileManager.default.removeItem(at: targetURL)
            }
            try FileManager.default.copyItem(at: sourceURL, to: targetURL)
            return targetFileName
        } catch {
            return nil
        }
    }
}
