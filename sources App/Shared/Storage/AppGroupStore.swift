import Foundation

public enum AppGroupStore {
    public static let suiteName = "group.com.liangweibin.clipboardboard"
    public static let widgetItemsKey = "widget_items.json"

    public static var containerURL: URL? {
        FileManager.default.containerURL(forSecurityApplicationGroupIdentifier: suiteName)
    }

    public static func widgetCacheURL() -> URL? {
        containerURL?.appendingPathComponent(widgetItemsKey, isDirectory: false)
    }

    public static func localFilesDirectory() -> URL? {
        guard let url = containerURL?.appendingPathComponent("Files", isDirectory: true) else {
            return nil
        }
        try? FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        return url
    }
}
