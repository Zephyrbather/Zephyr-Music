import AppKit
import SwiftUI

private struct DefaultMenuCleanupCommands: Commands {
    var body: some Commands {
        CommandGroup(replacing: .undoRedo) { }
        CommandGroup(replacing: .pasteboard) { }
        CommandGroup(replacing: .textEditing) { }
        CommandGroup(replacing: .textFormatting) { }
        CommandGroup(replacing: .toolbar) { }
        CommandGroup(replacing: .sidebar) { }
        CommandGroup(replacing: .appVisibility) { }
        CommandGroup(replacing: .windowSize) { }
        CommandGroup(replacing: .windowArrangement) { }
    }
}

@main
struct MusicPlayerApp: App {
    @StateObject private var viewModel = PlayerViewModel()
    @State private var desktopLyricsController: DesktopLyricsWindowController?
    @State private var playbackShortcutMonitor: PlaybackShortcutMonitor?
    @StateObject private var appMenuLocalizer = AppMenuLocalizer()

    private var language: PlayerViewModel.AppLanguage {
        viewModel.appLanguage
    }

    var body: some Scene {
        WindowGroup("Zephyr Player") {
            ContentView(viewModel: viewModel)
                .onAppear {
                    if desktopLyricsController == nil {
                        let controller = DesktopLyricsWindowController(viewModel: viewModel)
                        controller.setVisible(viewModel.isDesktopLyricsVisible)
                        desktopLyricsController = controller
                    }
                    if playbackShortcutMonitor == nil {
                        let monitor = PlaybackShortcutMonitor(viewModel: viewModel)
                        monitor.start()
                        playbackShortcutMonitor = monitor
                    }
                    appMenuLocalizer.apply(language: viewModel.appLanguage)
                }
                .onChange(of: viewModel.isDesktopLyricsVisible) { isVisible in
                    desktopLyricsController?.setVisible(isVisible)
                }
                .onChange(of: viewModel.isDesktopLyricsSettingsPresented) { _ in
                    desktopLyricsController?.refreshLayout()
                }
                .onChange(of: viewModel.desktopLyricsOpacity) { _ in
                    desktopLyricsController?.applySettings()
                }
                .onChange(of: viewModel.isDesktopLyricsLocked) { _ in
                    desktopLyricsController?.applySettings()
                }
                .onChange(of: viewModel.desktopLyricsBackgroundStyle) { _ in
                    desktopLyricsController?.applySettings()
                }
                .onChange(of: viewModel.desktopLyricsFontSize) { _ in
                    desktopLyricsController?.refreshLayout()
                }
                .onChange(of: viewModel.desktopLyricsDisplayMode) { _ in
                    desktopLyricsController?.refreshLayout(reposition: viewModel.isDesktopLyricsVisible)
                }
                .onChange(of: viewModel.currentLyricIndex) { _ in
                    desktopLyricsController?.refreshLayout()
                }
                .onChange(of: viewModel.currentTrack?.id) { _ in
                    desktopLyricsController?.refreshLayout(reposition: viewModel.isDesktopLyricsVisible)
                }
                .onChange(of: viewModel.appLanguage) { _ in
                    appMenuLocalizer.apply(language: viewModel.appLanguage)
                    desktopLyricsController?.refreshLayout()
                }
        }
        .windowResizability(.contentMinSize)

        MenuBarExtra {
            VStack(alignment: .leading, spacing: 12) {
                HStack(spacing: 12) {
                    Group {
                        if let artwork = viewModel.currentArtwork {
                            Image(nsImage: artwork)
                                .resizable()
                                .scaledToFill()
                        } else {
                            RoundedRectangle(cornerRadius: 10, style: .continuous)
                                .fill(.quaternary)
                                .overlay {
                                    Image(systemName: "music.note")
                                        .foregroundStyle(.secondary)
                                }
                        }
                    }
                    .frame(width: 42, height: 42)
                    .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))

                    VStack(alignment: .leading, spacing: 4) {
                        Text(viewModel.currentTrack?.title ?? "Zephyr Player")
                            .lineLimit(1)
                        Text(viewModel.isPlaying ? language.pick("正在播放", "Playing") : language.pick("已暂停", "Paused"))
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }

                Divider()

                HStack(spacing: 10) {
                    Button {
                        viewModel.playPrevious()
                    } label: {
                        Image(systemName: "backward.fill")
                    }

                    Button {
                        viewModel.togglePlayback()
                    } label: {
                        Image(systemName: viewModel.isPlaying ? "pause.fill" : "play.fill")
                    }

                    Button {
                        viewModel.playNext()
                    } label: {
                        Image(systemName: "forward.fill")
                    }
                }
                .buttonStyle(.bordered)

                Divider()

                Button(language.pick("添加音频文件", "Add Audio Files")) {
                    viewModel.openFiles()
                }
                Button(language.pick("扫描音频文件夹", "Scan Audio Folder")) {
                    viewModel.openFolder()
                }
                Button(viewModel.playbackMode.title(in: language)) {
                    viewModel.cyclePlaybackMode()
                }
                Button(viewModel.isDesktopLyricsVisible ? language.pick("关闭桌面歌词", "Hide Desktop Lyrics") : language.pick("开启桌面歌词", "Show Desktop Lyrics")) {
                    viewModel.isDesktopLyricsVisible.toggle()
                }

                Button(language.pick("听歌历史", "Listening History")) {
                    viewModel.listeningHistoryPresentationRequest += 1
                }
            }
            .padding(12)
            .frame(width: 260)
        } label: {
            Label(
                viewModel.currentTrack?.title ?? "Zephyr Player",
                systemImage: viewModel.isPlaying ? "waveform" : "music.note"
            )
        }

        Settings {
            AppSettingsView(viewModel: viewModel)
                .navigationTitle(language.pick("设置", "Settings"))
        }

        .commands {
            DefaultMenuCleanupCommands()

            CommandGroup(after: .newItem) {
                Button(language.pick("添加音频文件", "Add Audio Files")) {
                    viewModel.openFiles()
                }
                .keyboardShortcut("o", modifiers: [.command])

                Button(language.pick("扫描音频文件夹", "Scan Audio Folder")) {
                    viewModel.openFolder()
                }
                .keyboardShortcut("o", modifiers: [.command, .shift])

                Button(language.pick("搜索歌单", "Search Playlist")) {
                    viewModel.playlistSearchFocusRequest += 1
                }
                .keyboardShortcut("f", modifiers: [.command])

                Button(language.pick("听歌历史", "Listening History")) {
                    viewModel.listeningHistoryPresentationRequest += 1
                }
                .keyboardShortcut("h", modifiers: [.command, .option])

                Button(viewModel.isDesktopLyricsVisible ? language.pick("关闭桌面歌词", "Hide Desktop Lyrics") : language.pick("开启桌面歌词", "Show Desktop Lyrics")) {
                    viewModel.isDesktopLyricsVisible.toggle()
                }
                .keyboardShortcut("l", modifiers: [.command, .option])
            }

            CommandMenu(language.pick("播放模式", "Playback")) {
                ForEach(PlayerViewModel.PlaybackMode.allCases) { mode in
                    Button {
                        viewModel.playbackMode = mode
                    } label: {
                        if viewModel.playbackMode == mode {
                            Label(mode.title(in: language), systemImage: "checkmark")
                        } else {
                            Label(mode.title(in: language), systemImage: mode.symbolName)
                        }
                    }
                }
            }

            CommandMenu(language.pick("界面", "Interface")) {
                ForEach(PlayerViewModel.InterfaceMode.allCases) { mode in
                    Button {
                        viewModel.interfaceMode = mode
                    } label: {
                        if viewModel.interfaceMode == mode {
                            Label(mode.title(in: language), systemImage: "checkmark")
                        } else {
                            Label(mode.title(in: language), systemImage: mode.symbolName)
                        }
                    }
                }
            }

            CommandMenu(language.pick("主题", "Theme")) {
                ForEach(PlayerViewModel.AppTheme.allCases) { theme in
                    Button {
                        if theme == .customImage {
                            viewModel.openCustomBackgroundImage()
                        } else {
                            viewModel.appTheme = theme
                        }
                    } label: {
                        if viewModel.appTheme == theme {
                            Label(theme.title(in: language), systemImage: "checkmark")
                        } else {
                            Text(theme.title(in: language))
                        }
                    }
                }

                if viewModel.customBackgroundImagePath != nil {
                    Divider()

                    Button(language.pick("更换自定义图片", "Replace Custom Image")) {
                        viewModel.openCustomBackgroundImage()
                    }

                    Button(language.pick("移除自定义图片", "Remove Custom Image")) {
                        viewModel.clearCustomBackgroundImage()
                    }
                }
            }

            CommandMenu(language.pick("歌单", "Playlist")) {
                ForEach(viewModel.playlists) { playlist in
                    Button {
                        viewModel.selectPlaylist(playlist.id)
                    } label: {
                        if viewModel.selectedPlaylistID == playlist.id {
                            Label(viewModel.displayName(for: playlist), systemImage: "checkmark")
                        } else {
                            Text(viewModel.displayName(for: playlist))
                        }
                    }
                }

                Button(language.pick("新建歌单", "New Playlist")) {
                    viewModel.createPlaylist()
                }
            }

            CommandMenu(language.pick("均衡器", "Equalizer")) {
                Button(viewModel.isEqualizerEnabled ? language.pick("关闭均衡器", "Disable Equalizer") : language.pick("启用均衡器", "Enable Equalizer")) {
                    viewModel.isEqualizerEnabled.toggle()
                }

                Divider()

                ForEach(PlayerViewModel.EqualizerPreset.allCases) { preset in
                    Button {
                        viewModel.applyEqualizerPreset(preset)
                    } label: {
                        if viewModel.selectedUserEqualizerPresetID == nil && viewModel.selectedEqualizerPreset == preset {
                            Label(preset.title(in: language), systemImage: "checkmark")
                        } else {
                            Text(preset.title(in: language))
                        }
                    }
                }

                if !viewModel.userEqualizerPresets.isEmpty {
                    Divider()

                    ForEach(viewModel.userEqualizerPresets) { preset in
                        Button {
                            viewModel.applySavedEqualizerPreset(preset.id)
                        } label: {
                            if viewModel.selectedUserEqualizerPresetID == preset.id {
                                Label(preset.name, systemImage: "checkmark")
                            } else {
                                Text(preset.name)
                            }
                        }
                    }

                    Divider()

                    Menu(language.pick("删除自定义预设", "Delete Saved Preset")) {
                        ForEach(viewModel.userEqualizerPresets) { preset in
                            Button(role: .destructive) {
                                viewModel.removeSavedEqualizerPreset(preset.id)
                            } label: {
                                Text(preset.name)
                            }
                        }
                    }
                }

                Button(viewModel.isEqualizerExpanded ? language.pick("收起均衡器面板", "Collapse Equalizer Panel") : language.pick("展开均衡器面板", "Expand Equalizer Panel")) {
                    viewModel.isEqualizerExpanded.toggle()
                }

                Button(language.pick("重置均衡器", "Reset Equalizer")) {
                    viewModel.resetEqualizer()
                }

                Button(language.pick("保存当前风格", "Save Current Style")) {
                    viewModel.promptToSaveCurrentEqualizerPreset()
                }

                if let selectedSavedPreset = viewModel.selectedSavedEqualizerPreset {
                    Button(language.pick("删除当前风格", "Delete Current Style"), role: .destructive) {
                        viewModel.removeSavedEqualizerPreset(selectedSavedPreset.id)
                    }
                }
            }

            CommandMenu(language.pick("数据", "Data")) {
                Button(language.pick("导出个人数据", "Export Personal Data")) {
                    viewModel.exportPersonalData()
                }

                Button(language.pick("导入个人数据", "Import Personal Data")) {
                    viewModel.importPersonalData()
                }
            }

            CommandMenu(language.pick("桌面歌词", "Desktop Lyrics")) {
                Button(viewModel.isDesktopLyricsVisible ? language.pick("关闭桌面歌词", "Hide Desktop Lyrics") : language.pick("开启桌面歌词", "Show Desktop Lyrics")) {
                    viewModel.isDesktopLyricsVisible.toggle()
                }

                Divider()

                ForEach(PlayerViewModel.DesktopLyricsDisplayMode.allCases) { mode in
                    Button {
                        viewModel.desktopLyricsDisplayMode = mode
                    } label: {
                        if viewModel.desktopLyricsDisplayMode == mode {
                            Label(mode.title(in: language), systemImage: "checkmark")
                        } else {
                            Text(mode.title(in: language))
                        }
                    }
                }

                Divider()

                ForEach(PlayerViewModel.DesktopLyricsBackgroundStyle.allCases) { style in
                    Button {
                        viewModel.desktopLyricsBackgroundStyle = style
                    } label: {
                        if viewModel.desktopLyricsBackgroundStyle == style {
                            Label(style.title(in: language), systemImage: "checkmark")
                        } else {
                            Text(style.title(in: language))
                        }
                    }
                }

                Button(viewModel.isDesktopLyricsLocked ? language.pick("解除锁定位置", "Unlock Position") : language.pick("锁定位置", "Lock Position")) {
                    viewModel.isDesktopLyricsLocked.toggle()
                }

                Divider()

                Button(language.pick("字号减小", "Decrease Font Size") + " (\(Int(viewModel.desktopLyricsFontSize)))") {
                    viewModel.desktopLyricsFontSize = max(20, viewModel.desktopLyricsFontSize - 1)
                }

                Button(language.pick("字号增大", "Increase Font Size") + " (\(Int(viewModel.desktopLyricsFontSize)))") {
                    viewModel.desktopLyricsFontSize = min(44, viewModel.desktopLyricsFontSize + 1)
                }

                Button(language.pick("透明度降低", "Decrease Opacity") + " (\(Int(viewModel.desktopLyricsOpacity * 100))%)") {
                    viewModel.desktopLyricsOpacity = max(0.35, viewModel.desktopLyricsOpacity - 0.05)
                }

                Button(language.pick("透明度提高", "Increase Opacity") + " (\(Int(viewModel.desktopLyricsOpacity * 100))%)") {
                    viewModel.desktopLyricsOpacity = min(1, viewModel.desktopLyricsOpacity + 0.05)
                }
            }
        }
    }
}

private struct AppSettingsView: View {
    @ObservedObject var viewModel: PlayerViewModel

    private var language: PlayerViewModel.AppLanguage {
        viewModel.appLanguage
    }

    var body: some View {
        Form {
            Section {
                Picker(language.pick("界面语言", "Interface Language"), selection: $viewModel.appLanguage) {
                    ForEach(PlayerViewModel.AppLanguage.allCases) { option in
                        Text(language.title(for: option)).tag(option)
                    }
                }
                .pickerStyle(.menu)

                Text(language.pick("切换后界面文案会立即更新。", "Interface text updates immediately after switching."))
                    .font(.caption)
                    .foregroundStyle(.secondary)
            } header: {
                Text(language.pick("语言", "Language"))
            }

            Section {
                ForEach(PlaybackShortcutAction.allCases) { action in
                    PlaybackShortcutRecorderRow(viewModel: viewModel, action: action)
                }

                HStack {
                    Spacer()

                    Button(language.pick("恢复默认快捷键", "Restore Default Shortcuts")) {
                        viewModel.resetAllPlaybackShortcuts()
                    }
                }

                Text(language.pick(
                    "默认使用 Mac 键盘媒体键 F7 / F8 / F9。录制普通键盘快捷键时，至少包含一个修饰键；F1-F20 可单独录制。",
                    "Defaults use the Mac media keys F7 / F8 / F9. Custom keyboard shortcuts must include at least one modifier key, unless you record F1-F20 by themselves."
                ))
                .font(.caption)
                .foregroundStyle(.secondary)

                if let status = viewModel.playbackShortcutRecorderStatusText {
                    Text(status)
                        .font(.caption)
                        .foregroundStyle(.orange)
                }
            } header: {
                Text(language.pick("播放快捷键", "Playback Shortcuts"))
            }
        }
        .padding(20)
        .frame(width: 560)
        .onDisappear {
            viewModel.cancelRecordingPlaybackShortcut()
        }
    }
}

private struct PlaybackShortcutRecorderRow: View {
    @ObservedObject var viewModel: PlayerViewModel
    let action: PlaybackShortcutAction

    private var language: PlayerViewModel.AppLanguage {
        viewModel.appLanguage
    }

    private var isRecording: Bool {
        viewModel.recordingPlaybackShortcutAction == action
    }

    private var shortcutText: String {
        if isRecording {
            return language.pick("按下快捷键…", "Press shortcut...")
        }
        return viewModel.playbackShortcutDisplayText(for: action)
    }

    var body: some View {
        HStack(alignment: .center, spacing: 12) {
            Text(action.title(in: language))

            Spacer()

            Group {
                if isRecording {
                    Button(shortcutText) {
                        viewModel.cancelRecordingPlaybackShortcut()
                    }
                    .buttonStyle(.borderedProminent)
                } else {
                    Button(shortcutText) {
                        viewModel.beginRecordingPlaybackShortcut(for: action)
                    }
                    .buttonStyle(.bordered)
                }
            }
            .font(.system(.body, design: .monospaced))
            .frame(minWidth: 170)

            Button(language.pick("恢复默认", "Reset")) {
                viewModel.resetPlaybackShortcut(action)
            }
            .buttonStyle(.bordered)
        }
    }
}

@MainActor
private final class AppMenuLocalizer: NSObject, ObservableObject {
    private var language: PlayerViewModel.AppLanguage = .chinese

    override init() {
        super.init()
        let center = NotificationCenter.default
        center.addObserver(
            self,
            selector: #selector(handleMenuContextChange(_:)),
            name: NSApplication.didBecomeActiveNotification,
            object: nil
        )
        center.addObserver(
            self,
            selector: #selector(handleMenuContextChange(_:)),
            name: NSWindow.didBecomeKeyNotification,
            object: nil
        )
    }

    deinit {
        NotificationCenter.default.removeObserver(self)
    }

    func apply(language: PlayerViewModel.AppLanguage) {
        self.language = language
        applyCurrentLanguage()
    }

    @objc private func handleMenuContextChange(_ notification: Notification) {
        applyCurrentLanguage()
    }

    private func applyCurrentLanguage() {
        guard let mainMenu = NSApp.mainMenu else { return }
        let appName = applicationName

        if let appMenu = mainMenu.items.first?.submenu {
            localize(menu: appMenu, appName: appName)
        }

        for item in mainMenu.items.dropFirst() {
            guard let standardMenu = StandardMenu(title: item.title) else { continue }
            item.title = standardMenu.title(in: language)

            if let submenu = item.submenu {
                localize(menu: submenu, appName: appName)
            }
        }
    }

    private func localize(menu: NSMenu, appName: String) {
        for item in menu.items {
            if let translatedTitle = translatedTitle(for: item.title, appName: appName) {
                item.title = translatedTitle
            }

            if let submenu = item.submenu {
                localize(menu: submenu, appName: appName)
            }
        }
    }

    private func translatedTitle(for title: String, appName: String) -> String? {
        let normalizedTitle = normalized(title)

        switch normalizedTitle {
        case "File", "文件":
            return language.pick("文件", "File")
        case "Edit", "编辑":
            return language.pick("编辑", "Edit")
        case "View", "视图":
            return language.pick("视图", "View")
        case "Format", "格式":
            return language.pick("格式", "Format")
        case "Window", "窗口":
            return language.pick("窗口", "Window")
        case "Help", "帮助":
            return language.pick("帮助", "Help")
        case "Services", "服务":
            return language.pick("服务", "Services")
        case "Settings…", "Setting", "Settings", "Preferences…", "Preferences...", "设置…", "设置":
            return language.pick("设置…", "Settings…")
        case "Hide Others", "隐藏其他":
            return language.pick("隐藏其他", "Hide Others")
        case "Show All", "全部显示":
            return language.pick("全部显示", "Show All")
        case "Close", "关闭":
            return language.pick("关闭", "Close")
        case "Close Window", "关闭窗口":
            return language.pick("关闭窗口", "Close Window")
        case "Minimize", "最小化":
            return language.pick("最小化", "Minimize")
        case "Zoom", "缩放":
            return language.pick("缩放", "Zoom")
        case "Bring All to Front", "前置全部窗口":
            return language.pick("前置全部窗口", "Bring All to Front")
        case "Enter Full Screen", "进入全屏":
            return language.pick("进入全屏", "Enter Full Screen")
        case "Exit Full Screen", "退出全屏":
            return language.pick("退出全屏", "Exit Full Screen")
        case "Show Toolbar", "显示工具栏":
            return language.pick("显示工具栏", "Show Toolbar")
        case "Hide Toolbar", "隐藏工具栏":
            return language.pick("隐藏工具栏", "Hide Toolbar")
        case "Customize Toolbar…", "Customize Toolbar...", "自定工具栏…", "自定义工具栏…":
            return language.pick("自定义工具栏…", "Customize Toolbar…")
        case "Show Sidebar", "显示边栏":
            return language.pick("显示边栏", "Show Sidebar")
        case "Hide Sidebar", "隐藏边栏":
            return language.pick("隐藏边栏", "Hide Sidebar")
        case "Show Tab Bar", "显示标签栏":
            return language.pick("显示标签栏", "Show Tab Bar")
        case "Hide Tab Bar", "隐藏标签栏":
            return language.pick("隐藏标签栏", "Hide Tab Bar")
        case "Show Colors", "显示颜色":
            return language.pick("显示颜色", "Show Colors")
        case "Show Fonts", "显示字体":
            return language.pick("显示字体", "Show Fonts")
        case "Font", "字体":
            return language.pick("字体", "Font")
        case "Bold", "粗体":
            return language.pick("粗体", "Bold")
        case "Italic", "斜体":
            return language.pick("斜体", "Italic")
        case "Underline", "下划线":
            return language.pick("下划线", "Underline")
        case "Bigger", "放大":
            return language.pick("放大", "Bigger")
        case "Smaller", "缩小":
            return language.pick("缩小", "Smaller")
        case "Copy Style", "拷贝样式":
            return language.pick("拷贝样式", "Copy Style")
        case "Paste Style", "粘贴样式":
            return language.pick("粘贴样式", "Paste Style")
        case "Align", "对齐":
            return language.pick("对齐", "Align")
        case "Left", "左对齐":
            return language.pick("左对齐", "Left")
        case "Center", "居中":
            return language.pick("居中", "Center")
        case "Right", "右对齐":
            return language.pick("右对齐", "Right")
        case "Justify", "两端对齐":
            return language.pick("两端对齐", "Justify")
        default:
            if normalizedTitle == "About \(appName)" || normalizedTitle == "关于 \(appName)" || normalizedTitle == "关于\(appName)" {
                return language.pick("关于 \(appName)", "About \(appName)")
            }

            if normalizedTitle == "Hide \(appName)" || normalizedTitle == "隐藏 \(appName)" || normalizedTitle == "隐藏\(appName)" {
                return language.pick("隐藏 \(appName)", "Hide \(appName)")
            }

            if normalizedTitle == "Quit \(appName)" || normalizedTitle == "退出 \(appName)" || normalizedTitle == "退出\(appName)" {
                return language.pick("退出 \(appName)", "Quit \(appName)")
            }

            if normalizedTitle == "\(appName) Help" || normalizedTitle == "\(appName) 帮助" {
                return language.pick("\(appName) 帮助", "\(appName) Help")
            }

            return nil
        }
    }

    private func normalized(_ title: String) -> String {
        title
            .replacingOccurrences(of: "...", with: "…")
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private var applicationName: String {
        let bundle = Bundle.main
        return (bundle.object(forInfoDictionaryKey: "CFBundleDisplayName") as? String)
            ?? (bundle.object(forInfoDictionaryKey: kCFBundleNameKey as String) as? String)
            ?? "Zephyr Player"
    }
}

private enum StandardMenu {
    case file
    case edit
    case view
    case format
    case window
    case help

    init?(title: String) {
        switch title {
        case "File", "文件":
            self = .file
        case "Edit", "编辑":
            self = .edit
        case "View", "视图":
            self = .view
        case "Format", "格式":
            self = .format
        case "Window", "窗口":
            self = .window
        case "Help", "帮助":
            self = .help
        default:
            return nil
        }
    }

    func title(in language: PlayerViewModel.AppLanguage) -> String {
        switch self {
        case .file:
            return language.pick("文件", "File")
        case .edit:
            return language.pick("编辑", "Edit")
        case .view:
            return language.pick("视图", "View")
        case .format:
            return language.pick("格式", "Format")
        case .window:
            return language.pick("窗口", "Window")
        case .help:
            return language.pick("帮助", "Help")
        }
    }
}
