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

@MainActor
final class ClipboardPersistenceController {
    static let shared = ClipboardPersistenceController()

    private let fileManager = FileManager.default
    private let encoder = JSONEncoder()
    private let decoder = JSONDecoder()
    private let directoryURL: URL
    private let payloadsURL: URL
    private let historyURL: URL

    init() {
        let applicationSupport = fileManager.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
        directoryURL = applicationSupport.appendingPathComponent("ClipboardBoard", isDirectory: true)
        payloadsURL = directoryURL.appendingPathComponent("Payloads", isDirectory: true)
        historyURL = directoryURL.appendingPathComponent("history.json", isDirectory: false)

        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        decoder.dateDecodingStrategy = .iso8601
        encoder.dateEncodingStrategy = .iso8601

        ensureDirectories()
    }

    func loadItems(limit: Int) -> [ClipboardItem] {
        ensureDirectories()

        guard let data = try? Data(contentsOf: historyURL),
              let items = try? decoder.decode([ClipboardItem].self, from: data) else {
            return []
        }

        let limitedItems = Array(items.prefix(limit))
        cleanupPayloadFiles(keeping: Set(limitedItems.compactMap(\.payloadFileName)))
        return limitedItems
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

    func payloadData(for fileName: String) -> Data? {
        let targetURL = payloadsURL.appendingPathComponent(fileName, isDirectory: false)
        return try? Data(contentsOf: targetURL, options: [.mappedIfSafe])
    }

    func payloadURL(for fileName: String) -> URL {
        payloadsURL.appendingPathComponent(fileName, isDirectory: false)
    }

    func save(items: [ClipboardItem]) {
        ensureDirectories()

        guard let data = try? encoder.encode(items) else {
            return
        }

        try? data.write(to: historyURL, options: [.atomic])
        cleanupPayloadFiles(keeping: Set(items.compactMap(\.payloadFileName)))
    }

    private func ensureDirectories() {
        try? fileManager.createDirectory(at: payloadsURL, withIntermediateDirectories: true)
    }

    private func cleanupPayloadFiles(keeping fileNames: Set<String>) {
        let existingFiles = (try? fileManager.contentsOfDirectory(at: payloadsURL, includingPropertiesForKeys: nil)) ?? []
        for fileURL in existingFiles where !fileNames.contains(fileURL.lastPathComponent) {
            try? fileManager.removeItem(at: fileURL)
        }
    }
}

@MainActor
final class ClipboardStore: ObservableObject {
    @Published private(set) var items: [ClipboardItem]

    var onItemsChanged: (([ClipboardItem]) -> Void)?
    var onCopyCaptured: ((ClipboardItem) -> Void)?

    let maximumItems = 50
    private let persistence: ClipboardPersistenceController

    init(persistence: ClipboardPersistenceController = .shared) {
        self.persistence = persistence
        self.items = persistence.loadItems(limit: maximumItems)
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

    private func append(_ capture: ClipboardCapture, notifyFeedback: Bool) {
        let item = persistence.prepare(capture)
        guard items.first?.fingerprint != item.fingerprint else {
            return
        }

        items.removeAll { $0.fingerprint == item.fingerprint }
        items.insert(item, at: 0)

        if items.count > maximumItems {
            items = Array(items.prefix(maximumItems))
        }

        persistence.save(items: items)
        onItemsChanged?(items)
        if notifyFeedback {
            onCopyCaptured?(item)
        }
    }

    private func moveToFront(_ item: ClipboardItem) {
        items.removeAll { $0.id == item.id }
        items.insert(item, at: 0)
        persistence.save(items: items)
        onItemsChanged?(items)
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
    private let onQuit: () -> Void
    private var flashTask: Task<Void, Never>?
    private let normalColor = NSColor.labelColor
    private let successColor = NSColor.systemGreen

    init(onToggle: @escaping () -> Void, onQuit: @escaping () -> Void) {
        self.onToggle = onToggle
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
        button.toolTip = "ClipboardBoard"
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
        } else {
            onToggle()
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

    private func showMenu() {
        let menu = NSMenu()
        menu.addItem(NSMenuItem(title: "打开粘贴板", action: #selector(openPanel), keyEquivalent: ""))
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

    func windowDidResignKey(_ notification: Notification) {
        hide()
    }

    private func preferredFrame() -> NSRect {
        guard let screen = NSScreen.main else {
            return NSRect(x: 0, y: 0, width: 640, height: 760)
        }

        let width: CGFloat = 640
        let height: CGFloat = 760
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
