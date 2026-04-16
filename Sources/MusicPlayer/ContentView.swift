import SwiftUI
import UniformTypeIdentifiers

struct ContentView: View {
    private enum PlaylistSortOption: String, CaseIterable, Identifiable {
        case addedOrder = "导入顺序"
        case title = "歌曲名"
        case artist = "艺术家"
        case album = "专辑"

        var id: String { rawValue }
    }

    @ObservedObject var viewModel: PlayerViewModel
    @Environment(\.colorScheme) private var colorScheme
    @FocusState private var isPlaylistSearchFocused: Bool
    @State private var sliderValue: Double = 0
    @State private var isDraggingSlider = false
    @State private var playlistSearchText = ""
    @State private var selectedArtistFilter = "全部艺术家"
    @State private var selectedAlbumFilter = "全部专辑"
    @State private var sortOption: PlaylistSortOption = .addedOrder
    @State private var lyricScrollAnchor = UnitPoint.center
    @State private var hostWindow: NSWindow?
    @State private var artistOptionsCache = ["全部艺术家"]
    @State private var albumOptionsCache = ["全部专辑"]
    @State private var filteredPlaylistCache: [(index: Int, track: AudioTrack)] = []
    @State private var isHistorySheetPresented = false
    @State private var isCreatePlaylistSheetPresented = false
    @State private var newPlaylistName = ""
    @State private var isDeletePlaylistAlertPresented = false

    private var theme: PlayerTheme {
        PlayerTheme.forSelection(viewModel.appTheme, colorScheme: colorScheme)
    }

    private var artistOptions: [String] { artistOptionsCache }

    private var albumOptions: [String] { albumOptionsCache }

    private var filteredPlaylist: [(index: Int, track: AudioTrack)] { filteredPlaylistCache }
    private var usesImageBackground: Bool { viewModel.appTheme == .customImage && viewModel.customBackgroundImage != nil }
    private var forcedColorScheme: ColorScheme? {
        switch viewModel.appTheme {
        case .system:
            return nil
        case .pureBlack, .customImage:
            return .dark
        case .pureWhite, .pastelBlue, .pastelPurple, .pastelGreen:
            return .light
        }
    }

    var body: some View {
        Group {
            if viewModel.interfaceMode == .compact {
                compactLayout
            } else {
                fullLayout
            }
        }
        .background(WindowAccessor(window: $hostWindow))
        .padding(viewModel.interfaceMode == .compact ? 14 : 20)
        .frame(
            minWidth: viewModel.interfaceMode == .compact ? 380 : 1320,
            minHeight: viewModel.interfaceMode == .compact ? 720 : 780
        )
        .background(backgroundView)
        .foregroundStyle(theme.primaryText)
        .tint(theme.accent)
        .preferredColorScheme(forcedColorScheme)
        .overlay(dropOverlay)
        .onReceive(viewModel.$currentTime) { _ in
            guard !isDraggingSlider else { return }
            sliderValue = viewModel.progress
        }
        .onReceive(viewModel.$playlistSearchFocusRequest) { _ in
            isPlaylistSearchFocused = true
        }
        .onChange(of: viewModel.listeningHistoryPresentationRequest) { _ in
            isHistorySheetPresented = true
        }
        .onDrop(
            of: [UTType.fileURL],
            isTargeted: $viewModel.isDropTargeted,
            perform: viewModel.importItemProviders
        )
        .onAppear {
            refreshPlaylistDerivedState()
            resizeWindowIfNeeded(for: viewModel.interfaceMode)
        }
        .onChange(of: viewModel.interfaceMode) { newValue in
            resizeWindowIfNeeded(for: newValue)
        }
        .onChange(of: hostWindow) { _ in
            resizeWindowIfNeeded(for: viewModel.interfaceMode)
        }
        .onChange(of: viewModel.playlists) { _ in
            refreshPlaylistDerivedState()
        }
        .onChange(of: viewModel.selectedPlaylistID) { _ in
            selectedArtistFilter = "全部艺术家"
            selectedAlbumFilter = "全部专辑"
            playlistSearchText = ""
            refreshPlaylistDerivedState()
        }
        .onChange(of: playlistSearchText) { _ in
            refreshPlaylistDerivedState()
        }
        .onChange(of: selectedArtistFilter) { _ in
            refreshPlaylistDerivedState()
        }
        .onChange(of: selectedAlbumFilter) { _ in
            refreshPlaylistDerivedState()
        }
        .onChange(of: sortOption) { _ in
            refreshPlaylistDerivedState()
        }
        .sheet(isPresented: $isHistorySheetPresented) {
            ListeningHistorySheet(viewModel: viewModel, theme: theme)
        }
        .sheet(isPresented: $isCreatePlaylistSheetPresented) {
            createPlaylistSheet
        }
        .alert("删除歌单", isPresented: $isDeletePlaylistAlertPresented) {
            Button("取消", role: .cancel) {}
            Button("删除", role: .destructive) {
                viewModel.removeSelectedPlaylist()
            }
        } message: {
            Text("确定删除“\(viewModel.selectedPlaylistName)”吗？该歌单中的待播项目也会一并移除。")
        }
    }

    private var fullLayout: some View {
        HStack(spacing: 18) {
            VStack(spacing: 18) {
                header
                nowPlayingCard
                controls
                if viewModel.isEqualizerExpanded {
                    equalizerSection
                }
                playlistSection
            }

            lyricsPanel
                .frame(width: 300)
        }
    }

    private var compactLayout: some View {
        VStack(spacing: 8) {
            compactHeader
            compactNowPlayingCard
            compactControls
            compactPlaylistSection
        }
        .frame(maxWidth: 380, maxHeight: .infinity)
    }

    private var header: some View {
        HStack {
            VStack(alignment: .leading, spacing: 6) {
                Text("Zephyr Player")
                    .font(.system(size: 30, weight: .bold, design: .serif))
                    .italic()
                    .tracking(0.8)
            }

            Spacer()

            HStack(spacing: 10) {
                playlistSwitcher

                Button("均衡器") {
                    viewModel.isEqualizerExpanded.toggle()
                }
                .fixedSize()

                themeMenu

                Button(viewModel.interfaceMode.rawValue) {
                    viewModel.toggleInterfaceMode()
                }
                .fixedSize()

                Button("听歌历史") {
                    isHistorySheetPresented = true
                }
                .fixedSize()

                Button("扫描文件夹") {
                    viewModel.openFolder()
                }
                .fixedSize()

                Button("添加音频") {
                    viewModel.openFiles()
                }
                .fixedSize()
            }
        }
    }

    private var compactHeader: some View {
        HStack(spacing: 8) {
            playlistSwitcher
                .frame(maxWidth: .infinity)

            HStack(spacing: 8) {
                Menu {
                    Button("添加歌曲") {
                        viewModel.openFiles()
                    }

                    Button("添加文件夹") {
                        viewModel.openFolder()
                    }

                    Menu("从歌单添加") {
                        ForEach(viewModel.playlists.filter { $0.id != viewModel.selectedPlaylistID }) { playlist in
                            Button(playlist.name) {
                                viewModel.addTracks(fromPlaylist: playlist.id)
                            }
                        }
                    }
                } label: {
                    compactHeaderIconLabel(systemName: "plus.circle")
                }
                .menuIndicator(.hidden)

                compactHeaderIconButton {
                    viewModel.toggleInterfaceMode()
                } label: {
                    Image(systemName: viewModel.interfaceMode.symbolName)
                }

                Menu {
                    themeMenuContent
                } label: {
                    compactHeaderIconLabel(systemName: "paintpalette")
                }
                .menuIndicator(.hidden)

                compactHeaderIconButton {
                    isHistorySheetPresented = true
                } label: {
                    Image(systemName: "clock.arrow.circlepath")
                }
            }
            .frame(maxWidth: .infinity)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .buttonStyle(.bordered)
        .padding(.horizontal, 12)
        .padding(.vertical, 10)
        .background(panelBackground(primary: true))
    }

    private var nowPlayingCard: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(alignment: .center, spacing: 18) {
                artworkView(size: 134, cornerRadius: 20)

                VStack(alignment: .leading, spacing: 14) {
                    Text("正在播放")
                        .font(.headline)

                    Text(viewModel.currentTrack?.title ?? "未选择歌曲")
                        .font(.title3.weight(.semibold))
                        .lineLimit(1)

                    Text(nowPlayingSubtitle)
                        .foregroundStyle(theme.secondaryText)

                    transportSlider
                }
            }
        }
        .padding(18)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(panelBackground(primary: true))
    }

    private var compactNowPlayingCard: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 10) {
                artworkView(size: 54, cornerRadius: 12)

                VStack(alignment: .leading, spacing: 4) {
                    Text(viewModel.currentTrack?.title ?? "未选择歌曲")
                        .font(.subheadline.weight(.semibold))
                        .lineLimit(1)

                    Text(nowPlayingSubtitle)
                        .font(.caption)
                        .foregroundStyle(theme.secondaryText)
                        .lineLimit(1)
                }

                Spacer(minLength: 0)

                Text(viewModel.isPlaying ? "播放中" : "暂停")
                    .font(.caption2.weight(.medium))
                    .foregroundStyle(theme.accent)
                    .shadow(color: theme.primaryShadow, radius: usesImageBackground ? 8 : 0)
            }

            transportSliderCompact
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 10)
        .background(panelBackground(primary: true))
    }

    private var controls: some View {
        HStack(spacing: 16) {
            Button {
                viewModel.playPrevious()
            } label: {
                Image(systemName: "backward.fill")
            }
            .help("上一首")
            .fixedSize()

            Button {
                viewModel.togglePlayback()
            } label: {
                Label(viewModel.isPlaying ? "暂停" : "播放",
                      systemImage: viewModel.isPlaying ? "pause.fill" : "play.fill")
            }
            .keyboardShortcut(.space, modifiers: [])
            .fixedSize()

            Button {
                viewModel.playNext()
            } label: {
                Image(systemName: "forward.fill")
            }
            .help("下一首")
            .fixedSize()

            Button {
                viewModel.cyclePlaybackMode()
            } label: {
                Label(viewModel.playbackMode.rawValue, systemImage: viewModel.playbackMode.symbolName)
            }
            .fixedSize()

            Spacer()

            HStack(spacing: 8) {
                Image(systemName: "speaker.wave.2.fill")
                    .foregroundStyle(theme.secondaryText)

                Slider(value: $viewModel.volume, in: 0...1)
                    .frame(width: 150)
            }
            .frame(minWidth: 190)

            Button {
                viewModel.isDesktopLyricsVisible.toggle()
            } label: {
                Label(
                    viewModel.isDesktopLyricsVisible ? "关闭桌面歌词" : "桌面歌词",
                    systemImage: viewModel.isDesktopLyricsVisible ? "rectangle.on.rectangle.slash" : "rectangle.on.rectangle"
                )
            }
            .fixedSize()

            Button {
                viewModel.isEqualizerExpanded.toggle()
            } label: {
                Label(viewModel.isEqualizerExpanded ? "收起均衡器" : "展开均衡器", systemImage: "slider.horizontal.3")
            }
            .fixedSize()
        }
        .buttonStyle(.bordered)
    }

    private var compactControls: some View {
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
            .keyboardShortcut(.space, modifiers: [])

            Button {
                viewModel.playNext()
            } label: {
                Image(systemName: "forward.fill")
            }

            Button {
                viewModel.cyclePlaybackMode()
            } label: {
                Image(systemName: viewModel.playbackMode.symbolName)
            }

            Button {
                viewModel.isDesktopLyricsVisible.toggle()
            } label: {
                Image(systemName: viewModel.isDesktopLyricsVisible ? "quote.bubble.fill" : "quote.bubble")
            }

            HStack(spacing: 6) {
                Image(systemName: "speaker.wave.2.fill")
                    .foregroundStyle(theme.secondaryText)
                Slider(value: $viewModel.volume, in: 0...1)
                    .frame(width: 88)
            }
            .frame(minWidth: 112)
        }
        .buttonStyle(.bordered)
        .padding(.horizontal, 12)
        .padding(.vertical, 10)
        .background(panelBackground(primary: false))
    }

    private var equalizerSection: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack {
                Text("均衡器")
                    .font(.headline)

                Spacer()

                Toggle("启用", isOn: $viewModel.isEqualizerEnabled)
                    .toggleStyle(.switch)

                Button("重置") {
                    viewModel.resetEqualizer()
                }
            }

            HStack(spacing: 12) {
                Text("预设")
                    .foregroundStyle(theme.secondaryText)

                Picker("预设", selection: $viewModel.selectedEqualizerPreset) {
                    ForEach(PlayerViewModel.EqualizerPreset.allCases) { preset in
                        Text(preset.rawValue).tag(preset)
                    }
                }
                .pickerStyle(.menu)
                .onChange(of: viewModel.selectedEqualizerPreset) { preset in
                    viewModel.applyEqualizerPreset(preset)
                }

                Spacer()

                Text(viewModel.isEqualizerEnabled ? "当前已启用" : "当前未启用")
                    .font(.caption)
                    .foregroundStyle(viewModel.isEqualizerEnabled ? theme.accent : theme.secondaryText)
            }

            ScrollView(.horizontal, showsIndicators: false) {
                HStack(alignment: .bottom, spacing: 16) {
                    ForEach(Array(viewModel.equalizerBands.enumerated()), id: \.element.id) { index, band in
                        VStack(spacing: 10) {
                            Text(String(format: "%+.0f dB", band.gain))
                                .font(.caption.monospacedDigit())
                                .foregroundStyle(abs(band.gain) > 0.1 ? theme.accent : theme.secondaryText)

                            Slider(
                                value: Binding(
                                    get: { Double(viewModel.equalizerBands[index].gain) },
                                    set: { viewModel.updateEqualizerBandGain(at: index, gain: Float($0)) }
                                ),
                                in: -12...12,
                                step: 0.5
                            )
                            .frame(height: 120)
                            .rotationEffect(.degrees(-90))
                            .frame(width: 28, height: 120)

                            Text(band.label)
                                .font(.caption.weight(.semibold))
                                .foregroundStyle(theme.secondaryText)
                        }
                        .frame(width: 48)
                    }
                }
                .padding(.horizontal, 10)
                .padding(.vertical, 6)
            }
        }
        .padding(18)
        .background(panelBackground(primary: false))
    }

    private var playlistSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            playlistHeader
            playlistSearchBar
            playlistFilters

            List {
                ForEach(filteredPlaylist, id: \.track.id) { item in
                    PlaylistRow(
                        track: item.track,
                        isCurrent: viewModel.currentIndex == item.index,
                        isPlaying: viewModel.isPlaying,
                        theme: theme,
                        isQueuedNext: viewModel.queuedTrackPaths.contains(item.track.url.standardizedFileURL.path),
                        query: playlistSearchText
                    ) {
                        viewModel.playSelected(track: item.track)
                    } queueNextAction: {
                        viewModel.queueTrackNext(item.track, in: viewModel.selectedPlaylistID)
                    }
                }
                .onDelete(perform: removeFilteredTracks)
            }
            .listStyle(.inset)
            .scrollContentBackground(.hidden)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .padding(18)
        .background(panelBackground(primary: false))
    }

    private var compactPlaylistSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            compactPlaylistBar

            HStack(spacing: 8) {
                Menu {
                    ForEach(artistOptions, id: \.self) { artist in
                        Button {
                            selectedArtistFilter = artist
                        } label: {
                            if selectedArtistFilter == artist {
                                Label(artist, systemImage: "checkmark")
                            } else {
                                Text(artist)
                            }
                        }
                    }
                } label: {
                    filterMenuLabel(selectedArtistFilter)
                }

                Menu {
                    ForEach(albumOptions, id: \.self) { album in
                        Button {
                            selectedAlbumFilter = album
                        } label: {
                            if selectedAlbumFilter == album {
                                Label(album, systemImage: "checkmark")
                            } else {
                                Text(album)
                            }
                        }
                    }
                } label: {
                    filterMenuLabel(selectedAlbumFilter)
                }

                Menu {
                    ForEach(PlaylistSortOption.allCases) { option in
                        Button {
                            sortOption = option
                        } label: {
                            if sortOption == option {
                                Label(option.rawValue, systemImage: "checkmark")
                            } else {
                                Text(option.rawValue)
                            }
                        }
                    }
                } label: {
                    filterMenuLabel(sortOption.rawValue)
                }
            }
            .font(.caption)
            .menuStyle(.borderlessButton)

            List {
                ForEach(filteredPlaylist, id: \.track.id) { item in
                    PlaylistRow(
                        track: item.track,
                        isCurrent: viewModel.currentIndex == item.index,
                        isPlaying: viewModel.isPlaying,
                        theme: theme,
                        isQueuedNext: viewModel.queuedTrackPaths.contains(item.track.url.standardizedFileURL.path),
                        query: playlistSearchText
                    ) {
                        viewModel.playSelected(track: item.track)
                    } queueNextAction: {
                        viewModel.queueTrackNext(item.track, in: viewModel.selectedPlaylistID)
                    }
                }
                .onDelete(perform: removeFilteredTracks)
            }
            .listStyle(.inset)
            .scrollContentBackground(.hidden)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .padding(12)
        .background(panelBackground(primary: false))
    }

    private var playlistHeader: some View {
        HStack(alignment: .center) {
            VStack(alignment: .leading, spacing: 4) {
                Text("播放列表")
                    .font(.headline)
                Text(viewModel.selectedPlaylistName)
                    .font(.caption)
                    .foregroundStyle(theme.secondaryText)
            }
            Spacer()
            Text("\(filteredPlaylist.count) / \(viewModel.playlist.count) 首")
                .foregroundStyle(theme.secondaryText)
        }
    }

    private var compactPlaylistBar: some View {
        HStack(spacing: 8) {
            Text(viewModel.selectedPlaylistName)
                .font(.subheadline.weight(.semibold))
                .lineLimit(1)
                .frame(minWidth: 110, alignment: .leading)

            playlistSearchBarCompact
        }
    }

    private var playlistSwitcher: some View {
        HStack(spacing: 8) {
            Menu {
                ForEach(viewModel.playlists) { playlist in
                    Button {
                        viewModel.selectedPlaylistID = playlist.id
                    } label: {
                        if viewModel.selectedPlaylistID == playlist.id {
                            Label(playlist.name, systemImage: "checkmark")
                        } else {
                            Text(playlist.name)
                        }
                    }
                }
            } label: {
                HStack(spacing: 6) {
                    Text(viewModel.selectedPlaylistName)
                        .lineLimit(1)
                    Image(systemName: "chevron.down")
                        .font(.caption2.weight(.bold))
                }
                .foregroundStyle(theme.primaryText)
            }
            .frame(width: viewModel.interfaceMode == .compact ? 126 : 140)
            .menuIndicator(viewModel.interfaceMode == .compact ? .hidden : .visible)

            Button {
                newPlaylistName = ""
                isCreatePlaylistSheetPresented = true
            } label: {
                Image(systemName: "text.badge.plus")
            }
            .help("新建歌单")

            Button {
                isDeletePlaylistAlertPresented = true
            } label: {
                Image(systemName: "trash")
            }
            .help("删除当前歌单")
            .disabled(viewModel.playlists.count <= 1)
        }
        .frame(maxWidth: .infinity)
    }

    private var playlistSearchBar: some View {
        HStack(spacing: 10) {
            Image(systemName: "magnifyingglass")
                .foregroundStyle(theme.secondaryText)

            TextField("搜索歌曲、格式或文件夹", text: $playlistSearchText)
                .textFieldStyle(.plain)
                .focused($isPlaylistSearchFocused)
                .foregroundColor(theme.primaryText)

            if !playlistSearchText.isEmpty {
                Button {
                    playlistSearchText = ""
                } label: {
                    Image(systemName: "xmark.circle.fill")
                        .foregroundStyle(theme.secondaryText)
                }
                .buttonStyle(.plain)
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 10)
        .background(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .fill(theme.panel)
                .overlay(
                    RoundedRectangle(cornerRadius: 14, style: .continuous)
                        .stroke(theme.border, lineWidth: 1)
                )
        )
    }

    private var playlistSearchBarCompact: some View {
        HStack(spacing: 8) {
            Image(systemName: "magnifyingglass")
                .font(.caption)
                .foregroundStyle(theme.secondaryText)

            TextField("搜索", text: $playlistSearchText)
                .textFieldStyle(.plain)
                .focused($isPlaylistSearchFocused)
                .foregroundColor(theme.primaryText)

            if !playlistSearchText.isEmpty {
                Button {
                    playlistSearchText = ""
                } label: {
                    Image(systemName: "xmark.circle.fill")
                        .foregroundStyle(theme.secondaryText)
                }
                .buttonStyle(.plain)
            }
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 6)
        .background(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .fill(theme.panel)
                .overlay(
                    RoundedRectangle(cornerRadius: 12, style: .continuous)
                        .stroke(theme.border, lineWidth: 1)
                )
        )
    }

    private var playlistFilters: some View {
        HStack(spacing: 10) {
            Menu {
                ForEach(artistOptions, id: \.self) { artist in
                    Button {
                        selectedArtistFilter = artist
                    } label: {
                        if selectedArtistFilter == artist {
                            Label(artist, systemImage: "checkmark")
                        } else {
                            Text(artist)
                        }
                    }
                }
            } label: {
                filterMenuLabel(selectedArtistFilter)
            }

            Menu {
                ForEach(albumOptions, id: \.self) { album in
                    Button {
                        selectedAlbumFilter = album
                    } label: {
                        if selectedAlbumFilter == album {
                            Label(album, systemImage: "checkmark")
                        } else {
                            Text(album)
                        }
                    }
                }
            } label: {
                filterMenuLabel(selectedAlbumFilter)
            }

            Menu {
                ForEach(PlaylistSortOption.allCases) { option in
                    Button {
                        sortOption = option
                    } label: {
                        if sortOption == option {
                            Label(option.rawValue, systemImage: "checkmark")
                        } else {
                            Text(option.rawValue)
                        }
                    }
                }
            } label: {
                filterMenuLabel(sortOption.rawValue)
            }
        }
    }

    private func filterMenuLabel(_ title: String) -> some View {
        HStack(spacing: 6) {
            Text(title)
                .lineLimit(1)
            Image(systemName: "chevron.down")
                .font(.caption2.weight(.bold))
        }
        .foregroundStyle(theme.primaryText)
    }

    private func compactHeaderIconButton<Label: View>(
        action: @escaping () -> Void,
        @ViewBuilder label: () -> Label
    ) -> some View {
        Button(action: action) {
            compactHeaderIconLabel {
                label()
            }
        }
        .labelStyle(.iconOnly)
        .controlSize(.small)
        .font(.system(size: 12, weight: .semibold))
    }

    private func compactHeaderIconLabel(systemName: String) -> some View {
        compactHeaderIconLabel {
            Image(systemName: systemName)
        }
    }

    private func compactHeaderIconLabel<Label: View>(
        @ViewBuilder content: () -> Label
    ) -> some View {
        content()
            .frame(width: 24, height: 18)
            .foregroundStyle(theme.primaryText)
            .labelStyle(.iconOnly)
            .controlSize(.small)
            .font(.system(size: 12, weight: .semibold))
    }

    private var lyricsPanel: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text("歌词")
                .font(.headline)

            if !viewModel.lyrics.timedLines.isEmpty {
                ScrollViewReader { proxy in
                    ScrollView {
                        LazyVStack(alignment: .leading, spacing: 10) {
                            ForEach(Array(viewModel.lyrics.timedLines.enumerated()), id: \.element.id) { index, line in
                                LyricJumpRow(
                                    text: line.text,
                                    time: line.time,
                                    prominent: index == viewModel.currentLyricIndex,
                                    theme: theme,
                                    onSelect: {
                                        lyricScrollAnchor = UnitPoint(x: 0.5, y: 0.68)
                                        withAnimation(.easeInOut(duration: 0.22)) {
                                            proxy.scrollTo(index, anchor: lyricScrollAnchor)
                                        }
                                        viewModel.seekToTime(line.time)
                                        DispatchQueue.main.asyncAfter(deadline: .now() + 1.0) {
                                            lyricScrollAnchor = .center
                                        }
                                    }
                                )
                                .id(index)
                                .animation(.easeInOut(duration: 0.2), value: viewModel.currentLyricIndex)
                            }
                        }
                        .padding(.vertical, 24)
                    }
                    .onAppear {
                        if let index = viewModel.currentLyricIndex {
                            proxy.scrollTo(index, anchor: .center)
                        }
                    }
                    .onChange(of: viewModel.currentLyricIndex) { newValue in
                        guard let newValue else { return }
                        withAnimation(.easeInOut(duration: 0.35)) {
                            proxy.scrollTo(newValue, anchor: lyricScrollAnchor)
                        }
                    }
                }
            } else if let plainText = viewModel.lyrics.plainText, !plainText.isEmpty {
                ScrollView {
                    Text(plainText)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .foregroundStyle(theme.primaryText)
                        .textSelection(.enabled)
                }
            } else {
                Spacer()
                Text("当前歌曲未找到歌词文件。\n将同名 `.lrc` 或 `.txt` 放在音频文件旁即可自动加载。")
                    .foregroundStyle(theme.secondaryText)
                Spacer()
            }
        }
        .padding(22)
        .background(panelBackground(primary: false))
    }

    private var transportSlider: some View {
        VStack(spacing: 8) {
            Slider(
                value: Binding(
                    get: { sliderValue },
                    set: { sliderValue = $0 }
                ),
                in: 0...1,
                onEditingChanged: { editing in
                    isDraggingSlider = editing
                    if editing {
                        viewModel.beginScrubbing()
                    } else {
                        viewModel.seek(to: sliderValue)
                        viewModel.endScrubbing()
                    }
                }
            )

            HStack {
                Text(viewModel.formatTime(isDraggingSlider ? sliderValue * viewModel.duration : viewModel.currentTime))
                Spacer()
                Text(viewModel.formatTime(viewModel.duration))
            }
            .font(.caption.monospacedDigit())
            .foregroundStyle(theme.secondaryText)
        }
    }

    private var nowPlayingSubtitle: String {
        [
            viewModel.currentTrack?.artist ?? "未知艺术家",
            viewModel.currentTrack?.album ?? "未知专辑",
            viewModel.currentTrack?.fileExtension ?? "等待加载"
        ].joined(separator: " · ")
    }

    private var backgroundView: some View {
        ZStack {
            if viewModel.appTheme == .customImage, let backgroundImage = viewModel.customBackgroundImage {
                Image(nsImage: backgroundImage)
                    .resizable()
                    .scaledToFill()
                    .overlay {
                        LinearGradient(
                            colors: [theme.backgroundTop, theme.backgroundBottom],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        )
                    }
                    .clipped()
            } else {
                LinearGradient(
                    colors: [theme.backgroundTop, theme.backgroundBottom],
                    startPoint: .topLeading,
                    endPoint: .bottomTrailing
                )

                Circle()
                    .fill(theme.accentSoft.opacity(0.45))
                    .frame(width: 340, height: 340)
                    .blur(radius: 28)
                    .offset(x: 310, y: -180)

                Circle()
                    .fill(theme.lyricGlow)
                    .frame(width: 260, height: 260)
                    .blur(radius: 24)
                    .offset(x: -320, y: 200)
            }
        }
        .ignoresSafeArea()
    }

    private var themeMenu: some View {
        Menu {
            themeMenuContent
        } label: {
            Image(systemName: "paintpalette")
        }
        .labelStyle(.iconOnly)
        .fixedSize()
    }

    @ViewBuilder
    private var themeMenuContent: some View {
        ForEach(PlayerViewModel.AppTheme.allCases) { themeOption in
            Button {
                if themeOption == .customImage {
                    viewModel.openCustomBackgroundImage()
                } else {
                    viewModel.appTheme = themeOption
                }
            } label: {
                if viewModel.appTheme == themeOption {
                    Label(themeOption.rawValue, systemImage: "checkmark")
                } else {
                    Text(themeOption.rawValue)
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

    private var createPlaylistSheet: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("新建歌单")
                .font(.title3.weight(.semibold))

            TextField("输入歌单名称", text: $newPlaylistName)
                .textFieldStyle(.roundedBorder)

            HStack {
                Spacer()

                Button("取消") {
                    isCreatePlaylistSheetPresented = false
                }

                Button("创建") {
                    viewModel.createPlaylist(named: newPlaylistName)
                    isCreatePlaylistSheetPresented = false
                }
                .keyboardShortcut(.defaultAction)
            }
        }
        .padding(20)
        .frame(width: 360)
        .background(backgroundView)
    }

    private func panelBackground(primary: Bool) -> some View {
        RoundedRectangle(cornerRadius: 22, style: .continuous)
            .fill(primary ? theme.panel : theme.panelSecondary)
            .overlay(
                RoundedRectangle(cornerRadius: 22, style: .continuous)
                    .stroke(theme.border, lineWidth: 1)
            )
            .shadow(color: usesImageBackground ? .black.opacity(0.28) : .black.opacity(colorScheme == .dark ? 0.22 : 0.08), radius: 14, x: 0, y: 10)
    }

    private func artworkView(size: CGFloat, cornerRadius: CGFloat) -> some View {
        Group {
            if let artwork = viewModel.currentArtwork {
                Image(nsImage: artwork)
                    .resizable()
                    .scaledToFill()
            } else {
                ZStack {
                    RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                        .fill(theme.accentSoft)
                    Image(systemName: "music.note")
                        .font(.system(size: max(size * 0.32, 24), weight: .bold))
                        .foregroundStyle(theme.accent)
                        .shadow(color: theme.primaryShadow, radius: usesImageBackground ? 8 : 0)
                }
            }
        }
        .frame(width: size, height: size)
        .clipShape(RoundedRectangle(cornerRadius: cornerRadius, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                .stroke(theme.border, lineWidth: 1)
        )
    }

    private var dropOverlay: some View {
        Group {
            if viewModel.isDropTargeted {
                RoundedRectangle(cornerRadius: 30, style: .continuous)
                    .fill(theme.accentSoft.opacity(0.18))
                    .overlay(
                        RoundedRectangle(cornerRadius: 30, style: .continuous)
                            .stroke(theme.accent, style: StrokeStyle(lineWidth: 3, dash: [12, 10]))
                    )
                    .padding(12)
                    .overlay {
                        VStack(spacing: 10) {
                            Image(systemName: "square.and.arrow.down.on.square")
                                .font(.system(size: 42, weight: .semibold))
                            Text("拖入音频文件或文件夹以导入歌单")
                                .font(.title3.weight(.semibold))
                        }
                        .foregroundStyle(theme.accent)
                    }
            }
        }
    }

    private func removeFilteredTracks(at offsets: IndexSet) {
        let actualOffsets = IndexSet(offsets.compactMap { filteredPlaylist[$0].index })
        viewModel.removeTracks(at: actualOffsets)
    }

    private func compareByTitle(lhs: (index: Int, track: AudioTrack), rhs: (index: Int, track: AudioTrack)) -> Bool {
        lhs.track.title.localizedStandardCompare(rhs.track.title) == .orderedAscending
    }

    private func compareByArtist(lhs: (index: Int, track: AudioTrack), rhs: (index: Int, track: AudioTrack)) -> Bool {
        let left = (lhs.track.artist ?? "未知艺术家") + lhs.track.title
        let right = (rhs.track.artist ?? "未知艺术家") + rhs.track.title
        return left.localizedStandardCompare(right) == .orderedAscending
    }

    private func compareByAlbum(lhs: (index: Int, track: AudioTrack), rhs: (index: Int, track: AudioTrack)) -> Bool {
        let left = (lhs.track.album ?? "未知专辑") + lhs.track.title
        let right = (rhs.track.album ?? "未知专辑") + rhs.track.title
        return left.localizedStandardCompare(right) == .orderedAscending
    }

    private var transportSliderCompact: some View {
        VStack(spacing: 4) {
            Slider(
                value: Binding(
                    get: { sliderValue },
                    set: { sliderValue = $0 }
                ),
                in: 0...1,
                onEditingChanged: { editing in
                    isDraggingSlider = editing
                    if editing {
                        viewModel.beginScrubbing()
                    } else {
                        viewModel.seek(to: sliderValue)
                        viewModel.endScrubbing()
                    }
                }
            )

            HStack {
                Text(viewModel.formatTime(isDraggingSlider ? sliderValue * viewModel.duration : viewModel.currentTime))
                Spacer()
                Text(viewModel.formatTime(viewModel.duration))
            }
            .font(.caption2.monospacedDigit())
            .foregroundStyle(theme.secondaryText)
        }
    }

    private func refreshPlaylistDerivedState() {
        let playlist = viewModel.playlist
        artistOptionsCache = ["全部艺术家"] + Set(playlist.compactMap(\.artist)).sorted { $0.localizedStandardCompare($1) == .orderedAscending }
        albumOptionsCache = ["全部专辑"] + Set(playlist.compactMap(\.album)).sorted { $0.localizedStandardCompare($1) == .orderedAscending }

        if !artistOptionsCache.contains(selectedArtistFilter) {
            selectedArtistFilter = "全部艺术家"
        }
        if !albumOptionsCache.contains(selectedAlbumFilter) {
            selectedAlbumFilter = "全部专辑"
        }

        let items = Array(playlist.enumerated())
        let query = playlistSearchText
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .folding(options: [.diacriticInsensitive, .caseInsensitive], locale: .current)

        let filtered = items.compactMap { item -> (Int, AudioTrack)? in
            let track = item.element

            if selectedArtistFilter != "全部艺术家", track.artist != selectedArtistFilter {
                return nil
            }

            if selectedAlbumFilter != "全部专辑", track.album != selectedAlbumFilter {
                return nil
            }

            guard !query.isEmpty else {
                return (item.offset, track)
            }

            let haystack = [
                track.title,
                track.artist ?? "",
                track.album ?? "",
                track.fileExtension,
                track.url.lastPathComponent,
                track.url.deletingLastPathComponent().lastPathComponent
            ]
            .joined(separator: " ")
            .folding(options: [.diacriticInsensitive, .caseInsensitive], locale: .current)

            return haystack.contains(query) ? (item.offset, track) : nil
        }

        filteredPlaylistCache = {
            switch sortOption {
            case .addedOrder:
                return filtered
            case .title:
                return filtered.sorted(by: compareByTitle)
            case .artist:
                return filtered.sorted(by: compareByArtist)
            case .album:
                return filtered.sorted(by: compareByAlbum)
            }
        }()
    }

    private func resizeWindowIfNeeded(for mode: PlayerViewModel.InterfaceMode) {
        guard let window = hostWindow else { return }

        let targetSize = mode == .compact
            ? NSSize(width: 420, height: 760)
            : NSSize(width: 1360, height: 860)

        let newFrame = window.frameRect(forContentRect: NSRect(origin: .zero, size: targetSize))
        var frame = window.frame
        frame.origin.y += frame.size.height - newFrame.size.height
        frame.size = newFrame.size

        window.minSize = targetSize
        window.contentMinSize = targetSize
        window.setContentSize(targetSize)
        window.setFrame(frame, display: true, animate: false)
    }

}

private struct WindowAccessor: NSViewRepresentable {
    @Binding var window: NSWindow?

    func makeNSView(context: Context) -> NSView {
        let view = NSView()
        DispatchQueue.main.async {
            self.window = view.window
        }
        return view
    }

    func updateNSView(_ nsView: NSView, context: Context) {
        DispatchQueue.main.async {
            self.window = nsView.window
        }
    }
}

private struct LyricJumpRow: View {
    let text: String
    let time: TimeInterval
    let prominent: Bool
    let theme: PlayerTheme
    let onSelect: () -> Void

    @State private var isHovered = false

    var body: some View {
        Button(action: onSelect) {
            HStack(alignment: .firstTextBaseline, spacing: 12) {
                Text(formatLyricTimestamp(time))
                    .font(.caption.monospacedDigit())
                    .foregroundStyle(prominent ? theme.accent : (isHovered ? theme.accent : theme.secondaryText))
                    .frame(width: 46, alignment: .leading)

                Text(text)
                    .font(prominent ? .system(size: 28, weight: .bold) : .title3.weight(.medium))
                    .foregroundStyle(prominent ? theme.accent : theme.primaryText.opacity(isHovered ? 0.88 : 0.72))
                    .multilineTextAlignment(.leading)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
            .padding(.vertical, prominent ? 10 : 4)
            .padding(.horizontal, 8)
            .background(
                RoundedRectangle(cornerRadius: 14, style: .continuous)
                    .fill(backgroundFill)
            )
            .overlay(
                RoundedRectangle(cornerRadius: 14, style: .continuous)
                    .stroke(isHovered ? theme.accent.opacity(0.35) : .clear, lineWidth: 1)
            )
            .contentShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
        }
        .buttonStyle(.plain)
        .scaleEffect(isHovered && !prominent ? 1.01 : 1)
        .animation(.easeInOut(duration: 0.16), value: isHovered)
        .onHover { hovering in
            isHovered = hovering
        }
    }

    private var backgroundFill: Color {
        if prominent {
            return theme.lyricGlow
        }
        if isHovered {
            return theme.accentSoft.opacity(0.22)
        }
        return .clear
    }

    private func formatLyricTimestamp(_ time: TimeInterval) -> String {
        let totalSeconds = Int(time.rounded(.down))
        let minutes = totalSeconds / 60
        let seconds = totalSeconds % 60
        return String(format: "%02d:%02d", minutes, seconds)
    }
}

private struct PlaylistRow: View {
    let track: AudioTrack
    let isCurrent: Bool
    let isPlaying: Bool
    let theme: PlayerTheme
    let isQueuedNext: Bool
    let query: String
    let action: () -> Void
    let queueNextAction: () -> Void

    var body: some View {
        Button(action: action) {
            HStack {
                VStack(alignment: .leading, spacing: 4) {
                    highlightedText(track.title, query: query)
                        .foregroundStyle(theme.primaryText)
                    Text([
                        track.artist ?? "未知艺术家",
                        track.album ?? "未知专辑",
                        track.fileExtension
                    ].joined(separator: " · "))
                        .font(.caption)
                        .foregroundStyle(theme.secondaryText)
                        .lineLimit(2)
                }
                Spacer()
                if isQueuedNext {
                    Label("待播", systemImage: "text.line.first.and.arrowtriangle.forward")
                        .font(.caption2.weight(.medium))
                        .foregroundStyle(theme.secondaryText)
                }
                if isCurrent {
                    Image(systemName: isPlaying ? "speaker.wave.2.fill" : "pause.circle")
                        .foregroundStyle(theme.accent)
                }
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .contextMenu {
            Button("下一首播放") {
                queueNextAction()
            }
        }
        .listRowBackground(Color.clear)
    }

    private func highlightedText(_ source: String, query: String) -> Text {
        let trimmed = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty,
              let range = source.range(of: trimmed, options: [.caseInsensitive, .diacriticInsensitive]) else {
            return Text(source)
        }

        let before = String(source[..<range.lowerBound])
        let match = String(source[range])
        let after = String(source[range.upperBound...])

        return Text(before)
        + Text(match).foregroundColor(theme.accent)
        + Text(after)
    }
}

private struct ListeningHistorySheet: View {
    private enum HistoryScope: String, CaseIterable, Identifiable {
        case monthly = "月度统计"
        case yearly = "年度统计"
        case recent = "最近 100 首"

        var id: String { rawValue }
    }

    @ObservedObject var viewModel: PlayerViewModel
    let theme: PlayerTheme
    @Environment(\.dismiss) private var dismiss
    @State private var selectedScope: HistoryScope = .monthly
    @State private var selectedMonthID: String?
    @State private var selectedYearID: String?

    private var summaries: [MonthlyListeningSummary] {
        viewModel.monthlyListeningSummaries
    }

    private var selectedSummary: MonthlyListeningSummary? {
        if let selectedMonthID,
           let matched = summaries.first(where: { $0.id == selectedMonthID }) {
            return matched
        }
        return summaries.first
    }

    private var yearlySummaries: [YearlyListeningSummary] {
        viewModel.yearlyListeningSummaries
    }

    private var selectedYearSummary: YearlyListeningSummary? {
        if let selectedYearID,
           let matched = yearlySummaries.first(where: { $0.id == selectedYearID }) {
            return matched
        }
        return yearlySummaries.first
    }

    var body: some View {
        VStack(spacing: 18) {
            HStack {
                VStack(alignment: .leading, spacing: 4) {
                    Text("听歌历史")
                        .font(.title3.weight(.bold))
                    Text("按月份查看最常听歌曲与累计播放次数")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }

                Spacer()

                Button("关闭") {
                    dismiss()
                }
            }

            Picker("范围", selection: $selectedScope) {
                ForEach(HistoryScope.allCases) { scope in
                    Text(scope.rawValue).tag(scope)
                }
            }
            .pickerStyle(.segmented)

            if summaries.isEmpty && yearlySummaries.isEmpty && viewModel.recentListeningRecords.isEmpty {
                Spacer()
                VStack(spacing: 10) {
                    Image(systemName: "clock.badge.questionmark")
                        .font(.system(size: 34, weight: .semibold))
                        .foregroundStyle(theme.accent)
                    Text("还没有听歌历史")
                        .font(.headline)
                    Text("开始播放歌曲后，这里会统计每月最常听的歌。")
                        .foregroundStyle(.secondary)
                }
                Spacer()
            } else {
                switch selectedScope {
                case .monthly:
                    monthlyHistoryContent
                case .yearly:
                    yearlyHistoryContent
                case .recent:
                    recentHistoryContent
                }
            }
        }
        .padding(22)
        .frame(minWidth: 760, minHeight: 520)
        .background(
            LinearGradient(
                colors: [theme.backgroundTop, theme.backgroundBottom],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )
        )
        .onAppear {
            selectedMonthID = summaries.first?.id
            selectedYearID = yearlySummaries.first?.id
        }
    }

    private var monthlyHistoryContent: some View {
        HStack(alignment: .top, spacing: 16) {
            VStack(alignment: .leading, spacing: 10) {
                Text("月份")
                    .font(.headline)

                ScrollView {
                    LazyVStack(alignment: .leading, spacing: 8) {
                        ForEach(summaries) { summary in
                            Button {
                                selectedMonthID = summary.id
                            } label: {
                                VStack(alignment: .leading, spacing: 4) {
                                    Text(monthTitle(for: summary.monthStart))
                                        .font(.subheadline.weight(.semibold))
                                    Text("总播放 \(summary.totalPlays) 次")
                                        .font(.caption)
                                        .foregroundStyle(.secondary)
                                }
                                .frame(maxWidth: .infinity, alignment: .leading)
                                .padding(12)
                                .background(
                                    RoundedRectangle(cornerRadius: 14, style: .continuous)
                                        .fill(selectedMonthID == summary.id || (selectedMonthID == nil && summaries.first?.id == summary.id) ? theme.accentSoft.opacity(0.3) : theme.panel)
                                )
                            }
                            .buttonStyle(.plain)
                        }
                    }
                }
            }
            .frame(width: 180)

            summaryTrackList(
                title: selectedSummary.map { "\(monthTitle(for: $0.monthStart)) 最常听" } ?? "月度统计",
                tracks: selectedSummary?.tracks ?? []
            )
        }
    }

    private var yearlyHistoryContent: some View {
        HStack(alignment: .top, spacing: 16) {
            VStack(alignment: .leading, spacing: 10) {
                Text("年份")
                    .font(.headline)

                ScrollView {
                    LazyVStack(alignment: .leading, spacing: 8) {
                        ForEach(yearlySummaries) { summary in
                            Button {
                                selectedYearID = summary.id
                            } label: {
                                VStack(alignment: .leading, spacing: 4) {
                                    Text("\(summary.year) 年")
                                        .font(.subheadline.weight(.semibold))
                                    Text("总播放 \(summary.totalPlays) 次")
                                        .font(.caption)
                                        .foregroundStyle(.secondary)
                                }
                                .frame(maxWidth: .infinity, alignment: .leading)
                                .padding(12)
                                .background(
                                    RoundedRectangle(cornerRadius: 14, style: .continuous)
                                        .fill(selectedYearID == summary.id || (selectedYearID == nil && yearlySummaries.first?.id == summary.id) ? theme.accentSoft.opacity(0.3) : theme.panel)
                                )
                            }
                            .buttonStyle(.plain)
                        }
                    }
                }
            }
            .frame(width: 180)

            summaryTrackList(
                title: selectedYearSummary.map { "\($0.year) 年最常听" } ?? "年度统计",
                tracks: selectedYearSummary?.tracks ?? []
            )
        }
    }

    private var recentHistoryContent: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("最近听歌记录")
                .font(.headline)

            List {
                ForEach(Array(viewModel.recentListeningRecords.enumerated()), id: \.element.id) { offset, item in
                    HStack(alignment: .top, spacing: 12) {
                        Text("\(offset + 1)")
                            .font(.caption.monospacedDigit())
                            .foregroundStyle(.secondary)
                            .frame(width: 28, alignment: .leading)

                        VStack(alignment: .leading, spacing: 4) {
                            Text(item.title)
                                .font(.body.weight(.semibold))
                            Text([
                                item.artist ?? "未知艺术家",
                                item.album ?? "未知专辑"
                            ].joined(separator: " · "))
                            .font(.caption)
                            .foregroundStyle(.secondary)
                        }

                        Spacer()

                        VStack(alignment: .trailing, spacing: 4) {
                            Text(timeTitle(for: item.playedAt))
                                .font(.caption.monospacedDigit())
                                .foregroundStyle(theme.accent)
                            Text(dateTitle(for: item.playedAt))
                                .font(.caption2)
                                .foregroundStyle(.secondary)
                        }
                    }
                    .padding(.vertical, 4)
                }
            }
            .listStyle(.inset)
        }
    }

    private func summaryTrackList(title: String, tracks: [ListeningTrackSummary]) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            Text(title)
                .font(.headline)

            List {
                ForEach(Array(tracks.enumerated()), id: \.element.id) { offset, item in
                    HStack(alignment: .top, spacing: 12) {
                        Text("\(offset + 1)")
                            .font(.caption.monospacedDigit())
                            .foregroundStyle(.secondary)
                            .frame(width: 24, alignment: .leading)

                        VStack(alignment: .leading, spacing: 4) {
                            Text(item.title)
                                .font(.body.weight(.semibold))
                            Text([
                                item.artist ?? "未知艺术家",
                                item.album ?? "未知专辑"
                            ].joined(separator: " · "))
                            .font(.caption)
                            .foregroundStyle(.secondary)
                        }

                        Spacer()

                        Text("\(item.playCount) 次")
                            .font(.subheadline.monospacedDigit().weight(.semibold))
                            .foregroundStyle(theme.accent)
                    }
                    .padding(.vertical, 4)
                }
            }
            .listStyle(.inset)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private func monthTitle(for date: Date) -> String {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "zh_CN")
        formatter.dateFormat = "yyyy年M月"
        return formatter.string(from: date)
    }

    private func dateTitle(for date: Date) -> String {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "zh_CN")
        formatter.dateFormat = "M月d日"
        return formatter.string(from: date)
    }

    private func timeTitle(for date: Date) -> String {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "zh_CN")
        formatter.dateFormat = "HH:mm"
        return formatter.string(from: date)
    }
}
