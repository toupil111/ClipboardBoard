import Foundation

public enum ClipboardFileLocator {
    public static func localFileURL(for entry: ClipboardEntry) -> URL? {
        guard let localRelativePath = entry.localRelativePath,
              let baseURL = AppGroupStore.localFilesDirectory() else {
            return nil
        }
        let fileURL = baseURL.appendingPathComponent(localRelativePath, isDirectory: false)
        return FileManager.default.fileExists(atPath: fileURL.path) ? fileURL : nil
    }

    public static func isAvailableLocally(_ entry: ClipboardEntry) -> Bool {
        localFileURL(for: entry) != nil
    }
}
