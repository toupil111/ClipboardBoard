import Foundation

public actor ClipboardCacheStore {
    public static let shared = ClipboardCacheStore()

    private let encoder = JSONEncoder()
    private let decoder = JSONDecoder()

    public init() {
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        encoder.dateEncodingStrategy = .iso8601
        decoder.dateDecodingStrategy = .iso8601
    }

    public func saveWidgetItems(_ items: [ClipboardEntry], limit: Int = 6) throws {
        guard let url = AppGroupStore.widgetCacheURL() else { return }
        let payload = Array(items.prefix(limit))
        let data = try encoder.encode(payload)
        try data.write(to: url, options: [.atomic])
    }

    public func loadWidgetItems() -> [ClipboardEntry] {
        guard let url = AppGroupStore.widgetCacheURL(),
              let data = try? Data(contentsOf: url),
              let items = try? decoder.decode([ClipboardEntry].self, from: data) else {
            return ClipboardEntry.mockItems
        }
        return items
    }
}
