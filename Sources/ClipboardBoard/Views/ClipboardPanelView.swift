import SwiftUI

struct ClipboardPanelView: View {
    @ObservedObject var store: ClipboardStore
    @ObservedObject var launchAtLoginManager: LaunchAtLoginManager
    @ObservedObject var autoPasteService: AutoPasteService
    let onSelect: (ClipboardItem) -> Void
    let onClose: () -> Void

    var body: some View {
        VStack(spacing: 0) {
            header
                .padding(.horizontal, 24)
                .padding(.top, 22)
                .padding(.bottom, 18)

            Divider()
                .overlay(.white.opacity(0.08))

            ScrollView(showsIndicators: false) {
                LazyVStack(spacing: 14) {
                    ForEach(store.items) { item in
                        ClipboardRowView(item: item) {
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
                .padding(24)
            }
            .background(Color.clear)
            .animation(.spring(response: 0.32, dampingFraction: 0.85), value: store.items)

            Divider()
                .overlay(.white.opacity(0.08))

            footer
                .padding(.horizontal, 24)
                .padding(.vertical, 16)
        }
        .frame(minWidth: 640, minHeight: 760)
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
    }

    private var header: some View {
        HStack(alignment: .top, spacing: 16) {
            VStack(alignment: .leading, spacing: 8) {
                Text("粘贴板")
                    .font(.system(size: 28, weight: .bold, design: .rounded))
                    .foregroundStyle(.white)

                Text("最多保留 50 条记录，新增内容会自动挤出最旧的一条。")
                    .font(.callout)
                    .foregroundStyle(.white.opacity(0.72))

                Text("点击任意条目会恢复内容，并自动粘贴到刚刚使用的应用。")
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
}

private struct ClipboardRowView: View {
    let item: ClipboardItem
    let action: () -> Void
    @State private var isHovering = false

    var body: some View {
        Button(action: action) {
            HStack(alignment: .top, spacing: 14) {
                preview

                VStack(alignment: .leading, spacing: 7) {
                    HStack(alignment: .firstTextBaseline) {
                        Text(item.title)
                            .font(.headline)
                            .foregroundStyle(.white)
                            .lineLimit(1)

                        Spacer(minLength: 12)

                        Text(item.timestamp, style: .time)
                            .font(.caption)
                            .foregroundStyle(.white.opacity(0.5))
                    }

                    Text(item.subtitle)
                        .font(.subheadline)
                        .foregroundStyle(.white.opacity(0.72))
                        .lineLimit(1)

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
        }
        .buttonStyle(.plain)
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
