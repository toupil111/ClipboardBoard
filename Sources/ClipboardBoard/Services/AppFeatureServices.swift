import AppKit
import CryptoKit
import Foundation
import LocalAuthentication
import Security
import SwiftUI
import UniformTypeIdentifiers

enum AppAppearanceMode: String, Codable, CaseIterable, Identifiable {
    case system
    case light
    case dark

    var id: String { rawValue }

    var title: String {
        switch self {
        case .system:
            return "跟随系统"
        case .light:
            return "明亮"
        case .dark:
            return "暗黑"
        }
    }

    var colorScheme: ColorScheme? {
        switch self {
        case .system:
            return nil
        case .light:
            return .light
        case .dark:
            return .dark
        }
    }
}

enum PanelSizePreset: String, Codable, CaseIterable, Identifiable {
    case compact
    case regular
    case large

    var id: String { rawValue }

    var title: String {
        switch self {
        case .compact:
            return "紧凑"
        case .regular:
            return "标准"
        case .large:
            return "大面板"
        }
    }

    var size: CGSize {
        switch self {
        case .compact:
            return CGSize(width: 600, height: 700)
        case .regular:
            return CGSize(width: 720, height: 780)
        case .large:
            return CGSize(width: 860, height: 860)
        }
    }
}

enum ClipboardListDensity: String, Codable, CaseIterable, Identifiable {
    case compact
    case comfortable

    var id: String { rawValue }

    var title: String {
        switch self {
        case .compact:
            return "紧凑"
        case .comfortable:
            return "舒适"
        }
    }
}

enum ClipboardItemSortMode: String, Codable, CaseIterable, Identifiable {
    case newest
    case oldest
    case favoritesFirst
    case largeFirst
    case kind

    var id: String { rawValue }

    var title: String {
        switch self {
        case .newest:
            return "最新优先"
        case .oldest:
            return "最早优先"
        case .favoritesFirst:
            return "收藏优先"
        case .largeFirst:
            return "大附件优先"
        case .kind:
            return "类型分组"
        }
    }
}

private struct AppPreferencesPayload: Codable {
    var appearanceMode: AppAppearanceMode
    var accentColorHex: String
    var sensitiveRevealTimeoutSeconds: Int
    var sensitivePreviewVisibleCharacterCount: Int
    var requiresAuthenticationForSensitiveRestore: Bool
    var panelSizePreset: PanelSizePreset
    var listDensity: ClipboardListDensity
    var itemSortMode: ClipboardItemSortMode
    var largeAttachmentThresholdMB: Int
    var sensitiveClipboardClearSeconds: Int
    var hasCompletedOnboarding: Bool
    var autoCleanupOldBackupsEnabled: Bool
    var autoCleanupBackupKeepCount: Int
}

@MainActor
final class AppPreferencesStore: ObservableObject {
    @Published var appearanceMode: AppAppearanceMode {
        didSet { save() }
    }

    @Published var accentColorHex: String {
        didSet { save() }
    }

    @Published var sensitiveRevealTimeoutSeconds: Int {
        didSet { save() }
    }

    @Published var sensitivePreviewVisibleCharacterCount: Int {
        didSet { save() }
    }

    @Published var requiresAuthenticationForSensitiveRestore: Bool {
        didSet { save() }
    }

    @Published var panelSizePreset: PanelSizePreset {
        didSet { save() }
    }

    @Published var listDensity: ClipboardListDensity {
        didSet { save() }
    }

    @Published var itemSortMode: ClipboardItemSortMode {
        didSet { save() }
    }

    @Published var largeAttachmentThresholdMB: Int {
        didSet { save() }
    }

    @Published var sensitiveClipboardClearSeconds: Int {
        didSet { save() }
    }

    @Published var hasCompletedOnboarding: Bool {
        didSet { save() }
    }

    @Published var autoCleanupOldBackupsEnabled: Bool {
        didSet { save() }
    }

    @Published var autoCleanupBackupKeepCount: Int {
        didSet { save() }
    }

    private let preferencesURL: URL
    private let encoder = JSONEncoder()
    private let decoder = JSONDecoder()

    init() {
        let applicationSupport = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
        let directoryURL = applicationSupport.appendingPathComponent("ClipboardBoard", isDirectory: true)
        preferencesURL = directoryURL.appendingPathComponent("preferences.json", isDirectory: false)
        try? FileManager.default.createDirectory(at: directoryURL, withIntermediateDirectories: true)
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]

        if let data = try? Data(contentsOf: preferencesURL),
           let payload = try? decoder.decode(AppPreferencesPayload.self, from: data) {
            appearanceMode = payload.appearanceMode
            accentColorHex = payload.accentColorHex
            sensitiveRevealTimeoutSeconds = payload.sensitiveRevealTimeoutSeconds
            sensitivePreviewVisibleCharacterCount = payload.sensitivePreviewVisibleCharacterCount
            requiresAuthenticationForSensitiveRestore = payload.requiresAuthenticationForSensitiveRestore
            panelSizePreset = payload.panelSizePreset
            listDensity = payload.listDensity
            itemSortMode = payload.itemSortMode
            largeAttachmentThresholdMB = payload.largeAttachmentThresholdMB
            sensitiveClipboardClearSeconds = payload.sensitiveClipboardClearSeconds
            hasCompletedOnboarding = payload.hasCompletedOnboarding
            autoCleanupOldBackupsEnabled = payload.autoCleanupOldBackupsEnabled
            autoCleanupBackupKeepCount = payload.autoCleanupBackupKeepCount
        } else {
            appearanceMode = .system
            accentColorHex = "#59C36A"
            sensitiveRevealTimeoutSeconds = 20
            sensitivePreviewVisibleCharacterCount = 4
            requiresAuthenticationForSensitiveRestore = true
            panelSizePreset = .regular
            listDensity = .comfortable
            itemSortMode = .newest
            largeAttachmentThresholdMB = 100
            sensitiveClipboardClearSeconds = 15
            hasCompletedOnboarding = false
            autoCleanupOldBackupsEnabled = false
            autoCleanupBackupKeepCount = 3
        }
    }

    var accentColor: Color {
        Color(nsColor: nsAccentColor)
    }

    var nsAccentColor: NSColor {
        NSColor(hex: accentColorHex) ?? .systemGreen
    }

    private func save() {
        let payload = AppPreferencesPayload(
            appearanceMode: appearanceMode,
            accentColorHex: accentColorHex,
            sensitiveRevealTimeoutSeconds: sensitiveRevealTimeoutSeconds,
            sensitivePreviewVisibleCharacterCount: sensitivePreviewVisibleCharacterCount,
            requiresAuthenticationForSensitiveRestore: requiresAuthenticationForSensitiveRestore,
            panelSizePreset: panelSizePreset,
            listDensity: listDensity,
            itemSortMode: itemSortMode,
            largeAttachmentThresholdMB: largeAttachmentThresholdMB,
            sensitiveClipboardClearSeconds: sensitiveClipboardClearSeconds,
            hasCompletedOnboarding: hasCompletedOnboarding,
            autoCleanupOldBackupsEnabled: autoCleanupOldBackupsEnabled,
            autoCleanupBackupKeepCount: autoCleanupBackupKeepCount
        )

        guard let data = try? encoder.encode(payload) else {
            return
        }

        try? data.write(to: preferencesURL, options: [.atomic])
    }
}

@MainActor
final class LocalAuthenticationService: ObservableObject {
    @Published var lastError: String?

    func authenticate(reason: String) async -> Bool {
        let context = LAContext()
        context.localizedCancelTitle = "取消"

        var authError: NSError?
        let policy: LAPolicy = context.canEvaluatePolicy(.deviceOwnerAuthenticationWithBiometrics, error: &authError)
        ? .deviceOwnerAuthenticationWithBiometrics
        : .deviceOwnerAuthentication

        return await withCheckedContinuation { continuation in
            context.evaluatePolicy(policy, localizedReason: reason) { success, error in
                Task { @MainActor in
                    self.lastError = error?.localizedDescription
                    continuation.resume(returning: success)
                }
            }
        }
    }
}

struct ClipboardEncryptedEnvelope: Codable {
    let version: Int
    let algorithm: String
    let nonce: Data
    let ciphertext: Data
    let tag: Data
    let containsSensitiveItems: Bool
}

struct ClipboardTransferArchive: Codable {
    let version: Int
    let exportedAt: Date
    let containsSensitiveItems: Bool
    let items: [ClipboardItem]
    let customTags: [String]

    var previewSummary: String {
        let sensitiveCount = items.filter(\.isSensitive).count
        return [
            "记录 \(items.count) 条",
            "敏感 \(sensitiveCount) 条",
            "标签 \(customTags.count) 个"
        ].joined(separator: " · ")
    }
}

final class SecureCryptoService: @unchecked Sendable {
    static let shared = SecureCryptoService()
    static let sensitiveContent = SecureCryptoService(account: "PrimarySymmetricKey")

    private let service = "ClipboardBoard"
    private let account: String
    private let keyLock = NSLock()
    private var cachedKey: SymmetricKey?

    init(account: String = "PrimarySymmetricKey") {
        self.account = account
    }

    func encrypt(_ data: Data, containsSensitiveItems: Bool = false) throws -> Data {
        let key = try loadOrCreateKey()
        let sealedBox = try AES.GCM.seal(data, using: key)
        let envelope = ClipboardEncryptedEnvelope(
            version: 1,
            algorithm: "AES.GCM.256",
            nonce: sealedBox.nonce.withUnsafeBytes { Data($0) },
            ciphertext: sealedBox.ciphertext,
            tag: sealedBox.tag,
            containsSensitiveItems: containsSensitiveItems
        )
        return try JSONEncoder().encode(envelope)
    }

    func decrypt(_ data: Data) throws -> Data {
        let envelope = try JSONDecoder().decode(ClipboardEncryptedEnvelope.self, from: data)
        let key = try loadOrCreateKey()
        let nonce = try AES.GCM.Nonce(data: envelope.nonce)
        let sealedBox = try AES.GCM.SealedBox(nonce: nonce, ciphertext: envelope.ciphertext, tag: envelope.tag)
        return try AES.GCM.open(sealedBox, using: key)
    }

    private func loadOrCreateKey() throws -> SymmetricKey {
        keyLock.lock()
        if let cachedKey {
            keyLock.unlock()
            return cachedKey
        }
        keyLock.unlock()

        if let data = try loadKeyData() {
            let key = SymmetricKey(data: data)
            keyLock.lock()
            cachedKey = key
            keyLock.unlock()
            return key
        }

        let key = SymmetricKey(size: .bits256)
        let keyData = key.withUnsafeBytes { Data($0) }
        try saveKeyData(keyData)
        keyLock.lock()
        cachedKey = key
        keyLock.unlock()
        return key
    }

    private func loadKeyData() throws -> Data? {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
            kSecReturnData as String: true,
            kSecMatchLimit as String: kSecMatchLimitOne
        ]

        var item: CFTypeRef?
        let status = SecItemCopyMatching(query as CFDictionary, &item)
        switch status {
        case errSecSuccess:
            return item as? Data
        case errSecItemNotFound:
            return nil
        default:
            throw NSError(domain: NSOSStatusErrorDomain, code: Int(status))
        }
    }

    private func saveKeyData(_ data: Data) throws {
        let deleteQuery: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account
        ]
        SecItemDelete(deleteQuery as CFDictionary)

        let addQuery: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
            kSecValueData as String: data,
            kSecAttrAccessible as String: kSecAttrAccessibleAfterFirstUnlock
        ]

        let status = SecItemAdd(addQuery as CFDictionary, nil)
        guard status == errSecSuccess else {
            throw NSError(domain: NSOSStatusErrorDomain, code: Int(status))
        }
    }
}

struct SensitiveAccessLogEntry: Codable, Identifiable {
    let id: UUID
    let itemID: UUID
    let itemTitle: String
    let action: String
    let timestamp: Date
}

@MainActor
final class SensitiveAccessLogService: ObservableObject {
    @Published private(set) var entries: [SensitiveAccessLogEntry] = []

    private let fileURL: URL
    private let encoder = JSONCoders.clipboardBoardEncoder
    private let decoder = JSONCoders.clipboardBoardDecoder

    init() {
        let applicationSupport = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
        let directoryURL = applicationSupport.appendingPathComponent("ClipboardBoard", isDirectory: true)
        try? FileManager.default.createDirectory(at: directoryURL, withIntermediateDirectories: true)
        fileURL = directoryURL.appendingPathComponent("sensitive-access-log.json", isDirectory: false)
        load()
    }

    func record(item: ClipboardItem, action: String) {
        let entry = SensitiveAccessLogEntry(
            id: UUID(),
            itemID: item.id,
            itemTitle: item.title,
            action: action,
            timestamp: Date()
        )
        entries.insert(entry, at: 0)
        if entries.count > 50 {
            entries = Array(entries.prefix(50))
        }
        save()
    }

    private func load() {
        guard let data = try? Data(contentsOf: fileURL),
              let decoded = try? decoder.decode([SensitiveAccessLogEntry].self, from: data) else {
            entries = []
            return
        }
        entries = decoded.sorted { $0.timestamp > $1.timestamp }
    }

    private func save() {
        guard let data = try? encoder.encode(entries) else {
            return
        }
        try? data.write(to: fileURL, options: [.atomic])
    }
}

@MainActor
final class ClipboardTransferService: ObservableObject {
    @Published var lastMessage: String?
    @Published var lastError: String?

    private let cryptoService: SecureCryptoService

    init(cryptoService: SecureCryptoService = .shared) {
        self.cryptoService = cryptoService
    }

    func exportArchive(items: [ClipboardItem], customTags: [String], includeSensitiveItems: Bool) {
        let exportItems = includeSensitiveItems ? items : items.filter { !$0.isSensitive }
        guard !exportItems.isEmpty else {
            lastError = "没有可导出的内容。"
            return
        }

        let archive = ClipboardTransferArchive(
            version: 1,
            exportedAt: Date(),
            containsSensitiveItems: exportItems.contains(where: \.isSensitive),
            items: exportItems,
            customTags: customTags
        )

        do {
            let plainData = try JSONCoders.clipboardBoardEncoder.encode(archive)
            let encryptedData = try cryptoService.encrypt(plainData, containsSensitiveItems: archive.containsSensitiveItems)
            let savePanel = NSSavePanel()
            savePanel.canCreateDirectories = true
            savePanel.nameFieldStringValue = "ClipboardBoard-Export.json"
            savePanel.allowedContentTypes = [UTType.json]
            savePanel.title = "导出剪贴板"
            savePanel.message = archive.containsSensitiveItems ? "此导出包含敏感内容，会生成 AES-GCM 加密的 JSON 文件。" : "将生成 AES-GCM 加密的 JSON 文件。"

            if savePanel.runModal() == .OK, let url = savePanel.url {
                try encryptedData.write(to: url, options: Data.WritingOptions.atomic)
                lastError = nil
                lastMessage = "导出成功：\(url.lastPathComponent)"
            }
        } catch {
            lastError = error.localizedDescription
        }
    }

    func importArchive() -> ClipboardTransferArchive? {
        let openPanel = NSOpenPanel()
        openPanel.allowsMultipleSelection = false
        openPanel.canChooseDirectories = false
        openPanel.allowedContentTypes = [UTType.json]
        openPanel.title = "导入剪贴板"
        openPanel.message = "选择之前导出的 ClipboardBoard 加密 JSON 文件。"

        guard openPanel.runModal() == .OK, let url = openPanel.url else {
            return nil
        }

        do {
            let encryptedData = try Data(contentsOf: url)
            let plainData = try cryptoService.decrypt(encryptedData)
            let archive = try JSONCoders.clipboardBoardDecoder.decode(ClipboardTransferArchive.self, from: plainData)

            let alert = NSAlert()
            alert.messageText = "确认导入此备份？"
            alert.informativeText = archive.previewSummary
            alert.addButton(withTitle: "导入")
            alert.addButton(withTitle: "取消")
            guard alert.runModal() == .alertFirstButtonReturn else {
                return nil
            }

            lastError = nil
            lastMessage = "导入成功：\(url.lastPathComponent)"
            return archive
        } catch {
            lastError = error.localizedDescription
            return nil
        }
    }
}

@MainActor
final class BlackScreenIntegrationService: ObservableObject {
    @Published private(set) var isInstalled = false
    private(set) var applicationURL: URL?
    private let bundleIdentifiers = [
        "com.blackscreen.app",
        "com.BlackScreen.app",
        "com.prodisup.BlackScreen"
    ]

    init() {
        refreshStatus()
    }

    func refreshStatus() {
        if let matchedURL = bundleIdentifiers.compactMap({ NSWorkspace.shared.urlForApplication(withBundleIdentifier: $0) }).first {
            applicationURL = matchedURL
            isInstalled = true
            return
        }

        let candidates = [
            URL(fileURLWithPath: "/Applications/BlackScreen.app"),
            FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent("Applications/BlackScreen.app", isDirectory: true)
        ]

        if let matched = candidates.first(where: { FileManager.default.fileExists(atPath: $0.path) }) ?? scanForBlackScreenApplication() {
            applicationURL = matched
            isInstalled = true
        } else {
            applicationURL = nil
            isInstalled = false
        }
    }

    func openIfAvailable() {
        refreshStatus()
        guard let applicationURL else {
            return
        }
        NSWorkspace.shared.openApplication(at: applicationURL, configuration: NSWorkspace.OpenConfiguration()) { _, _ in }
    }

    private func scanForBlackScreenApplication() -> URL? {
        let searchRoots = [
            URL(fileURLWithPath: "/Applications", isDirectory: true),
            FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent("Applications", isDirectory: true)
        ]

        for root in searchRoots {
            guard let enumerator = FileManager.default.enumerator(
                at: root,
                includingPropertiesForKeys: [.isDirectoryKey],
                options: [.skipsHiddenFiles, .skipsPackageDescendants]
            ) else {
                continue
            }

            for case let url as URL in enumerator {
                if url.lastPathComponent.localizedCaseInsensitiveContains("BlackScreen") && url.pathExtension == "app" {
                    return url
                }
            }
        }

        return nil
    }
}

private enum JSONCoders {
    static var clipboardBoardEncoder: JSONEncoder {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        encoder.dateEncodingStrategy = .iso8601
        return encoder
    }

    static var clipboardBoardDecoder: JSONDecoder {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return decoder
    }
}

extension NSColor {
    convenience init?(hex: String) {
        let value = hex.trimmingCharacters(in: CharacterSet.alphanumerics.inverted)
        guard value.count == 6, let int = Int(value, radix: 16) else {
            return nil
        }

        self.init(
            red: CGFloat((int >> 16) & 0xFF) / 255,
            green: CGFloat((int >> 8) & 0xFF) / 255,
            blue: CGFloat(int & 0xFF) / 255,
            alpha: 1
        )
    }

    var hexString: String {
        let color = usingColorSpace(.deviceRGB) ?? self
        return String(
            format: "#%02X%02X%02X",
            Int(color.redComponent * 255),
            Int(color.greenComponent * 255),
            Int(color.blueComponent * 255)
        )
    }
}
