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
            hideWindow()
        }
    }

    func applySettings() {
        guard let panel, let viewModel else { return }
        panel.alphaValue = viewModel.desktopLyricsOpacity
        panel.isMovableByWindowBackground = !viewModel.isDesktopLyricsLocked
        panel.ignoresMouseEvents = false
        panel.hasShadow = viewModel.desktopLyricsBackgroundStyle == .themed
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
        panel.hasShadow = viewModel.desktopLyricsBackgroundStyle == .themed
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
            let x = clamp(midX - (size.width / 2), min: visibleFrame.minX + windowPadding, max: visibleFrame.maxX - size.width - windowPadding)
            let y = clamp(panel.frame.origin.y, min: visibleFrame.minY + dockSpacing, max: visibleFrame.maxY - size.height - windowPadding)
            frame = NSRect(origin: NSPoint(x: x, y: y), size: size)
        }

        guard frame.integral != panel.frame.integral else { return }
        panel.setFrame(frame.integral, display: true, animate: panel.isVisible && reposition)
    }

    private func alignedFrame(for size: NSSize, in visibleFrame: NSRect) -> NSRect {
        let x = visibleFrame.midX - (size.width / 2)
        let y = visibleFrame.minY + dockSpacing
        let clampedX = clamp(x, min: visibleFrame.minX + windowPadding, max: visibleFrame.maxX - size.width - windowPadding)
        return NSRect(origin: NSPoint(x: clampedX, y: y), size: size)
    }

    private func preferredPanelSize(in visibleFrame: NSRect) -> NSSize {
        guard let viewModel else {
            return NSSize(width: 760, height: 110)
        }

        let maxWidth = max(visibleFrame.width - (windowPadding * 2), 620)
        let minWidth: CGFloat = 620
        let width: CGFloat
        let height: CGFloat

        switch viewModel.desktopLyricsDisplayMode {
        case .currentOnly:
            let current = viewModel.currentLyricLine ?? viewModel.lyrics.plainText ?? ""
            width = clamp(textWidth(current, size: viewModel.desktopLyricsFontSize, weight: .bold) + 110, min: minWidth, max: maxWidth)
            height = 118

        case .dualLine:
            let current = viewModel.currentLyricLine ?? ""
            let next = viewModel.nextLyricLine ?? ""
            let combinedWidth = textWidth(current, size: viewModel.desktopLyricsFontSize, weight: .bold)
                + textWidth(next, size: max(viewModel.desktopLyricsFontSize - 6, 16), weight: .medium)
                + 150
            width = clamp(combinedWidth, min: minWidth, max: maxWidth)
            height = 104

        case .threeLines:
            let lineWidths = [
                textWidth(viewModel.currentLyricLine ?? "", size: viewModel.desktopLyricsFontSize, weight: .bold),
                textWidth(viewModel.previousLyricLine ?? "", size: max(viewModel.desktopLyricsFontSize - 10, 14), weight: .medium),
                textWidth(viewModel.nextLyricLine ?? "", size: max(viewModel.desktopLyricsFontSize - 10, 14), weight: .medium)
            ]
            width = clamp((lineWidths.max() ?? minWidth) + 110, min: minWidth, max: maxWidth)
            height = 136
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
            RoundedRectangle(cornerRadius: 24, style: .continuous)
                .fill(backgroundFill)
                .overlay(borderOverlay)

            VStack(alignment: .leading, spacing: 14) {
                if !viewModel.lyrics.timedLines.isEmpty {
                    lyricsContent
                } else if let plainText = viewModel.lyrics.plainText, !plainText.isEmpty {
                    Text(plainText)
                        .font(.system(size: max(viewModel.desktopLyricsFontSize - 8, 16), weight: .medium))
                        .lineLimit(4)
                        .multilineTextAlignment(.leading)
                } else {
                    EmptyView()
                }
            }
            .padding(20)
        }
        .frame(minWidth: 520, minHeight: 72)
        .padding(8)
    }

    @ViewBuilder
    private var lyricsContent: some View {
        switch viewModel.desktopLyricsDisplayMode {
        case .currentOnly:
            if let current = viewModel.currentLyricLine {
                seekableCurrentLyric(text: current)
            } else {
                EmptyView()
            }

        case .dualLine:
            if let current = viewModel.currentLyricLine {
                Button {
                    seekToCurrentLine()
                } label: {
                    HStack(spacing: 22) {
                        Text(current)
                            .font(.system(size: viewModel.desktopLyricsFontSize, weight: .bold))
                            .foregroundStyle(Color.accentColor)
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
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
            } else {
                EmptyView()
            }

        case .threeLines:
            VStack(alignment: .leading, spacing: 8) {
                if let current = viewModel.currentLyricLine {
                    seekableCurrentLyric(text: current)
                } else {
                    EmptyView()
                }

                if let previous = viewModel.previousLyricLine {
                    Text(previous)
                        .font(.system(size: max(viewModel.desktopLyricsFontSize - 10, 14), weight: .medium))
                        .foregroundStyle(secondaryLyricColor)
                        .lineLimit(1)
                        .minimumScaleFactor(0.74)
                        .allowsTightening(true)
                }

                if let next = viewModel.nextLyricLine {
                    Text(next)
                        .font(.system(size: max(viewModel.desktopLyricsFontSize - 10, 14), weight: .medium))
                        .foregroundStyle(secondaryLyricColor)
                        .lineLimit(1)
                        .minimumScaleFactor(0.74)
                        .allowsTightening(true)
                }
            }
        }
    }

    @ViewBuilder
    private func seekableCurrentLyric(text: String) -> some View {
        Button {
            seekToCurrentLine()
        } label: {
            currentLyricBlock(text)
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

    private var backgroundFill: some ShapeStyle {
        switch viewModel.desktopLyricsBackgroundStyle {
        case .themed:
            return AnyShapeStyle(.ultraThinMaterial)
        case .transparent:
            return AnyShapeStyle(Color.clear)
        }
    }

    @ViewBuilder
    private var borderOverlay: some View {
        if viewModel.desktopLyricsBackgroundStyle == .themed {
            RoundedRectangle(cornerRadius: 24, style: .continuous)
                .stroke(Color.white.opacity(0.18), lineWidth: 1)
        } else {
            RoundedRectangle(cornerRadius: 24, style: .continuous)
                .stroke(Color.clear, lineWidth: 0)
        }
    }

    private var currentLyricColor: Color {
        switch viewModel.desktopLyricsBackgroundStyle {
        case .themed:
            return .accentColor
        case .transparent:
            return .white
        }
    }

    private var secondaryLyricColor: Color {
        switch viewModel.desktopLyricsBackgroundStyle {
        case .themed:
            return .secondary
        case .transparent:
            return .white.opacity(0.72)
        }
    }

    private func seekToCurrentLine() {
        if let currentIndex = viewModel.currentLyricIndex,
           viewModel.lyrics.timedLines.indices.contains(currentIndex) {
            viewModel.seekToTime(viewModel.lyrics.timedLines[currentIndex].time)
        }
    }
}
