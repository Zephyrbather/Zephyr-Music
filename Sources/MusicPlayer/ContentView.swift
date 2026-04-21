import SwiftUI
import UniformTypeIdentifiers

private struct PlaylistListEntry: Identifiable, Equatable {
    let index: Int
    let track: AudioTrack

    var id: String {
        track.url.standardizedFileURL.path
    }
}

private struct PlaylistDestinationOption: Identifiable, Equatable {
    let id: UUID
    let title: String
}

struct ContentView: View {
    private enum PlaylistSortOption: String, CaseIterable, Identifiable {
        case addedOrder = "导入顺序"
        case title = "歌曲名"
        case artist = "艺术家"
        case album = "专辑"

        var id: String { rawValue }

        func title(in language: PlayerViewModel.AppLanguage) -> String {
            switch self {
            case .addedOrder:
                return language.pick("导入顺序", "Import Order")
            case .title:
                return language.pick("歌曲名", "Title")
            case .artist:
                return language.pick("艺术家", "Artist")
            case .album:
                return language.pick("专辑", "Album")
            }
        }
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
    @State private var filteredPlaylistCache: [PlaylistListEntry] = []
    @State private var isHistorySheetPresented = false
    @State private var isCreatePlaylistSheetPresented = false
    @State private var newPlaylistName = ""
    @State private var pendingTrackForNewPlaylist: AudioTrack?
    @State private var isDeletePlaylistAlertPresented = false
    @State private var isImmersiveVolumeExpanded = false
    @State private var isImmersivePlaylistPreviewPresented = false
    @State private var immersivePlaylistPreviewHideToken = UUID()
    @State private var isImmersiveMetadataControlsVisible = false
    @State private var suppressLyricAutoScrollAnimation = false
    @State private var playlistScrollRequestToken = UUID()
    @State private var playlistScrollTargetPath: String?
    @State private var playlistScrollAnimated = false

    private var theme: PlayerTheme {
        PlayerTheme.forSelection(viewModel.appTheme, colorScheme: colorScheme)
    }

    private var language: PlayerViewModel.AppLanguage {
        viewModel.appLanguage
    }

    private var allArtistsLabel: String {
        language.pick("全部艺术家", "All Artists")
    }

    private var allAlbumsLabel: String {
        language.pick("全部专辑", "All Albums")
    }

    private func tr(_ chinese: String, _ english: String) -> String {
        language.pick(chinese, english)
    }

    private var artistOptions: [String] { artistOptionsCache }

    private var albumOptions: [String] { albumOptionsCache }

    private var filteredPlaylist: [PlaylistListEntry] { filteredPlaylistCache }
    private var playlistCopyDestinations: [PlaylistDestinationOption] {
        viewModel.playlists
            .filter { $0.id != viewModel.selectedPlaylistID }
            .map { PlaylistDestinationOption(id: $0.id, title: viewModel.displayName(for: $0)) }
    }
    private var usesImageBackground: Bool { viewModel.appTheme == .customImage && viewModel.customBackgroundImage != nil }
    private var currentLyricsSourceTitle: String {
        guard let selected = viewModel.displayedLyricsSource else {
            return tr("暂无歌词", "No Lyrics")
        }
        return lyricsSourceTitle(for: selected)
    }
    private var lyricsPanelStatusText: String {
        if viewModel.isSearchingLyricsOnline {
            return tr("正在在线搜索歌词…", "Searching lyrics online...")
        }
        if viewModel.hasLyricsPreview {
            return tr("预览中，可应用或恢复", "Previewing, apply or restore")
        }
        if viewModel.onlineLyricsResultCount > 0 {
            return tr("已找到 \(viewModel.onlineLyricsResultCount) 条在线结果", "\(viewModel.onlineLyricsResultCount) online results found")
        }
        if viewModel.didAttemptOnlineLyricsSearch {
            return tr("未找到可用的在线歌词", "No online lyrics found")
        }
        if viewModel.onlineLyricsSourcesCount > 0 {
            return tr("可切换 \(viewModel.onlineLyricsSourcesCount) 条在线结果", "\(viewModel.onlineLyricsSourcesCount) online results available")
        }
        if let selected = viewModel.displayedLyricsSource,
           let subtitle = lyricsSourceSubtitle(for: selected) {
            return subtitle
        }
        return currentLyricsSourceTitle
    }
    private var currentArtworkSourceTitle: String {
        guard let selected = viewModel.displayedArtworkSource else {
            return tr("暂无封面", "No Artwork")
        }
        return artworkSourceTitle(for: selected)
    }
    private var artworkPanelStatusText: String {
        if viewModel.isSearchingArtworkOnline {
            return tr("正在在线搜索封面…", "Searching artwork online...")
        }
        if viewModel.hasArtworkPreview {
            return tr("预览中，可应用或恢复", "Previewing, apply or restore")
        }
        if viewModel.onlineArtworkResultCount > 0 {
            return tr("已找到 \(viewModel.onlineArtworkResultCount) 张在线封面", "\(viewModel.onlineArtworkResultCount) online covers found")
        }
        if viewModel.didAttemptOnlineArtworkSearch {
            return tr("未找到可用的在线封面", "No online artwork found")
        }
        if viewModel.onlineArtworkSourcesCount > 0 {
            return tr("可切换 \(viewModel.onlineArtworkSourcesCount) 张在线封面", "\(viewModel.onlineArtworkSourcesCount) online covers available")
        }
        if let selected = viewModel.displayedArtworkSource,
           let subtitle = artworkSourceSubtitle(for: selected) {
            return subtitle
        }
        return currentArtworkSourceTitle
    }
    private var immersiveMetadataSearchEmphasized: Bool {
        viewModel.isSearchingOnlineMetadata || viewModel.hasOnlineMetadataPreview || viewModel.hasOnlineMetadataResults
    }
    private var immersivePreviewPlaylist: PlaylistCollection? {
        let targetID = viewModel.currentPlayingPlaylistID ?? viewModel.selectedPlaylistID
        return viewModel.playlists.first(where: { $0.id == targetID }) ?? viewModel.playlists.first
    }
    private var immersivePreviewPlaylistID: UUID {
        immersivePreviewPlaylist?.id ?? viewModel.selectedPlaylistID
    }
    private var immersivePreviewPlaylistName: String {
        immersivePreviewPlaylist.map(viewModel.displayName(for:)) ?? viewModel.selectedPlaylistName
    }
    private var immersivePreviewTrackCount: Int {
        immersivePreviewPlaylist?.tracks.count ?? 0
    }
    private var immersivePreviewCurrentIndex: Int? {
        guard viewModel.currentPlayingPlaylistID == immersivePreviewPlaylist?.id else { return nil }
        return viewModel.currentIndex
    }
    private var immersivePreviewTracks: [(index: Int, track: AudioTrack)] {
        guard let tracks = immersivePreviewPlaylist?.tracks else { return [] }
        return Array(tracks.enumerated()).map { (index: $0.offset, track: $0.element) }
    }
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
    private var rootPadding: CGFloat {
        switch viewModel.interfaceMode {
        case .compact:
            return 14
        case .full:
            return 20
        case .immersive:
            return 0
        }
    }

    private var minimumContentSize: CGSize {
        switch viewModel.interfaceMode {
        case .compact:
            return CGSize(width: 380, height: 720)
        case .full:
            return CGSize(width: 1320, height: 780)
        case .immersive:
            return CGSize(width: 960, height: 620)
        }
    }

    private var currentTrackPath: String? {
        viewModel.currentTrack?.url.standardizedFileURL.path
    }

    private var canLocateCurrentTrack: Bool {
        currentTrackPath != nil && viewModel.currentPlayingPlaylistID != nil
    }

    private var playlistThemeKey: String {
        viewModel.appTheme.rawValue + "|" + (colorScheme == .dark ? "dark" : "light")
    }

    var body: some View {
        Group {
            switch viewModel.interfaceMode {
            case .compact:
                compactLayout
            case .full:
                fullLayout
            case .immersive:
                immersiveLayout
            }
        }
        .background(WindowAccessor(window: $hostWindow))
        .padding(rootPadding)
        .frame(
            minWidth: minimumContentSize.width,
            minHeight: minimumContentSize.height
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
        .onChange(of: viewModel.currentTrack?.url.standardizedFileURL.path) { _ in
            lyricScrollAnchor = .center
            suppressLyricAutoScrollAnimation = true
            isImmersiveMetadataControlsVisible = false
            if viewModel.currentPlayingPlaylistID == viewModel.selectedPlaylistID {
                requestPlaylistLocateToCurrent(animated: true)
            }
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
            if viewModel.currentPlayingPlaylistID == viewModel.selectedPlaylistID {
                requestPlaylistLocateToCurrent(animated: false)
            }
        }
        .onChange(of: viewModel.interfaceMode) { newValue in
            if newValue != .immersive {
                isImmersiveVolumeExpanded = false
                isImmersivePlaylistPreviewPresented = false
                isImmersiveMetadataControlsVisible = false
                if viewModel.currentPlayingPlaylistID == viewModel.selectedPlaylistID {
                    requestPlaylistLocateToCurrent(animated: false)
                }
            }
            resizeWindowIfNeeded(for: newValue)
        }
        .onChange(of: hostWindow) { _ in
            resizeWindowIfNeeded(for: viewModel.interfaceMode)
        }
        .onChange(of: viewModel.playlists) { _ in
            refreshPlaylistDerivedState()
        }
        .onChange(of: viewModel.selectedPlaylistID) { _ in
            selectedArtistFilter = allArtistsLabel
            selectedAlbumFilter = allAlbumsLabel
            playlistSearchText = ""
            refreshPlaylistDerivedState()
            if viewModel.currentPlayingPlaylistID == viewModel.selectedPlaylistID {
                requestPlaylistLocateToCurrent(animated: false)
            }
        }
        .onChange(of: viewModel.appLanguage) { _ in
            selectedArtistFilter = allArtistsLabel
            selectedAlbumFilter = allAlbumsLabel
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
            ListeningHistorySheet(viewModel: viewModel, theme: theme, language: language)
        }
        .sheet(isPresented: $isCreatePlaylistSheetPresented, onDismiss: {
            newPlaylistName = ""
            pendingTrackForNewPlaylist = nil
        }) {
            createPlaylistSheet
        }
        .alert(tr("删除歌单", "Delete Playlist"), isPresented: $isDeletePlaylistAlertPresented) {
            Button(tr("取消", "Cancel"), role: .cancel) {}
            Button(tr("删除", "Delete"), role: .destructive) {
                viewModel.removeSelectedPlaylist()
            }
        } message: {
            Text(tr("确定删除“\(viewModel.selectedPlaylistName)”吗？该歌单中的待播项目也会一并移除。", "Delete \"\(viewModel.selectedPlaylistName)\"? Queued tracks from this playlist will also be removed."))
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

    private var immersiveLayout: some View {
        GeometryReader { geometry in
            let size = geometry.size
            let compactHeight = size.height < 700
            let compactWidth = size.width < 1120
            let horizontalPadding = clamp(size.width * (compactWidth ? 0.042 : 0.05), min: 20, max: 56)
            let topPadding = clamp(size.height * 0.035, min: 16, max: 28)
            let bottomPadding = clamp(size.height * 0.028, min: 16, max: 26)
            let leftWidth = clamp(size.width * (compactWidth ? 0.36 : 0.33), min: 280, max: 420)
            let discSize = clamp(
                min(size.width * (compactWidth ? 0.29 : 0.31), size.height * (compactHeight ? 0.31 : 0.39)),
                min: 180,
                max: 380
            )
            let lyricWidth = clamp(size.width * (compactWidth ? 0.27 : 0.24), min: 200, max: 280)
            let lyricHeight = clamp(size.height * (compactHeight ? 0.42 : 0.52), min: 240, max: 420)
            let contentSpacing = clamp(size.width * 0.04, min: 16, max: 44)
            let titleFontSize = clamp(size.width * 0.021, min: compactHeight ? 20 : 22, max: 34)
            let lyricProminentFont = clamp(min(size.width * 0.021, size.height * 0.04), min: 20, max: 34)
            let lyricRegularFont = clamp(lyricProminentFont * 0.62, min: 15, max: 22)
            let lyricTimestampWidth = clamp(size.width * 0.036, min: 36, max: 52)
            let transportWidth = clamp(size.width * 0.36, min: 300, max: 430)
            let discInfoSpacing = clamp(size.height * 0.016, min: 10, max: 18)
            let topSectionSpacing = clamp(size.height * 0.016, min: 8, max: 18)
            let bottomSectionSpacing = clamp(size.height * 0.012, min: 6, max: 14)
            let sidePanelWidth = viewModel.isEqualizerExpanded
                ? clamp(size.width * (compactWidth ? 0.32 : 0.3), min: 260, max: 380)
                : lyricWidth
            let sidePanelHeight = viewModel.isEqualizerExpanded
                ? clamp(size.height * (compactHeight ? 0.35 : 0.44), min: 210, max: 340)
                : lyricHeight

            VStack(spacing: 0) {
                immersiveHeader

                Spacer(minLength: topSectionSpacing)

                HStack(alignment: .center, spacing: contentSpacing) {
                    VStack(spacing: discInfoSpacing) {
                        SpinningVinylDisc(
                            artwork: viewModel.currentArtwork,
                            theme: theme,
                            usesImageBackground: usesImageBackground,
                            size: discSize,
                            isPlaying: viewModel.isPlaying,
                            tapHint: tr("点击封面退出沉浸式模式", "Click the artwork to exit immersive mode")
                        ) {
                            viewModel.toggleImmersiveMode()
                        }

                        immersiveTrackInfoSection(titleFontSize: titleFontSize)
                    }
                    .frame(width: leftWidth)

                    Group {
                        if viewModel.isEqualizerExpanded {
                            equalizerSection(isImmersive: true)
                        } else {
                            immersiveLyricsPanel(
                                contentPadding: clamp(size.height * 0.02, min: 12, max: 18),
                                rowSpacing: clamp(size.height * 0.012, min: 8, max: 14),
                                prominentFontSize: lyricProminentFont,
                                regularFontSize: lyricRegularFont,
                                timestampWidth: lyricTimestampWidth
                            )
                        }
                    }
                    .frame(width: sidePanelWidth, height: sidePanelHeight, alignment: .top)
                }
                .frame(maxWidth: .infinity)

                Spacer(minLength: bottomSectionSpacing)

                immersiveTransportSection(maxWidth: transportWidth, compact: compactHeight)
                    .frame(maxWidth: .infinity, alignment: .center)
            }
            .padding(.horizontal, horizontalPadding)
            .padding(.top, topPadding)
            .padding(.bottom, bottomPadding)
            .frame(width: size.width, height: size.height)
            .overlay(alignment: .topTrailing) {
                if isImmersivePlaylistPreviewPresented {
                    immersivePlaylistPreviewPanel
                        .padding(.top, topPadding + 40)
                        .padding(.trailing, horizontalPadding + 132)
                        .transition(.opacity.combined(with: .scale(scale: 0.98, anchor: .topTrailing)))
                        .zIndex(10)
                }
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private var header: some View {
        HStack(spacing: 14) {
            VStack(alignment: .leading, spacing: 6) {
                Text("Zephyr Player")
                    .font(.system(size: 30, weight: .bold, design: .serif))
                    .italic()
                    .tracking(0.8)
            }

            Spacer(minLength: 12)

            HStack(spacing: 8) {
                playlistSwitcher

                compactHeaderIconButton {
                    viewModel.isEqualizerExpanded.toggle()
                } label: {
                    Image(systemName: viewModel.isEqualizerExpanded ? "slider.horizontal.below.square.filled.and.square" : "slider.horizontal.3")
                }
                .help(viewModel.isEqualizerExpanded ? tr("隐藏均衡器", "Hide equalizer") : tr("显示均衡器", "Show equalizer"))

                dataTransferMenu

                batchScrapeHeaderButton
                .disabled(viewModel.playlist.isEmpty)
                .help(viewModel.isBatchScrapingMissingMetadata ? viewModel.batchScrapeProgressText : tr("为当前歌单缺失的歌词和封面一键刮削", "Auto scrape missing lyrics and artwork for the selected playlist"))

                themeMenu

                compactHeaderIconButton {
                    viewModel.toggleInterfaceMode()
                } label: {
                    Image(systemName: viewModel.interfaceMode.symbolName)
                }
                .help(viewModel.interfaceMode.title(in: language))

                compactHeaderIconButton {
                    isHistorySheetPresented = true
                } label: {
                    Image(systemName: "clock.arrow.circlepath")
                }
                .help(tr("听歌历史", "Listening History"))

                Menu {
                    Button(tr("添加音频", "Add Audio")) {
                        viewModel.openFiles()
                    }

                    Button(tr("扫描文件夹", "Scan Folder")) {
                        viewModel.openFolder()
                    }
                } label: {
                    compactHeaderIconLabel(systemName: "plus.circle")
                }
                .menuStyle(.borderlessButton)
                .menuIndicator(.hidden)
                .help(tr("添加音频或扫描文件夹", "Add audio or scan folders"))
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(18)
        .background(panelBackground(primary: true))
    }

    private var compactHeader: some View {
        HStack(spacing: 8) {
            playlistSwitcher
                .frame(maxWidth: .infinity)

            HStack(spacing: 8) {
                Menu {
                    Button(tr("添加歌曲", "Add Songs")) {
                        viewModel.openFiles()
                    }

                    Button(tr("添加文件夹", "Add Folder")) {
                        viewModel.openFolder()
                    }

                    Menu(tr("从歌单添加", "Add From Playlist")) {
                        ForEach(viewModel.playlists.filter { $0.id != viewModel.selectedPlaylistID }) { playlist in
                            Button(viewModel.displayName(for: playlist)) {
                                viewModel.addTracks(fromPlaylist: playlist.id)
                            }
                        }
                    }
                } label: {
                    compactHeaderIconLabel(systemName: "plus.circle")
                }
                .menuStyle(.borderlessButton)
                .menuIndicator(.hidden)

                compactHeaderIconButton {
                    viewModel.searchArtworkOnlineForCurrentTrack()
                } label: {
                    Image(systemName: viewModel.isSearchingArtworkOnline ? "arrow.trianglehead.2.clockwise.rotate.90" : "magnifyingglass")
                }
                .disabled(viewModel.currentTrack == nil || viewModel.isSearchingArtworkOnline)
                .help(tr("在线搜索当前歌曲封面", "Search artwork online for the current track"))

                Menu {
                    artworkSourceMenuContent
                } label: {
                    compactHeaderIconLabel(systemName: "photo.on.rectangle")
                }
                .menuStyle(.borderlessButton)
                .menuIndicator(.hidden)
                .disabled(viewModel.availableArtworkSources.isEmpty && viewModel.onlineArtworkSearchResults.isEmpty)
                .help(tr("切换当前歌曲封面", "Switch artwork source for the current track"))

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
                .menuStyle(.borderlessButton)
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
        .padding(.horizontal, 12)
        .padding(.vertical, 10)
        .background(panelBackground(primary: true))
    }

    private var nowPlayingCard: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(alignment: .center, spacing: 18) {
                VStack(alignment: .leading, spacing: 10) {
                    immersiveToggleArtworkButton(size: 134, cornerRadius: 20)

                    VStack(alignment: .leading, spacing: 4) {
                        Text(artworkPanelStatusText)
                            .font(.caption)
                            .foregroundStyle(theme.secondaryText)
                            .lineLimit(1)

                        artworkControls(compact: false)
                    }
                    .frame(width: 190, alignment: .leading)
                }

                VStack(alignment: .leading, spacing: 14) {
                    Text(tr("正在播放", "Now Playing"))
                        .font(.headline)

                    Text(viewModel.currentTrack?.title ?? tr("未选择歌曲", "No Track Selected"))
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
                VStack(alignment: .leading, spacing: 6) {
                    immersiveToggleArtworkButton(size: 54, cornerRadius: 12)
                    artworkControls(
                        compact: true,
                        showsOnlineSearchButton: false,
                        showsSourceSwitcher: false
                    )
                }

                VStack(alignment: .leading, spacing: 4) {
                    Text(viewModel.currentTrack?.title ?? tr("未选择歌曲", "No Track Selected"))
                        .font(.subheadline.weight(.semibold))
                        .lineLimit(1)

                    Text(nowPlayingSubtitle)
                        .font(.caption)
                        .foregroundStyle(theme.secondaryText)
                        .lineLimit(1)
                }

                Spacer(minLength: 0)

                Text(viewModel.isPlaying ? tr("播放中", "Playing") : tr("暂停", "Paused"))
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
            .help(playbackShortcutHelp(for: .previousTrack, "上一首", "Previous"))
            .fixedSize()

            Button {
                viewModel.togglePlayback()
            } label: {
                Label(viewModel.isPlaying ? tr("暂停", "Pause") : tr("播放", "Play"),
                      systemImage: viewModel.isPlaying ? "pause.fill" : "play.fill")
            }
            .help(playbackShortcutHelp(for: .playPause, viewModel.isPlaying ? "暂停" : "播放", viewModel.isPlaying ? "Pause" : "Play"))
            .fixedSize()

            Button {
                viewModel.playNext()
            } label: {
                Image(systemName: "forward.fill")
            }
            .help(playbackShortcutHelp(for: .nextTrack, "下一首", "Next"))
            .fixedSize()

            Button {
                viewModel.cyclePlaybackMode()
            } label: {
                Label(viewModel.playbackMode.title(in: language), systemImage: viewModel.playbackMode.symbolName)
            }
            .fixedSize()

            playbackRateControl
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
                    viewModel.isDesktopLyricsVisible ? tr("关闭桌面歌词", "Hide Desktop Lyrics") : tr("桌面歌词", "Desktop Lyrics"),
                    systemImage: viewModel.isDesktopLyricsVisible ? "rectangle.on.rectangle.slash" : "rectangle.on.rectangle"
                )
            }
            .fixedSize()

            Button {
                viewModel.isEqualizerExpanded.toggle()
            } label: {
                Label(viewModel.isEqualizerExpanded ? tr("收起均衡器", "Hide Equalizer") : tr("展开均衡器", "Show Equalizer"), systemImage: "slider.horizontal.3")
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
            .help(playbackShortcutHelp(for: .previousTrack, "上一首", "Previous"))

            Button {
                viewModel.togglePlayback()
            } label: {
                Image(systemName: viewModel.isPlaying ? "pause.fill" : "play.fill")
            }
            .help(playbackShortcutHelp(for: .playPause, viewModel.isPlaying ? "暂停" : "播放", viewModel.isPlaying ? "Pause" : "Play"))

            Button {
                viewModel.playNext()
            } label: {
                Image(systemName: "forward.fill")
            }
            .help(playbackShortcutHelp(for: .nextTrack, "下一首", "Next"))

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
        equalizerSection(isImmersive: false)
    }

    private func equalizerSection(isImmersive: Bool) -> some View {
        VStack(alignment: .leading, spacing: isImmersive ? 14 : 16) {
            HStack(alignment: .top, spacing: 12) {
                VStack(alignment: .leading, spacing: 4) {
                    Text(tr("均衡器", "Equalizer"))
                        .font(.headline)

                    Text(viewModel.currentEqualizerPresetDisplayName)
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(theme.secondaryText)
                }

                Spacer(minLength: 12)

                HStack(spacing: 8) {
                    equalizerStatusChip(
                        title: viewModel.isEqualizerEnabled ? tr("已启用", "Enabled") : tr("已关闭", "Disabled"),
                        systemName: viewModel.isEqualizerEnabled ? "waveform.path" : "waveform.path.badge.minus"
                    )

                    Button {
                        viewModel.resetEqualizer()
                    } label: {
                        equalizerControlPill(
                            title: tr("重置", "Reset"),
                            systemName: "arrow.counterclockwise",
                            active: false,
                            isImmersive: isImmersive
                        )
                    }
                    .buttonStyle(.plain)
                }
            }

            HStack(spacing: 10) {
                Button {
                    viewModel.isEqualizerEnabled.toggle()
                } label: {
                    equalizerControlPill(
                        title: viewModel.isEqualizerEnabled ? tr("关闭", "Disable") : tr("启用", "Enable"),
                        systemName: viewModel.isEqualizerEnabled ? "bolt.slash" : "bolt",
                        active: viewModel.isEqualizerEnabled,
                        isImmersive: isImmersive
                    )
                }
                .buttonStyle(.plain)

                Menu {
                    equalizerPresetMenuContent
                } label: {
                    equalizerControlPill(
                        title: tr("预设", "Preset") + " · " + viewModel.currentEqualizerPresetDisplayName,
                        systemName: "dial.medium",
                        active: false,
                        isImmersive: isImmersive
                    )
                }
                .menuStyle(.borderlessButton)
                .menuIndicator(.hidden)

                Button {
                    viewModel.promptToSaveCurrentEqualizerPreset()
                } label: {
                    equalizerControlPill(
                        title: tr("保存风格", "Save Style"),
                        systemName: "square.and.arrow.down",
                        active: false,
                        isImmersive: isImmersive
                    )
                }
                .buttonStyle(.plain)

                if let savedPreset = viewModel.selectedSavedEqualizerPreset {
                    Button {
                        viewModel.removeSavedEqualizerPreset(savedPreset.id)
                    } label: {
                        equalizerControlPill(
                            title: tr("删除风格", "Delete Style"),
                            systemName: "trash",
                            active: false,
                            isImmersive: isImmersive
                        )
                    }
                    .buttonStyle(.plain)
                }

                Spacer(minLength: 0)

                Text(tr("向上提亮，向下压低", "Lift for brightness, pull down for warmth"))
                    .font(.caption)
                    .foregroundStyle(theme.secondaryText)
                    .lineLimit(1)
                    .minimumScaleFactor(0.75)
            }

            ScrollView(.horizontal, showsIndicators: false) {
                HStack(alignment: .top, spacing: isImmersive ? 10 : 12) {
                    ForEach(Array(viewModel.equalizerBands.enumerated()), id: \.element.id) { index, band in
                        EqualizerBandCard(
                            band: band,
                            theme: theme,
                            isEnabled: viewModel.isEqualizerEnabled,
                            isImmersive: isImmersive
                        ) { newGain in
                            viewModel.updateEqualizerBandGain(at: index, gain: Float(newGain))
                        }
                    }
                }
                .padding(.horizontal, isImmersive ? 2 : 4)
                .padding(.vertical, 4)
            }
        }
        .padding(isImmersive ? 0 : 18)
        .background {
            if !isImmersive {
                panelBackground(primary: false)
            }
        }
    }

    private func equalizerStatusChip(title: String, systemName: String) -> some View {
        HStack(spacing: 6) {
            Image(systemName: systemName)
            Text(title)
        }
        .font(.caption.weight(.semibold))
        .foregroundStyle(viewModel.isEqualizerEnabled ? theme.accent : theme.secondaryText)
        .padding(.horizontal, 10)
        .padding(.vertical, 6)
        .background(
            Capsule(style: .continuous)
                .fill(viewModel.isEqualizerEnabled ? theme.accentSoft.opacity(0.34) : theme.panelSecondary.opacity(0.72))
        )
    }

    private func equalizerControlPill(
        title: String,
        systemName: String,
        active: Bool,
        isImmersive: Bool
    ) -> some View {
        HStack(spacing: 6) {
            Image(systemName: systemName)
            Text(title)
                .lineLimit(1)
        }
        .font(.caption.weight(.semibold))
        .foregroundStyle(active ? theme.accent : theme.primaryText)
        .padding(.horizontal, isImmersive ? 10 : 12)
        .padding(.vertical, 7)
        .background(
            Capsule(style: .continuous)
                .fill(active ? theme.accentSoft.opacity(0.42) : theme.panelSecondary.opacity(isImmersive ? 0.52 : 0.78))
        )
        .overlay(
            Capsule(style: .continuous)
                .stroke(active ? theme.accent.opacity(0.22) : theme.border.opacity(isImmersive ? 0.28 : 0.8), lineWidth: 1)
        )
    }

    @ViewBuilder
    private var equalizerPresetMenuContent: some View {
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

            Menu(tr("删除自定义预设", "Delete Saved Preset")) {
                ForEach(viewModel.userEqualizerPresets) { preset in
                    Button(role: .destructive) {
                        viewModel.removeSavedEqualizerPreset(preset.id)
                    } label: {
                        Text(preset.name)
                    }
                }
            }
        }
    }

    private var playlistList: some View {
        PlaylistListView(
            items: filteredPlaylist,
            currentPlaylistID: viewModel.selectedPlaylistID,
            currentPlayingPlaylistID: viewModel.currentPlayingPlaylistID,
            currentIndex: viewModel.currentIndex,
            isPlaying: viewModel.isPlaying,
            queuedTrackPaths: Set(viewModel.queuedTrackPaths),
            query: playlistSearchText,
            theme: theme,
            themeKey: playlistThemeKey,
            language: language,
            playlistDestinations: playlistCopyDestinations,
            scrollRequestToken: playlistScrollRequestToken,
            scrollTargetPath: playlistScrollTargetPath,
            scrollAnimated: playlistScrollAnimated
        ) { track in
            viewModel.playSelected(track: track)
        } queueNextAction: { track in
            viewModel.queueTrackNext(track, in: viewModel.selectedPlaylistID)
        } addToNewPlaylistAction: { track in
            presentCreatePlaylistSheet(adding: track)
        } addToPlaylistAction: { track, playlistID in
            viewModel.addTrack(track, to: playlistID)
        } removeAction: { offsets in
            removeFilteredTracks(at: offsets)
        }
        .equatable()
    }

    private var playlistSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            playlistHeader
            playlistSearchBar
            playlistFilters

            playlistList
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
                                Label(option.title(in: language), systemImage: "checkmark")
                            } else {
                                Text(option.title(in: language))
                            }
                        }
                    }
                } label: {
                    filterMenuLabel(sortOption.title(in: language))
                }
            }
            .font(.caption)
            .menuStyle(.borderlessButton)

            playlistList
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .padding(12)
        .background(panelBackground(primary: false))
    }

    private var playlistHeader: some View {
        HStack(alignment: .center) {
            VStack(alignment: .leading, spacing: 4) {
                Text(tr("播放列表", "Playlist"))
                    .font(.headline)
                Text(viewModel.selectedPlaylistName)
                    .font(.caption)
                    .foregroundStyle(theme.secondaryText)
            }
            Spacer()
            HStack(spacing: 10) {
                playlistLocateCurrentButton

                Text(tr("\(filteredPlaylist.count) / \(viewModel.playlist.count) 首", "\(filteredPlaylist.count) / \(viewModel.playlist.count) tracks"))
                    .foregroundStyle(theme.secondaryText)
            }
        }
    }

    private var compactPlaylistBar: some View {
        HStack(spacing: 8) {
            Text(viewModel.selectedPlaylistName)
                .font(.subheadline.weight(.semibold))
                .lineLimit(1)
                .frame(minWidth: 110, alignment: .leading)

            playlistLocateCurrentButton

            playlistSearchBarCompact
        }
    }

    private var playlistLocateCurrentButton: some View {
        Button {
            requestPlaylistLocateToCurrent(animated: true, ensureCurrentPlaylistSelected: true, resetFilters: true)
        } label: {
            Image(systemName: "scope")
                .symbolRenderingMode(.monochrome)
                .foregroundStyle(canLocateCurrentTrack ? theme.accent : theme.secondaryText)
        }
        .buttonStyle(.plain)
        .help(tr("定位到正在播放", "Locate Now Playing"))
        .disabled(!canLocateCurrentTrack)
    }

    private var playlistSwitcher: some View {
        HStack(spacing: 8) {
            Menu {
                ForEach(viewModel.playlists) { playlist in
                    Button {
                        viewModel.selectedPlaylistID = playlist.id
                    } label: {
                        if viewModel.selectedPlaylistID == playlist.id {
                            Label(viewModel.displayName(for: playlist), systemImage: "checkmark")
                        } else {
                            Text(viewModel.displayName(for: playlist))
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
            .frame(width: playlistSwitcherWidth)
            .menuStyle(.borderlessButton)
            .menuIndicator(viewModel.interfaceMode == .compact ? .hidden : .visible)

            Button {
                presentCreatePlaylistSheet()
            } label: {
                compactHeaderIconLabel(systemName: "text.badge.plus")
            }
            .buttonStyle(.plain)
            .help(tr("新建歌单", "New Playlist"))

            Button {
                isDeletePlaylistAlertPresented = true
            } label: {
                compactHeaderIconLabel(systemName: "trash")
            }
            .buttonStyle(.plain)
            .help(tr("删除当前歌单", "Delete Current Playlist"))
            .disabled(viewModel.playlists.count <= 1)
        }
    }

    private var playlistSearchBar: some View {
        HStack(spacing: 10) {
            Image(systemName: "magnifyingglass")
                .foregroundStyle(theme.secondaryText)

            TextField(tr("搜索歌曲、格式或文件夹", "Search songs, formats, or folders"), text: $playlistSearchText)
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

            TextField(tr("搜索", "Search"), text: $playlistSearchText)
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
                            Label(option.title(in: language), systemImage: "checkmark")
                        } else {
                            Text(option.title(in: language))
                        }
                    }
                }
            } label: {
                filterMenuLabel(sortOption.title(in: language))
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

    private func requestPlaylistLocateToCurrent(
        animated: Bool,
        ensureCurrentPlaylistSelected: Bool = false,
        resetFilters: Bool = false
    ) {
        guard let targetPath = currentTrackPath else { return }

        if ensureCurrentPlaylistSelected {
            viewModel.selectCurrentPlayingPlaylist()
        }

        if resetFilters {
            selectedArtistFilter = allArtistsLabel
            selectedAlbumFilter = allAlbumsLabel
            playlistSearchText = ""
            refreshPlaylistDerivedState()
        }

        playlistScrollTargetPath = targetPath
        playlistScrollAnimated = animated
        playlistScrollRequestToken = UUID()
    }

    private func playbackShortcutHelp(
        for action: PlaybackShortcutAction,
        _ chinese: String,
        _ english: String
    ) -> String {
        tr(chinese, english) + " · " + viewModel.playbackShortcutDisplayText(for: action)
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
        .buttonStyle(.plain)
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
            .symbolRenderingMode(.monochrome)
            .frame(width: 24, height: 18)
            .foregroundStyle(theme.primaryText)
            .labelStyle(.iconOnly)
            .controlSize(.small)
            .font(.system(size: 12, weight: .semibold))
    }

    private var batchScrapeHeaderButton: some View {
        Button {
            viewModel.scrapeMissingMetadataInSelectedPlaylist()
        } label: {
            ZStack {
                if viewModel.isBatchScrapingMissingMetadata {
                    Circle()
                        .stroke(theme.border.opacity(0.65), lineWidth: 2)

                    Circle()
                        .trim(from: 0, to: batchScrapeProgressValue)
                        .stroke(
                            theme.accent,
                            style: StrokeStyle(lineWidth: 2, lineCap: .round)
                        )
                        .rotationEffect(.degrees(-90))
                }

                Image(systemName: "wand.and.stars")
                    .symbolRenderingMode(.monochrome)
                    .foregroundStyle(theme.primaryText)
                    .font(.system(size: 12, weight: .semibold))
            }
            .frame(width: 24, height: 24)
        }
        .buttonStyle(.plain)
        .controlSize(.small)
    }

    private var batchScrapeProgressValue: CGFloat {
        guard viewModel.batchScrapeTargetCount > 0 else { return 0 }
        return min(max(CGFloat(viewModel.batchScrapeCompletedCount) / CGFloat(viewModel.batchScrapeTargetCount), 0), 1)
    }

    private var immersiveHeader: some View {
        HStack(alignment: .top, spacing: 12) {
            VStack(alignment: .leading, spacing: 6) {
                Text("Zephyr Player")
                    .font(.system(size: 24, weight: .bold, design: .serif))
                    .italic()
                    .tracking(0.6)

                Text(tr("沉浸式模式", "Immersive Mode"))
                    .font(.caption.weight(.medium))
                    .foregroundStyle(theme.secondaryText)

                immersivePlaylistSwitcher
            }

            Spacer()

            HStack(spacing: 12) {
                immersivePlaylistPreviewTrigger

                immersiveMetadataSearchButton

                immersiveHeaderIconButton(
                    systemName: viewModel.isDesktopLyricsVisible ? "quote.bubble.fill" : "quote.bubble",
                    helpText: viewModel.isDesktopLyricsVisible
                        ? tr("关闭桌面歌词", "Hide desktop lyrics")
                        : tr("开启桌面歌词", "Show desktop lyrics"),
                    emphasized: viewModel.isDesktopLyricsVisible
                ) {
                    viewModel.isDesktopLyricsVisible.toggle()
                }

                immersiveHeaderIconButton(
                    systemName: viewModel.isEqualizerExpanded ? "slider.horizontal.below.square.filled.and.square" : "slider.horizontal.3",
                    helpText: viewModel.isEqualizerExpanded
                        ? tr("隐藏均衡器", "Hide equalizer")
                        : tr("显示均衡器", "Show equalizer"),
                    emphasized: viewModel.isEqualizerExpanded
                ) {
                    withAnimation(.easeInOut(duration: 0.22)) {
                        viewModel.isEqualizerExpanded.toggle()
                    }
                }

                immersiveThemeMenu

                immersiveHeaderIconButton(
                    systemName: "xmark",
                    helpText: tr("退出沉浸式模式", "Exit immersive mode"),
                    emphasized: false
                ) {
                    viewModel.toggleImmersiveMode()
                }
            }
        }
        .zIndex(2)
    }

    private var immersivePlaylistPreviewTrigger: some View {
        Button {
            withAnimation(.easeInOut(duration: 0.18)) {
                isImmersivePlaylistPreviewPresented.toggle()
            }
        } label: {
            immersiveIconLabel(systemName: "music.note.list", emphasized: isImmersivePlaylistPreviewPresented)
        }
        .buttonStyle(.plain)
        .help(tr("查看当前播放歌单", "View now playing playlist"))
        .onHover { hovering in
            if hovering {
                showImmersivePlaylistPreview()
            } else {
                scheduleImmersivePlaylistPreviewHide()
            }
        }
    }

    private var immersivePlaylistSwitcher: some View {
        Menu {
            ForEach(viewModel.playlists) { playlist in
                Button {
                    viewModel.selectedPlaylistID = playlist.id
                } label: {
                    if viewModel.selectedPlaylistID == playlist.id {
                        Label(viewModel.displayName(for: playlist), systemImage: "checkmark")
                    } else {
                        Text(viewModel.displayName(for: playlist))
                    }
                }
            }
        } label: {
            HStack(spacing: 6) {
                Text(viewModel.selectedPlaylistName)
                    .font(.subheadline.weight(.semibold))
                    .lineLimit(1)

                Image(systemName: "chevron.down")
                    .font(.caption.weight(.semibold))
            }
            .foregroundStyle(theme.primaryText)
        }
        .menuStyle(.borderlessButton)
        .menuIndicator(.hidden)
    }

    private var immersiveMetadataSearchButton: some View {
        Button {
            isImmersiveMetadataControlsVisible = true
            viewModel.searchOnlineMetadataForCurrentTrack()
        } label: {
            Group {
                if viewModel.isSearchingOnlineMetadata {
                    ProgressView()
                        .controlSize(.small)
                        .scaleEffect(0.78)
                        .frame(width: 24, height: 18)
                } else {
                    immersiveIconLabel(systemName: "magnifyingglass", emphasized: immersiveMetadataSearchEmphasized)
                }
            }
        }
        .buttonStyle(.plain)
        .disabled(viewModel.currentTrack == nil || viewModel.isSearchingOnlineMetadata)
        .help(tr("在线搜索歌词和封面", "Search lyrics and artwork online"))
    }

    private var immersiveThemeMenu: some View {
        Menu {
            themeMenuContent
        } label: {
            immersiveIconLabel(systemName: "paintpalette")
        }
        .menuStyle(.borderlessButton)
        .menuIndicator(.hidden)
    }

    private var immersivePlaylistPreviewPanel: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(alignment: .firstTextBaseline) {
                VStack(alignment: .leading, spacing: 4) {
                    Text(tr("当前播放歌单", "Now Playing Playlist"))
                        .font(.headline)
                        .lineLimit(1)

                    Text(immersivePreviewSubtitle)
                        .font(.caption)
                        .foregroundStyle(theme.secondaryText)
                        .lineLimit(1)
                }

                Spacer(minLength: 12)

                Image(systemName: "music.note.list")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(theme.secondaryText)
            }

            if immersivePreviewTracks.isEmpty {
                Text(tr("当前歌单还没有歌曲", "This playlist is empty"))
                    .font(.subheadline)
                    .foregroundStyle(theme.secondaryText)
                    .padding(.vertical, 18)
            } else {
                ScrollViewReader { proxy in
                    ScrollView(.vertical, showsIndicators: true) {
                        LazyVStack(alignment: .leading, spacing: 6) {
                            ForEach(immersivePreviewTracks, id: \.index) { item in
                                HStack(spacing: 10) {
                                    Text("\(item.index + 1)")
                                        .font(.caption.monospacedDigit())
                                        .foregroundStyle(isImmersivePreviewTrackCurrent(item.index) ? theme.accent : theme.secondaryText)
                                        .frame(width: 20, alignment: .leading)

                                    VStack(alignment: .leading, spacing: 3) {
                                        Text(item.track.title)
                                            .font(.subheadline.weight(isImmersivePreviewTrackCurrent(item.index) ? .semibold : .medium))
                                            .foregroundStyle(isImmersivePreviewTrackCurrent(item.index) ? theme.accent : theme.primaryText)
                                            .lineLimit(1)

                                        Text([
                                            item.track.artist ?? tr("未知艺术家", "Unknown Artist"),
                                            item.track.album ?? tr("未知专辑", "Unknown Album")
                                        ].joined(separator: " · "))
                                        .font(.caption)
                                        .foregroundStyle(theme.secondaryText)
                                        .lineLimit(1)
                                    }

                                    Spacer(minLength: 0)

                                    Button {
                                        viewModel.queueTrackNext(item.track, in: immersivePreviewPlaylistID)
                                    } label: {
                                        Image(systemName: isImmersivePreviewTrackQueued(item.track) ? "checkmark.circle.fill" : "plus.circle")
                                            .symbolRenderingMode(.monochrome)
                                            .font(.caption.weight(.semibold))
                                            .foregroundStyle(isImmersivePreviewTrackQueued(item.track) ? theme.accent : theme.secondaryText)
                                            .frame(width: 18, height: 18)
                                    }
                                    .buttonStyle(.plain)
                                    .help(tr("添加到下一首播放", "Play next"))

                                    if isImmersivePreviewTrackCurrent(item.index) {
                                        Image(systemName: viewModel.isPlaying ? "waveform" : "pause.fill")
                                            .font(.caption.weight(.bold))
                                            .foregroundStyle(theme.accent)
                                    }
                                }
                                .padding(.horizontal, 10)
                                .padding(.vertical, 8)
                                .background(
                                    RoundedRectangle(cornerRadius: 14, style: .continuous)
                                        .fill(isImmersivePreviewTrackCurrent(item.index) ? theme.accentSoft.opacity(0.26) : .clear)
                                )
                                .contentShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
                                .help(tr("点击播放", "Click to play"))
                                .onTapGesture {
                                    viewModel.play(track: item.track, in: immersivePreviewPlaylistID)
                                }
                                .id(item.index)
                            }
                        }
                    }
                    .frame(maxHeight: 300)
                    .onAppear {
                        scrollImmersivePlaylistPreviewToCurrent(using: proxy, animated: false)
                    }
                    .onChange(of: immersivePreviewCurrentIndex) { _ in
                        scrollImmersivePlaylistPreviewToCurrent(using: proxy, animated: true)
                    }
                    .onChange(of: immersivePreviewPlaylistID) { _ in
                        scrollImmersivePlaylistPreviewToCurrent(using: proxy, animated: false)
                    }
                    .onChange(of: isImmersivePlaylistPreviewPresented) { isPresented in
                        guard isPresented else { return }
                        scrollImmersivePlaylistPreviewToCurrent(using: proxy, animated: false)
                    }
                }
            }
        }
        .padding(14)
        .frame(width: 320, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: 24, style: .continuous)
                .fill(theme.backgroundBottom.opacity(0.96))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 24, style: .continuous)
                .stroke(theme.border.opacity(0.28), lineWidth: 1)
        )
        .shadow(color: .black.opacity(0.14), radius: 18, x: 0, y: 12)
        .onHover { hovering in
            if hovering {
                showImmersivePlaylistPreview()
            } else {
                scheduleImmersivePlaylistPreviewHide()
            }
        }
    }

    private func immersiveHeaderIconButton(
        systemName: String,
        helpText: String,
        emphasized: Bool = false,
        action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            immersiveIconLabel(systemName: systemName, emphasized: emphasized)
        }
        .buttonStyle(.plain)
        .help(helpText)
    }

    private func showImmersivePlaylistPreview() {
        immersivePlaylistPreviewHideToken = UUID()
        withAnimation(.easeInOut(duration: 0.16)) {
            isImmersivePlaylistPreviewPresented = true
        }
    }

    private func scheduleImmersivePlaylistPreviewHide() {
        let token = UUID()
        immersivePlaylistPreviewHideToken = token
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.18) {
            guard immersivePlaylistPreviewHideToken == token else { return }
            withAnimation(.easeInOut(duration: 0.16)) {
                isImmersivePlaylistPreviewPresented = false
            }
        }
    }

    private var immersivePreviewSubtitle: String {
        if let currentIndex = immersivePreviewCurrentIndex {
            return tr(
                "\(immersivePreviewPlaylistName) · 正在播放第 \(currentIndex + 1) / \(immersivePreviewTrackCount) 首",
                "\(immersivePreviewPlaylistName) · playing \(currentIndex + 1) of \(immersivePreviewTrackCount)"
            )
        }

        return "\(immersivePreviewPlaylistName) · \(tr("\(immersivePreviewTrackCount) 首歌曲", "\(immersivePreviewTrackCount) tracks"))"
    }

    private func scrollImmersivePlaylistPreviewToCurrent(using proxy: ScrollViewProxy, animated: Bool) {
        guard isImmersivePlaylistPreviewPresented, let currentIndex = immersivePreviewCurrentIndex else { return }

        let scrollAction = {
            proxy.scrollTo(currentIndex, anchor: .center)
        }

        if animated {
            withAnimation(.easeInOut(duration: 0.22)) {
                scrollAction()
            }
        } else {
            DispatchQueue.main.async {
                scrollAction()
            }
        }
    }

    private func isImmersivePreviewTrackCurrent(_ index: Int) -> Bool {
        viewModel.currentPlayingPlaylistID == immersivePreviewPlaylist?.id && viewModel.currentIndex == index
    }

    private func isImmersivePreviewTrackQueued(_ track: AudioTrack) -> Bool {
        viewModel.queuedTrackPaths.contains(track.url.standardizedFileURL.path)
    }

    private func immersiveIconLabel(systemName: String, emphasized: Bool = false, compact: Bool = false) -> some View {
        Image(systemName: systemName)
            .symbolRenderingMode(.monochrome)
            .font(
                .system(
                    size: compact ? (emphasized ? 18 : 14) : (emphasized ? 20 : 16),
                    weight: emphasized ? .bold : .semibold
                )
            )
            .foregroundStyle(emphasized ? theme.accent : theme.primaryText)
            .frame(
                width: compact ? (emphasized ? 28 : 22) : (emphasized ? 30 : 24),
                height: compact ? (emphasized ? 28 : 22) : (emphasized ? 30 : 24)
            )
    }

    private func immersiveTrackInfoSection(titleFontSize: CGFloat) -> some View {
        VStack(spacing: 6) {
            Text(viewModel.currentTrack?.title ?? tr("未选择歌曲", "No Track Selected"))
                .font(.system(size: titleFontSize, weight: .bold, design: .rounded))
                .lineLimit(1)
                .multilineTextAlignment(.center)
                .minimumScaleFactor(0.72)

            Text(viewModel.currentTrack?.album ?? tr("未知专辑", "Unknown Album"))
                .font(.body.weight(.medium))
                .foregroundStyle(theme.primaryText.opacity(0.90))
                .multilineTextAlignment(.center)
                .lineLimit(1)
                .minimumScaleFactor(0.78)

            Text(viewModel.currentTrack?.artist ?? tr("未知艺术家", "Unknown Artist"))
                .font(.subheadline.weight(.medium))
                .foregroundStyle(theme.secondaryText)
                .multilineTextAlignment(.center)
                .lineLimit(1)
                .minimumScaleFactor(0.78)

            Text(immersiveTechnicalSummary)
                .font(.caption.weight(.medium))
                .foregroundStyle(theme.secondaryText)
                .multilineTextAlignment(.center)
                .lineLimit(2)
                .minimumScaleFactor(0.8)
                .fixedSize(horizontal: false, vertical: true)

            VStack(spacing: 4) {
                Text(artworkPanelStatusText)
                    .font(.caption2.weight(.medium))
                    .foregroundStyle(theme.secondaryText)
                    .multilineTextAlignment(.center)
                    .lineLimit(1)

                artworkControls(
                    compact: true,
                    showsOnlineSearchButton: false,
                    showsSourceSwitcher: isImmersiveMetadataControlsVisible
                )
            }
        }
        .frame(maxWidth: .infinity)
    }

    private func immersiveTransportSection(maxWidth: CGFloat, compact: Bool) -> some View {
        VStack(spacing: compact ? 10 : 12) {
            transportSlider
                .frame(maxWidth: maxWidth)

            HStack(spacing: compact ? 18 : 24) {
                immersiveTransportButton(
                    systemName: viewModel.playbackMode.symbolName,
                    helpText: viewModel.playbackMode.title(in: language),
                    compact: compact
                ) {
                    viewModel.cyclePlaybackMode()
                }

                immersiveTransportButton(
                    systemName: "backward.fill",
                    helpText: playbackShortcutHelp(for: .previousTrack, "上一首", "Previous"),
                    compact: compact
                ) {
                    viewModel.playPrevious()
                }

                immersiveTransportButton(
                    systemName: viewModel.isPlaying ? "pause.fill" : "play.fill",
                    helpText: playbackShortcutHelp(for: .playPause, viewModel.isPlaying ? "暂停" : "播放", viewModel.isPlaying ? "Pause" : "Play"),
                    emphasized: true,
                    compact: compact
                ) {
                    viewModel.togglePlayback()
                }

                immersiveTransportButton(
                    systemName: "forward.fill",
                    helpText: playbackShortcutHelp(for: .nextTrack, "下一首", "Next"),
                    compact: compact
                ) {
                    viewModel.playNext()
                }

                immersivePlaybackRateControl(compact: compact)

                immersiveVolumeControl(compact: compact)
            }
            .frame(maxWidth: maxWidth)
        }
    }

    private func immersiveTransportButton(
        systemName: String,
        helpText: String,
        emphasized: Bool = false,
        compact: Bool = false,
        action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            immersiveIconLabel(systemName: systemName, emphasized: emphasized, compact: compact)
        }
        .buttonStyle(.plain)
        .help(helpText)
    }

    private func immersiveVolumeControl(compact: Bool) -> some View {
        Button {
            withAnimation(.easeInOut(duration: 0.22)) {
                isImmersiveVolumeExpanded.toggle()
            }
        } label: {
            immersiveIconLabel(systemName: "speaker.wave.2.fill", compact: compact)
        }
        .buttonStyle(.plain)
        .help(tr("显示音量滑块", "Show volume slider"))
        .overlay(alignment: .leading) {
            if isImmersiveVolumeExpanded {
                Slider(value: $viewModel.volume, in: 0...1)
                    .frame(width: compact ? 96 : 112)
                    .controlSize(.small)
                    .offset(x: compact ? 34 : 38)
                    .transition(.move(edge: .trailing).combined(with: .opacity))
            }
        }
        .zIndex(isImmersiveVolumeExpanded ? 1 : 0)
    }

    private var playbackRateControl: some View {
        Menu {
            playbackRateMenuContent
        } label: {
            Label(viewModel.playbackRateDisplayText, systemImage: "speedometer")
        }
        .help(tr("播放倍速", "Playback speed"))
    }

    private func immersivePlaybackRateControl(compact: Bool) -> some View {
        Menu {
            playbackRateMenuContent
        } label: {
            Text(viewModel.playbackRateDisplayText)
                .font(.system(size: compact ? 13 : 14, weight: .semibold, design: .rounded))
                .monospacedDigit()
                .foregroundStyle(viewModel.playbackRate == 1.0 ? theme.primaryText : theme.accent)
                .frame(width: compact ? 42 : 46, height: compact ? 22 : 24)
                .contentShape(Rectangle())
        }
        .menuStyle(.borderlessButton)
        .menuIndicator(.hidden)
        .help(tr("播放倍速", "Playback speed"))
    }

    @ViewBuilder
    private var playbackRateMenuContent: some View {
        ForEach(viewModel.availablePlaybackRates, id: \.self) { rate in
            let title = viewModel.playbackRateText(for: rate)
            Button {
                viewModel.setPlaybackRate(rate)
            } label: {
                if viewModel.playbackRate == rate {
                    Label(title, systemImage: "checkmark")
                } else {
                    Text(title)
                }
            }
        }
    }

    private var immersiveTechnicalTags: [String] {
        var items: [String] = []

        if let bitRate = viewModel.currentBitRateKbps {
            items.append("\(bitRate) kbps")
        }

        if viewModel.playbackSampleRate > 0 {
            items.append(formattedSampleRate(viewModel.playbackSampleRate))
        }

        if viewModel.currentChannelCount > 0 {
            items.append(channelDescription(viewModel.currentChannelCount))
        }

        if let format = viewModel.currentTrack?.fileExtension, !format.isEmpty {
            items.append(format)
        }

        if items.isEmpty {
            items.append(tr("等待加载", "Loading"))
        }

        return items
    }

    private var immersiveTechnicalSummary: String {
        let baseSummary = immersiveTechnicalTags.joined(separator: " · ")
        if viewModel.duration > 0 {
            return baseSummary + " · " + viewModel.formatTime(viewModel.duration)
        }
        return baseSummary
    }

    private func formattedSampleRate(_ sampleRate: Double) -> String {
        let kiloHertz = sampleRate / 1_000
        if kiloHertz >= 100 {
            return String(format: "%.0f kHz", kiloHertz)
        }
        return String(format: "%.1f kHz", kiloHertz)
    }

    private func channelDescription(_ channelCount: Int) -> String {
        switch channelCount {
        case 1:
            return tr("单声道", "Mono")
        case 2:
            return tr("立体声", "Stereo")
        default:
            return tr("\(channelCount) 声道", "\(channelCount) ch")
        }
    }

    private var playlistSwitcherWidth: CGFloat {
        switch viewModel.interfaceMode {
        case .compact:
            return 126
        case .full:
            return 128
        case .immersive:
            return 190
        }
    }

    private func clamp(_ value: CGFloat, min lower: CGFloat, max upper: CGFloat) -> CGFloat {
        Swift.min(Swift.max(value, lower), upper)
    }

    private func immersiveToggleArtworkButton(size: CGFloat, cornerRadius: CGFloat) -> some View {
        Button {
            viewModel.toggleImmersiveMode()
        } label: {
            artworkView(size: size, cornerRadius: cornerRadius)
        }
        .buttonStyle(.plain)
        .help(tr("点击封面进入沉浸式模式", "Click the artwork to enter immersive mode"))
    }

    private func immersiveLyricsPanel(
        contentPadding: CGFloat,
        rowSpacing: CGFloat,
        prominentFontSize: CGFloat,
        regularFontSize: CGFloat,
        timestampWidth: CGFloat
    ) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            lyricsPanelControls(
                compact: true,
                showsOnlineSearchButton: false,
                showsSourceSwitcher: isImmersiveMetadataControlsVisible
            )

            lyricsContent(
                rowSpacing: rowSpacing,
                prominentFontSize: prominentFontSize,
                regularFontSize: regularFontSize,
                timestampWidth: timestampWidth,
                showsTimestamps: false,
                showsRowBackgrounds: false,
                showsScrollIndicators: false
            )
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
            .mask {
                LinearGradient(
                    stops: [
                        .init(color: .clear, location: 0),
                        .init(color: .black, location: 0.08),
                        .init(color: .black, location: 0.92),
                        .init(color: .clear, location: 1)
                    ],
                    startPoint: .top,
                    endPoint: .bottom
                )
            }
        }
        .padding(.vertical, contentPadding)
        .padding(.horizontal, contentPadding * 0.2)
    }

    private var lyricsPanel: some View {
        lyricsPanelCard(
            contentPadding: 22,
            titleFont: .headline,
            rowSpacing: 10,
            prominentFontSize: 28,
            regularFontSize: 20,
            timestampWidth: 46
        )
    }

    private func lyricsPanelCard(
        contentPadding: CGFloat,
        titleFont: Font,
        rowSpacing: CGFloat,
        prominentFontSize: CGFloat,
        regularFontSize: CGFloat,
        timestampWidth: CGFloat
    ) -> some View {
        VStack(alignment: .leading, spacing: 14) {
            lyricsPanelControls(compact: false, titleFont: titleFont)

            lyricsContent(
                rowSpacing: rowSpacing,
                prominentFontSize: prominentFontSize,
                regularFontSize: regularFontSize,
                timestampWidth: timestampWidth
            )
        }
        .padding(contentPadding)
        .background(panelBackground(primary: false))
    }

    @ViewBuilder
    private func lyricsContent(
        rowSpacing: CGFloat,
        prominentFontSize: CGFloat,
        regularFontSize: CGFloat,
        timestampWidth: CGFloat,
        showsTimestamps: Bool = true,
        showsRowBackgrounds: Bool = true,
        showsScrollIndicators: Bool = true
    ) -> some View {
        if !viewModel.lyrics.timedLines.isEmpty {
            ScrollViewReader { proxy in
                ScrollView(.vertical, showsIndicators: showsScrollIndicators) {
                    LazyVStack(alignment: .leading, spacing: rowSpacing) {
                        ForEach(Array(viewModel.lyrics.timedLines.enumerated()), id: \.element.id) { index, line in
                            LyricJumpRow(
                                text: line.text,
                                time: line.time,
                                prominent: index == viewModel.currentLyricIndex,
                                theme: theme,
                                prominentFontSize: prominentFontSize,
                                regularFontSize: regularFontSize,
                                timestampWidth: timestampWidth,
                                showsTimestamp: showsTimestamps,
                                showsBackgrounds: showsRowBackgrounds,
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
                            .animation(suppressLyricAutoScrollAnimation ? nil : .easeInOut(duration: 0.16), value: viewModel.currentLyricIndex)
                        }
                    }
                    .padding(.vertical, 24)
                }
                .onAppear {
                    if let index = viewModel.currentLyricIndex {
                        scrollLyrics(with: proxy, to: index, anchor: .center, animated: false)
                    }
                }
                .onChange(of: viewModel.currentLyricIndex) { newValue in
                    guard let newValue else { return }
                    scrollLyrics(with: proxy, to: newValue, anchor: lyricScrollAnchor, animated: !suppressLyricAutoScrollAnimation)
                    if suppressLyricAutoScrollAnimation {
                        DispatchQueue.main.async {
                            suppressLyricAutoScrollAnimation = false
                        }
                    }
                }
            }
        } else if let plainText = viewModel.lyrics.plainText, !plainText.isEmpty {
            ScrollView(.vertical, showsIndicators: showsScrollIndicators) {
                Text(plainText)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .foregroundStyle(theme.primaryText)
                    .textSelection(.enabled)
            }
        } else {
            Spacer()
            Text(tr("当前歌曲未找到歌词文件。\n将同名 `.lrc` 或 `.txt` 放在音频文件旁即可自动加载。", "No lyrics were found for the current track.\nPlace a matching `.lrc` or `.txt` file next to the audio file to load it automatically."))
                .foregroundStyle(theme.secondaryText)
            Spacer()
        }
    }

    private func lyricsPanelControls(
        compact: Bool,
        titleFont: Font = .headline,
        showsOnlineSearchButton: Bool = true,
        showsSourceSwitcher: Bool = true
    ) -> some View {
        HStack(alignment: .center, spacing: 10) {
            VStack(alignment: .leading, spacing: compact ? 2 : 4) {
                Text(tr("歌词", "Lyrics"))
                    .font(compact ? .subheadline.weight(.semibold) : titleFont)

                Text(lyricsPanelStatusText)
                    .font(compact ? .caption2 : .caption)
                    .foregroundStyle(theme.secondaryText)
                    .lineLimit(1)
            }

            Spacer(minLength: 12)

            HStack(spacing: compact ? 8 : 10) {
                if showsSourceSwitcher {
                    lyricsSourceSwitcher(compact: compact)
                }
                if showsOnlineSearchButton {
                    lyricsOnlineSearchButton(compact: compact)
                }
                if viewModel.hasLyricsPreview {
                    previewActionButton(
                        systemName: "checkmark",
                        compact: compact,
                        helpText: tr("应用预览歌词", "Apply previewed lyrics")
                    ) {
                        viewModel.applyPreviewLyricsSource()
                    }

                    previewActionButton(
                        systemName: "arrow.uturn.backward",
                        compact: compact,
                        helpText: tr("恢复原歌词", "Restore original lyrics")
                    ) {
                        viewModel.restoreLyricsSourceSelection()
                    }
                }
            }
        }
    }

    private func lyricsSourceSwitcher(compact: Bool) -> some View {
        Menu {
            if !viewModel.availableLyricsSources.isEmpty {
                ForEach(viewModel.availableLyricsSources) { source in
                    Button {
                        viewModel.selectLyricsSource(source.id)
                    } label: {
                        let menuTitle = lyricsSourceMenuTitle(for: source)
                        if viewModel.selectedLyricsSourceID == source.id && !viewModel.hasLyricsPreview {
                            Label(menuTitle, systemImage: "checkmark")
                        } else {
                            Text(menuTitle)
                        }
                    }
                }
            }

            if !viewModel.availableLyricsSources.isEmpty && !viewModel.onlineLyricsSearchResults.isEmpty {
                Divider()
            }

            if !viewModel.onlineLyricsSearchResults.isEmpty {
                ForEach(viewModel.onlineLyricsSearchResults) { source in
                    Button {
                        viewModel.previewLyricsSearchResult(source.id)
                    } label: {
                        let menuTitle = tr("预览", "Preview") + " · " + lyricsSourceMenuTitle(for: source)
                        if viewModel.previewLyricsSource?.id == source.id {
                            Label(menuTitle, systemImage: "eye")
                        } else {
                            Text(menuTitle)
                        }
                    }
                }
            }
        } label: {
            HStack(spacing: compact ? 5 : 6) {
                Image(systemName: "music.note.list")
                    .font(compact ? .caption2 : .caption.weight(.semibold))

                Text(currentLyricsSourceTitle)
                    .lineLimit(1)

                if viewModel.availableLyricsSources.count > 1 {
                    Image(systemName: "chevron.down")
                        .font(.caption2.weight(.bold))
                }
            }
            .foregroundStyle(theme.primaryText)
            .padding(.horizontal, compact ? 10 : 12)
            .padding(.vertical, compact ? 6 : 8)
            .background(
                RoundedRectangle(cornerRadius: compact ? 12 : 14, style: .continuous)
                    .fill(theme.panel)
                    .overlay(
                        RoundedRectangle(cornerRadius: compact ? 12 : 14, style: .continuous)
                            .stroke(theme.border, lineWidth: 1)
                    )
            )
        }
        .menuStyle(.borderlessButton)
        .disabled(viewModel.availableLyricsSources.isEmpty && viewModel.onlineLyricsSearchResults.isEmpty)
    }

    private func lyricsOnlineSearchButton(compact: Bool) -> some View {
        Button {
            viewModel.searchLyricsOnlineForCurrentTrack()
        } label: {
            Group {
                if viewModel.isSearchingLyricsOnline {
                    ProgressView()
                        .controlSize(.small)
                        .scaleEffect(compact ? 0.72 : 0.78)
                } else {
                    Image(systemName: "magnifyingglass")
                        .font(.system(size: compact ? 11 : 12, weight: .semibold))
                }
            }
            .foregroundStyle(theme.primaryText)
            .frame(width: compact ? 22 : 24, height: compact ? 22 : 24)
            .background(
                Circle()
                    .fill(theme.panel)
                    .overlay(
                        Circle()
                            .stroke(theme.border, lineWidth: 1)
                    )
            )
        }
        .buttonStyle(.plain)
        .disabled(viewModel.currentTrack == nil || viewModel.isSearchingLyricsOnline)
        .help(tr("在线搜索当前歌曲歌词", "Search lyrics online for the current track"))
    }

    private func previewActionButton(
        systemName: String,
        compact: Bool,
        helpText: String,
        action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            Image(systemName: systemName)
                .font(.system(size: compact ? 11 : 12, weight: .semibold))
                .foregroundStyle(theme.primaryText)
                .frame(width: compact ? 22 : 24, height: compact ? 22 : 24)
                .background(
                    Circle()
                        .fill(theme.panel)
                        .overlay(
                            Circle()
                                .stroke(theme.border, lineWidth: 1)
                        )
                )
        }
        .buttonStyle(.plain)
        .help(helpText)
    }

    private func artworkControls(
        compact: Bool,
        showsOnlineSearchButton: Bool = true,
        showsSourceSwitcher: Bool = true
    ) -> some View {
        HStack(spacing: compact ? 8 : 10) {
            if showsSourceSwitcher {
                artworkSourceSwitcher(compact: compact)
            }
            if showsOnlineSearchButton {
                artworkOnlineSearchButton(compact: compact)
            }
            if viewModel.hasArtworkPreview {
                previewActionButton(
                    systemName: "checkmark",
                    compact: compact,
                    helpText: tr("应用预览封面", "Apply previewed artwork")
                ) {
                    viewModel.applyPreviewArtworkSource()
                }

                previewActionButton(
                    systemName: "arrow.uturn.backward",
                    compact: compact,
                    helpText: tr("恢复原封面", "Restore original artwork")
                ) {
                    viewModel.restoreArtworkSourceSelection()
                }
            }
        }
    }

    private func artworkSourceSwitcher(compact: Bool) -> some View {
        Menu {
            artworkSourceMenuContent
        } label: {
            HStack(spacing: compact ? 5 : 6) {
                Image(systemName: "photo")
                    .font(compact ? .caption2 : .caption.weight(.semibold))

                Text(currentArtworkSourceTitle)
                    .lineLimit(1)

                if viewModel.availableArtworkSources.count + viewModel.onlineArtworkSearchResults.count > 1 {
                    Image(systemName: "chevron.down")
                        .font(.caption2.weight(.bold))
                }
            }
            .foregroundStyle(theme.primaryText)
            .padding(.horizontal, compact ? 10 : 12)
            .padding(.vertical, compact ? 6 : 8)
            .background(
                RoundedRectangle(cornerRadius: compact ? 12 : 14, style: .continuous)
                    .fill(theme.panel)
                    .overlay(
                        RoundedRectangle(cornerRadius: compact ? 12 : 14, style: .continuous)
                            .stroke(theme.border, lineWidth: 1)
                    )
            )
        }
        .menuStyle(.borderlessButton)
        .disabled(viewModel.availableArtworkSources.isEmpty && viewModel.onlineArtworkSearchResults.isEmpty)
    }

    @ViewBuilder
    private var artworkSourceMenuContent: some View {
        if viewModel.hasArtworkPreview {
            Button(tr("应用预览封面", "Apply Preview Artwork")) {
                viewModel.applyPreviewArtworkSource()
            }

            Button(tr("恢复原封面", "Restore Original Artwork")) {
                viewModel.restoreArtworkSourceSelection()
            }

            if !viewModel.availableArtworkSources.isEmpty || !viewModel.onlineArtworkSearchResults.isEmpty {
                Divider()
            }
        }

        if !viewModel.availableArtworkSources.isEmpty {
            ForEach(viewModel.availableArtworkSources) { source in
                Button {
                    viewModel.selectArtworkSource(source.id)
                } label: {
                    let menuTitle = artworkSourceMenuTitle(for: source)
                    if viewModel.selectedArtworkSourceID == source.id && !viewModel.hasArtworkPreview {
                        Label(menuTitle, systemImage: "checkmark")
                    } else {
                        Text(menuTitle)
                    }
                }
            }
        }

        if !viewModel.availableArtworkSources.isEmpty && !viewModel.onlineArtworkSearchResults.isEmpty {
            Divider()
        }

        if !viewModel.onlineArtworkSearchResults.isEmpty {
            ForEach(viewModel.onlineArtworkSearchResults) { source in
                Button {
                    viewModel.previewArtworkSearchResult(source.id)
                } label: {
                    let menuTitle = tr("预览", "Preview") + " · " + artworkSourceMenuTitle(for: source)
                    if viewModel.previewArtworkSource?.id == source.id {
                        Label(menuTitle, systemImage: "eye")
                    } else {
                        Text(menuTitle)
                    }
                }
            }
        }
    }

    private func artworkOnlineSearchButton(compact: Bool) -> some View {
        Button {
            viewModel.searchArtworkOnlineForCurrentTrack()
        } label: {
            Group {
                if viewModel.isSearchingArtworkOnline {
                    ProgressView()
                        .controlSize(.small)
                        .scaleEffect(compact ? 0.72 : 0.78)
                } else {
                    Image(systemName: "magnifyingglass")
                        .font(.system(size: compact ? 11 : 12, weight: .semibold))
                }
            }
            .foregroundStyle(theme.primaryText)
            .frame(width: compact ? 22 : 24, height: compact ? 22 : 24)
            .background(
                Circle()
                    .fill(theme.panel)
                    .overlay(
                        Circle()
                            .stroke(theme.border, lineWidth: 1)
                    )
            )
        }
        .buttonStyle(.plain)
        .disabled(viewModel.currentTrack == nil || viewModel.isSearchingArtworkOnline)
        .help(tr("在线搜索当前歌曲封面", "Search artwork online for the current track"))
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
            viewModel.currentTrack?.artist ?? tr("未知艺术家", "Unknown Artist"),
            viewModel.currentTrack?.album ?? tr("未知专辑", "Unknown Album"),
            viewModel.currentTrack?.fileExtension ?? tr("等待加载", "Loading")
        ].joined(separator: " · ")
    }

    private func lyricsSourceTitle(for source: LyricsSourceOption) -> String {
        switch source.kind {
        case .embedded:
            return tr("内嵌歌词", "Embedded")
        case .sidecarLRC:
            return tr("外挂 LRC", "Sidecar LRC")
        case .sidecarTXT:
            return tr("外挂 TXT", "Sidecar TXT")
        case .onlineSynced:
            let fallback = tr("在线逐行歌词", "Online Synced")
            return lyricsOnlineTitle(for: source, fallback: fallback)
        case .onlinePlain:
            let fallback = tr("在线纯文本歌词", "Online Plain")
            return lyricsOnlineTitle(for: source, fallback: fallback)
        }
    }

    private func lyricsSourceSubtitle(for source: LyricsSourceOption) -> String? {
        guard source.kind.isOnline else { return nil }

        var details: [String] = []
        if let provider = source.providerName?.trimmingCharacters(in: .whitespacesAndNewlines), !provider.isEmpty {
            details.append(provider)
        }
        details.append(source.kind == .onlineSynced ? tr("逐行歌词", "Synced") : tr("纯文本歌词", "Plain"))
        if let album = source.albumName, !album.isEmpty {
            details.append(album)
        }

        return details.isEmpty ? nil : details.joined(separator: " · ")
    }

    private func lyricsSourceMenuTitle(for source: LyricsSourceOption) -> String {
        var details = [lyricsSourceTitle(for: source)]
        if source.kind.isOnline, let provider = source.providerName?.trimmingCharacters(in: .whitespacesAndNewlines), !provider.isEmpty {
            details.append(provider)
        }
        if source.kind.isOnline, let rank = source.rank {
            details.append("#" + String(rank))
        }
        return details.joined(separator: " · ")
    }

    private func artworkSourceTitle(for source: ArtworkOption) -> String {
        switch source.kind {
        case .embedded:
            return tr("内嵌封面", "Embedded")
        case .sidecar:
            return tr("外挂封面", "Sidecar Cover")
        case .online:
            let fallback = tr("在线封面", "Online Cover")
            return artworkOnlineTitle(for: source, fallback: fallback)
        }
    }

    private func artworkSourceSubtitle(for source: ArtworkOption) -> String? {
        guard source.kind.isOnline else { return nil }

        var details: [String] = []
        if let provider = source.providerName?.trimmingCharacters(in: .whitespacesAndNewlines), !provider.isEmpty {
            details.append(provider)
        } else {
            details.append(tr("在线封面", "Online"))
        }
        if let album = source.albumName?.trimmingCharacters(in: .whitespacesAndNewlines), !album.isEmpty {
            details.append(album)
        }
        return details.joined(separator: " · ")
    }

    private func artworkSourceMenuTitle(for source: ArtworkOption) -> String {
        var details = [artworkSourceTitle(for: source)]
        if source.kind.isOnline, let provider = source.providerName?.trimmingCharacters(in: .whitespacesAndNewlines), !provider.isEmpty {
            details.append(provider)
        }
        if source.kind.isOnline, let rank = source.rank {
            details.append("#" + String(rank))
        }
        return details.joined(separator: " · ")
    }

    private func lyricsOnlineTitle(for source: LyricsSourceOption, fallback: String) -> String {
        let artist = source.artistName?.trimmingCharacters(in: .whitespacesAndNewlines)
        let title = source.trackName?.trimmingCharacters(in: .whitespacesAndNewlines)

        if let artist, !artist.isEmpty, let title, !title.isEmpty {
            return artist + " - " + title
        }
        if let title, !title.isEmpty {
            return title
        }
        if let rank = source.rank {
            return fallback + " \(rank)"
        }
        return fallback
    }

    private func artworkOnlineTitle(for source: ArtworkOption, fallback: String) -> String {
        let artist = source.artistName?.trimmingCharacters(in: .whitespacesAndNewlines)
        let title = source.title?.trimmingCharacters(in: .whitespacesAndNewlines)

        if let artist, !artist.isEmpty, let title, !title.isEmpty {
            return artist + " - " + title
        }
        if let title, !title.isEmpty {
            return title
        }
        if let rank = source.rank {
            return fallback + " \(rank)"
        }
        return fallback
    }

    private func scrollLyrics(with proxy: ScrollViewProxy, to index: Int, anchor: UnitPoint, animated: Bool) {
        let action = {
            proxy.scrollTo(index, anchor: anchor)
        }

        if animated {
            withAnimation(.easeInOut(duration: 0.24)) {
                action()
            }
            return
        }

        var transaction = Transaction()
        transaction.animation = nil
        withTransaction(transaction) {
            action()
        }
    }

    private var backgroundView: some View {
        ZStack {
            if viewModel.interfaceMode == .immersive {
                theme.backgroundBottom
            } else if viewModel.appTheme == .customImage, let backgroundImage = viewModel.customBackgroundImage {
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

    private var dataTransferMenu: some View {
        Menu {
            Button(tr("导出个人数据", "Export Personal Data")) {
                viewModel.exportPersonalData()
            }

            Button(tr("导入个人数据", "Import Personal Data")) {
                viewModel.importPersonalData()
            }
        } label: {
            Image(systemName: "arrow.up.arrow.down")
                .symbolRenderingMode(.monochrome)
        }
        .menuStyle(.borderlessButton)
        .menuIndicator(.hidden)
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
                    Label(themeOption.title(in: language), systemImage: "checkmark")
                } else {
                    Text(themeOption.title(in: language))
                }
            }
        }

        if viewModel.customBackgroundImagePath != nil {
            Divider()

            Button(tr("更换自定义图片", "Replace Custom Image")) {
                viewModel.openCustomBackgroundImage()
            }

            Button(tr("移除自定义图片", "Remove Custom Image")) {
                viewModel.clearCustomBackgroundImage()
            }
        }
    }

    private var createPlaylistSheet: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text(tr("新建歌单", "New Playlist"))
                .font(.title3.weight(.semibold))

            TextField(tr("输入歌单名称", "Enter playlist name"), text: $newPlaylistName)
                .textFieldStyle(.roundedBorder)

            HStack {
                Spacer()

                Button(tr("取消", "Cancel")) {
                    isCreatePlaylistSheetPresented = false
                }

                Button(tr("创建", "Create")) {
                    let playlist = viewModel.createPlaylist(named: newPlaylistName)
                    if let pendingTrackForNewPlaylist {
                        viewModel.addTrack(pendingTrackForNewPlaylist, to: playlist.id)
                    }
                    isCreatePlaylistSheetPresented = false
                }
                .keyboardShortcut(.defaultAction)
            }
        }
        .padding(20)
        .frame(width: 360)
        .background(backgroundView)
    }

    private func presentCreatePlaylistSheet(adding track: AudioTrack? = nil) {
        pendingTrackForNewPlaylist = track
        newPlaylistName = ""
        isCreatePlaylistSheetPresented = true
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
        AlbumArtworkView(
            artwork: viewModel.currentArtwork,
            theme: theme,
            usesImageBackground: usesImageBackground,
            size: size,
            cornerRadius: cornerRadius
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
                            Text(tr("拖入音频文件或文件夹以导入歌单", "Drop audio files or folders to import"))
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

    private func compareByTitle(lhs: PlaylistListEntry, rhs: PlaylistListEntry) -> Bool {
        lhs.track.title.localizedStandardCompare(rhs.track.title) == .orderedAscending
    }

    private func compareByArtist(lhs: PlaylistListEntry, rhs: PlaylistListEntry) -> Bool {
        let left = (lhs.track.artist ?? tr("未知艺术家", "Unknown Artist")) + lhs.track.title
        let right = (rhs.track.artist ?? tr("未知艺术家", "Unknown Artist")) + rhs.track.title
        return left.localizedStandardCompare(right) == .orderedAscending
    }

    private func compareByAlbum(lhs: PlaylistListEntry, rhs: PlaylistListEntry) -> Bool {
        let left = (lhs.track.album ?? tr("未知专辑", "Unknown Album")) + lhs.track.title
        let right = (rhs.track.album ?? tr("未知专辑", "Unknown Album")) + rhs.track.title
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
        artistOptionsCache = [allArtistsLabel] + Set(playlist.compactMap(\.artist)).sorted { $0.localizedStandardCompare($1) == .orderedAscending }
        albumOptionsCache = [allAlbumsLabel] + Set(playlist.compactMap(\.album)).sorted { $0.localizedStandardCompare($1) == .orderedAscending }

        if !artistOptionsCache.contains(selectedArtistFilter) {
            selectedArtistFilter = allArtistsLabel
        }
        if !albumOptionsCache.contains(selectedAlbumFilter) {
            selectedAlbumFilter = allAlbumsLabel
        }

        let items = Array(playlist.enumerated())
        let query = playlistSearchText
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .folding(options: [.diacriticInsensitive, .caseInsensitive], locale: .current)

        let filtered = items.compactMap { item -> PlaylistListEntry? in
            let track = item.element

            if selectedArtistFilter != allArtistsLabel, track.artist != selectedArtistFilter {
                return nil
            }

            if selectedAlbumFilter != allAlbumsLabel, track.album != selectedAlbumFilter {
                return nil
            }

            guard !query.isEmpty else {
                return PlaylistListEntry(index: item.offset, track: track)
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

            return haystack.contains(query) ? PlaylistListEntry(index: item.offset, track: track) : nil
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

        let targetSize: NSSize
        switch mode {
        case .compact:
            targetSize = NSSize(width: 420, height: 760)
        case .full:
            targetSize = NSSize(width: 1360, height: 860)
        case .immersive:
            targetSize = NSSize(width: 1180, height: 740)
        }

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

private struct AlbumArtworkView: View {
    let artwork: NSImage?
    let theme: PlayerTheme
    let usesImageBackground: Bool
    let size: CGFloat
    let cornerRadius: CGFloat
    var isCircular = false
    var showsBorder = true

    var body: some View {
        if isCircular {
            artworkContent
                .frame(width: size, height: size)
                .clipShape(Circle())
                .overlay {
                    if showsBorder {
                        Circle()
                            .stroke(theme.border, lineWidth: 1)
                    }
                }
        } else {
            artworkContent
                .frame(width: size, height: size)
                .clipShape(RoundedRectangle(cornerRadius: cornerRadius, style: .continuous))
                .overlay {
                    if showsBorder {
                        RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                            .stroke(theme.border, lineWidth: 1)
                    }
                }
        }
    }

    @ViewBuilder
    private var artworkContent: some View {
        ZStack {
            if let artwork {
                Image(nsImage: artwork)
                    .resizable()
                    .scaledToFill()
                    .id(artworkTransitionID(for: artwork))
                    .transition(.opacity)
            } else {
                placeholderArtwork
                    .id("artwork-placeholder")
                    .transition(.opacity)
            }
        }
        .animation(.easeInOut(duration: 0.22), value: artwork.map(artworkTransitionID(for:)) ?? "artwork-placeholder")
    }

    @ViewBuilder
    private var placeholderArtwork: some View {
        ZStack {
            if isCircular {
                Circle()
                    .fill(theme.accentSoft)
            } else {
                RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                    .fill(theme.accentSoft)
            }

            Image(systemName: "music.note")
                .font(.system(size: max(size * 0.32, 24), weight: .bold))
                .foregroundStyle(theme.accent)
                .shadow(color: theme.primaryShadow, radius: usesImageBackground ? 8 : 0)
        }
    }

    private func artworkTransitionID(for artwork: NSImage) -> String {
        String(describing: ObjectIdentifier(artwork))
    }
}

private struct SpinningVinylDisc: View {
    let artwork: NSImage?
    let theme: PlayerTheme
    let usesImageBackground: Bool
    let size: CGFloat
    let isPlaying: Bool
    let tapHint: String
    let onTap: () -> Void

    @State private var anchoredRotation: Double = 0
    @State private var rotationStartDate = Date()

    var body: some View {
        TimelineView(.animation(minimumInterval: 1.0 / 30.0)) { context in
            let angle = rotationAngle(at: context.date)

            ZStack {
                Circle()
                    .fill(
                        RadialGradient(
                            colors: [
                                Color.white.opacity(0.14),
                                Color.black.opacity(0.96),
                                Color.black
                            ],
                            center: .center,
                            startRadius: size * 0.03,
                            endRadius: size * 0.54
                        )
                    )

                ForEach(0..<8, id: \.self) { index in
                    Circle()
                        .stroke(Color.white.opacity(index.isMultiple(of: 2) ? 0.05 : 0.03), lineWidth: max(size * 0.008, 1))
                        .padding(size * (0.11 + CGFloat(index) * 0.05))
                }

                Circle()
                    .stroke(theme.accent.opacity(0.18), lineWidth: max(size * 0.018, 2))
                    .padding(size * 0.22)

                Capsule()
                    .fill(theme.accent.opacity(0.30))
                    .frame(width: size * 0.14, height: max(size * 0.012, 3))
                    .blur(radius: max(size * 0.01, 2))
                    .offset(y: -size * 0.26)

                Button(action: onTap) {
                    AlbumArtworkView(
                        artwork: artwork,
                        theme: theme,
                        usesImageBackground: usesImageBackground,
                        size: size * 0.35,
                        cornerRadius: size * 0.08,
                        isCircular: true,
                        showsBorder: false
                    )
                }
                .buttonStyle(.plain)
                .help(tapHint)

                Circle()
                    .fill(theme.primaryText.opacity(0.9))
                    .frame(width: size * 0.028, height: size * 0.028)
            }
            .rotationEffect(.degrees(angle))
        }
        .frame(width: size, height: size)
        .onAppear {
            rotationStartDate = Date()
        }
        .onChange(of: isPlaying) { _ in
            anchoredRotation = rotationAngle(at: Date())
            rotationStartDate = Date()
        }
    }

    private func rotationAngle(at date: Date) -> Double {
        guard isPlaying else { return anchoredRotation }
        let degreesPerSecond = 360.0 / 18.0
        return anchoredRotation + date.timeIntervalSince(rotationStartDate) * degreesPerSecond
    }
}

private struct LyricJumpRow: View {
    let text: String
    let time: TimeInterval
    let prominent: Bool
    let theme: PlayerTheme
    let prominentFontSize: CGFloat
    let regularFontSize: CGFloat
    let timestampWidth: CGFloat
    let showsTimestamp: Bool
    let showsBackgrounds: Bool
    let onSelect: () -> Void

    @State private var isHovered = false

    var body: some View {
        Button(action: onSelect) {
            HStack(alignment: .firstTextBaseline, spacing: 12) {
                if showsTimestamp {
                    Text(formatLyricTimestamp(time))
                        .font(.caption.monospacedDigit())
                        .foregroundStyle(prominent ? theme.accent : (isHovered ? theme.accent : theme.secondaryText))
                        .frame(width: timestampWidth, alignment: .leading)
                }

                Text(text)
                    .font(prominent ? .system(size: prominentFontSize, weight: .bold) : .system(size: regularFontSize, weight: .medium))
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
                    .stroke(showsBackgrounds && isHovered ? theme.accent.opacity(0.35) : .clear, lineWidth: 1)
            )
            .contentShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
        }
        .buttonStyle(.plain)
        .scaleEffect(showsBackgrounds && isHovered && !prominent ? 1.01 : 1)
        .animation(.easeInOut(duration: 0.16), value: isHovered)
        .onHover { hovering in
            isHovered = hovering
        }
    }

    private var backgroundFill: Color {
        if prominent {
            return theme.lyricGlow
        }
        guard showsBackgrounds else { return .clear }
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

private struct EqualizerBandCard: View {
    let band: EqualizerBandSetting
    let theme: PlayerTheme
    let isEnabled: Bool
    let isImmersive: Bool
    let onChange: (Double) -> Void

    var body: some View {
        VStack(spacing: isImmersive ? 8 : 10) {
            Text(String(format: "%+.1f", band.gain) + " dB")
                .font(.caption2.monospacedDigit().weight(.semibold))
                .foregroundStyle(abs(band.gain) > 0.1 ? theme.accent : theme.secondaryText)

            EqualizerBandFader(
                value: Double(band.gain),
                theme: theme,
                isEnabled: isEnabled,
                isImmersive: isImmersive,
                onChange: onChange
            )
            .frame(width: isImmersive ? 34 : 38, height: isImmersive ? 138 : 150)

            Text(band.label)
                .font(.caption.weight(.semibold))
                .foregroundStyle(theme.secondaryText)
                .lineLimit(1)
                .minimumScaleFactor(0.75)
        }
        .padding(.horizontal, isImmersive ? 8 : 10)
        .padding(.vertical, isImmersive ? 12 : 14)
        .frame(width: isImmersive ? 62 : 70)
        .background(
            RoundedRectangle(cornerRadius: 20, style: .continuous)
                .fill(cardFill)
        )
        .overlay(
            RoundedRectangle(cornerRadius: 20, style: .continuous)
                .stroke(borderColor, lineWidth: 1)
        )
    }

    private var cardFill: LinearGradient {
        LinearGradient(
            colors: [
                theme.panel.opacity(isImmersive ? 0.48 : 0.82),
                theme.panelSecondary.opacity(isImmersive ? 0.72 : 0.9)
            ],
            startPoint: .top,
            endPoint: .bottom
        )
    }

    private var borderColor: Color {
        isEnabled ? theme.accent.opacity(0.14) : theme.border.opacity(0.75)
    }
}

private struct EqualizerBandFader: View {
    let value: Double
    let theme: PlayerTheme
    let isEnabled: Bool
    let isImmersive: Bool
    let onChange: (Double) -> Void

    private let range: ClosedRange<Double> = -12...12

    var body: some View {
        GeometryReader { geometry in
            let height = geometry.size.height
            let trackWidth = geometry.size.width
            let progress = CGFloat((value - range.lowerBound) / (range.upperBound - range.lowerBound))
            let clampedProgress = min(max(progress, 0), 1)
            let knobY = height * (1 - clampedProgress)
            let centerY = height / 2
            let activeHeight = max(abs(centerY - knobY) + 10, 10)
            let activeOffset = ((centerY + knobY) / 2) - centerY
            let knobOffset = knobY - centerY

            ZStack {
                Capsule(style: .continuous)
                    .fill(theme.primaryText.opacity(isImmersive ? 0.09 : 0.08))

                Capsule(style: .continuous)
                    .fill(theme.accentSoft.opacity(isEnabled ? 0.18 : 0.08))
                    .frame(width: trackWidth * 0.44)

                Rectangle()
                    .fill(theme.primaryText.opacity(0.16))
                    .frame(width: trackWidth * 0.8, height: 1.2)

                Capsule(style: .continuous)
                    .fill(
                        LinearGradient(
                            colors: [
                                theme.accent.opacity(isEnabled ? 0.82 : 0.3),
                                theme.accentSoft.opacity(isEnabled ? 0.98 : 0.18)
                            ],
                            startPoint: .top,
                            endPoint: .bottom
                        )
                    )
                    .frame(width: trackWidth * 0.5, height: activeHeight)
                    .offset(y: activeOffset)

                Circle()
                    .fill(theme.primaryText.opacity(isEnabled ? 0.98 : 0.7))
                    .frame(width: trackWidth * 0.62, height: trackWidth * 0.62)
                    .overlay(
                        Circle()
                            .stroke(theme.accent.opacity(isEnabled ? 0.45 : 0.14), lineWidth: 2)
                    )
                    .shadow(color: isEnabled ? theme.accent.opacity(0.22) : .clear, radius: 8, x: 0, y: 4)
                    .offset(y: knobOffset)
            }
            .contentShape(Rectangle())
            .gesture(
                DragGesture(minimumDistance: 0)
                    .onChanged { drag in
                        let clampedY = min(max(drag.location.y, 0), height)
                        let dragProgress = 1 - (clampedY / height)
                        let rawValue = range.lowerBound + Double(dragProgress) * (range.upperBound - range.lowerBound)
                        let steppedValue = (rawValue * 2).rounded() / 2
                        onChange(min(max(steppedValue, range.lowerBound), range.upperBound))
                    }
            )
        }
    }
}

private struct PlaylistListView: View, @MainActor Equatable {
    let items: [PlaylistListEntry]
    let currentPlaylistID: UUID
    let currentPlayingPlaylistID: UUID?
    let currentIndex: Int?
    let isPlaying: Bool
    let queuedTrackPaths: Set<String>
    let query: String
    let theme: PlayerTheme
    let themeKey: String
    let language: PlayerViewModel.AppLanguage
    let playlistDestinations: [PlaylistDestinationOption]
    let scrollRequestToken: UUID
    let scrollTargetPath: String?
    let scrollAnimated: Bool
    let playAction: (AudioTrack) -> Void
    let queueNextAction: (AudioTrack) -> Void
    let addToNewPlaylistAction: (AudioTrack) -> Void
    let addToPlaylistAction: (AudioTrack, UUID) -> Void
    let removeAction: (IndexSet) -> Void

    @State private var lastHandledScrollRequestToken: UUID?

    static func == (lhs: PlaylistListView, rhs: PlaylistListView) -> Bool {
        lhs.items == rhs.items &&
        lhs.currentPlaylistID == rhs.currentPlaylistID &&
        lhs.currentPlayingPlaylistID == rhs.currentPlayingPlaylistID &&
        lhs.currentIndex == rhs.currentIndex &&
        lhs.isPlaying == rhs.isPlaying &&
        lhs.queuedTrackPaths == rhs.queuedTrackPaths &&
        lhs.query == rhs.query &&
        lhs.themeKey == rhs.themeKey &&
        lhs.language == rhs.language &&
        lhs.playlistDestinations == rhs.playlistDestinations &&
        lhs.scrollRequestToken == rhs.scrollRequestToken &&
        lhs.scrollTargetPath == rhs.scrollTargetPath &&
        lhs.scrollAnimated == rhs.scrollAnimated
    }

    private var itemIDs: [String] {
        items.map(\.id)
    }

    var body: some View {
        ScrollViewReader { proxy in
            List {
                ForEach(items) { item in
                    PlaylistRow(
                        track: item.track,
                        isCurrent: currentPlayingPlaylistID == currentPlaylistID && currentIndex == item.index,
                        isPlaying: isPlaying,
                        theme: theme,
                        themeKey: themeKey,
                        language: language,
                        isQueuedNext: queuedTrackPaths.contains(item.id),
                        query: query,
                        playlistDestinations: playlistDestinations
                    ) {
                        playAction(item.track)
                    } queueNextAction: {
                        queueNextAction(item.track)
                    } addToNewPlaylistAction: {
                        addToNewPlaylistAction(item.track)
                    } addToPlaylistAction: { playlistID in
                        addToPlaylistAction(item.track, playlistID)
                    }
                    .equatable()
                    .id(item.id)
                }
                .onDelete(perform: removeAction)
            }
            .listStyle(.inset)
            .scrollContentBackground(.hidden)
            .onAppear {
                scrollToCurrentIfNeeded(using: proxy)
            }
            .onChange(of: scrollRequestToken) { _ in
                scrollToCurrentIfNeeded(using: proxy)
            }
            .onChange(of: itemIDs) { _ in
                scrollToCurrentIfNeeded(using: proxy)
            }
        }
    }

    private func scrollToCurrentIfNeeded(using proxy: ScrollViewProxy) {
        guard let targetPath = scrollTargetPath else { return }
        guard lastHandledScrollRequestToken != scrollRequestToken else { return }
        guard itemIDs.contains(targetPath) else { return }

        let animated = scrollAnimated
        DispatchQueue.main.async {
            let scrollAction = {
                proxy.scrollTo(targetPath, anchor: .center)
            }

            if animated {
                withAnimation(.easeInOut(duration: 0.22)) {
                    scrollAction()
                }
            } else {
                var transaction = Transaction()
                transaction.animation = nil
                withTransaction(transaction) {
                    scrollAction()
                }
            }
        }

        lastHandledScrollRequestToken = scrollRequestToken
    }
}

private struct PlaylistRow: View, @MainActor Equatable {
    let track: AudioTrack
    let isCurrent: Bool
    let isPlaying: Bool
    let theme: PlayerTheme
    let themeKey: String
    let language: PlayerViewModel.AppLanguage
    let isQueuedNext: Bool
    let query: String
    let playlistDestinations: [PlaylistDestinationOption]
    let action: () -> Void
    let queueNextAction: () -> Void
    let addToNewPlaylistAction: () -> Void
    let addToPlaylistAction: (UUID) -> Void

    static func == (lhs: PlaylistRow, rhs: PlaylistRow) -> Bool {
        lhs.track == rhs.track &&
        lhs.isCurrent == rhs.isCurrent &&
        lhs.isPlaying == rhs.isPlaying &&
        lhs.themeKey == rhs.themeKey &&
        lhs.language == rhs.language &&
        lhs.isQueuedNext == rhs.isQueuedNext &&
        lhs.query == rhs.query &&
        lhs.playlistDestinations == rhs.playlistDestinations
    }

    var body: some View {
        Button(action: action) {
            HStack {
                VStack(alignment: .leading, spacing: 4) {
                    highlightedText(track.title, query: query)
                        .foregroundStyle(theme.primaryText)
                    Text([
                        track.artist ?? language.pick("未知艺术家", "Unknown Artist"),
                        track.album ?? language.pick("未知专辑", "Unknown Album"),
                        track.fileExtension
                    ].joined(separator: " · "))
                        .font(.caption)
                        .foregroundStyle(theme.secondaryText)
                        .lineLimit(2)
                }
                Spacer()
                if isQueuedNext {
                    Label(language.pick("待播", "Queued"), systemImage: "text.line.first.and.arrowtriangle.forward")
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
            Button(language.pick("下一首播放", "Play Next")) {
                queueNextAction()
            }

            Button(language.pick("添加到新歌单", "Add to New Playlist")) {
                addToNewPlaylistAction()
            }

            Menu(language.pick("添加到歌单", "Add to Playlist")) {
                if playlistDestinations.isEmpty {
                    Button(language.pick("没有其他歌单", "No Other Playlists")) {}
                        .disabled(true)
                } else {
                    ForEach(playlistDestinations, id: \.id) { playlist in
                        Button(playlist.title) {
                            addToPlaylistAction(playlist.id)
                        }
                    }
                }
            }
            .disabled(playlistDestinations.isEmpty)
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

        func title(in language: PlayerViewModel.AppLanguage) -> String {
            switch self {
            case .monthly:
                return language.pick("月度统计", "Monthly")
            case .yearly:
                return language.pick("年度统计", "Yearly")
            case .recent:
                return language.pick("最近 100 首", "Recent 100")
            }
        }
    }

    @ObservedObject var viewModel: PlayerViewModel
    let theme: PlayerTheme
    let language: PlayerViewModel.AppLanguage
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

    private func tr(_ chinese: String, _ english: String) -> String {
        language.pick(chinese, english)
    }

    var body: some View {
        VStack(spacing: 18) {
            HStack {
                VStack(alignment: .leading, spacing: 4) {
                    Text(tr("听歌历史", "Listening History"))
                        .font(.title3.weight(.bold))
                    Text(tr("按月份、年份或最近记录查看最常听歌曲与累计播放次数", "Browse your top tracks and play counts by month, year, or recent history"))
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }

                Spacer()

                Button(tr("关闭", "Close")) {
                    dismiss()
                }
            }

            Picker(tr("范围", "Scope"), selection: $selectedScope) {
                ForEach(HistoryScope.allCases) { scope in
                    Text(scope.title(in: language)).tag(scope)
                }
            }
            .pickerStyle(.segmented)

            if summaries.isEmpty && yearlySummaries.isEmpty && viewModel.recentListeningRecords.isEmpty {
                Spacer()
                VStack(spacing: 10) {
                    Image(systemName: "clock.badge.questionmark")
                        .font(.system(size: 34, weight: .semibold))
                        .foregroundStyle(theme.accent)
                    Text(tr("还没有听歌历史", "No listening history yet"))
                        .font(.headline)
                    Text(tr("开始播放歌曲后，这里会统计每月最常听的歌。", "Play some music and your monthly listening stats will appear here."))
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
                Text(tr("月份", "Month"))
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
                                    Text(tr("总播放 \(summary.totalPlays) 次", "\(summary.totalPlays) plays"))
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
                title: selectedSummary.map {
                    language == .chinese
                        ? "\(monthTitle(for: $0.monthStart)) 最常听"
                        : "Top Tracks of \(monthTitle(for: $0.monthStart))"
                } ?? tr("月度统计", "Monthly Stats"),
                tracks: selectedSummary?.tracks ?? []
            )
        }
    }

    private var yearlyHistoryContent: some View {
        HStack(alignment: .top, spacing: 16) {
            VStack(alignment: .leading, spacing: 10) {
                Text(tr("年份", "Year"))
                    .font(.headline)

                ScrollView {
                    LazyVStack(alignment: .leading, spacing: 8) {
                        ForEach(yearlySummaries) { summary in
                            Button {
                                selectedYearID = summary.id
                            } label: {
                                VStack(alignment: .leading, spacing: 4) {
                                    Text(language == .chinese ? "\(summary.year) 年" : "\(summary.year)")
                                        .font(.subheadline.weight(.semibold))
                                    Text(tr("总播放 \(summary.totalPlays) 次", "\(summary.totalPlays) plays"))
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
                title: selectedYearSummary.map {
                    language == .chinese
                        ? "\($0.year) 年最常听"
                        : "Top Tracks of \($0.year)"
                } ?? tr("年度统计", "Yearly Stats"),
                tracks: selectedYearSummary?.tracks ?? []
            )
        }
    }

    private var recentHistoryContent: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text(tr("最近听歌记录", "Recent Listening"))
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
                                item.artist ?? tr("未知艺术家", "Unknown Artist"),
                                item.album ?? tr("未知专辑", "Unknown Album")
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
                                item.artist ?? tr("未知艺术家", "Unknown Artist"),
                                item.album ?? tr("未知专辑", "Unknown Album")
                            ].joined(separator: " · "))
                            .font(.caption)
                            .foregroundStyle(.secondary)
                        }

                        Spacer()

                        Text(tr("\(item.playCount) 次", "\(item.playCount) plays"))
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
        formatter.locale = Locale(identifier: language.localeIdentifier)
        formatter.dateFormat = language == .chinese ? "yyyy年M月" : "MMM yyyy"
        return formatter.string(from: date)
    }

    private func dateTitle(for date: Date) -> String {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: language.localeIdentifier)
        formatter.dateFormat = language == .chinese ? "M月d日" : "MMM d"
        return formatter.string(from: date)
    }

    private func timeTitle(for date: Date) -> String {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: language.localeIdentifier)
        formatter.dateFormat = "HH:mm"
        return formatter.string(from: date)
    }
}
