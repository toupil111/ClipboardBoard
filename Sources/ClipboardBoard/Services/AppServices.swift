import AppKit
import ApplicationServices
import Carbon
import Security
import ServiceManagement
import SwiftUI

enum AppCapabilityInspector {
    static func hasICloudEntitlement() -> Bool {
        guard let task = SecTaskCreateFromSelf(nil) else {
            return false
        }

        let entitlement = SecTaskCopyValueForEntitlement(
            task,
            "com.apple.developer.icloud-services" as CFString,
            nil
        )

        return entitlement != nil
    }
}

struct ClipboardBackupVersion: Identifiable, Hashable {
    let url: URL
    let name: String
    let createdAt: Date
    let fileSize: Int64
    let itemCount: Int
    let sensitiveItemCount: Int

    var id: String { url.lastPathComponent }
}

struct ClipboardStatusSummary {
    let itemCount: Int
    let latestBackupDate: Date?
    let latestBackupName: String?

    var menuTitle: String {
        var parts = ["历史 \(itemCount) 条"]
        if let latestBackupDate {
            parts.append("最近备份 \(latestBackupDate.formatted(date: .abbreviated, time: .shortened))")
        } else {
            parts.append("暂无备份")
        }
        if let latestBackupName, !latestBackupName.isEmpty {
            parts.append("快照 \(latestBackupName)")
        }
        return parts.joined(separator: " · ")
    }

    var toolTip: String {
        "ClipboardBoard\n\(menuTitle)"
    }
}

struct ClipboardStorageUsage {
    let historyBytes: Int64
    let backupsBytes: Int64
    let payloadsBytes: Int64

    var totalBytes: Int64 {
        historyBytes + backupsBytes + payloadsBytes
    }
}

struct ClipboardCleanupPolicy {
    let autoCleanupOldBackupsEnabled: Bool
    let keepBackupCount: Int
}

@MainActor
final class ClipboardPersistenceController {
    static let shared = ClipboardPersistenceController()

    private let fileManager = FileManager.default
    private let encoder = JSONEncoder()
    private let decoder = JSONDecoder()
    private let directoryURL: URL
    private let payloadsURL: URL
    private let backupsURL: URL
    private let historyURL: URL
    private let customTagsURL: URL
    private let cryptoService = SecureCryptoService.shared
    private let sensitiveCryptoService = SecureCryptoService.sensitiveContent

    init() {
        let applicationSupport = fileManager.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
        directoryURL = applicationSupport.appendingPathComponent("ClipboardBoard", isDirectory: true)
        payloadsURL = directoryURL.appendingPathComponent("Payloads", isDirectory: true)
        backupsURL = directoryURL.appendingPathComponent("Backups", isDirectory: true)
        historyURL = directoryURL.appendingPathComponent("history.json", isDirectory: false)
        customTagsURL = directoryURL.appendingPathComponent("custom-tags.json", isDirectory: false)

        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        decoder.dateDecodingStrategy = .iso8601
        encoder.dateEncodingStrategy = .iso8601

        ensureDirectories()
    }

    func loadItems(limit: Int) -> [ClipboardItem] {
        ensureDirectories()

        guard let data = try? Data(contentsOf: historyURL),
              let items = decodeItems(from: data) else {
            return []
        }

        let limitedItems = Array(items.prefix(limit))
        cleanupPayloadFiles(keeping: Set(limitedItems.compactMap(\.payloadFileName)))
        return limitedItems
    }

    func loadBackupVersions(limit: Int = 8) -> [ClipboardBackupVersion] {
        ensureDirectories()

        let urls = (try? fileManager.contentsOfDirectory(
            at: backupsURL,
            includingPropertiesForKeys: [.creationDateKey, .contentModificationDateKey, .fileSizeKey],
            options: [.skipsHiddenFiles]
        )) ?? []

        return urls.compactMap { url in
            let resource = try? url.resourceValues(forKeys: [.creationDateKey, .contentModificationDateKey, .fileSizeKey])
            let createdAt = resource?.creationDate ?? resource?.contentModificationDate ?? Date.distantPast
            let fileSize = Int64(resource?.fileSize ?? 0)
            let items = (try? Data(contentsOf: url)).flatMap(decodeItems(from:)) ?? []
            let parsedName = displayName(forBackupURL: url, createdAt: createdAt)

            return ClipboardBackupVersion(
                url: url,
                name: parsedName,
                createdAt: createdAt,
                fileSize: fileSize,
                itemCount: items.count,
                sensitiveItemCount: items.filter(\.isSensitive).count
            )
        }
        .sorted { $0.createdAt > $1.createdAt }
        .prefix(limit)
        .map { $0 }
    }

    func restoreItems(from backup: ClipboardBackupVersion, limit: Int) -> [ClipboardItem]? {
        guard let data = try? Data(contentsOf: backup.url),
              let items = decodeItems(from: data) else {
            return nil
        }

        let limitedItems = Array(items.prefix(limit))
        save(items: limitedItems)
        return limitedItems
    }

    func deleteBackup(_ backup: ClipboardBackupVersion) {
        try? fileManager.removeItem(at: backup.url)
    }

    func purgeOldBackups(keeping limit: Int) {
        let safeLimit = max(1, limit)
        let backups = loadBackupVersions(limit: .max)
        guard backups.count > safeLimit else {
            return
        }

        for backup in backups.dropFirst(safeLimit) {
            try? fileManager.removeItem(at: backup.url)
        }
    }

    func createManualBackup(name: String, items: [ClipboardItem]) -> ClipboardBackupVersion? {
        ensureDirectories()
        let normalized = normalizedBackupName(name)
                let sanitizedItems = prepareItemsForStorage(items)
                guard !normalized.isEmpty,
                            let data = try? encoder.encode(sanitizedItems),
              let encryptedData = try? cryptoService.encrypt(data, containsSensitiveItems: items.contains(where: { $0.isSensitive })) else {
            return nil
        }

        let fileName = "manual-\(normalized)-\(timestampString()).bak"
        let backupURL = backupsURL.appendingPathComponent(fileName, isDirectory: false)
        try? encryptedData.write(to: backupURL, options: [.atomic])
        cleanupBackupsIfNeeded(limit: 8)
        return loadBackupVersions(limit: 8).first { $0.url == backupURL }
    }

    func renameBackup(_ backup: ClipboardBackupVersion, to name: String) -> ClipboardBackupVersion? {
        ensureDirectories()
        let normalized = normalizedBackupName(name)
        guard !normalized.isEmpty else {
            return nil
        }

        let fileName = "manual-\(normalized)-\(timestampString(from: backup.createdAt)).bak"
        let targetURL = backupsURL.appendingPathComponent(fileName, isDirectory: false)
        guard targetURL != backup.url else {
            return backup
        }

        try? fileManager.removeItem(at: targetURL)
        do {
            try fileManager.moveItem(at: backup.url, to: targetURL)
        } catch {
            return nil
        }

        return loadBackupVersions(limit: 8).first { $0.url == targetURL }
    }

    func exportBackup(_ backup: ClipboardBackupVersion) -> Bool {
        let savePanel = NSSavePanel()
        savePanel.canCreateDirectories = true
        savePanel.nameFieldStringValue = backup.url.lastPathComponent
        savePanel.title = "导出备份快照"
        savePanel.message = "导出选中的本地加密备份文件。"

        guard savePanel.runModal() == .OK,
              let url = savePanel.url,
              let data = try? Data(contentsOf: backup.url) else {
            return false
        }

        do {
            try data.write(to: url, options: [.atomic])
            return true
        } catch {
            return false
        }
    }

    func prepare(_ capture: ClipboardCapture) -> ClipboardItem {
        guard let payloadData = capture.payloadData else {
            return capture.item
        }

        ensureDirectories()
        let fileName = "\(capture.item.id.uuidString).payload"
        let targetURL = payloadsURL.appendingPathComponent(fileName, isDirectory: false)
        try? payloadData.write(to: targetURL, options: [.atomic])
        return capture.item.withPayloadFileName(fileName)
    }

    func loadCustomTags() -> [String] {
        ensureDirectories()

        guard let data = try? Data(contentsOf: customTagsURL),
              let tags = try? decoder.decode([String].self, from: data) else {
            return []
        }

        return normalizedTags(tags)
    }

    func saveCustomTags(_ tags: [String]) {
        ensureDirectories()
        guard let data = try? encoder.encode(normalizedTags(tags)) else {
            return
        }

        try? data.write(to: customTagsURL, options: [.atomic])
    }

    func payloadData(for fileName: String) -> Data? {
        let targetURL = payloadsURL.appendingPathComponent(fileName, isDirectory: false)
        return try? Data(contentsOf: targetURL, options: [.mappedIfSafe])
    }

    func payloadURL(for fileName: String) -> URL {
        payloadsURL.appendingPathComponent(fileName, isDirectory: false)
    }

    func openDataDirectory() {
        ensureDirectories()
        NSWorkspace.shared.activateFileViewerSelecting([directoryURL])
    }

    func openBackupsDirectory() {
        ensureDirectories()
        NSWorkspace.shared.activateFileViewerSelecting([backupsURL])
    }

    func openPayloadsDirectory() {
        ensureDirectories()
        NSWorkspace.shared.activateFileViewerSelecting([payloadsURL])
    }

    func loadStorageUsage() -> ClipboardStorageUsage {
        ensureDirectories()

        let historyBytes = fileSize(at: historyURL) + fileSize(at: customTagsURL)
        let backupsBytes = directorySize(at: backupsURL)
        let payloadsBytes = directorySize(at: payloadsURL)

        return ClipboardStorageUsage(
            historyBytes: historyBytes,
            backupsBytes: backupsBytes,
            payloadsBytes: payloadsBytes
        )
    }

    func save(items: [ClipboardItem]) {
        ensureDirectories()
        let sanitizedItems = prepareItemsForStorage(items)

        guard let data = try? encoder.encode(sanitizedItems),
              let encryptedData = try? cryptoService.encrypt(data, containsSensitiveItems: items.contains(where: { $0.isSensitive })) else {
            return
        }

        backupCurrentHistoryIfNeeded()
        try? encryptedData.write(to: historyURL, options: [.atomic])
        cleanupPayloadFiles(keeping: Set(items.compactMap(\.payloadFileName)))
        cleanupBackupsIfNeeded(limit: 8)
    }

    private func ensureDirectories() {
        try? fileManager.createDirectory(at: payloadsURL, withIntermediateDirectories: true)
        try? fileManager.createDirectory(at: backupsURL, withIntermediateDirectories: true)
    }

    private func cleanupPayloadFiles(keeping fileNames: Set<String>) {
        let existingFiles = (try? fileManager.contentsOfDirectory(at: payloadsURL, includingPropertiesForKeys: nil)) ?? []
        for fileURL in existingFiles where !fileNames.contains(fileURL.lastPathComponent) {
            try? fileManager.removeItem(at: fileURL)
        }
    }

    private func normalizedTags(_ tags: [String]) -> [String] {
        Array(Set(tags.map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }.filter { !$0.isEmpty })).sorted()
    }

    private func decodeItems(from data: Data) -> [ClipboardItem]? {
        if let decrypted = try? cryptoService.decrypt(data),
           let decoded = try? decoder.decode([ClipboardItem].self, from: decrypted) {
            return materializeItemsForUsage(decoded)
        }

        if let decoded = try? decoder.decode([ClipboardItem].self, from: data) {
            return materializeItemsForUsage(decoded)
        }
        return nil
    }

    private func backupCurrentHistoryIfNeeded() {
        guard fileManager.fileExists(atPath: historyURL.path),
              let currentData = try? Data(contentsOf: historyURL),
              !currentData.isEmpty else {
            return
        }

        let fileName = "history-\(timestampString()).bak"
        let backupURL = backupsURL.appendingPathComponent(fileName, isDirectory: false)
        try? currentData.write(to: backupURL, options: [.atomic])
    }

    private func timestampString() -> String {
        timestampString(from: Date())
    }

    private func timestampString(from date: Date) -> String {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return formatter.string(from: date).replacingOccurrences(of: ":", with: "-")
    }

    private func normalizedBackupName(_ name: String) -> String {
        name
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .replacingOccurrences(of: #"[^\p{L}\p{N}\s_-]"#, with: "", options: .regularExpression)
            .replacingOccurrences(of: #"\s+"#, with: "_", options: .regularExpression)
    }

    private func displayName(forBackupURL url: URL, createdAt: Date) -> String {
        let rawName = url.deletingPathExtension().lastPathComponent
        if rawName.hasPrefix("manual-") {
            let trimmed = rawName.replacingOccurrences(of: "manual-", with: "")
            let timestamp = timestampString(from: createdAt)
            let cleaned = trimmed.replacingOccurrences(of: "-\(timestamp)", with: "")
            return cleaned.replacingOccurrences(of: "_", with: " ")
        }

        return "自动备份 \(createdAt.formatted(date: .abbreviated, time: .shortened))"
    }

    private func cleanupBackupsIfNeeded(limit: Int) {
        let backups = loadBackupVersions(limit: .max)
        guard backups.count > limit else {
            return
        }

        for backup in backups.dropFirst(limit) {
            try? fileManager.removeItem(at: backup.url)
        }
    }

    private func fileSize(at url: URL) -> Int64 {
        let resourceValues = try? url.resourceValues(forKeys: [.fileSizeKey])
        return Int64(resourceValues?.fileSize ?? 0)
    }

    private func directorySize(at url: URL) -> Int64 {
        let urls = (try? fileManager.contentsOfDirectory(
            at: url,
            includingPropertiesForKeys: [.fileSizeKey],
            options: [.skipsHiddenFiles]
        )) ?? []

        return urls.reduce(into: Int64(0)) { partialResult, childURL in
            partialResult += fileSize(at: childURL)
        }
    }

    private func prepareItemsForStorage(_ items: [ClipboardItem]) -> [ClipboardItem] {
        items.map { item in
            guard item.isSensitive,
                  let previewText = item.previewText,
                  let encrypted = try? sensitiveCryptoService.encrypt(Data(previewText.utf8), containsSensitiveItems: true) else {
                return item
            }

            return item.withSecondaryEncryptedPreviewText(encrypted, previewText: nil)
        }
    }

    private func materializeItemsForUsage(_ items: [ClipboardItem]) -> [ClipboardItem] {
        items.map { item in
            guard item.isSensitive,
                  item.previewText == nil,
                  let encrypted = item.secondaryEncryptedPreviewText,
                  let decrypted = try? sensitiveCryptoService.decrypt(encrypted),
                  let previewText = String(data: decrypted, encoding: .utf8) else {
                return item
            }

            return item.withResolvedPreviewText(previewText)
        }
    }
}

@MainActor
final class ClipboardStore: ObservableObject {
    @Published private(set) var items: [ClipboardItem]
    @Published private(set) var customTags: [String]
    @Published private(set) var backupVersions: [ClipboardBackupVersion]
    @Published private(set) var storageUsage: ClipboardStorageUsage

    var onItemsChanged: (([ClipboardItem]) -> Void)?
    var onCopyCaptured: ((ClipboardItem) -> Void)?
    var cleanupPolicyProvider: (() -> ClipboardCleanupPolicy)?

    let maximumItems = 50
    private let persistence: ClipboardPersistenceController

    init(persistence: ClipboardPersistenceController = .shared) {
        self.persistence = persistence
        self.items = persistence.loadItems(limit: maximumItems)
        self.customTags = persistence.loadCustomTags()
        self.backupVersions = persistence.loadBackupVersions()
        self.storageUsage = persistence.loadStorageUsage()
    }

    func captureCurrentPasteboard(notifyFeedback: Bool = true) {
        autoreleasepool {
            guard let capture = ClipboardItem.capture(from: .general) else {
                return
            }
            append(capture, notifyFeedback: notifyFeedback)
        }
    }

    func restoreItem(_ item: ClipboardItem) {
        item.restore(to: .general, payloadDataProvider: persistence.payloadData)
        moveToFront(item)
    }

    func toggleFavorite(_ item: ClipboardItem) {
        setFavorite(item, isFavorite: !item.isFavorite)
    }

    func setFavorite(_ item: ClipboardItem, isFavorite: Bool) {
        guard let index = items.firstIndex(where: { $0.id == item.id }) else {
            return
        }

        items[index] = items[index].withFavorite(isFavorite)
        persistAndNotifyChanges()
    }

    func togglePin(_ item: ClipboardItem) {
        guard let index = items.firstIndex(where: { $0.id == item.id }) else {
            return
        }

        let shouldPin = !items[index].isPinned
        items = items.map { current in
            if current.id == item.id {
                return current.withPinned(shouldPin)
            }
            return current.isPinned ? current.withPinned(false) : current
        }

        if shouldPin, let pinnedItem = items.first(where: { $0.id == item.id }) {
            moveToFront(pinnedItem, persist: false)
        }

        persistAndNotifyChanges()
    }

    func toggleSensitive(_ item: ClipboardItem) {
        guard let index = items.firstIndex(where: { $0.id == item.id }) else {
            return
        }

        items[index] = items[index].withSensitive(!items[index].isSensitive)
        persistAndNotifyChanges()
    }

    func updateSensitiveTimeout(_ timeout: Int?, for item: ClipboardItem) {
        guard let index = items.firstIndex(where: { $0.id == item.id }) else {
            return
        }

        items[index] = items[index].withSensitiveTimeout(timeout)
        persistAndNotifyChanges()
    }

    func deleteItem(_ item: ClipboardItem) {
        items.removeAll { $0.id == item.id }
        persistAndNotifyChanges()
    }

    @discardableResult
    func createCustomTag(_ name: String) -> String? {
        let normalized = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !normalized.isEmpty else {
            return nil
        }

        if !customTags.contains(normalized) {
            customTags.append(normalized)
            customTags.sort()
            persistence.saveCustomTags(customTags)
        }
        return normalized
    }

    func updateCustomTags(_ tags: [String], for item: ClipboardItem, markFavorite: Bool = true) {
        guard let index = items.firstIndex(where: { $0.id == item.id }) else {
            return
        }

        let normalizedTags = tags.compactMap { createCustomTag($0) }
        items[index] = items[index].withCustomTags(normalizedTags, markFavorite: markFavorite || !normalizedTags.isEmpty)
        persistAndNotifyChanges()
    }

    func assignTag(_ tag: String, to item: ClipboardItem) {
        guard let index = items.firstIndex(where: { $0.id == item.id }) else {
            return
        }

        guard let normalized = createCustomTag(tag) else {
            return
        }

        var tags = items[index].customTags
        if !tags.contains(normalized) {
            tags.append(normalized)
        }
        items[index] = items[index].withCustomTags(tags, markFavorite: true)
        persistAndNotifyChanges()
    }

    func applyImportedArchive(_ archive: ClipboardTransferArchive) {
        customTags = Array(Set(customTags + archive.customTags)).sorted()

        for importedItem in archive.items.reversed() {
            items.removeAll { $0.fingerprint == importedItem.fingerprint }
            items.insert(importedItem, at: 0)
        }

        if items.count > maximumItems {
            items = Array(items.prefix(maximumItems))
        }

        if let latestPinned = items.first(where: { $0.isPinned }) {
            items = items.map { current in
                current.id == latestPinned.id ? current : (current.isPinned ? current.withPinned(false) : current)
            }
            moveToFront(latestPinned, persist: false)
        }

        persistAndNotifyChanges()
    }

    @discardableResult
    func createNamedBackup(_ name: String) -> ClipboardBackupVersion? {
        let backup = persistence.createManualBackup(name: name, items: items)
        applyCleanupPolicyIfNeeded()
        backupVersions = persistence.loadBackupVersions()
        storageUsage = persistence.loadStorageUsage()
        return backup
    }

    @discardableResult
    func renameBackup(_ backup: ClipboardBackupVersion, to name: String) -> ClipboardBackupVersion? {
        let renamed = persistence.renameBackup(backup, to: name)
        backupVersions = persistence.loadBackupVersions()
        storageUsage = persistence.loadStorageUsage()
        return renamed
    }

    func exportBackup(_ backup: ClipboardBackupVersion) -> Bool {
        persistence.exportBackup(backup)
    }

    @discardableResult
    func restoreBackup(_ backup: ClipboardBackupVersion) -> [ClipboardItem]? {
        guard let restoredItems = persistence.restoreItems(from: backup, limit: maximumItems) else {
            return nil
        }

        items = restoredItems
        backupVersions = persistence.loadBackupVersions()
        onItemsChanged?(items)
        return restoredItems
    }

    func deleteBackup(_ backup: ClipboardBackupVersion) {
        persistence.deleteBackup(backup)
        backupVersions = persistence.loadBackupVersions()
        storageUsage = persistence.loadStorageUsage()
    }

    func purgeOldBackups(keeping limit: Int = 3) {
        persistence.purgeOldBackups(keeping: limit)
        backupVersions = persistence.loadBackupVersions()
        storageUsage = persistence.loadStorageUsage()
    }

    func openDataDirectory() {
        persistence.openDataDirectory()
    }

    func openBackupsDirectory() {
        persistence.openBackupsDirectory()
    }

    func openPayloadsDirectory() {
        persistence.openPayloadsDirectory()
    }

    func refreshStorageUsage() {
        storageUsage = persistence.loadStorageUsage()
    }

    var statusSummary: ClipboardStatusSummary {
        ClipboardStatusSummary(
            itemCount: items.count,
            latestBackupDate: backupVersions.first?.createdAt,
            latestBackupName: backupVersions.first?.name
        )
    }

    private func append(_ capture: ClipboardCapture, notifyFeedback: Bool) {
        let preparedItem = persistence.prepare(capture)
        let item: ClipboardItem

        if let duplicateIndex = items.firstIndex(where: { $0.fingerprint == preparedItem.fingerprint || $0.isSemanticallySimilar(to: preparedItem) }) {
            let existing = items.remove(at: duplicateIndex)
            item = preparedItem.mergingDuplicateMetadata(from: existing)
        } else {
            item = preparedItem
        }

        guard items.first?.fingerprint != item.fingerprint else {
            return
        }

        items.removeAll { $0.fingerprint == item.fingerprint }
        items.insert(item, at: 0)

        if items.count > maximumItems {
            items = Array(items.prefix(maximumItems))
        }

        persistAndNotifyChanges()
        if notifyFeedback {
            onCopyCaptured?(item)
        }
    }

    private func moveToFront(_ item: ClipboardItem, persist: Bool = true) {
        items.removeAll { $0.id == item.id }
        items.insert(item, at: 0)
        if persist {
            persistAndNotifyChanges()
        }
    }

    private func persistAndNotifyChanges() {
        persistence.save(items: items)
        persistence.saveCustomTags(customTags)
        applyCleanupPolicyIfNeeded()
        backupVersions = persistence.loadBackupVersions()
        storageUsage = persistence.loadStorageUsage()
        onItemsChanged?(items)
    }

    private func applyCleanupPolicyIfNeeded() {
        guard let policy = cleanupPolicyProvider?(), policy.autoCleanupOldBackupsEnabled else {
            return
        }

        persistence.purgeOldBackups(keeping: policy.keepBackupCount)
    }
}

@MainActor
final class PasteboardMonitor {
    private let store: ClipboardStore
    private var timer: Timer?
    private var lastChangeCount: Int

    init(store: ClipboardStore) {
        self.store = store
        self.lastChangeCount = NSPasteboard.general.changeCount
    }

    func start() {
        store.captureCurrentPasteboard(notifyFeedback: false)

        timer = Timer.scheduledTimer(withTimeInterval: 0.4, repeats: true) { [weak self] _ in
            Task { @MainActor in
                guard let self else {
                    return
                }

                let pasteboard = NSPasteboard.general
                guard pasteboard.changeCount != self.lastChangeCount else {
                    return
                }

                self.lastChangeCount = pasteboard.changeCount
                self.store.captureCurrentPasteboard()
            }
        }
        timer?.tolerance = 0.08
    }

    func stop() {
        timer?.invalidate()
        timer = nil
    }
}

@MainActor
final class AutoPasteService: ObservableObject {
    @Published private(set) var accessibilityGranted = AXIsProcessTrusted()
    @Published var lastError: String?

    private var targetApplication: NSRunningApplication?
    private var clearTask: Task<Void, Never>?

    func rememberFrontmostApplication(excluding bundleIdentifier: String?) {
        let app = NSWorkspace.shared.frontmostApplication
        guard app?.bundleIdentifier != bundleIdentifier else {
            return
        }
        targetApplication = app
    }

    func requestAccessibilityPermission() {
        let options = ["AXTrustedCheckOptionPrompt": true] as CFDictionary
        accessibilityGranted = AXIsProcessTrustedWithOptions(options)
        if !accessibilityGranted {
            lastError = "请在系统设置 > 隐私与安全性 > 辅助功能中允许本应用，才能自动粘贴。"
        } else {
            lastError = nil
        }
    }

    func pasteIntoRememberedApplication() {
        accessibilityGranted = AXIsProcessTrusted()
        guard accessibilityGranted else {
            requestAccessibilityPermission()
            return
        }

        lastError = nil
        let targetApplication = targetApplication
        targetApplication?.activate()

        DispatchQueue.main.asyncAfter(deadline: .now() + 0.12) {
            self.sendPasteShortcut()
        }
    }

    func clearClipboardAfterDelay(seconds: Int) {
        clearTask?.cancel()
        clearTask = Task { @MainActor in
            try? await Task.sleep(for: .seconds(max(seconds, 1)))
            guard !Task.isCancelled else {
                return
            }
            let pasteboard = NSPasteboard.general
            pasteboard.clearContents()
        }
    }

    private func sendPasteShortcut() {
        guard let source = CGEventSource(stateID: .combinedSessionState) else {
            return
        }

        let keyCode: CGKeyCode = 9
        let keyDown = CGEvent(keyboardEventSource: source, virtualKey: keyCode, keyDown: true)
        let keyUp = CGEvent(keyboardEventSource: source, virtualKey: keyCode, keyDown: false)
        keyDown?.flags = .maskCommand
        keyUp?.flags = .maskCommand
        keyDown?.post(tap: .cghidEventTap)
        keyUp?.post(tap: .cghidEventTap)
    }
}

@MainActor
final class CopyHUDController {
    static let shared = CopyHUDController()

    private var panel: NSPanel?
    private var hideTask: Task<Void, Never>?

    func show(message: String, isWarning: Bool = false) {
        let label = NSTextField(labelWithString: message)
        label.textColor = isWarning ? .white : .white
        label.font = .systemFont(ofSize: 16, weight: .bold)
        label.alignment = .center
        label.maximumNumberOfLines = 2
        label.lineBreakMode = .byTruncatingTail

        let container = NSView(frame: NSRect(x: 0, y: 0, width: 320, height: 72))
        let visualEffect = NSVisualEffectView(frame: container.bounds)
        visualEffect.material = .hudWindow
        visualEffect.blendingMode = .withinWindow
        visualEffect.state = .active
        visualEffect.wantsLayer = true
        visualEffect.layer?.cornerRadius = 18
        visualEffect.layer?.masksToBounds = true
        visualEffect.layer?.borderWidth = 1
        visualEffect.layer?.borderColor = (isWarning ? NSColor.systemRed : NSColor.systemGreen).withAlphaComponent(0.55).cgColor
        container.addSubview(visualEffect)

        label.frame = NSRect(x: 20, y: 22, width: 280, height: 28)
        container.addSubview(label)

        let panel = self.panel ?? NSPanel(
            contentRect: container.frame,
            styleMask: [.borderless],
            backing: .buffered,
            defer: false
        )
        panel.isFloatingPanel = true
        panel.level = .statusBar
        panel.backgroundColor = .clear
        panel.isOpaque = false
        panel.hasShadow = true
        panel.ignoresMouseEvents = true
        panel.collectionBehavior = [.moveToActiveSpace, .fullScreenAuxiliary]
        panel.contentView = container

        if let screen = NSScreen.main {
            let origin = NSPoint(
                x: screen.visibleFrame.midX - container.frame.width / 2,
                y: screen.visibleFrame.maxY - container.frame.height - 56
            )
            panel.setFrameOrigin(origin)
        }

        panel.alphaValue = 0
        panel.orderFrontRegardless()

        NSAnimationContext.runAnimationGroup { context in
            context.duration = 0.18
            panel.animator().alphaValue = 1
        }

        self.panel = panel
        hideTask?.cancel()
        hideTask = Task { @MainActor in
            try? await Task.sleep(for: .seconds(1.4))
            guard !Task.isCancelled else {
                return
            }
            NSAnimationContext.runAnimationGroup { context in
                context.duration = 0.18
                panel.animator().alphaValue = 0
            } completionHandler: {
                Task { @MainActor in
                    panel.orderOut(nil)
                }
            }
        }
    }
}

@MainActor
final class HotKeyManager {
    static let shared = HotKeyManager()

    var onToggle: (() -> Void)?

    private var hotKeyRef: EventHotKeyRef?
    private var eventHandlerRef: EventHandlerRef?

    func register() {
        unregister()

        var eventType = EventTypeSpec(
            eventClass: OSType(kEventClassKeyboard),
            eventKind: UInt32(kEventHotKeyPressed)
        )

        let callback: EventHandlerUPP = { _, eventRef, userData in
            guard let eventRef, let userData else {
                return noErr
            }

            var hotKeyID = EventHotKeyID()
            let status = GetEventParameter(
                eventRef,
                EventParamName(kEventParamDirectObject),
                EventParamType(typeEventHotKeyID),
                nil,
                MemoryLayout<EventHotKeyID>.size,
                nil,
                &hotKeyID
            )

            guard status == noErr, hotKeyID.id == 1 else {
                return noErr
            }

            let manager = Unmanaged<HotKeyManager>.fromOpaque(userData).takeUnretainedValue()
            DispatchQueue.main.async {
                manager.onToggle?()
            }
            return noErr
        }

        InstallEventHandler(
            GetEventDispatcherTarget(),
            callback,
            1,
            &eventType,
            UnsafeMutableRawPointer(Unmanaged.passUnretained(self).toOpaque()),
            &eventHandlerRef
        )

        let hotKeyID = EventHotKeyID(signature: fourCharCode("CLIP"), id: 1)
        let modifiers = UInt32(cmdKey) | UInt32(optionKey)

        RegisterEventHotKey(
            UInt32(kVK_ANSI_V),
            modifiers,
            hotKeyID,
            GetEventDispatcherTarget(),
            0,
            &hotKeyRef
        )
    }

    func unregister() {
        if let hotKeyRef {
            UnregisterEventHotKey(hotKeyRef)
            self.hotKeyRef = nil
        }

        if let eventHandlerRef {
            RemoveEventHandler(eventHandlerRef)
            self.eventHandlerRef = nil
        }
    }

    private func fourCharCode(_ string: String) -> OSType {
        string.utf8.reduce(0) { partial, byte in
            (partial << 8) + OSType(byte)
        }
    }
}

@MainActor
final class LaunchAtLoginManager: ObservableObject {
    @Published var isEnabled = false
    @Published var lastError: String?

    init() {
        refreshStatus()
    }

    func setEnabled(_ enabled: Bool) {
        guard #available(macOS 13.0, *) else {
            lastError = "开机启动需要 macOS 13 及以上。"
            isEnabled = false
            return
        }

        do {
            if enabled {
                try SMAppService.mainApp.register()
            } else {
                try SMAppService.mainApp.unregister()
            }
            lastError = nil
        } catch {
            lastError = error.localizedDescription
        }

        refreshStatus()
    }

    func refreshStatus() {
        guard #available(macOS 13.0, *) else {
            isEnabled = false
            return
        }
        isEnabled = SMAppService.mainApp.status == .enabled
    }
}

@MainActor
final class StatusBarController: NSObject {
    private let statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
    private let onToggle: () -> Void
    private let onCreateNamedBackup: () -> Void
    private let onQuickImport: () -> Void
    private let onQuickExport: () -> Void
    private let onExportLatestBackup: () -> Void
    private let onExportBackup: (ClipboardBackupVersion) -> Void
    private let onRestoreLatestBackup: () -> Void
    private let historySummaryProvider: () -> ClipboardStatusSummary
    private let backupsProvider: () -> [ClipboardBackupVersion]
    private let onRestoreBackup: (ClipboardBackupVersion) -> Void
    private let onOpenDataDirectory: () -> Void
    private let onOpenBackupsDirectory: () -> Void
    private let onOpenPayloadsDirectory: () -> Void
    private let onQuit: () -> Void
    private var flashTask: Task<Void, Never>?
    private let normalColor = NSColor.labelColor
    private let successColor = NSColor.systemGreen

    init(
        onToggle: @escaping () -> Void,
        onCreateNamedBackup: @escaping () -> Void,
        onQuickImport: @escaping () -> Void,
        onQuickExport: @escaping () -> Void,
        onExportLatestBackup: @escaping () -> Void,
        onExportBackup: @escaping (ClipboardBackupVersion) -> Void,
        onRestoreLatestBackup: @escaping () -> Void,
        historySummaryProvider: @escaping () -> ClipboardStatusSummary,
        backupsProvider: @escaping () -> [ClipboardBackupVersion],
        onRestoreBackup: @escaping (ClipboardBackupVersion) -> Void,
        onOpenDataDirectory: @escaping () -> Void,
        onOpenBackupsDirectory: @escaping () -> Void,
        onOpenPayloadsDirectory: @escaping () -> Void,
        onQuit: @escaping () -> Void
    ) {
        self.onToggle = onToggle
        self.onCreateNamedBackup = onCreateNamedBackup
        self.onQuickImport = onQuickImport
        self.onQuickExport = onQuickExport
        self.onExportLatestBackup = onExportLatestBackup
        self.onExportBackup = onExportBackup
        self.onRestoreLatestBackup = onRestoreLatestBackup
        self.historySummaryProvider = historySummaryProvider
        self.backupsProvider = backupsProvider
        self.onRestoreBackup = onRestoreBackup
        self.onOpenDataDirectory = onOpenDataDirectory
        self.onOpenBackupsDirectory = onOpenBackupsDirectory
        self.onOpenPayloadsDirectory = onOpenPayloadsDirectory
        self.onQuit = onQuit
        super.init()
        configure()
    }

    private func configure() {
        guard let button = statusItem.button else {
            return
        }

        button.image = makeStatusBarImage(color: normalColor)
        button.imagePosition = .imageOnly
        button.toolTip = historySummaryProvider().toolTip
        button.target = self
        button.action = #selector(handleStatusBarButton)
        button.sendAction(on: [.leftMouseUp, .rightMouseUp])
        button.wantsLayer = true
        button.layer?.cornerRadius = 6
        button.layer?.masksToBounds = true
    }

    func showCopySuccessFeedback() {
        flashTask?.cancel()
        guard let button = statusItem.button else {
            return
        }

        flashTask = Task { @MainActor [weak button] in
            guard let button else {
                return
            }

            for _ in 0..<3 {
                guard !Task.isCancelled else {
                    self.resetFeedbackAppearance(for: button)
                    return
                }

                await self.animateFeedback(on: button, ascending: true)

                guard !Task.isCancelled else {
                    self.resetFeedbackAppearance(for: button)
                    return
                }

                await self.animateFeedback(on: button, ascending: false)
            }

            self.resetFeedbackAppearance(for: button)
        }
    }

    @objc
    private func handleStatusBarButton() {
        if NSApp.currentEvent?.type == .rightMouseUp {
            showMenu()
        }
    }

    @objc
    private func openPanel() {
        onToggle()
    }

    @objc
    private func quitApp() {
        onQuit()
    }

    @objc
    private func quickImport() {
        onQuickImport()
    }

    @objc
    private func createNamedBackup() {
        onCreateNamedBackup()
    }

    @objc
    private func quickExport() {
        onQuickExport()
    }

    @objc
    private func exportLatestBackup() {
        onExportLatestBackup()
    }

    @objc
    private func restoreLatestBackup() {
        onRestoreLatestBackup()
    }

    @objc
    private func openDataDirectory() {
        onOpenDataDirectory()
    }

    @objc
    private func openBackupsDirectory() {
        onOpenBackupsDirectory()
    }

    @objc
    private func openPayloadsDirectory() {
        onOpenPayloadsDirectory()
    }

    @objc
    private func restoreBackupMenuItem(_ sender: NSMenuItem) {
        guard let representedObject = sender.representedObject as? ClipboardBackupVersion else {
            return
        }
        onRestoreBackup(representedObject)
    }

    @objc
    private func exportBackupMenuItem(_ sender: NSMenuItem) {
        guard let representedObject = sender.representedObject as? ClipboardBackupVersion else {
            return
        }
        onExportBackup(representedObject)
    }

    private func showMenu() {
        refreshStatusSummary()
        let menu = NSMenu()
        let summaryItem = NSMenuItem(title: historySummaryProvider().menuTitle, action: nil, keyEquivalent: "")
        summaryItem.isEnabled = false
        menu.addItem(summaryItem)
        menu.addItem(.separator())
        menu.addItem(NSMenuItem(title: "打开粘贴板", action: #selector(openPanel), keyEquivalent: ""))
        menu.addItem(NSMenuItem(title: "创建命名快照", action: #selector(createNamedBackup), keyEquivalent: ""))
        menu.addItem(NSMenuItem(title: "快速导入", action: #selector(quickImport), keyEquivalent: ""))
        menu.addItem(NSMenuItem(title: "快速导出", action: #selector(quickExport), keyEquivalent: ""))
        menu.addItem(NSMenuItem(title: "导出最近备份", action: #selector(exportLatestBackup), keyEquivalent: ""))
        menu.addItem(NSMenuItem(title: "恢复最近备份", action: #selector(restoreLatestBackup), keyEquivalent: ""))

        let recentBackupsItem = NSMenuItem(title: "最近备份", action: nil, keyEquivalent: "")
        let recentBackupsMenu = NSMenu()
        let exportBackupsItem = NSMenuItem(title: "导出指定备份", action: nil, keyEquivalent: "")
        let exportBackupsMenu = NSMenu()
        let backups = Array(backupsProvider().prefix(3))
        if backups.isEmpty {
            let emptyItem = NSMenuItem(title: "暂无备份", action: nil, keyEquivalent: "")
            emptyItem.isEnabled = false
            recentBackupsMenu.addItem(emptyItem)

            let exportEmptyItem = NSMenuItem(title: "暂无备份", action: nil, keyEquivalent: "")
            exportEmptyItem.isEnabled = false
            exportBackupsMenu.addItem(exportEmptyItem)
        } else {
            for backup in backups {
                let item = NSMenuItem(
                    title: backup.name,
                    action: #selector(restoreBackupMenuItem(_:)),
                    keyEquivalent: ""
                )
                item.representedObject = backup
                item.target = self
                recentBackupsMenu.addItem(item)

                let exportItem = NSMenuItem(
                    title: backup.name,
                    action: #selector(exportBackupMenuItem(_:)),
                    keyEquivalent: ""
                )
                exportItem.representedObject = backup
                exportItem.target = self
                exportBackupsMenu.addItem(exportItem)
            }
        }
        recentBackupsItem.submenu = recentBackupsMenu
        menu.addItem(recentBackupsItem)
        exportBackupsItem.submenu = exportBackupsMenu
        menu.addItem(exportBackupsItem)

        menu.addItem(.separator())
        menu.addItem(NSMenuItem(title: "打开本地数据目录", action: #selector(openDataDirectory), keyEquivalent: ""))
        menu.addItem(NSMenuItem(title: "打开备份目录", action: #selector(openBackupsDirectory), keyEquivalent: ""))
        menu.addItem(NSMenuItem(title: "打开附件目录", action: #selector(openPayloadsDirectory), keyEquivalent: ""))
        menu.addItem(.separator())
        menu.addItem(NSMenuItem(title: "退出", action: #selector(quitApp), keyEquivalent: "q"))
        menu.items.forEach { $0.target = self }
        statusItem.menu = menu
        statusItem.button?.performClick(nil)
        statusItem.menu = nil
    }

    private func animateFeedback(on button: NSStatusBarButton, ascending: Bool) async {
        let steps = ascending ? Array(0...5) : Array((0...5).reversed())

        for step in steps {
            let progress = CGFloat(step) / 5
            applyFeedbackAppearance(to: button, progress: progress)
            try? await Task.sleep(for: .milliseconds(36))
        }
    }

    private func applyFeedbackAppearance(to button: NSStatusBarButton, progress: CGFloat) {
        let tint = blendedColor(from: normalColor, to: successColor, progress: progress)
        button.image = makeStatusBarImage(color: tint)
        button.alphaValue = 1
        button.layer?.backgroundColor = successColor.withAlphaComponent(0.10 + 0.22 * progress).cgColor
    }

    private func resetFeedbackAppearance(for button: NSStatusBarButton) {
        button.image = makeStatusBarImage(color: normalColor)
        button.alphaValue = 1
        button.layer?.backgroundColor = NSColor.clear.cgColor
        button.toolTip = historySummaryProvider().toolTip
    }

    private func refreshStatusSummary() {
        statusItem.button?.toolTip = historySummaryProvider().toolTip
    }

    private func blendedColor(from start: NSColor, to end: NSColor, progress: CGFloat) -> NSColor {
        let start = start.usingColorSpace(.deviceRGB) ?? start
        let end = end.usingColorSpace(.deviceRGB) ?? end

        let red = start.redComponent + (end.redComponent - start.redComponent) * progress
        let green = start.greenComponent + (end.greenComponent - start.greenComponent) * progress
        let blue = start.blueComponent + (end.blueComponent - start.blueComponent) * progress
        let alpha = start.alphaComponent + (end.alphaComponent - start.alphaComponent) * progress

        return NSColor(deviceRed: red, green: green, blue: blue, alpha: alpha)
    }

    private func makeStatusBarImage(color: NSColor) -> NSImage {
        let size = NSSize(width: 18, height: 18)
        let image = NSImage(size: size)
        image.lockFocus()
        defer { image.unlockFocus() }

        let paragraph = NSMutableParagraphStyle()
        paragraph.alignment = .center

        let attributes: [NSAttributedString.Key: Any] = [
            .font: NSFont.systemFont(ofSize: 14, weight: .black),
            .foregroundColor: color,
            .paragraphStyle: paragraph
        ]

        NSString(string: "C").draw(in: NSRect(x: 0, y: 1, width: size.width, height: size.height), withAttributes: attributes)
        image.isTemplate = false
        return image
    }
}

final class FloatingPanel: NSPanel {
    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { true }
}

@MainActor
final class FloatingPanelController: NSObject, NSWindowDelegate {
    let panel: FloatingPanel
    private(set) var isVisible = false
    private var preferredSize = CGSize(width: 640, height: 760)

    init<Content: View>(rootView: Content) {
        self.panel = FloatingPanel(
            contentRect: NSRect(x: 0, y: 0, width: 640, height: 760),
            styleMask: [.titled, .fullSizeContentView, .closable],
            backing: .buffered,
            defer: false
        )
        super.init()

        panel.isFloatingPanel = true
        panel.level = .statusBar
        panel.collectionBehavior = [.moveToActiveSpace, .fullScreenAuxiliary]
        panel.hidesOnDeactivate = false
        panel.titleVisibility = .hidden
        panel.titlebarAppearsTransparent = true
        panel.isMovableByWindowBackground = true
        panel.isReleasedWhenClosed = false
        panel.standardWindowButton(.zoomButton)?.isHidden = true
        panel.standardWindowButton(.miniaturizeButton)?.isHidden = true
        panel.backgroundColor = .clear
        panel.isOpaque = false
        panel.hasShadow = true
        panel.alphaValue = 0
        panel.delegate = self
        panel.contentViewController = NSHostingController(rootView: rootView)
    }

    func toggle() {
        isVisible ? hide() : show()
    }

    func show() {
        let finalFrame = preferredFrame()
        let startFrame = finalFrame.offsetBy(dx: 0, dy: 24)
        panel.setFrame(startFrame, display: true)
        panel.alphaValue = 0
        presentPanel(finalFrame: finalFrame)
    }

    func hide() {
        guard isVisible else {
            return
        }

        let targetFrame = panel.frame.offsetBy(dx: 0, dy: 18)
        NSAnimationContext.runAnimationGroup { context in
            context.duration = 0.2
            context.timingFunction = CAMediaTimingFunction(name: .easeInEaseOut)
            panel.animator().alphaValue = 0
            panel.animator().setFrame(targetFrame, display: true)
        } completionHandler: { [weak self] in
            Task { @MainActor in
                self?.panel.orderOut(nil)
                self?.isVisible = false
            }
        }
    }

    func updatePreferredSize(_ size: CGSize, animated: Bool) {
        preferredSize = size
        guard isVisible else {
            return
        }

        let frame = preferredFrame()
        if animated {
            NSAnimationContext.runAnimationGroup { context in
                context.duration = 0.18
                panel.animator().setFrame(frame, display: true)
            }
        } else {
            panel.setFrame(frame, display: true)
        }
    }

    private func preferredFrame() -> NSRect {
        guard let screen = NSScreen.main else {
            return NSRect(x: 0, y: 0, width: preferredSize.width, height: preferredSize.height)
        }

        let width = preferredSize.width
        let height = preferredSize.height
        let originX = screen.visibleFrame.midX - width / 2
        let originY = screen.visibleFrame.maxY - height - 50
        return NSRect(x: originX, y: originY, width: width, height: height)
    }

    private func presentPanel(finalFrame: NSRect) {
        NSApp.activate(ignoringOtherApps: true)
        panel.makeKeyAndOrderFront(nil)

        NSAnimationContext.runAnimationGroup { context in
            context.duration = 0.24
            context.timingFunction = CAMediaTimingFunction(name: .easeInEaseOut)
            panel.animator().alphaValue = 1
            panel.animator().setFrame(finalFrame, display: true)
        }
        isVisible = true
    }
}
