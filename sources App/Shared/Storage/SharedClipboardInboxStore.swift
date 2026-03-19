import Foundation

public actor SharedClipboardInboxStore {
    public static let shared = SharedClipboardInboxStore()

    private let encoder = JSONEncoder()
    private let decoder = JSONDecoder()

    public init() {
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        encoder.dateEncodingStrategy = .iso8601
        decoder.dateDecodingStrategy = .iso8601
    }

    public func loadEntries() -> [ClipboardEntry] {
        guard let url = storageURL(),
              let data = try? Data(contentsOf: url),
              let entries = try? decoder.decode([ClipboardEntry].self, from: data) else {
            return []
        }
        return entries.sorted { $0.createdAt > $1.createdAt }
    }

    public func append(_ entry: ClipboardEntry) throws {
        var entries = loadEntries()
        entries.removeAll { $0.id == entry.id }
        entries.insert(entry, at: 0)
        entries = Array(entries.prefix(50))
        try save(entries)
    }

    private func save(_ entries: [ClipboardEntry]) throws {
        guard let url = storageURL() else { return }
        let data = try encoder.encode(entries)
        try data.write(to: url, options: [.atomic])
    }

    private func storageURL() -> URL? {
        AppGroupStore.containerURL?.appendingPathComponent("shared_inbox.json", isDirectory: false)
    }
}
