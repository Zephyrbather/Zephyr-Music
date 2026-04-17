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
                }
                .onChange(of: viewModel.isDesktopLyricsVisible) { isVisible in
                    desktopLyricsController?.setVisible(isVisible)
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
        }
        .padding(20)
        .frame(width: 420)
    }
}
