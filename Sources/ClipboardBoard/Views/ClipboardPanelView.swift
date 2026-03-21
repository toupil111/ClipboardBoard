import AppKit
import SwiftUI

private enum BackupSortMode: String, CaseIterable, Identifiable {
    case newest
    case oldest
    case name

    var id: String { rawValue }

    var title: String {
        switch self {
        case .newest:
            return "最新"
        case .oldest:
            return "最旧"
        case .name:
            return "名称"
        }
    }
}

private struct ClipboardPanelTab: Identifiable, Hashable {
    enum Kind: Hashable {
        case all
        case favorites
        case sensitive
        case emails
        case phones
        case accounts
        case custom(String)
    }

    let kind: Kind

    var id: String {
        switch kind {
        case .all:
            return "all"
        case .favorites:
            return "favorites"
        case .sensitive:
            return "sensitive"
        case .emails:
            return "emails"
        case .phones:
            return "phones"
        case .accounts:
            return "accounts"
        case .custom(let name):
            return "custom-\(name)"
        }
    }

    var title: String {
        switch kind {
        case .all:
            return "全部"
        case .favorites:
            return "收藏"
        case .sensitive:
            return "敏感"
        case .emails:
            return "邮箱"
        case .phones:
            return "手机号"
        case .accounts:
            return "账号"
        case .custom(let name):
            return name
        }
    }

    var symbolName: String {
        switch kind {
        case .all:
            return "tray.full"
        case .favorites:
            return "star.fill"
        case .sensitive:
            return "lock.shield.fill"
        case .emails:
            return "envelope.fill"
        case .phones:
            return "phone.fill"
        case .accounts:
            return "person.crop.circle.fill"
        case .custom:
            return "tag.fill"
        }
    }

    func matches(_ item: ClipboardItem) -> Bool {
        switch kind {
        case .all:
            return !item.isSensitive
        case .favorites:
            return item.isFavorite && !item.isSensitive
        case .sensitive:
            return item.isSensitive
        case .emails:
            return !item.isSensitive && item.detectedLabel == .email
        case .phones:
            return !item.isSensitive && item.detectedLabel == .phone
        case .accounts:
            return !item.isSensitive && item.detectedLabel == .account
        case .custom(let name):
            return !item.isSensitive && item.customTags.contains(name)
        }
    }

    static let builtInTabs: [ClipboardPanelTab] = [
        ClipboardPanelTab(kind: .all),
        ClipboardPanelTab(kind: .favorites),
        ClipboardPanelTab(kind: .sensitive),
        ClipboardPanelTab(kind: .emails),
        ClipboardPanelTab(kind: .phones),
        ClipboardPanelTab(kind: .accounts)
    ]
}

private struct TagEditorContext: Identifiable {
    let item: ClipboardItem

    var id: UUID { item.id }
}

private struct BackupRenameContext: Identifiable {
    let backup: ClipboardBackupVersion

    var id: String { backup.id }
}

struct ClipboardPanelView: View {
    @ObservedObject var store: ClipboardStore
    @ObservedObject var launchAtLoginManager: LaunchAtLoginManager
    @ObservedObject var autoPasteService: AutoPasteService
    @ObservedObject var preferencesStore: AppPreferencesStore
    @ObservedObject var authenticationService: LocalAuthenticationService
    @ObservedObject var sensitiveAccessLogService: SensitiveAccessLogService
    @ObservedObject var transferService: ClipboardTransferService
    @ObservedObject var blackScreenService: BlackScreenIntegrationService
    let onPanelResize: (CGSize) -> Void
    let onSelect: (ClipboardItem) -> Void
    let onClose: () -> Void

    @State private var selectedTab = ClipboardPanelTab(kind: .all)
    @State private var isCreatingTag = false
    @State private var pendingTagName = ""
    @State private var tagEditorContext: TagEditorContext?
    @State private var isShowingExportSheet = false
    @State private var isShowingSettingsSheet = false
    @State private var exportIncludesSensitive = true
    @State private var exportFavoritesOnly = false
    @State private var exportCurrentTabOnly = false
    @State private var exportSensitiveOnly = false
    @State private var revealedSensitiveIDs: Set<UUID> = []
    @State private var revealTasks: [UUID: Task<Void, Never>] = [:]
    @State private var pendingBackupName = ""
    @State private var backupSearchText = ""
    @State private var backupSortMode: BackupSortMode = .newest
    @State private var backupRenameContext: BackupRenameContext?
    @State private var pendingRenameBackupName = ""
    @State private var copiedBackupName: String?
    @State private var copiedBackupPath: String?
    @State private var searchText = ""
    @State private var selectedItemID: UUID?
    @State private var isSensitiveTabAuthorized = false
    @FocusState private var isSearchFieldFocused: Bool

    var body: some View {
        VStack(spacing: 0) {
            header
                .padding(.horizontal, 24)
                .padding(.top, 22)
                .padding(.bottom, 18)

            Divider()
                .overlay(.white.opacity(0.08))

            tabBar
                .padding(.horizontal, 24)
                .padding(.top, 18)
                .padding(.bottom, 8)

            searchBar
                .padding(.horizontal, 24)
                .padding(.bottom, 10)

            if isCreatingTag {
                tagComposer
                    .padding(.horizontal, 24)
                    .padding(.bottom, 6)
                    .transition(.move(edge: .top).combined(with: .opacity))
            }

            ScrollView(showsIndicators: false) {
                LazyVStack(spacing: 14) {
                    if filteredItems.isEmpty {
                        emptyState
                    } else {
                        ForEach(filteredItems) { item in
                            ClipboardRowView(
                                item: item,
                                availableTags: store.customTags,
                                isSensitiveRevealed: revealedSensitiveIDs.contains(item.id) || (selectedTab.kind == .sensitive && isSensitiveTabAuthorized),
                                isSelected: selectedItemID == item.id,
                                largeAttachmentThresholdMB: preferencesStore.largeAttachmentThresholdMB,
                                sensitiveVisibleCharacterCount: preferencesStore.sensitivePreviewVisibleCharacterCount,
                                density: preferencesStore.listDensity,
                                searchKeyword: searchText,
                                onFavoriteToggle: { store.toggleFavorite(item) },
                                onPinToggle: { store.togglePin(item) },
                                onSensitiveToggle: { store.toggleSensitive(item) },
                                onSetSensitiveTimeout: { store.updateSensitiveTimeout($0, for: item) },
                                onRevealSensitive: {
                                    if preferencesStore.requiresAuthenticationForSensitiveRestore {
                                        revealSensitiveItem(item)
                                    } else {
                                        revealSensitiveItemWithoutAuthentication(item)
                                    }
                                },
                                onDelete: { store.deleteItem(item) },
                                onAssignTag: { store.assignTag($0, to: item) },
                                onEditTags: { tagEditorContext = TagEditorContext(item: item) }
                            ) {
                                selectedItemID = item.id
                                onSelect(item)
                            }
                            .scrollTransition(axis: .vertical) { content, phase in
                                content
                                    .scaleEffect(phase.isIdentity ? 1 : 0.97)
                                    .opacity(phase.isIdentity ? 1 : 0.72)
                                    .blur(radius: phase.isIdentity ? 0 : 1.6)
                            }
                        }
                    }
                }
                .padding(24)
            }
            .background(Color.clear)
            .animation(.spring(response: 0.32, dampingFraction: 0.85), value: store.items)
            .animation(.spring(response: 0.28, dampingFraction: 0.84), value: selectedTab)
            .animation(.spring(response: 0.24, dampingFraction: 0.86), value: isCreatingTag)

            Divider()
                .overlay(.white.opacity(0.08))

            footer
                .padding(.horizontal, 24)
                .padding(.vertical, 16)
        }
        .frame(minWidth: preferencesStore.panelSizePreset.size.width, minHeight: preferencesStore.panelSizePreset.size.height)
        .background(
            panelBackground
        )
        .preferredColorScheme(preferencesStore.appearanceMode.colorScheme)
        .tint(preferencesStore.accentColor)
        .overlay {
            KeyboardMonitorView { event in
                handleKeyDown(event)
            }
            .frame(width: 0, height: 0)

            if isShowingExportSheet {
                exportOverlay
                    .zIndex(21)
            }

            if isShowingSettingsSheet {
                settingsOverlay
                    .zIndex(22)
            }

            if let renameContext = backupRenameContext {
                backupRenameOverlay(renameContext)
                    .zIndex(30)
            }

            if let context = tagEditorContext {
                ZStack {
                    Rectangle()
                        .fill(.black.opacity(0.28))
                        .ignoresSafeArea()
                        .contentShape(Rectangle())
                        .onTapGesture {
                            tagEditorContext = nil
                        }

                    TagAssignmentSheet(
                        item: context.item,
                        availableTags: store.customTags,
                        onSave: { tags in
                            store.updateCustomTags(tags, for: context.item, markFavorite: true)
                            tagEditorContext = nil
                        },
                        onCreateTag: { name in
                            store.createCustomTag(name)
                        },
                        onClose: {
                            tagEditorContext = nil
                        }
                    )
                    .frame(width: secondaryOverlayWidth)
                    .frame(maxHeight: secondaryOverlayMaxHeight)
                    .padding(.horizontal, overlayHorizontalInset)
                    .padding(.vertical, overlayVerticalInset)
                    .transition(.scale(scale: 0.96).combined(with: .opacity))
                }
                .zIndex(31)
            }

            if !preferencesStore.hasCompletedOnboarding {
                onboardingOverlay
                    .zIndex(40)
            }
        }
        .onChange(of: store.customTags) { _, tags in
            if case let .custom(name) = selectedTab.kind, !tags.contains(name) {
                selectedTab = ClipboardPanelTab(kind: .all)
            }
        }
        .onAppear {
            onPanelResize(preferencesStore.panelSizePreset.size)
            syncSelectionWithFilteredItems()
        }
        .onChange(of: preferencesStore.panelSizePreset) { _, preset in
            onPanelResize(preset.size)
        }
        .onChange(of: filteredItems.map(\.id)) { _, _ in
            syncSelectionWithFilteredItems()
        }
    }

    private var header: some View {
        HStack(alignment: .top, spacing: 16) {
            VStack(alignment: .leading, spacing: 8) {
                Text("粘贴板")
                    .font(.system(size: 28, weight: .bold, design: .rounded))
                    .foregroundStyle(.white)

                if let lastMessage = transferService.lastMessage {
                    Text(lastMessage)
                        .font(.caption)
                        .foregroundStyle(preferencesStore.accentColor.opacity(0.95))
                } else if let lastError = transferService.lastError ?? authenticationService.lastError {
                    Text(lastError)
                        .font(.caption)
                        .foregroundStyle(.orange.opacity(0.95))
                        .lineLimit(2)
                }
            }

            Spacer()

            VStack(alignment: .trailing, spacing: 10) {
                if let lastError = autoPasteService.lastError {
                    Button(lastError) {
                        autoPasteService.requestAccessibilityPermission()
                    }
                    .buttonStyle(.plain)
                    .font(.caption)
                    .foregroundStyle(.orange.opacity(0.95))
                    .multilineTextAlignment(.trailing)
                    .frame(maxWidth: 220, alignment: .trailing)
                }

                controlBar
            }
        }
    }

    private var controlBar: some View {
        HStack(spacing: 10) {
            Button {
                if let archive = transferService.importArchive() {
                    Task { @MainActor in
                        if archive.containsSensitiveItems {
                            let authenticated = await authenticationService.authenticate(reason: "导入敏感剪贴板内容需要验证身份")
                            guard authenticated else {
                                return
                            }
                        }
                        store.applyImportedArchive(archive)
                    }
                }
            } label: {
                Label("导入", systemImage: "square.and.arrow.down")
            }
            .buttonStyle(.borderless)
            .foregroundStyle(.white.opacity(0.88))

            Button {
                exportIncludesSensitive = true
                exportFavoritesOnly = false
                exportCurrentTabOnly = false
                exportSensitiveOnly = false
                isShowingExportSheet = true
            } label: {
                Label("导出", systemImage: "square.and.arrow.up")
            }
            .buttonStyle(.borderless)
            .foregroundStyle(.white.opacity(0.88))

            Button {
                isShowingSettingsSheet = true
            } label: {
                Label("设置", systemImage: "gearshape.fill")
                    .foregroundStyle(.white.opacity(0.88))
            }
            .buttonStyle(.borderless)

            Button {
                blackScreenService.openIfAvailable()
            } label: {
                ZStack {
                    Circle()
                        .fill(blackScreenService.isInstalled ? preferencesStore.accentColor.opacity(0.88) : .white.opacity(0.12))
                    Text("B")
                        .font(.system(size: 12, weight: .black))
                        .foregroundStyle(blackScreenService.isInstalled ? Color.black.opacity(0.82) : .white.opacity(0.42))
                }
                .frame(width: 28, height: 28)
            }
            .buttonStyle(.plain)
            .help(blackScreenService.isInstalled ? "打开 BlackScreen" : "未检测到 BlackScreen")
        }
    }

    private var tabBar: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 10) {
                ForEach(allTabs) { tab in
                    Button {
                        handleTabSelection(tab)
                    } label: {
                        HStack(spacing: 8) {
                            Image(systemName: tab.symbolName)
                                .font(.system(size: 12, weight: .semibold))

                            Text(tab.title)
                                .font(.system(size: 13, weight: .semibold))

                            Text("\(count(for: tab))")
                                .font(.system(size: 12, weight: .bold))
                                .foregroundStyle(selectedTab == tab ? Color.black.opacity(0.72) : .white.opacity(0.72))
                                .padding(.horizontal, 8)
                                .padding(.vertical, 3)
                                .background(
                                    Capsule(style: .continuous)
                                        .fill(selectedTab == tab ? .white.opacity(0.85) : .white.opacity(0.08))
                                )
                        }
                        .foregroundStyle(selectedTab == tab ? Color.black.opacity(0.82) : .white.opacity(0.88))
                        .padding(.horizontal, 14)
                        .padding(.vertical, 10)
                        .background(
                            Capsule(style: .continuous)
                                .fill(selectedTab == tab ? .white : .white.opacity(0.08))
                        )
                    }
                    .buttonStyle(.plain)
                }

                Button {
                    withAnimation(.spring(response: 0.24, dampingFraction: 0.84)) {
                        isCreatingTag.toggle()
                    }
                    if !isCreatingTag {
                        pendingTagName = ""
                    }
                } label: {
                    Label("新标签", systemImage: "plus")
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundStyle(.white.opacity(0.88))
                        .padding(.horizontal, 14)
                        .padding(.vertical, 10)
                        .background(
                            Capsule(style: .continuous)
                                .fill(.white.opacity(0.08))
                        )
                }
                .buttonStyle(.plain)
            }
            .padding(.trailing, 4)
        }
    }

    private var searchBar: some View {
        HStack(spacing: 10) {
            Image(systemName: "magnifyingglass")
                .foregroundStyle(.white.opacity(0.6))

            TextField("搜索标题、内容、标签或文件名", text: $searchText)
                .textFieldStyle(.plain)
                .foregroundStyle(.white)
                .focused($isSearchFieldFocused)

            if !searchText.isEmpty {
                Button {
                    searchText = ""
                } label: {
                    Image(systemName: "xmark.circle.fill")
                        .foregroundStyle(.white.opacity(0.6))
                }
                .buttonStyle(.plain)
            }
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 12)
        .background(
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .fill(.white.opacity(0.08))
        )
    }

    private var tagComposer: some View {
        HStack(spacing: 10) {
            Image(systemName: "tag.fill")
                .foregroundStyle(.white.opacity(0.65))

            TextField("输入新的标签分组，例如：工作邮箱 / 家庭账号", text: $pendingTagName)
                .textFieldStyle(.plain)
                .font(.callout)
                .foregroundStyle(.white)
                .padding(.horizontal, 12)
                .padding(.vertical, 10)
                .background(
                    RoundedRectangle(cornerRadius: 14, style: .continuous)
                        .fill(.white.opacity(0.08))
                )

            Button("添加") {
                addStandaloneTag()
            }
            .buttonStyle(.borderedProminent)
            .tint(.green.opacity(0.8))

            Button("取消") {
                withAnimation(.spring(response: 0.24, dampingFraction: 0.84)) {
                    isCreatingTag = false
                    pendingTagName = ""
                }
            }
            .buttonStyle(.plain)
            .foregroundStyle(.white.opacity(0.74))
        }
    }

    private var emptyState: some View {
        VStack(spacing: 14) {
            Image(systemName: selectedTab.symbolName)
                .font(.system(size: 28, weight: .semibold))
                .foregroundStyle(.white.opacity(0.65))

            Text(emptyTitle)
                .font(.headline)
                .foregroundStyle(.white)

            Text(emptyMessage)
                .font(.callout)
                .foregroundStyle(.white.opacity(0.64))
                .multilineTextAlignment(.center)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 60)
        .background(
            RoundedRectangle(cornerRadius: 24, style: .continuous)
                .fill(.white.opacity(0.06))
        )
    }

    private var footer: some View {
        VStack(spacing: 10) {
            HStack(spacing: 14) {
                Label("Option + Command + V 唤醒", systemImage: "keyboard")
                    .font(.callout)
                    .foregroundStyle(.white.opacity(0.7))

                Label("↑↓ 选择 · Enter 粘贴 · ⌘F 搜索 · Esc 关闭", systemImage: "command")
                    .font(.caption)
                    .foregroundStyle(.white.opacity(0.54))
            }
            .frame(maxWidth: .infinity, alignment: .center)

            Button("关闭") {
                onClose()
            }
            .buttonStyle(.borderedProminent)
            .tint(preferencesStore.accentColor.opacity(0.8))
        }
        .frame(maxWidth: .infinity)
    }

    private var panelBackground: some View {
        LinearGradient(
            colors: preferencesStore.appearanceMode == .light
            ? [Color(red: 0.95, green: 0.96, blue: 0.98), Color(red: 0.9, green: 0.92, blue: 0.96)]
            : [Color(red: 0.12, green: 0.14, blue: 0.2), Color(red: 0.08, green: 0.09, blue: 0.14)],
            startPoint: .topLeading,
            endPoint: .bottomTrailing
        )
    }

    private var exportOverlay: some View {
        ZStack {
            Rectangle()
                .fill(.black.opacity(0.3))
                .ignoresSafeArea()
                .contentShape(Rectangle())
                .onTapGesture {
                    isShowingExportSheet = false
                }

            VStack(alignment: .leading, spacing: 18) {
                Text("导出剪贴板")
                    .font(.title3.weight(.bold))

                Text("导出文件会使用 AES-GCM 加密保存。包含敏感内容时，需要先完成 Touch ID 或系统密码验证。")
                    .font(.callout)
                    .foregroundStyle(.secondary)

                Toggle("仅导出当前标签页", isOn: $exportCurrentTabOnly)
                Toggle("仅导出收藏内容", isOn: $exportFavoritesOnly)
                Toggle("仅导出敏感分组", isOn: $exportSensitiveOnly)
                Toggle("包含敏感分组内容", isOn: $exportIncludesSensitive)
                    .disabled(exportSensitiveOnly)

                Text(exportSummaryText)
                    .font(.caption)
                    .foregroundStyle(.secondary)

                HStack {
                    Button("取消") {
                        isShowingExportSheet = false
                    }

                    Spacer()

                    Button("开始导出") {
                        Task { @MainActor in
                            if exportItems.contains(where: { $0.isSensitive }) {
                                let authenticated = await authenticationService.authenticate(reason: "导出敏感剪贴板内容需要验证身份")
                                guard authenticated else {
                                    return
                                }
                            }

                            transferService.exportArchive(
                                items: exportItems,
                                customTags: store.customTags,
                                includeSensitiveItems: exportItems.contains(where: { $0.isSensitive })
                            )
                            isShowingExportSheet = false
                        }
                    }
                    .buttonStyle(.borderedProminent)
                }
            }
            .padding(24)
            .frame(width: 460)
            .background(
                RoundedRectangle(cornerRadius: 24, style: .continuous)
                    .fill(.ultraThinMaterial)
                    .overlay(
                        RoundedRectangle(cornerRadius: 24, style: .continuous)
                            .stroke(.white.opacity(0.12), lineWidth: 1)
                    )
            )
            .shadow(color: .black.opacity(0.3), radius: 24, y: 16)
        }
    }

    private var settingsOverlay: some View {
        ZStack {
            Rectangle()
                .fill(.black.opacity(0.3))
                .ignoresSafeArea()
                .contentShape(Rectangle())
                .onTapGesture {
                    isShowingSettingsSheet = false
                }

            ScrollView(showsIndicators: false) {
                VStack(alignment: .leading, spacing: 18) {
                    Text("界面与安全设置")
                        .font(.title3.weight(.bold))

                    VStack(alignment: .leading, spacing: 12) {
                        Toggle("开机启动", isOn: Binding(
                            get: { launchAtLoginManager.isEnabled },
                            set: { launchAtLoginManager.setEnabled($0) }
                        ))

                        if let lastError = launchAtLoginManager.lastError {
                            Text(lastError)
                                .font(.caption)
                                .foregroundStyle(.orange.opacity(0.9))
                        }
                    }

                VStack(alignment: .leading, spacing: 12) {
                    Text("界面模式")
                        .font(.headline)

                    Picker("界面模式", selection: $preferencesStore.appearanceMode) {
                        ForEach(AppAppearanceMode.allCases) { mode in
                            Text(mode.title).tag(mode)
                        }
                    }
                    .pickerStyle(.segmented)
                }

                VStack(alignment: .leading, spacing: 12) {
                    Text("强调色")
                        .font(.headline)

                    ColorPicker("选择强调色", selection: Binding(
                        get: { preferencesStore.accentColor },
                        set: { color in
                            preferencesStore.accentColorHex = NSColor(color).hexString
                        }
                    ), supportsOpacity: false)
                }

                VStack(alignment: .leading, spacing: 12) {
                    Text("敏感明文自动隐藏")
                        .font(.headline)

                    Picker("自动隐藏时间", selection: $preferencesStore.sensitiveRevealTimeoutSeconds) {
                        Text("10 秒").tag(10)
                        Text("20 秒").tag(20)
                        Text("30 秒").tag(30)
                        Text("60 秒").tag(60)
                    }
                    .pickerStyle(.segmented)

                    Text("验证后显示的敏感内容会在设定时间后自动重新隐藏。")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }

                Toggle("恢复敏感内容时始终验证身份", isOn: $preferencesStore.requiresAuthenticationForSensitiveRestore)

                VStack(alignment: .leading, spacing: 12) {
                    Text("界面布局")
                        .font(.headline)

                    Picker("面板尺寸", selection: $preferencesStore.panelSizePreset) {
                        ForEach(PanelSizePreset.allCases) { preset in
                            Text(preset.title).tag(preset)
                        }
                    }
                    .pickerStyle(.segmented)

                    Picker("列表密度", selection: $preferencesStore.listDensity) {
                        ForEach(ClipboardListDensity.allCases) { density in
                            Text(density.title).tag(density)
                        }
                    }
                    .pickerStyle(.segmented)

                }

                VStack(alignment: .leading, spacing: 12) {
                    Text("大附件提醒")
                        .font(.headline)

                    Picker("大附件阈值", selection: $preferencesStore.largeAttachmentThresholdMB) {
                        Text("25 MB").tag(25)
                        Text("50 MB").tag(50)
                        Text("100 MB").tag(100)
                        Text("250 MB").tag(250)
                    }
                    .pickerStyle(.segmented)

                    Text("超过阈值的附件会显示红色标记，并在复制时弹出更明显提醒。")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }

                VStack(alignment: .leading, spacing: 12) {
                    Text("敏感内容策略")
                        .font(.headline)

                    Picker("显示开头字符数", selection: $preferencesStore.sensitivePreviewVisibleCharacterCount) {
                        Text("2 个").tag(2)
                        Text("4 个").tag(4)
                        Text("6 个").tag(6)
                    }
                    .pickerStyle(.segmented)

                    Picker("剪贴板自动清空", selection: $preferencesStore.sensitiveClipboardClearSeconds) {
                        Text("10 秒").tag(10)
                        Text("15 秒").tag(15)
                        Text("30 秒").tag(30)
                        Text("60 秒").tag(60)
                    }
                    .pickerStyle(.segmented)

                    Text("敏感条目只显示开头少量字符，其余内容继续遮罩，并在恢复到系统剪贴板后自动清空。")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }

                VStack(alignment: .leading, spacing: 12) {
                    Text("本地存储占用")
                        .font(.headline)

                    VStack(alignment: .leading, spacing: 10) {
                        ProgressView(value: storageUsageProgress)
                            .progressViewStyle(.linear)

                        HStack {
                            Text("总占用")
                                .font(.callout.weight(.semibold))
                            Spacer()
                            Text(formattedBytes(store.storageUsage.totalBytes))
                                .font(.callout.monospacedDigit())
                                .foregroundStyle(.secondary)
                        }

                        Text("历史、备份、附件都会计入同一条存储进度。")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                    .padding(14)
                    .background(
                        RoundedRectangle(cornerRadius: 14, style: .continuous)
                            .fill(.white.opacity(0.06))
                    )

                    HStack(spacing: 10) {
                        Button("刷新占用") {
                            store.refreshStorageUsage()
                        }
                        .buttonStyle(.bordered)
                    }
                }

                VStack(alignment: .leading, spacing: 12) {
                    Text("自动清理策略")
                        .font(.headline)

                    Toggle("自动清理旧备份", isOn: $preferencesStore.autoCleanupOldBackupsEnabled)

                    if preferencesStore.autoCleanupOldBackupsEnabled {
                        Picker("保留数量", selection: $preferencesStore.autoCleanupBackupKeepCount) {
                            Text("保留 3 个").tag(3)
                            Text("保留 5 个").tag(5)
                            Text("保留 8 个").tag(8)
                        }
                        .pickerStyle(.segmented)

                        Button(role: .destructive) {
                            store.purgeOldBackups(keeping: preferencesStore.autoCleanupBackupKeepCount)
                        } label: {
                            Text("立即执行自动清理")
                        }
                        .buttonStyle(.bordered)
                    }

                    Text("通过勾选启用自动清理，后续保存历史和创建快照时会自动按保留数量清理旧备份。")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }

                VStack(alignment: .leading, spacing: 12) {
                    Text("本地数据目录")
                        .font(.headline)

                    Text("所有历史记录、加密备份和标签数据都保存在本机 Application Support 目录中。")
                        .font(.caption)
                        .foregroundStyle(.secondary)

                    HStack(spacing: 10) {
                        Button("打开数据目录") {
                            store.openDataDirectory()
                        }
                        .buttonStyle(.bordered)

                        Button("打开备份目录") {
                            store.openBackupsDirectory()
                        }
                        .buttonStyle(.bordered)

                        Button("打开附件目录") {
                            store.openPayloadsDirectory()
                        }
                        .buttonStyle(.bordered)
                    }

                    if let copiedBackupName {
                        Text("已复制备份名称：\(copiedBackupName)")
                            .font(.caption)
                            .foregroundStyle(preferencesStore.accentColor)
                    }

                    if let copiedBackupPath {
                        Text("已复制备份路径：\(copiedBackupPath)")
                            .font(.caption)
                            .foregroundStyle(preferencesStore.accentColor)
                            .lineLimit(2)
                    }
                }

                VStack(alignment: .leading, spacing: 12) {
                    Text("敏感访问日志")
                        .font(.headline)

                    if sensitiveAccessLogService.entries.isEmpty {
                        Text("暂时还没有敏感内容访问记录。")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    } else {
                        VStack(spacing: 8) {
                            ForEach(Array(sensitiveAccessLogService.entries.prefix(5))) { entry in
                                HStack(alignment: .top) {
                                    VStack(alignment: .leading, spacing: 3) {
                                        Text(entry.itemTitle)
                                            .font(.callout.weight(.medium))
                                        Text(entry.action)
                                            .font(.caption)
                                            .foregroundStyle(.secondary)
                                    }

                                    Spacer()

                                    Text(entry.timestamp.formatted(date: .abbreviated, time: .shortened))
                                        .font(.caption)
                                        .foregroundStyle(.secondary)
                                }
                                .padding(10)
                                .background(
                                    RoundedRectangle(cornerRadius: 12, style: .continuous)
                                        .fill(.white.opacity(0.06))
                                )
                            }
                        }
                    }
                }

                    HStack {
                        Button("关闭") {
                            isShowingSettingsSheet = false
                        }

                        Spacer()
                    }
                }
                .padding(overlayContentPadding)
            }
            .frame(width: primaryOverlayWidth)
            .frame(maxHeight: primaryOverlayMaxHeight)
            .padding(.horizontal, overlayHorizontalInset)
            .padding(.vertical, overlayVerticalInset)
            .background(
                RoundedRectangle(cornerRadius: 24, style: .continuous)
                    .fill(.ultraThinMaterial)
                    .overlay(
                        RoundedRectangle(cornerRadius: 24, style: .continuous)
                            .stroke(.white.opacity(0.12), lineWidth: 1)
                    )
            )
            .shadow(color: .black.opacity(0.3), radius: 24, y: 16)
        }
    }

    private func backupRenameOverlay(_ context: BackupRenameContext) -> some View {
        ZStack {
            Rectangle()
                .fill(.black.opacity(0.3))
                .ignoresSafeArea()
                .contentShape(Rectangle())
                .onTapGesture {
                    backupRenameContext = nil
                    pendingRenameBackupName = ""
                }

            ScrollView(showsIndicators: false) {
                VStack(alignment: .leading, spacing: 18) {
                    Text("重命名备份")
                        .font(.title3.weight(.bold))

                    Text(context.backup.name)
                        .font(.callout)
                        .foregroundStyle(.secondary)

                    TextField("输入新的备份名称", text: $pendingRenameBackupName)
                        .textFieldStyle(.roundedBorder)

                    HStack {
                        Button("取消") {
                            backupRenameContext = nil
                            pendingRenameBackupName = ""
                        }

                        Spacer()

                        Button("保存") {
                            _ = store.renameBackup(context.backup, to: pendingRenameBackupName)
                            backupRenameContext = nil
                            pendingRenameBackupName = ""
                        }
                        .buttonStyle(.borderedProminent)
                        .disabled(pendingRenameBackupName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                    }
                }
            }
            .padding(overlayContentPadding)
            .frame(width: secondaryOverlayWidth)
            .frame(maxHeight: secondaryOverlayMaxHeight)
            .padding(.horizontal, overlayHorizontalInset)
            .padding(.vertical, overlayVerticalInset)
            .background(
                RoundedRectangle(cornerRadius: 24, style: .continuous)
                    .fill(.ultraThinMaterial)
                    .overlay(
                        RoundedRectangle(cornerRadius: 24, style: .continuous)
                            .stroke(.white.opacity(0.12), lineWidth: 1)
                    )
            )
            .shadow(color: .black.opacity(0.3), radius: 24, y: 16)
        }
    }

    private var allTabs: [ClipboardPanelTab] {
        ClipboardPanelTab.builtInTabs + store.customTags.map { ClipboardPanelTab(kind: .custom($0)) }
    }

    private var filteredItems: [ClipboardItem] {
        let tabMatched = store.items.filter { selectedTab.matches($0) }
        let searched = tabMatched.filter(matchesSearch)
        let sorted = sortItems(searched)
        guard let pinned = sorted.first(where: \.isPinned) else {
            return sorted
        }
        return [pinned] + sorted.filter { $0.id != pinned.id }
    }

    private func count(for tab: ClipboardPanelTab) -> Int {
        store.items.filter { tab.matches($0) }.count
    }

    private func addStandaloneTag() {
        guard let created = store.createCustomTag(pendingTagName) else {
            return
        }
        selectedTab = ClipboardPanelTab(kind: .custom(created))
        pendingTagName = ""
        withAnimation(.spring(response: 0.24, dampingFraction: 0.84)) {
            isCreatingTag = false
        }
    }

    private func backupSummary(for backup: ClipboardBackupVersion) -> String {
        var parts = ["\(backup.itemCount) 条记录"]
        if backup.sensitiveItemCount > 0 {
            parts.append("敏感 \(backup.sensitiveItemCount) 条")
        }
        parts.append(ByteCountFormatter.string(fromByteCount: backup.fileSize, countStyle: .file))
        return parts.joined(separator: " · ")
    }

    private var displayedBackups: [ClipboardBackupVersion] {
        let filtered = store.backupVersions.filter {
            backupSearchText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            || $0.name.localizedCaseInsensitiveContains(backupSearchText)
        }

        switch backupSortMode {
        case .newest:
            return filtered.sorted { $0.createdAt > $1.createdAt }
        case .oldest:
            return filtered.sorted { $0.createdAt < $1.createdAt }
        case .name:
            return filtered.sorted { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }
        }
    }

    private var emptyTitle: String {
        switch selectedTab.kind {
        case .all:
            return "还没有剪贴记录"
        case .favorites:
            return "先收藏几条常用内容"
        case .sensitive:
            return "敏感分组中还没有内容"
        case .emails:
            return "暂时没有识别到邮箱"
        case .phones:
            return "暂时没有识别到手机号"
        case .accounts:
            return "暂时没有识别到账号信息"
        case .custom(let name):
            return "标签「\(name)」里还没有内容"
        }
    }

    private var emptyMessage: String {
        switch selectedTab.kind {
        case .all:
            return searchText.isEmpty ? "复制一段文字、图片或文件后，这里会自动出现。" : "换个关键词试试，或清空搜索后查看全部记录。"
        case .favorites:
            return "把鼠标移到常用条目上，点击星标或加入标签即可进入收藏。"
        case .sensitive:
            return "把密码、验证码或隐私内容标记为敏感后，会在这里单独保护展示。"
        case .emails, .phones, .accounts:
            return "系统会自动识别常用信息；你也可以通过自定义标签继续细分管理。"
        case .custom(let name):
            return "先把常用内容加入「\(name)」分组，后续就能一键横向切换查看。"
        }
    }

    private var exportSummaryText: String {
        var summary: [String] = ["本次将导出 \(exportItems.count) 条记录"]
        if exportCurrentTabOnly {
            summary.append("当前标签页")
        }
        if exportFavoritesOnly {
            summary.append("仅收藏")
        }
        if exportSensitiveOnly {
            summary.append("仅敏感分组")
        }
        if !exportIncludesSensitive {
            summary.append("已排除敏感内容")
        }
        return summary.joined(separator: " · ")
    }

    private func formattedBytes(_ bytes: Int64) -> String {
        ByteCountFormatter.string(fromByteCount: bytes, countStyle: .file)
    }

    private var overlayHorizontalInset: CGFloat {
        max(20, preferencesStore.panelSizePreset.size.width * 0.06)
    }

    private var overlayVerticalInset: CGFloat {
        max(24, preferencesStore.panelSizePreset.size.height * 0.07)
    }

    private var overlayContentPadding: CGFloat {
        preferencesStore.listDensity == .compact ? 18 : 24
    }

    private var primaryOverlayWidth: CGFloat {
        min(max(preferencesStore.panelSizePreset.size.width - 120, 420), 620)
    }

    private var primaryOverlayMaxHeight: CGFloat {
        max(preferencesStore.panelSizePreset.size.height - (overlayVerticalInset * 2), 360)
    }

    private var secondaryOverlayWidth: CGFloat {
        min(max(primaryOverlayWidth - 80, 320), 500)
    }

    private var secondaryOverlayMaxHeight: CGFloat {
        max(primaryOverlayMaxHeight - 80, 260)
    }

    private var storageUsageProgress: Double {
        let maximumBytes = max(Int64(preferencesStore.largeAttachmentThresholdMB) * 1_048_576 * 4, 200 * 1_048_576)
        return min(Double(store.storageUsage.totalBytes) / Double(maximumBytes), 1)
    }

    @ViewBuilder
    private func storageUsageRow(title: String, value: String, emphasized: Bool = false) -> some View {
        HStack {
            Text(title)
                .font(emphasized ? .callout.weight(.semibold) : .callout)
            Spacer()
            Text(value)
                .font(emphasized ? .callout.weight(.bold) : .callout.monospacedDigit())
                .foregroundStyle(emphasized ? .primary : .secondary)
        }
    }

    private var exportItems: [ClipboardItem] {
        var items = exportCurrentTabOnly ? filteredItems : store.items
        if exportFavoritesOnly {
            items = items.filter { $0.isFavorite }
        }
        if exportSensitiveOnly {
            items = items.filter { $0.isSensitive }
        } else if !exportIncludesSensitive {
            items = items.filter { !$0.isSensitive }
        }
        return items
    }

    private func revealSensitiveItem(_ item: ClipboardItem) {
        if selectedTab.kind == .sensitive && isSensitiveTabAuthorized {
            revealSensitiveItemWithoutAuthentication(item)
            return
        }

        Task { @MainActor in
            let authenticated = await authenticationService.authenticate(reason: "查看敏感剪贴板内容需要验证身份")
            guard authenticated else {
                return
            }

            revealSensitiveItemWithoutAuthentication(item)
        }
    }

    private func revealSensitiveItemWithoutAuthentication(_ item: ClipboardItem) {
        sensitiveAccessLogService.record(item: item, action: "查看敏感明文")
        revealedSensitiveIDs.insert(item.id)
        revealTasks[item.id]?.cancel()

        let timeout = item.sensitiveRevealTimeoutSeconds ?? preferencesStore.sensitiveRevealTimeoutSeconds
        revealTasks[item.id] = Task { @MainActor in
            try? await Task.sleep(for: .seconds(timeout))
            guard !Task.isCancelled else {
                return
            }
            revealedSensitiveIDs.remove(item.id)
            revealTasks[item.id] = nil
        }
    }

    private func syncSelectionWithFilteredItems() {
        guard !filteredItems.isEmpty else {
            selectedItemID = nil
            return
        }

        if let selectedItemID,
           filteredItems.contains(where: { $0.id == selectedItemID }) {
            return
        }

        self.selectedItemID = filteredItems.first?.id
    }

    private func handleTabSelection(_ tab: ClipboardPanelTab) {
        switch tab.kind {
        case .sensitive:
            Task { @MainActor in
                guard preferencesStore.requiresAuthenticationForSensitiveRestore else {
                    isSensitiveTabAuthorized = true
                    selectedTab = tab
                    return
                }

                let authenticated = await authenticationService.authenticate(reason: "访问敏感分组需要验证身份")
                guard authenticated else {
                    return
                }

                isSensitiveTabAuthorized = true
                selectedTab = tab
            }
        default:
            isSensitiveTabAuthorized = false
            selectedTab = tab
        }
    }

    private func handleKeyDown(_ event: NSEvent) -> Bool {
        if event.modifierFlags.contains(.command) {
            switch event.charactersIgnoringModifiers {
            case "f":
                isSearchFieldFocused = true
                return true
            case "1":
                selectBuiltInTab(at: 0)
                return true
            case "2":
                selectBuiltInTab(at: 1)
                return true
            case "3":
                selectBuiltInTab(at: 2)
                return true
            case "4":
                selectBuiltInTab(at: 3)
                return true
            case "5":
                selectBuiltInTab(at: 4)
                return true
            case "6":
                selectBuiltInTab(at: 5)
                return true
            default:
                break
            }
        }

        switch event.keyCode {
        case 125:
            moveSelection(offset: 1)
            return true
        case 126:
            moveSelection(offset: -1)
            return true
        case 36, 76:
            activateSelectedItem()
            return true
        case 51:
            deleteSelectedItem()
            return true
        case 53:
            if isSearchFieldFocused, !searchText.isEmpty {
                searchText = ""
                return true
            }
            onClose()
            return true
        case 49:
            revealSelectedSensitiveItem()
            return true
        default:
            return false
        }
    }

    private func selectBuiltInTab(at index: Int) {
        guard ClipboardPanelTab.builtInTabs.indices.contains(index) else {
            return
        }
        selectedTab = ClipboardPanelTab.builtInTabs[index]
    }

    private func moveSelection(offset: Int) {
        guard !filteredItems.isEmpty else {
            return
        }

        let currentIndex = filteredItems.firstIndex(where: { $0.id == selectedItemID }) ?? 0
        let nextIndex = min(max(currentIndex + offset, 0), filteredItems.count - 1)
        selectedItemID = filteredItems[nextIndex].id
    }

    private func activateSelectedItem() {
        guard let selectedItem = filteredItems.first(where: { $0.id == selectedItemID }) else {
            return
        }
        onSelect(selectedItem)
    }

    private func deleteSelectedItem() {
        guard let selectedItem = filteredItems.first(where: { $0.id == selectedItemID }) else {
            return
        }
        store.deleteItem(selectedItem)
    }

    private func revealSelectedSensitiveItem() {
        guard let selectedItem = filteredItems.first(where: { $0.id == selectedItemID }), selectedItem.isSensitive else {
            return
        }

        if preferencesStore.requiresAuthenticationForSensitiveRestore {
            revealSensitiveItem(selectedItem)
        } else {
            revealSensitiveItemWithoutAuthentication(selectedItem)
        }
    }

    private func copyBackupName(_ backup: ClipboardBackupVersion) {
        let pasteboard = NSPasteboard.general
        pasteboard.clearContents()
        pasteboard.setString(backup.name, forType: .string)
        copiedBackupName = backup.name
        copiedBackupPath = nil
    }

    private func copyBackupPath(_ backup: ClipboardBackupVersion) {
        let pasteboard = NSPasteboard.general
        pasteboard.clearContents()
        pasteboard.setString(backup.url.path, forType: .string)
        copiedBackupPath = backup.url.path
        copiedBackupName = nil
    }

    private func matchesSearch(_ item: ClipboardItem) -> Bool {
        let keyword = searchText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !keyword.isEmpty else {
            return true
        }

        let haystacks = [
            item.title,
            item.subtitle,
            item.previewText ?? "",
            item.fileURLs.map(\.lastPathComponent).joined(separator: "\n"),
            item.displayTags.joined(separator: " ")
        ]

        return haystacks.contains { $0.localizedCaseInsensitiveContains(keyword) }
    }

    private func sortItems(_ items: [ClipboardItem]) -> [ClipboardItem] {
        items.sorted { $0.timestamp > $1.timestamp }
    }

    private var onboardingOverlay: some View {
        ZStack {
            Rectangle()
                .fill(.black.opacity(0.36))
                .ignoresSafeArea()

            VStack(alignment: .leading, spacing: 18) {
                Text("欢迎使用 ClipboardBoard")
                    .font(.title2.weight(.bold))

                Label("使用 Option + Command + V 快速呼出面板", systemImage: "keyboard")
                Label("敏感条目会二次加密、禁止自动粘贴并支持自动清空", systemImage: "lock.shield.fill")
                Label("支持搜索、标签分组、备份恢复与本地加密", systemImage: "magnifyingglass")
                Label("设置中可调整面板尺寸、列表密度和排序方式", systemImage: "slider.horizontal.3")

                HStack {
                    Spacer()

                    Button("开始使用") {
                        preferencesStore.hasCompletedOnboarding = true
                    }
                    .buttonStyle(.borderedProminent)
                }
            }
            .padding(24)
            .frame(width: 460)
            .background(
                RoundedRectangle(cornerRadius: 24, style: .continuous)
                    .fill(.ultraThinMaterial)
                    .overlay(
                        RoundedRectangle(cornerRadius: 24, style: .continuous)
                            .stroke(.white.opacity(0.12), lineWidth: 1)
                    )
            )
        }
    }
}

private struct ClipboardRowView: View {
    let item: ClipboardItem
    let availableTags: [String]
    let isSensitiveRevealed: Bool
    let isSelected: Bool
    let largeAttachmentThresholdMB: Int
    let sensitiveVisibleCharacterCount: Int
    let density: ClipboardListDensity
    let searchKeyword: String
    let onFavoriteToggle: () -> Void
    let onPinToggle: () -> Void
    let onSensitiveToggle: () -> Void
    let onSetSensitiveTimeout: (Int?) -> Void
    let onRevealSensitive: () -> Void
    let onDelete: () -> Void
    let onAssignTag: (String) -> Void
    let onEditTags: () -> Void
    let action: () -> Void

    @State private var isHovering = false

    var body: some View {
        HStack(alignment: .top, spacing: 14) {
            Button(action: action) {
                preview
            }
            .buttonStyle(.plain)

            VStack(alignment: .leading, spacing: density == .compact ? 5 : 7) {
                HStack(alignment: .firstTextBaseline, spacing: 8) {
                    Text(highlightedText(item.title))
                        .font(.headline)
                        .foregroundStyle(.white)
                        .lineLimit(1)

                    if item.isPinned {
                        Label("置顶", systemImage: "pin.fill")
                            .font(.caption2)
                            .foregroundStyle(.orange.opacity(0.95))
                    }

                    if item.isSensitive {
                        Label("敏感", systemImage: "lock.fill")
                            .font(.caption2)
                            .foregroundStyle(.red.opacity(0.95))
                    }

                    if item.isLargeAttachment(thresholdMB: largeAttachmentThresholdMB) {
                        Label("大附件", systemImage: "exclamationmark.triangle.fill")
                            .font(.caption2)
                            .foregroundStyle(.red.opacity(0.95))
                    }

                    if item.hasCustomSensitiveTimeout {
                        Label("独立超时", systemImage: "timer")
                            .font(.caption2)
                            .foregroundStyle(.purple.opacity(0.95))
                    }

                    Spacer(minLength: 10)

                    Text(item.timestamp, style: .time)
                        .font(.caption2)
                        .foregroundStyle(.white.opacity(0.5))
                }

                HStack(spacing: 8) {
                    Text(highlightedText(item.subtitle))
                        .font(.subheadline)
                        .foregroundStyle(.white.opacity(0.72))
                        .lineLimit(1)

                    if let label = item.detectedLabel {
                        Label(label.title, systemImage: label.symbolName)
                            .font(.caption2)
                            .foregroundStyle(.green.opacity(0.95))
                    }
                }

                if !item.displayTags.isEmpty {
                    ScrollView(.horizontal, showsIndicators: false) {
                        HStack(spacing: 6) {
                            ForEach(item.displayTags, id: \.self) { tag in
                                Text(tag)
                                    .font(.caption2)
                                    .foregroundStyle(.cyan.opacity(0.95))
                                    .lineLimit(1)
                            }
                        }
                    }
                }

                if let previewText = displayPreviewText {
                    Text(highlightedText(previewText))
                        .font(.caption)
                        .foregroundStyle(.white.opacity(0.62))
                        .lineLimit(1)
                        .multilineTextAlignment(.leading)
                }

                if item.isSensitive && !isSensitiveRevealed {
                    Button("验证后查看部分内容") {
                        onRevealSensitive()
                    }
                    .buttonStyle(.plain)
                    .font(.caption2)
                    .foregroundStyle(.red.opacity(0.92))
                }
            }

            Spacer(minLength: 0)

            HStack(spacing: 8) {
                Button(action: onPinToggle) {
                    Image(systemName: item.isPinned ? "pin.fill" : "pin")
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundStyle(item.isPinned ? .orange : .white.opacity(0.62))
                        .frame(width: 34, height: 34)
                        .background(
                            Circle()
                                .fill(item.isPinned ? .orange.opacity(0.18) : .white.opacity(0.08))
                        )
                }
                .buttonStyle(.plain)

                Button(action: onFavoriteToggle) {
                    Image(systemName: item.isFavorite ? "star.fill" : "star")
                        .font(.system(size: 15, weight: .semibold))
                        .foregroundStyle(item.isFavorite ? .yellow : .white.opacity(0.62))
                        .frame(width: 34, height: 34)
                        .background(
                            Circle()
                                .fill(item.isFavorite ? .yellow.opacity(0.18) : .white.opacity(0.08))
                        )
                }
                .buttonStyle(.plain)

                Button(action: onSensitiveToggle) {
                    Image(systemName: item.isSensitive ? "lock.shield.fill" : "lock.shield")
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundStyle(item.isSensitive ? .red : .white.opacity(0.62))
                        .frame(width: 34, height: 34)
                        .background(
                            Circle()
                                .fill(item.isSensitive ? .red.opacity(0.18) : .white.opacity(0.08))
                        )
                }
                .buttonStyle(.plain)

                Menu {
                    if !availableTags.isEmpty {
                        Section("加入标签分组") {
                            ForEach(availableTags, id: \.self) { tag in
                                Button(tag) {
                                    onAssignTag(tag)
                                }
                            }
                        }
                    }

                    Button("管理当前条目标签…") {
                        onEditTags()
                    }

                    Button(item.isSensitive ? "取消敏感保护" : "设为敏感内容") {
                        onSensitiveToggle()
                    }

                    if item.isSensitive {
                        Section("敏感明文自动隐藏") {
                            Button("跟随全局设置") { onSetSensitiveTimeout(nil) }
                            Button("10 秒") { onSetSensitiveTimeout(10) }
                            Button("20 秒") { onSetSensitiveTimeout(20) }
                            Button("30 秒") { onSetSensitiveTimeout(30) }
                            Button("60 秒") { onSetSensitiveTimeout(60) }
                        }
                    }

                    Divider()

                    Button(role: .destructive) {
                        onDelete()
                    } label: {
                        Label("删除", systemImage: "trash")
                    }
                } label: {
                    Image(systemName: "ellipsis.circle")
                        .font(.system(size: 16, weight: .semibold))
                        .foregroundStyle(.white.opacity(0.72))
                        .frame(width: 34, height: 34)
                        .background(
                            Circle()
                                .fill(.white.opacity(0.08))
                        )
                }
                .menuStyle(.borderlessButton)
                .fixedSize()
            }
        }
        .padding(.horizontal, density == .compact ? 12 : 14)
        .padding(.vertical, density == .compact ? 10 : 12)
        .background(
            RoundedRectangle(cornerRadius: 20, style: .continuous)
                .fill(.white.opacity(isSelected ? 0.18 : (isHovering ? 0.14 : 0.08)))
                .overlay(
                    RoundedRectangle(cornerRadius: 20, style: .continuous)
                        .stroke(isSelected ? Color.accentColor.opacity(0.9) : .white.opacity(isHovering ? 0.18 : 0.08), lineWidth: isSelected ? 1.4 : 1)
                )
        )
        .scaleEffect(isHovering || isSelected ? 1.01 : 1)
        .shadow(color: .black.opacity(isHovering || isSelected ? 0.16 : 0.06), radius: isHovering || isSelected ? 18 : 8, y: isHovering || isSelected ? 10 : 4)
        .animation(.spring(response: 0.24, dampingFraction: 0.82), value: isHovering)
        .animation(.spring(response: 0.24, dampingFraction: 0.82), value: isSelected)
        .onHover { isHovering = $0 }
    }

    @ViewBuilder
    private var preview: some View {
        if let image = item.previewImage() {
            Image(nsImage: image)
                .resizable()
                .scaledToFill()
                .frame(width: density == .compact ? 42 : 48, height: density == .compact ? 42 : 48)
                .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
        } else {
            ZStack {
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .fill(.white.opacity(0.1))

                Image(systemName: item.contentKind.symbolName)
                    .font(.system(size: 18, weight: .medium))
                    .foregroundStyle(.white.opacity(0.9))
            }
            .frame(width: density == .compact ? 42 : 48, height: density == .compact ? 42 : 48)
        }
    }

    private var displayPreviewText: String? {
        if item.isSensitive {
            return isSensitiveRevealed
            ? item.partiallyRevealedPreviewText(visibleCount: sensitiveVisibleCharacterCount)
            : item.protectedPreviewText
        }
        return item.previewText
    }

    private func highlightedText(_ source: String) -> AttributedString {
        var attributed = AttributedString(source)
        let keyword = searchKeyword.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !keyword.isEmpty else {
            return attributed
        }

        let nsRange = NSRange(source.startIndex..<source.endIndex, in: source)
        let matches = try? NSRegularExpression(pattern: NSRegularExpression.escapedPattern(for: keyword), options: [.caseInsensitive]).matches(in: source, range: nsRange)

        matches?.forEach { match in
            guard let stringRange = Range(match.range, in: source),
                  let range = Range(stringRange, in: attributed) else {
                return
            }
            attributed[range].backgroundColor = .yellow.opacity(0.35)
            attributed[range].foregroundColor = .white
        }

        return attributed
    }
}

private struct TagAssignmentSheet: View {
    let item: ClipboardItem
    let availableTags: [String]
    let onSave: ([String]) -> Void
    let onCreateTag: (String) -> Void
    let onClose: () -> Void

    @State private var selection: Set<String>
    @State private var newTagName = ""

    init(item: ClipboardItem, availableTags: [String], onSave: @escaping ([String]) -> Void, onCreateTag: @escaping (String) -> Void, onClose: @escaping () -> Void) {
        self.item = item
        self.availableTags = availableTags
        self.onSave = onSave
        self.onCreateTag = onCreateTag
        self.onClose = onClose
        _selection = State(initialValue: Set(item.customTags))
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            Text("管理标签分组")
                .font(.title3.weight(.bold))

            Text(item.title)
                .font(.callout)
                .foregroundStyle(.secondary)
                .lineLimit(2)

            HStack(spacing: 10) {
                TextField("新建标签", text: $newTagName)
                    .textFieldStyle(.roundedBorder)

                Button("新增") {
                    addTag()
                }
                .buttonStyle(.borderedProminent)
            }

            ScrollView {
                LazyVGrid(columns: [GridItem(.adaptive(minimum: 110), spacing: 10)], spacing: 10) {
                    ForEach(availableTags, id: \.self) { tag in
                        Button {
                            toggle(tag)
                        } label: {
                            HStack(spacing: 8) {
                                Image(systemName: selection.contains(tag) ? "checkmark.circle.fill" : "circle")
                                Text(tag)
                                    .lineLimit(1)
                            }
                            .frame(maxWidth: .infinity)
                            .padding(.horizontal, 12)
                            .padding(.vertical, 10)
                            .foregroundStyle(selection.contains(tag) ? .white : .primary)
                            .background(
                                RoundedRectangle(cornerRadius: 14, style: .continuous)
                                    .fill(selection.contains(tag) ? Color.accentColor : Color.secondary.opacity(0.12))
                            )
                        }
                        .buttonStyle(.plain)
                    }
                }
                .padding(.vertical, 4)
            }
            .frame(minHeight: 120, maxHeight: 220)

            HStack {
                Button("取消") {
                    onClose()
                }

                Spacer()

                Button("保存") {
                    onSave(selection.sorted())
                    onClose()
                }
                .buttonStyle(.borderedProminent)
            }
        }
        .padding(24)
        .frame(width: 460)
        .background(
            RoundedRectangle(cornerRadius: 24, style: .continuous)
                .fill(.ultraThinMaterial)
                .overlay(
                    RoundedRectangle(cornerRadius: 24, style: .continuous)
                        .stroke(.white.opacity(0.12), lineWidth: 1)
                )
        )
        .shadow(color: .black.opacity(0.3), radius: 24, y: 16)
    }

    private func toggle(_ tag: String) {
        if selection.contains(tag) {
            selection.remove(tag)
        } else {
            selection.insert(tag)
        }
    }

    private func addTag() {
        let normalized = newTagName.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !normalized.isEmpty else {
            return
        }

        onCreateTag(normalized)
        selection.insert(normalized)
        newTagName = ""
    }
}

private struct KeyboardMonitorView: NSViewRepresentable {
    let handler: (NSEvent) -> Bool

    func makeCoordinator() -> Coordinator {
        Coordinator(handler: handler)
    }

    func makeNSView(context: Context) -> NSView {
        context.coordinator.start()
        return NSView(frame: .zero)
    }

    func updateNSView(_ nsView: NSView, context: Context) {
        context.coordinator.handler = handler
    }

    static func dismantleNSView(_ nsView: NSView, coordinator: Coordinator) {
        coordinator.stop()
    }

    final class Coordinator {
        var handler: (NSEvent) -> Bool
        private var monitor: Any?

        init(handler: @escaping (NSEvent) -> Bool) {
            self.handler = handler
        }

        func start() {
            guard monitor == nil else {
                return
            }

            monitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self] event in
                guard let self else {
                    return event
                }
                return self.handler(event) ? nil : event
            }
        }

        func stop() {
            if let monitor {
                NSEvent.removeMonitor(monitor)
                self.monitor = nil
            }
        }
    }
}
