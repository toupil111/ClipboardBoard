import SwiftUI

private struct ClipboardPanelTab: Identifiable, Hashable {
    enum Kind: Hashable {
        case all
        case favorites
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
            return true
        case .favorites:
            return item.isFavorite
        case .emails:
            return item.detectedLabel == .email
        case .phones:
            return item.detectedLabel == .phone
        case .accounts:
            return item.detectedLabel == .account
        case .custom(let name):
            return item.customTags.contains(name)
        }
    }

    static let builtInTabs: [ClipboardPanelTab] = [
        ClipboardPanelTab(kind: .all),
        ClipboardPanelTab(kind: .favorites),
        ClipboardPanelTab(kind: .emails),
        ClipboardPanelTab(kind: .phones),
        ClipboardPanelTab(kind: .accounts)
    ]
}

private struct TagEditorContext: Identifiable {
    let item: ClipboardItem

    var id: UUID { item.id }
}

struct ClipboardPanelView: View {
    @ObservedObject var store: ClipboardStore
    @ObservedObject var launchAtLoginManager: LaunchAtLoginManager
    @ObservedObject var autoPasteService: AutoPasteService
    let onSelect: (ClipboardItem) -> Void
    let onClose: () -> Void

    @State private var selectedTab = ClipboardPanelTab(kind: .all)
    @State private var isCreatingTag = false
    @State private var pendingTagName = ""
    @State private var tagEditorContext: TagEditorContext?

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
                                onFavoriteToggle: { store.toggleFavorite(item) },
                                onPinToggle: { store.togglePin(item) },
                                onDelete: { store.deleteItem(item) },
                                onAssignTag: { store.assignTag($0, to: item) },
                                onEditTags: { tagEditorContext = TagEditorContext(item: item) }
                            ) {
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
        .frame(minWidth: 720, minHeight: 780)
        .background(
            LinearGradient(
                colors: [
                    Color(red: 0.12, green: 0.14, blue: 0.2),
                    Color(red: 0.08, green: 0.09, blue: 0.14)
                ],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )
        )
        .overlay {
            if let context = tagEditorContext {
                ZStack {
                    Rectangle()
                        .fill(.black.opacity(0.28))
                        .ignoresSafeArea()
                        .contentShape(Rectangle())
                        .onTapGesture {
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
                    .frame(maxWidth: 460)
                    .transition(.scale(scale: 0.96).combined(with: .opacity))
                }
                .zIndex(20)
            }
        }
        .onChange(of: store.customTags) { _, tags in
            if case let .custom(name) = selectedTab.kind, !tags.contains(name) {
                selectedTab = ClipboardPanelTab(kind: .all)
            }
        }
    }

    private var header: some View {
        HStack(alignment: .top, spacing: 16) {
            VStack(alignment: .leading, spacing: 8) {
                Text("粘贴板")
                    .font(.system(size: 28, weight: .bold, design: .rounded))
                    .foregroundStyle(.white)

                Text("支持删除、单一置顶和自定义标签分组，常用账号信息可以长期整理保存。")
                    .font(.callout)
                    .foregroundStyle(.white.opacity(0.72))

                Text("置顶只保留一条，新的置顶会自动替换旧的；加入分组时会自动进入收藏。")
                    .font(.footnote)
                    .foregroundStyle(.white.opacity(0.5))
            }

            Spacer()

            VStack(alignment: .trailing, spacing: 10) {
                Toggle("开机启动", isOn: Binding(
                    get: { launchAtLoginManager.isEnabled },
                    set: { launchAtLoginManager.setEnabled($0) }
                ))
                .toggleStyle(.switch)
                .foregroundStyle(.white)
                .labelsHidden()
                .overlay(alignment: .leading) {
                    Text("开机启动")
                        .font(.callout)
                        .foregroundStyle(.white.opacity(0.88))
                        .offset(x: -88)
                }

                if let lastError = launchAtLoginManager.lastError {
                    Text(lastError)
                        .font(.caption)
                        .foregroundStyle(.orange.opacity(0.9))
                        .multilineTextAlignment(.trailing)
                        .frame(maxWidth: 220, alignment: .trailing)
                }

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
            }
        }
    }

    private var tabBar: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 10) {
                ForEach(allTabs) { tab in
                    Button {
                        selectedTab = tab
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
        HStack {
            Label("Option + Command + V 唤醒", systemImage: "keyboard")
                .font(.callout)
                .foregroundStyle(.white.opacity(0.7))

            Spacer()

            Button("关闭") {
                onClose()
            }
            .buttonStyle(.borderedProminent)
            .tint(.white.opacity(0.15))
        }
    }

    private var allTabs: [ClipboardPanelTab] {
        ClipboardPanelTab.builtInTabs + store.customTags.map { ClipboardPanelTab(kind: .custom($0)) }
    }

    private var filteredItems: [ClipboardItem] {
        let matched = store.items.filter { selectedTab.matches($0) }
        guard let pinned = matched.first(where: \.isPinned) else {
            return matched
        }
        return [pinned] + matched.filter { $0.id != pinned.id }
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

    private var emptyTitle: String {
        switch selectedTab.kind {
        case .all:
            return "还没有剪贴记录"
        case .favorites:
            return "先收藏几条常用内容"
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
            return "复制一段文字、图片或文件后，这里会自动出现。"
        case .favorites:
            return "把鼠标移到常用条目上，点击星标或加入标签即可进入收藏。"
        case .emails, .phones, .accounts:
            return "系统会自动识别常用信息；你也可以通过自定义标签继续细分管理。"
        case .custom(let name):
            return "先把常用内容加入「\(name)」分组，后续就能一键横向切换查看。"
        }
    }
}

private struct ClipboardRowView: View {
    let item: ClipboardItem
    let availableTags: [String]
    let onFavoriteToggle: () -> Void
    let onPinToggle: () -> Void
    let onDelete: () -> Void
    let onAssignTag: (String) -> Void
    let onEditTags: () -> Void
    let action: () -> Void

    @State private var isHovering = false

    var body: some View {
        HStack(alignment: .top, spacing: 14) {
            Button(action: action) {
                HStack(alignment: .top, spacing: 14) {
                    preview

                    VStack(alignment: .leading, spacing: 8) {
                        HStack(alignment: .firstTextBaseline, spacing: 8) {
                            Text(item.title)
                                .font(.headline)
                                .foregroundStyle(.white)
                                .lineLimit(1)

                            if item.isPinned {
                                Label("置顶", systemImage: "pin.fill")
                                    .font(.caption)
                                    .foregroundStyle(.orange.opacity(0.95))
                                    .padding(.horizontal, 8)
                                    .padding(.vertical, 4)
                                    .background(
                                        Capsule(style: .continuous)
                                            .fill(.orange.opacity(0.16))
                                    )
                            }

                            Spacer(minLength: 12)

                            Text(item.timestamp, style: .time)
                                .font(.caption)
                                .foregroundStyle(.white.opacity(0.5))
                        }

                        HStack(spacing: 8) {
                            Text(item.subtitle)
                                .font(.subheadline)
                                .foregroundStyle(.white.opacity(0.72))
                                .lineLimit(1)

                            if let label = item.detectedLabel {
                                Label(label.title, systemImage: label.symbolName)
                                    .font(.caption)
                                    .foregroundStyle(.green.opacity(0.95))
                                    .padding(.horizontal, 8)
                                    .padding(.vertical, 4)
                                    .background(
                                        Capsule(style: .continuous)
                                            .fill(.green.opacity(0.14))
                                    )
                            }
                        }

                        if !item.customTags.isEmpty {
                            ScrollView(.horizontal, showsIndicators: false) {
                                HStack(spacing: 6) {
                                    ForEach(item.customTags, id: \.self) { tag in
                                        Label(tag, systemImage: "tag.fill")
                                            .font(.caption)
                                            .foregroundStyle(.cyan.opacity(0.95))
                                            .padding(.horizontal, 8)
                                            .padding(.vertical, 4)
                                            .background(
                                                Capsule(style: .continuous)
                                                    .fill(.cyan.opacity(0.14))
                                            )
                                    }
                                }
                            }
                        }

                        if let previewText = item.previewText {
                            Text(previewText)
                                .font(.callout)
                                .foregroundStyle(.white.opacity(0.62))
                                .lineLimit(2)
                                .multilineTextAlignment(.leading)
                        }
                    }

                    Spacer(minLength: 0)
                }
            }
            .buttonStyle(.plain)

            VStack(spacing: 8) {
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
        .padding(16)
        .background(
            RoundedRectangle(cornerRadius: 20, style: .continuous)
                .fill(.white.opacity(isHovering ? 0.14 : 0.08))
                .overlay(
                    RoundedRectangle(cornerRadius: 20, style: .continuous)
                        .stroke(.white.opacity(isHovering ? 0.18 : 0.08), lineWidth: 1)
                )
        )
        .scaleEffect(isHovering ? 1.01 : 1)
        .shadow(color: .black.opacity(isHovering ? 0.16 : 0.06), radius: isHovering ? 18 : 8, y: isHovering ? 10 : 4)
        .animation(.spring(response: 0.24, dampingFraction: 0.82), value: isHovering)
        .onHover { isHovering = $0 }
    }

    @ViewBuilder
    private var preview: some View {
        if let image = item.previewImage() {
            Image(nsImage: image)
                .resizable()
                .scaledToFill()
                .frame(width: 60, height: 60)
                .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
        } else {
            ZStack {
                RoundedRectangle(cornerRadius: 16, style: .continuous)
                    .fill(.white.opacity(0.1))

                Image(systemName: item.contentKind.symbolName)
                    .font(.system(size: 24, weight: .medium))
                    .foregroundStyle(.white.opacity(0.9))
            }
            .frame(width: 60, height: 60)
        }
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
