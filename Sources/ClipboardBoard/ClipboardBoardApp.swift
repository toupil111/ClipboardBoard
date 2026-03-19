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
            onSelect: { [weak self] item in
                self?.selectItem(item)
            },
            onClose: { [weak self] in
                self?.panelController?.hide()
            }
        )

        panelController = FloatingPanelController(rootView: panelView)
        statusBarController = StatusBarController(
            onToggle: { [weak self] in
                self?.togglePanel()
            },
            onQuit: {
                NSApp.terminate(nil)
            }
        )

        let monitor = PasteboardMonitor(store: store)
        monitor.start()
        self.monitor = monitor

        store.onItemsChanged = { [weak self] items in
            self?.cloudSyncService?.scheduleUpload(items: items)
        }
        store.onCopyCaptured = { [weak self] _ in
            self?.statusBarController?.showCopySuccessFeedback()
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
        }
        panelController?.toggle()
    }

    private func selectItem(_ item: ClipboardItem) {
        store.restoreItem(item)
        panelController?.hide()
        autoPasteService.pasteIntoRememberedApplication()
    }
}
