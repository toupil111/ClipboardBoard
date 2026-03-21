import AppKit
import SwiftUI

@main
struct ClipboardBoardApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate

    var body: some Scene {
        Settings {
            EmptyView()
        }
    }
}

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    private let store = ClipboardStore()
    private let launchAtLoginManager = LaunchAtLoginManager()
    private let autoPasteService = AutoPasteService()
    private let preferencesStore = AppPreferencesStore()
    private let authenticationService = LocalAuthenticationService()
    private let sensitiveAccessLogService = SensitiveAccessLogService()
    private let transferService = ClipboardTransferService()
    private let blackScreenService = BlackScreenIntegrationService()
    private lazy var cloudSyncService: ClipboardCloudSyncService? = {
        guard AppCapabilityInspector.hasICloudEntitlement() else {
            return nil
        }
        return ClipboardCloudSyncService()
    }()
    private var monitor: PasteboardMonitor?
    private var panelController: FloatingPanelController?
    private var statusBarController: StatusBarController?

    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.accessory)

        let panelView = ClipboardPanelView(
            store: store,
            launchAtLoginManager: launchAtLoginManager,
            autoPasteService: autoPasteService,
            preferencesStore: preferencesStore,
            authenticationService: authenticationService,
            sensitiveAccessLogService: sensitiveAccessLogService,
            transferService: transferService,
            blackScreenService: blackScreenService,
            onPanelResize: { [weak self] size in
                self?.panelController?.updatePreferredSize(size, animated: true)
            },
            onSelect: { [weak self] item in
                Task { @MainActor [weak self] in
                    await self?.selectItem(item)
                }
            },
            onClose: { [weak self] in
                self?.panelController?.hide()
            }
        )

        panelController = FloatingPanelController(rootView: panelView)
        panelController?.updatePreferredSize(preferencesStore.panelSizePreset.size, animated: false)
        statusBarController = StatusBarController(
            onToggle: { [weak self] in
                self?.togglePanel()
            },
            onCreateNamedBackup: { [weak self] in
                Task { @MainActor [weak self] in
                    self?.createNamedBackupFromMenu()
                }
            },
            onQuickImport: { [weak self] in
                Task { @MainActor [weak self] in
                    await self?.performQuickImport()
                }
            },
            onQuickExport: { [weak self] in
                Task { @MainActor [weak self] in
                    await self?.performQuickExport()
                }
            },
            onExportLatestBackup: { [weak self] in
                Task { @MainActor [weak self] in
                    await self?.exportLatestBackup()
                }
            },
            onExportBackup: { [weak self] backup in
                Task { @MainActor [weak self] in
                    await self?.exportBackup(backup)
                }
            },
            onRestoreLatestBackup: { [weak self] in
                Task { @MainActor [weak self] in
                    await self?.restoreLatestBackup()
                }
            },
            historySummaryProvider: { [weak self] in
                self?.store.statusSummary ?? ClipboardStatusSummary(itemCount: 0, latestBackupDate: nil, latestBackupName: nil)
            },
            backupsProvider: { [weak self] in
                self?.store.backupVersions ?? []
            },
            onRestoreBackup: { [weak self] backup in
                Task { @MainActor [weak self] in
                    await self?.restoreBackup(backup)
                }
            },
            onOpenDataDirectory: { [weak self] in
                self?.store.openDataDirectory()
            },
            onOpenBackupsDirectory: { [weak self] in
                self?.store.openBackupsDirectory()
            },
            onOpenPayloadsDirectory: { [weak self] in
                self?.store.openPayloadsDirectory()
            },
            onQuit: {
                NSApp.terminate(nil)
            }
        )

        let monitor = PasteboardMonitor(store: store)
        monitor.start()
        self.monitor = monitor

        store.cleanupPolicyProvider = { [weak self] in
            ClipboardCleanupPolicy(
                autoCleanupOldBackupsEnabled: self?.preferencesStore.autoCleanupOldBackupsEnabled ?? false,
                keepBackupCount: self?.preferencesStore.autoCleanupBackupKeepCount ?? 3
            )
        }

        store.onItemsChanged = { [weak self] items in
            self?.cloudSyncService?.scheduleUpload(items: items)
        }
        store.onCopyCaptured = { [weak self] item in
            self?.statusBarController?.showCopySuccessFeedback()
            let isWarning = item.isLargeAttachment(thresholdMB: self?.preferencesStore.largeAttachmentThresholdMB ?? 100)
            let message = isWarning ? "已复制大附件 · \(item.title)" : "复制成功 · \(item.title)"
            CopyHUDController.shared.show(message: message, isWarning: isWarning)
        }
        cloudSyncService?.syncNow(items: store.items)

        HotKeyManager.shared.onToggle = { [weak self] in
            self?.togglePanel()
        }
        HotKeyManager.shared.register()
    }

    func applicationWillTerminate(_ notification: Notification) {
        monitor?.stop()
        HotKeyManager.shared.unregister()
    }

    private func togglePanel() {
        if panelController?.isVisible == false {
            autoPasteService.rememberFrontmostApplication(excluding: Bundle.main.bundleIdentifier)
            blackScreenService.refreshStatus()
        }
        panelController?.toggle()
    }

    private func selectItem(_ item: ClipboardItem) async {
        store.restoreItem(item)
        panelController?.hide()
        if item.isSensitive {
            sensitiveAccessLogService.record(item: item, action: "选择并粘贴敏感条目")
            autoPasteService.clearClipboardAfterDelay(seconds: preferencesStore.sensitiveClipboardClearSeconds)
        }

        autoPasteService.pasteIntoRememberedApplication()
    }

    private func performQuickImport() async {
        if let archive = transferService.importArchive() {
            if archive.containsSensitiveItems {
                let authenticated = await authenticationService.authenticate(reason: "导入敏感剪贴板内容需要验证身份")
                guard authenticated else {
                    return
                }
            }
            store.applyImportedArchive(archive)
        }
    }

    private func performQuickExport() async {
        if store.items.contains(where: { $0.isSensitive }) {
            let authenticated = await authenticationService.authenticate(reason: "导出敏感剪贴板内容需要验证身份")
            guard authenticated else {
                return
            }
        }

        transferService.exportArchive(
            items: store.items,
            customTags: store.customTags,
            includeSensitiveItems: store.items.contains(where: { $0.isSensitive })
        )
    }

    private func restoreLatestBackup() async {
        guard let latestBackup = store.backupVersions.first else {
            return
        }

        await restoreBackup(latestBackup)
    }

    private func exportLatestBackup() async {
        guard let latestBackup = store.backupVersions.first else {
            return
        }

        await exportBackup(latestBackup)
    }

    private func exportBackup(_ backup: ClipboardBackupVersion) async {
        guard store.backupVersions.contains(backup) else {
            return
        }

        if backup.sensitiveItemCount > 0 {
            let authenticated = await authenticationService.authenticate(reason: "导出最近备份需要验证身份")
            guard authenticated else {
                return
            }
        }

        _ = store.exportBackup(backup)
    }

    private func restoreBackup(_ backup: ClipboardBackupVersion) async {
        guard store.backupVersions.contains(backup) else {
            return
        }

        if preferencesStore.requiresAuthenticationForSensitiveRestore {
            let authenticated = await authenticationService.authenticate(reason: "恢复最近备份需要验证身份")
            guard authenticated else {
                return
            }
        }

        _ = store.restoreBackup(backup)
    }

    private func createNamedBackupFromMenu() {
        let alert = NSAlert()
        alert.messageText = "创建命名快照"
        alert.informativeText = "输入一个便于识别的备份名称。"
        alert.addButton(withTitle: "保存")
        alert.addButton(withTitle: "取消")

        let textField = NSTextField(frame: NSRect(x: 0, y: 0, width: 260, height: 24))
        textField.placeholderString = "例如：升级前 / 整理前"
        alert.accessoryView = textField

        guard alert.runModal() == .alertFirstButtonReturn else {
            return
        }

        let name = textField.stringValue.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !name.isEmpty else {
            return
        }

        _ = store.createNamedBackup(name)
    }
}
