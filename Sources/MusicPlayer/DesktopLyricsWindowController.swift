import AppKit
import SwiftUI

@MainActor
final class DesktopLyricsWindowController: NSObject, NSWindowDelegate {
    private weak var viewModel: PlayerViewModel?
    private var panel: NSPanel?
    private let windowPadding: CGFloat = 20
    private let dockSpacing: CGFloat = 18

    init(viewModel: PlayerViewModel) {
        self.viewModel = viewModel
    }

    func setVisible(_ isVisible: Bool) {
        if isVisible {
            showWindow()
        } else {
            viewModel?.isDesktopLyricsSettingsPresented = false
            hideWindow()
        }
    }

    func applySettings() {
        guard let panel, let viewModel else { return }
        panel.alphaValue = viewModel.desktopLyricsOpacity
        panel.isMovableByWindowBackground = !viewModel.isDesktopLyricsLocked
        panel.ignoresMouseEvents = false
        panel.hasShadow = !viewModel.desktopLyricsBackgroundStyle.isTransparent
        refreshLayout()
    }

    func refreshLayout(reposition: Bool = false) {
        guard let panel else { return }
        updatePanelFrame(panel, reposition: reposition)
    }

    private func showWindow() {
        if panel == nil {
            createWindow()
        }

        applySettings()
        refreshLayout(reposition: true)
        panel?.orderFrontRegardless()
    }

    private func hideWindow() {
        panel?.orderOut(nil)
    }

    private func createWindow() {
        guard let viewModel else { return }

        let panel = NSPanel(
            contentRect: initialFrame(),
            styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered,
            defer: false
        )
        panel.isFloatingPanel = true
        panel.level = .statusBar
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .stationary]
        panel.backgroundColor = .clear
        panel.isOpaque = false
        panel.hasShadow = !viewModel.desktopLyricsBackgroundStyle.isTransparent
        panel.hidesOnDeactivate = false
        panel.isMovableByWindowBackground = true
        panel.delegate = self

        let rootView = DesktopLyricsView(viewModel: viewModel)

        panel.contentViewController = NSHostingController(rootView: rootView)
        self.panel = panel
        applySettings()
    }

    private func initialFrame() -> NSRect {
        let screen = NSScreen.main ?? NSScreen.screens.first
        let visibleFrame = screen?.visibleFrame ?? NSRect(x: 180, y: 180, width: 1280, height: 720)
        let size = preferredPanelSize(in: visibleFrame)
        return alignedFrame(for: size, in: visibleFrame)
    }

    private func updatePanelFrame(_ panel: NSPanel, reposition: Bool) {
        guard let screen = panel.screen ?? NSScreen.main ?? NSScreen.screens.first else { return }
        let visibleFrame = screen.visibleFrame
        let size = preferredPanelSize(in: visibleFrame)

        let frame: NSRect
        if reposition {
            frame = alignedFrame(for: size, in: visibleFrame)
        } else {
            let midX = panel.frame.midX
            let maxX = max(visibleFrame.minX + windowPadding, visibleFrame.maxX - size.width - windowPadding)
            let maxY = max(visibleFrame.minY + dockSpacing, visibleFrame.maxY - size.height - windowPadding)
            let x = clamp(midX - (size.width / 2), min: visibleFrame.minX + windowPadding, max: maxX)
            let y = clamp(panel.frame.origin.y, min: visibleFrame.minY + dockSpacing, max: maxY)
            frame = NSRect(origin: NSPoint(x: x, y: y), size: size)
        }

        guard frame.integral != panel.frame.integral else { return }
        panel.setFrame(frame.integral, display: true, animate: panel.isVisible && reposition)
    }

    private func alignedFrame(for size: NSSize, in visibleFrame: NSRect) -> NSRect {
        let x = visibleFrame.midX - (size.width / 2)
        let y = visibleFrame.minY + dockSpacing
        let maxX = max(visibleFrame.minX + windowPadding, visibleFrame.maxX - size.width - windowPadding)
        let clampedX = clamp(x, min: visibleFrame.minX + windowPadding, max: maxX)
        return NSRect(origin: NSPoint(x: clampedX, y: y), size: size)
    }

    private func preferredPanelSize(in visibleFrame: NSRect) -> NSSize {
        guard let viewModel else {
            return NSSize(width: 680, height: 104)
        }

        let maxWidth = max(visibleFrame.width - (windowPadding * 2), 1)
        let minWidth = min(520.0, maxWidth)
        let width: CGFloat
        let height: CGFloat

        switch viewModel.desktopLyricsDisplayMode {
        case .currentOnly:
            let current = viewModel.currentLyricLine ?? viewModel.lyrics.plainText ?? ""
            width = clamp(textWidth(current, size: viewModel.desktopLyricsFontSize, weight: .bold) + 96, min: minWidth, max: maxWidth)
            height = 108

        case .dualLine:
            let current = viewModel.currentLyricLine ?? ""
            let next = viewModel.nextLyricLine ?? ""
            let combinedWidth = textWidth(current, size: viewModel.desktopLyricsFontSize, weight: .bold)
                + textWidth(next, size: max(viewModel.desktopLyricsFontSize - 6, 16), weight: .medium)
                + 124
            width = clamp(combinedWidth, min: minWidth, max: maxWidth)
            height = 94

        case .threeLines:
            let lineWidths = [
                textWidth(viewModel.currentLyricLine ?? "", size: viewModel.desktopLyricsFontSize, weight: .bold),
                textWidth(viewModel.previousLyricLine ?? "", size: max(viewModel.desktopLyricsFontSize - 10, 14), weight: .medium),
                textWidth(viewModel.nextLyricLine ?? "", size: max(viewModel.desktopLyricsFontSize - 10, 14), weight: .medium)
            ]
            width = clamp((lineWidths.max() ?? minWidth) + 96, min: minWidth, max: maxWidth)
            height = 124
        }

        if viewModel.isDesktopLyricsSettingsPresented {
            let maxHeight = max(visibleFrame.height - dockSpacing - windowPadding, height)
            let expandedWidth = clamp(620, min: minWidth, max: maxWidth)
            let expandedHeight = min(height + 156, maxHeight)
            return NSSize(width: max(width, expandedWidth), height: expandedHeight)
        }

        return NSSize(width: width, height: height)
    }

    private func textWidth(_ text: String, size: Double, weight: NSFont.Weight) -> CGFloat {
        guard !text.isEmpty else { return 0 }
        let font = NSFont.systemFont(ofSize: size, weight: weight)
        return (text as NSString).size(withAttributes: [.font: font]).width
    }

    private func clamp(_ value: CGFloat, min lowerBound: CGFloat, max upperBound: CGFloat) -> CGFloat {
        Swift.min(Swift.max(value, lowerBound), upperBound)
    }
}

private struct DesktopLyricsView: View {
    @ObservedObject var viewModel: PlayerViewModel

    var body: some View {
        ZStack {
            RoundedRectangle(cornerRadius: 22, style: .continuous)
                .fill(backgroundFill)
                .overlay(borderOverlay)

            VStack(alignment: .leading, spacing: 12) {
                if !viewModel.lyrics.timedLines.isEmpty {
                    lyricsContent
                } else if let plainText = viewModel.lyrics.plainText, !plainText.isEmpty {
                    settingsRevealButton {
                        Text(plainText)
                            .font(.system(size: max(viewModel.desktopLyricsFontSize - 8, 16), weight: .medium))
                            .foregroundStyle(currentLyricColor)
                            .lineLimit(4)
                            .multilineTextAlignment(.leading)
                    }
                } else {
                    settingsRevealButton {
                        Text(viewModel.appLanguage.pick("暂无歌词，点击打开桌面歌词设置", "No lyrics. Click to open desktop lyrics settings"))
                            .font(.system(size: max(viewModel.desktopLyricsFontSize - 10, 14), weight: .medium))
                            .foregroundStyle(secondaryLyricColor)
                            .lineLimit(2)
                    }
                }

                if viewModel.isDesktopLyricsSettingsPresented {
                    settingsPanel
                }
            }
            .padding(18)
        }
        .frame(minWidth: 440, minHeight: 68)
        .padding(6)
        .animation(.easeInOut(duration: 0.18), value: viewModel.isDesktopLyricsSettingsPresented)
    }

    @ViewBuilder
    private var lyricsContent: some View {
        switch viewModel.desktopLyricsDisplayMode {
        case .currentOnly:
            if let current = viewModel.currentLyricLine {
                settingsRevealButton {
                    currentLyricBlock(current)
                }
            } else {
                settingsRevealButton {
                    Text(viewModel.appLanguage.pick("点击打开桌面歌词设置", "Click to open desktop lyrics settings"))
                        .font(.system(size: max(viewModel.desktopLyricsFontSize - 8, 16), weight: .medium))
                        .foregroundStyle(secondaryLyricColor)
                }
            }

        case .dualLine:
            if let current = viewModel.currentLyricLine {
                settingsRevealButton {
                    HStack(spacing: 22) {
                        Text(current)
                            .font(.system(size: viewModel.desktopLyricsFontSize, weight: .bold))
                            .foregroundStyle(currentLyricColor)
                            .lineLimit(1)
                            .minimumScaleFactor(0.72)
                            .allowsTightening(true)
                            .frame(maxWidth: .infinity, alignment: .leading)

                        if let next = viewModel.nextLyricLine {
                            Text(next)
                                .font(.system(size: max(viewModel.desktopLyricsFontSize - 6, 16), weight: .medium))
                                .foregroundStyle(secondaryLyricColor)
                                .lineLimit(1)
                                .minimumScaleFactor(0.72)
                                .allowsTightening(true)
                            .frame(maxWidth: .infinity, alignment: .leading)
                        }
                    }
                }
            } else {
                settingsRevealButton {
                    Text(viewModel.appLanguage.pick("点击打开桌面歌词设置", "Click to open desktop lyrics settings"))
                        .font(.system(size: max(viewModel.desktopLyricsFontSize - 8, 16), weight: .medium))
                        .foregroundStyle(secondaryLyricColor)
                }
            }

        case .threeLines:
            settingsRevealButton {
                VStack(alignment: .leading, spacing: 8) {
                    if let current = viewModel.currentLyricLine {
                        currentLyricBlock(current)
                    }

                    if let previous = viewModel.previousLyricLine {
                        secondaryLyricBlock(previous)
                    }

                    if let next = viewModel.nextLyricLine {
                        secondaryLyricBlock(next)
                    }
                }
            }
        }
    }

    @ViewBuilder
    private func settingsRevealButton<Content: View>(@ViewBuilder content: () -> Content) -> some View {
        Button {
            viewModel.isDesktopLyricsSettingsPresented = true
        } label: {
            content()
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }

    @ViewBuilder
    private func currentLyricBlock(_ text: String) -> some View {
        Text(text)
            .font(.system(size: viewModel.desktopLyricsFontSize, weight: .bold))
            .foregroundStyle(currentLyricColor)
            .lineLimit(viewModel.desktopLyricsDisplayMode == .currentOnly ? 3 : 2)
            .minimumScaleFactor(0.74)
            .allowsTightening(true)
    }

    @ViewBuilder
    private func secondaryLyricBlock(_ text: String) -> some View {
        Text(text)
            .font(.system(size: max(viewModel.desktopLyricsFontSize - 10, 14), weight: .medium))
            .foregroundStyle(secondaryLyricColor)
            .lineLimit(1)
            .minimumScaleFactor(0.74)
            .allowsTightening(true)
    }

    private var settingsPanel: some View {
        ScrollView(.vertical, showsIndicators: false) {
            VStack(alignment: .leading, spacing: 12) {
                HStack(alignment: .top, spacing: 10) {
                    Text(viewModel.appLanguage.pick("桌面歌词设置", "Desktop Lyrics Settings"))
                        .font(.system(size: 13, weight: .semibold))

                    Text(viewModel.appLanguage.pick("桌面点击仅打开设置", "Desktop click opens settings"))
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)

                    Spacer(minLength: 8)

                    Button {
                        viewModel.isDesktopLyricsSettingsPresented = false
                    } label: {
                        Image(systemName: "xmark.circle.fill")
                            .font(.system(size: 13, weight: .semibold))
                            .foregroundStyle(.secondary)
                    }
                    .buttonStyle(.plain)
                }

                settingsSection(title: viewModel.appLanguage.pick("显示模式", "Display Mode")) {
                    LazyVGrid(columns: [GridItem(.adaptive(minimum: 86), spacing: 6)], spacing: 6) {
                    ForEach(PlayerViewModel.DesktopLyricsDisplayMode.allCases) { mode in
                            settingsOptionButton(
                                title: mode.title(in: viewModel.appLanguage),
                                isSelected: viewModel.desktopLyricsDisplayMode == mode
                            ) {
                                viewModel.desktopLyricsDisplayMode = mode
                            }
                        }
                    }
                }

                settingsSection(title: viewModel.appLanguage.pick("背景色", "Background")) {
                    LazyVGrid(columns: [GridItem(.adaptive(minimum: 94), spacing: 6)], spacing: 6) {
                    ForEach(PlayerViewModel.DesktopLyricsBackgroundStyle.allCases) { style in
                            settingsColorButton(
                                title: style.title(in: viewModel.appLanguage),
                                style: style,
                                isSelected: viewModel.desktopLyricsBackgroundStyle == style
                            ) {
                                viewModel.desktopLyricsBackgroundStyle = style
                            }
                        }
                    }
                }

                HStack(spacing: 8) {
                    settingsMiniButton(systemName: "textformat.size.smaller") {
                        viewModel.desktopLyricsFontSize = max(20, viewModel.desktopLyricsFontSize - 1)
                    }

                    Text(viewModel.appLanguage.pick("字号 \(Int(viewModel.desktopLyricsFontSize))", "Font \(Int(viewModel.desktopLyricsFontSize))"))
                        .font(.caption2.weight(.medium))
                        .foregroundStyle(.secondary)

                    settingsMiniButton(systemName: "textformat.size.larger") {
                        viewModel.desktopLyricsFontSize = min(44, viewModel.desktopLyricsFontSize + 1)
                    }

                    Spacer(minLength: 0)

                    settingsOptionButton(
                        title: viewModel.isDesktopLyricsLocked
                            ? viewModel.appLanguage.pick("已锁定", "Locked")
                            : viewModel.appLanguage.pick("锁定", "Lock"),
                        isSelected: viewModel.isDesktopLyricsLocked
                    ) {
                        viewModel.isDesktopLyricsLocked.toggle()
                    }
                    .frame(maxWidth: 92)
                }

                HStack(spacing: 10) {
                    Text(viewModel.appLanguage.pick("透明度", "Opacity"))
                        .font(.caption2.weight(.medium))
                        .foregroundStyle(.secondary)

                    Slider(value: $viewModel.desktopLyricsOpacity, in: 0.35...1)

                    Text("\(Int(viewModel.desktopLyricsOpacity * 100))%")
                        .font(.caption2.monospacedDigit())
                        .foregroundStyle(.secondary)
                        .frame(width: 36, alignment: .trailing)
                }

                Button {
                    viewModel.isDesktopLyricsSettingsPresented = false
                    viewModel.isDesktopLyricsVisible = false
                } label: {
                    HStack(spacing: 6) {
                        Image(systemName: "eye.slash")
                            .font(.system(size: 11, weight: .medium))

                        Text(viewModel.appLanguage.pick("关闭桌面歌词", "Hide Desktop Lyrics"))
                            .font(.caption2.weight(.medium))

                        Spacer(minLength: 0)
                    }
                    .foregroundStyle(Color.primary)
                    .padding(.horizontal, 10)
                    .padding(.vertical, 7)
                    .frame(maxWidth: .infinity)
                    .background(
                        RoundedRectangle(cornerRadius: 10, style: .continuous)
                            .fill(Color.white.opacity(0.07))
                    )
                    .overlay(
                        RoundedRectangle(cornerRadius: 10, style: .continuous)
                            .stroke(Color.white.opacity(0.08), lineWidth: 1)
                    )
                }
                .buttonStyle(.plain)
            }
        }
        .frame(maxHeight: 162)
        .padding(.trailing, 2)
        .padding(12)
        .background(
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .fill(.ultraThinMaterial)
                .overlay(
                    RoundedRectangle(cornerRadius: 16, style: .continuous)
                        .stroke(Color.white.opacity(0.12), lineWidth: 1)
                )
        )
    }

    private func settingsSection<Content: View>(
        title: String,
        @ViewBuilder content: () -> Content
    ) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(title)
                .font(.caption2.weight(.semibold))
                .foregroundStyle(.secondary)

            content()
        }
    }

    private func settingsOptionButton(
        title: String,
        isSelected: Bool,
        action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            Text(title)
                .font(.caption2.weight(.medium))
                .foregroundStyle(isSelected ? Color.white : Color.primary)
                .frame(maxWidth: .infinity)
                .lineLimit(1)
                .padding(.horizontal, 8)
                .padding(.vertical, 6)
                .background(
                    RoundedRectangle(cornerRadius: 10, style: .continuous)
                        .fill(isSelected ? Color.accentColor : Color.white.opacity(0.10))
                )
                .overlay(
                    RoundedRectangle(cornerRadius: 10, style: .continuous)
                        .stroke(isSelected ? Color.accentColor.opacity(0.28) : Color.white.opacity(0.08), lineWidth: 1)
                )
        }
        .buttonStyle(.plain)
    }

    private func settingsColorButton(
        title: String,
        style: PlayerViewModel.DesktopLyricsBackgroundStyle,
        isSelected: Bool,
        action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            HStack(spacing: 6) {
                Circle()
                    .fill(style.swatchFill)
                    .frame(width: 12, height: 12)
                    .overlay(
                        Circle()
                            .stroke(style.swatchBorderColor, style: StrokeStyle(lineWidth: 1, dash: style.isTransparent ? [3, 2] : []))
                    )

                Text(title)
                    .font(.caption2.weight(.medium))
                    .lineLimit(1)

                Spacer(minLength: 0)
            }
            .foregroundStyle(isSelected ? Color.white : Color.primary)
            .padding(.horizontal, 8)
            .padding(.vertical, 6)
            .frame(maxWidth: .infinity)
            .background(
                RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .fill(isSelected ? Color.accentColor : Color.white.opacity(0.10))
            )
            .overlay(
                RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .stroke(isSelected ? Color.accentColor.opacity(0.28) : Color.white.opacity(0.08), lineWidth: 1)
            )
        }
        .buttonStyle(.plain)
    }

    private func settingsMiniButton(systemName: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: systemName)
                .font(.system(size: 10, weight: .medium))
                .foregroundStyle(Color.primary)
                .frame(width: 22, height: 22)
                .background(
                    Circle()
                        .fill(Color.white.opacity(0.10))
                )
                .overlay(
                    Circle()
                        .stroke(Color.white.opacity(0.08), lineWidth: 1)
                )
        }
        .buttonStyle(.plain)
    }

    private var backgroundFill: some ShapeStyle {
        viewModel.desktopLyricsBackgroundStyle.panelFill
    }

    private var borderOverlay: some View {
        RoundedRectangle(cornerRadius: 22, style: .continuous)
            .stroke(viewModel.desktopLyricsBackgroundStyle.borderColor, lineWidth: viewModel.desktopLyricsBackgroundStyle.isTransparent ? 0 : 1)
    }

    private var currentLyricColor: Color {
        viewModel.desktopLyricsBackgroundStyle.primaryLyricColor
    }

    private var secondaryLyricColor: Color {
        viewModel.desktopLyricsBackgroundStyle.secondaryLyricColor
    }
}

private extension PlayerViewModel.DesktopLyricsBackgroundStyle {
    var isTransparent: Bool {
        self == .transparent
    }

    var panelFill: AnyShapeStyle {
        switch self {
        case .themed:
            return AnyShapeStyle(.ultraThinMaterial)
        case .graphite:
            return AnyShapeStyle(Color(red: 0.17, green: 0.18, blue: 0.21).opacity(0.86))
        case .ocean:
            return AnyShapeStyle(Color(red: 0.16, green: 0.31, blue: 0.54).opacity(0.82))
        case .rose:
            return AnyShapeStyle(Color(red: 0.54, green: 0.24, blue: 0.36).opacity(0.82))
        case .transparent:
            return AnyShapeStyle(Color.clear)
        }
    }

    var borderColor: Color {
        switch self {
        case .themed:
            return Color.white.opacity(0.18)
        case .graphite, .ocean, .rose:
            return Color.white.opacity(0.14)
        case .transparent:
            return .clear
        }
    }

    var primaryLyricColor: Color {
        switch self {
        case .themed:
            return .accentColor
        case .graphite, .ocean, .rose, .transparent:
            return .white
        }
    }

    var secondaryLyricColor: Color {
        switch self {
        case .themed:
            return .secondary
        case .graphite, .ocean, .rose, .transparent:
            return .white.opacity(0.72)
        }
    }

    var swatchFill: Color {
        switch self {
        case .themed:
            return .accentColor.opacity(0.85)
        case .graphite:
            return Color(red: 0.17, green: 0.18, blue: 0.21)
        case .ocean:
            return Color(red: 0.16, green: 0.31, blue: 0.54)
        case .rose:
            return Color(red: 0.54, green: 0.24, blue: 0.36)
        case .transparent:
            return .clear
        }
    }

    var swatchBorderColor: Color {
        switch self {
        case .transparent:
            return .white.opacity(0.55)
        default:
            return Color.white.opacity(0.24)
        }
    }
}
