import SwiftUI

@main
struct MusicPlayerApp: App {
    @StateObject private var viewModel = PlayerViewModel()
    @State private var desktopLyricsController: DesktopLyricsWindowController?

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
                        Text(viewModel.isPlaying ? "正在播放" : "已暂停")
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

                Button("添加音频文件") {
                    viewModel.openFiles()
                }
                Button("扫描音频文件夹") {
                    viewModel.openFolder()
                }
                Button(viewModel.playbackMode.rawValue) {
                    viewModel.cyclePlaybackMode()
                }
                Button(viewModel.isDesktopLyricsVisible ? "关闭桌面歌词" : "开启桌面歌词") {
                    viewModel.isDesktopLyricsVisible.toggle()
                }

                Button("听歌历史") {
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

        .commands {
            CommandGroup(after: .newItem) {
                Button("添加音频文件") {
                    viewModel.openFiles()
                }
                .keyboardShortcut("o", modifiers: [.command])

                Button("扫描音频文件夹") {
                    viewModel.openFolder()
                }
                .keyboardShortcut("o", modifiers: [.command, .shift])

                Button("搜索歌单") {
                    viewModel.playlistSearchFocusRequest += 1
                }
                .keyboardShortcut("f", modifiers: [.command])

                Button("听歌历史") {
                    viewModel.listeningHistoryPresentationRequest += 1
                }
                .keyboardShortcut("h", modifiers: [.command, .option])

                Button(viewModel.isDesktopLyricsVisible ? "关闭桌面歌词" : "开启桌面歌词") {
                    viewModel.isDesktopLyricsVisible.toggle()
                }
                .keyboardShortcut("l", modifiers: [.command, .option])
            }

            CommandMenu("播放模式") {
                ForEach(PlayerViewModel.PlaybackMode.allCases) { mode in
                    Button {
                        viewModel.playbackMode = mode
                    } label: {
                        if viewModel.playbackMode == mode {
                            Label(mode.rawValue, systemImage: "checkmark")
                        } else {
                            Label(mode.rawValue, systemImage: mode.symbolName)
                        }
                    }
                }
            }

            CommandMenu("界面") {
                ForEach(PlayerViewModel.InterfaceMode.allCases) { mode in
                    Button {
                        viewModel.interfaceMode = mode
                    } label: {
                        if viewModel.interfaceMode == mode {
                            Label(mode.rawValue, systemImage: "checkmark")
                        } else {
                            Label(mode.rawValue, systemImage: mode.symbolName)
                        }
                    }
                }
            }

            CommandMenu("主题") {
                ForEach(PlayerViewModel.AppTheme.allCases) { theme in
                    Button {
                        if theme == .customImage {
                            viewModel.openCustomBackgroundImage()
                        } else {
                            viewModel.appTheme = theme
                        }
                    } label: {
                        if viewModel.appTheme == theme {
                            Label(theme.rawValue, systemImage: "checkmark")
                        } else {
                            Text(theme.rawValue)
                        }
                    }
                }

                if viewModel.customBackgroundImagePath != nil {
                    Divider()

                    Button("更换自定义图片") {
                        viewModel.openCustomBackgroundImage()
                    }

                    Button("移除自定义图片") {
                        viewModel.clearCustomBackgroundImage()
                    }
                }
            }

            CommandMenu("歌单") {
                ForEach(viewModel.playlists) { playlist in
                    Button {
                        viewModel.selectPlaylist(playlist.id)
                    } label: {
                        if viewModel.selectedPlaylistID == playlist.id {
                            Label(playlist.name, systemImage: "checkmark")
                        } else {
                            Text(playlist.name)
                        }
                    }
                }

                Button("新建歌单") {
                    viewModel.createPlaylist()
                }
            }

            CommandMenu("均衡器") {
                Button(viewModel.isEqualizerEnabled ? "关闭均衡器" : "启用均衡器") {
                    viewModel.isEqualizerEnabled.toggle()
                }

                Divider()

                ForEach(PlayerViewModel.EqualizerPreset.allCases) { preset in
                    Button {
                        viewModel.applyEqualizerPreset(preset)
                    } label: {
                        if viewModel.selectedEqualizerPreset == preset {
                            Label(preset.rawValue, systemImage: "checkmark")
                        } else {
                            Text(preset.rawValue)
                        }
                    }
                }

                Button(viewModel.isEqualizerExpanded ? "收起均衡器面板" : "展开均衡器面板") {
                    viewModel.isEqualizerExpanded.toggle()
                }

                Button("重置均衡器") {
                    viewModel.resetEqualizer()
                }
            }

            CommandMenu("桌面歌词") {
                Button(viewModel.isDesktopLyricsVisible ? "关闭桌面歌词" : "开启桌面歌词") {
                    viewModel.isDesktopLyricsVisible.toggle()
                }

                Divider()

                ForEach(PlayerViewModel.DesktopLyricsDisplayMode.allCases) { mode in
                    Button {
                        viewModel.desktopLyricsDisplayMode = mode
                    } label: {
                        if viewModel.desktopLyricsDisplayMode == mode {
                            Label(mode.rawValue, systemImage: "checkmark")
                        } else {
                            Text(mode.rawValue)
                        }
                    }
                }

                Divider()

                ForEach(PlayerViewModel.DesktopLyricsBackgroundStyle.allCases) { style in
                    Button {
                        viewModel.desktopLyricsBackgroundStyle = style
                    } label: {
                        if viewModel.desktopLyricsBackgroundStyle == style {
                            Label(style.rawValue, systemImage: "checkmark")
                        } else {
                            Text(style.rawValue)
                        }
                    }
                }

                Button(viewModel.isDesktopLyricsLocked ? "解除锁定位置" : "锁定位置") {
                    viewModel.isDesktopLyricsLocked.toggle()
                }

                Divider()

                Button("字号减小 (\(Int(viewModel.desktopLyricsFontSize)))") {
                    viewModel.desktopLyricsFontSize = max(20, viewModel.desktopLyricsFontSize - 1)
                }

                Button("字号增大 (\(Int(viewModel.desktopLyricsFontSize)))") {
                    viewModel.desktopLyricsFontSize = min(44, viewModel.desktopLyricsFontSize + 1)
                }

                Button("透明度降低 (\(Int(viewModel.desktopLyricsOpacity * 100))%)") {
                    viewModel.desktopLyricsOpacity = max(0.35, viewModel.desktopLyricsOpacity - 0.05)
                }

                Button("透明度提高 (\(Int(viewModel.desktopLyricsOpacity * 100))%)") {
                    viewModel.desktopLyricsOpacity = min(1, viewModel.desktopLyricsOpacity + 0.05)
                }
            }
        }
    }
}
