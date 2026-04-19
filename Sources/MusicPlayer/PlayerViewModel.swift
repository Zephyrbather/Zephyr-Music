import AppKit
@preconcurrency import AVFoundation
@preconcurrency import Combine
import Foundation
import UniformTypeIdentifiers

struct EqualizerBandSetting: Identifiable, Equatable {
    let id: Int
    let frequency: Float
    let label: String
    var gain: Float
}

struct SavedEqualizerPreset: Identifiable, Codable, Equatable {
    let id: UUID
    var name: String
    var gains: [Float]

    init(id: UUID = UUID(), name: String, gains: [Float]) {
        self.id = id
        self.name = name
        self.gains = gains
    }
}

struct PlaylistCollection: Identifiable, Equatable {
    let id: UUID
    var name: String
    var tracks: [AudioTrack]

    init(id: UUID = UUID(), name: String, tracks: [AudioTrack] = []) {
        self.id = id
        self.name = name
        self.tracks = tracks
    }
}

private struct PersistedAudioTrack: Codable {
    let urlPath: String
    let title: String?
    let artist: String?
    let album: String?

    init(track: AudioTrack) {
        urlPath = track.url.path
        title = track.title
        artist = track.artist
        album = track.album
    }

    var resolvedTrack: AudioTrack {
        AudioTrack(
            url: URL(fileURLWithPath: urlPath),
            title: title,
            artist: artist,
            album: album
        )
    }
}

private struct PersistedPlaylistCollection: Codable {
    let id: UUID
    let name: String
    let tracks: [PersistedAudioTrack]

    init(playlist: PlaylistCollection) {
        id = playlist.id
        name = playlist.name
        tracks = playlist.tracks.map(PersistedAudioTrack.init)
    }

    var resolvedPlaylist: PlaylistCollection {
        PlaylistCollection(id: id, name: name, tracks: tracks.map(\.resolvedTrack))
    }
}

private struct PersistedPlaybackState: Codable {
    let selectedPlaylistID: UUID?
    let currentPlayingPlaylistID: UUID?
    let currentTrackPath: String?
    let currentTime: TimeInterval
    let wasPlaying: Bool
}

private struct PersistedAppState: Codable {
    let playlists: [PersistedPlaylistCollection]
    let selectedPlaylistID: UUID
    let appLanguage: String?
    let playbackMode: String
    let interfaceMode: String
    let lastStandardInterfaceMode: String?
    let volume: Float
    let playbackRate: Float?
    let isDesktopLyricsVisible: Bool
    let desktopLyricsFontSize: Double
    let desktopLyricsOpacity: Double
    let isDesktopLyricsLocked: Bool
    let desktopLyricsDisplayMode: String
    let desktopLyricsBackgroundStyle: String
    let isEqualizerEnabled: Bool
    let isEqualizerExpanded: Bool
    let selectedEqualizerPreset: String
    let equalizerGains: [Float]
    let appTheme: String
    let customBackgroundImagePath: String?
    let queuedTracks: [PersistedQueuedTrack]?
    let userEqualizerPresets: [SavedEqualizerPreset]?
    let selectedUserEqualizerPresetID: UUID?
    let playbackState: PersistedPlaybackState
}

private struct PersistedQueuedTrack: Codable {
    let playlistID: UUID
    let trackPath: String
}

private struct PersistedSecurityScopedBookmark: Codable {
    let path: String
    let data: Data
}

private struct ExportedBackgroundAsset: Codable {
    let originalFileName: String
    let data: Data
}

private struct ExportedUserDataPackage: Codable {
    let version: Int
    let exportedAt: Date
    let appState: PersistedAppState
    let listeningHistory: [ListeningHistoryRecord]
    let securityScopedBookmarks: [PersistedSecurityScopedBookmark]
    let backgroundAsset: ExportedBackgroundAsset?
}

struct ListeningHistoryRecord: Codable, Identifiable {
    let id: UUID
    let trackPath: String
    let title: String
    let artist: String?
    let album: String?
    let playedAt: Date

    init(track: AudioTrack, playedAt: Date = Date()) {
        id = UUID()
        trackPath = track.url.path
        title = track.title
        artist = track.artist
        album = track.album
        self.playedAt = playedAt
    }
}

struct ListeningTrackSummary: Identifiable {
    let id: String
    let trackPath: String
    let title: String
    let artist: String?
    let album: String?
    let playCount: Int
    let lastPlayedAt: Date
}

struct MonthlyListeningSummary: Identifiable {
    let id: String
    let monthStart: Date
    let totalPlays: Int
    let tracks: [ListeningTrackSummary]
}

struct YearlyListeningSummary: Identifiable {
    let id: String
    let year: Int
    let totalPlays: Int
    let tracks: [ListeningTrackSummary]
}

@MainActor
final class PlayerViewModel: NSObject, ObservableObject {
    enum AppLanguage: String, CaseIterable, Identifiable {
        case chinese = "zh-Hans"
        case english = "en"

        var id: String { rawValue }
    }

    enum AppTheme: String, CaseIterable, Identifiable {
        case system = "跟随系统"
        case pureBlack = "纯黑"
        case pureWhite = "纯白"
        case pastelBlue = "淡蓝"
        case pastelPurple = "淡紫"
        case pastelGreen = "淡绿"
        case customImage = "自定义图片"

        var id: String { rawValue }
    }

    enum DesktopLyricsDisplayMode: String, CaseIterable, Identifiable {
        case currentOnly = "当前一句"
        case dualLine = "两句横排"
        case threeLines = "三句模式"

        var id: String { rawValue }
    }

    enum DesktopLyricsBackgroundStyle: String, CaseIterable, Identifiable {
        case themed = "主题色背景"
        case graphite = "石墨灰背景"
        case ocean = "海盐蓝背景"
        case rose = "晚霞粉背景"
        case transparent = "纯透明背景"

        var id: String { rawValue }
    }

    enum PlaybackMode: String, CaseIterable, Identifiable {
        case sequential = "顺序播放"
        case listLoop = "循环播放"
        case shuffle = "随机播放"

        var id: String { rawValue }

        var symbolName: String {
            switch self {
            case .sequential:
                return "list.number"
            case .listLoop:
                return "repeat"
            case .shuffle:
                return "shuffle"
            }
        }
    }

    enum InterfaceMode: String, CaseIterable, Identifiable {
        case full = "完整模式"
        case compact = "简洁模式"
        case immersive = "沉浸式模式"

        var id: String { rawValue }

        var symbolName: String {
            switch self {
            case .full:
                return "rectangle.split.2x1"
            case .compact:
                return "rectangle.portrait"
            case .immersive:
                return "sparkles"
            }
        }
    }

    enum EqualizerPreset: String, CaseIterable, Identifiable {
        case custom = "custom"
        case vocal = "vocal"
        case bassBoost = "bass_boost"
        case pop = "pop"
        case rock = "rock"
        case classical = "classical"
        case musicHall = "music_hall"
        case studio = "studio"
        case ktv = "ktv"
        case concert = "concert"

        var id: String { rawValue }

        init(persistedValue: String) {
            switch persistedValue {
            case "自定义", "custom":
                self = .custom
            case "人声增强", "vocal":
                self = .vocal
            case "低音增强", "bass_boost":
                self = .bassBoost
            case "流行", "pop":
                self = .pop
            case "摇滚", "rock":
                self = .rock
            case "古典", "classical":
                self = .classical
            case "音乐厅", "music_hall":
                self = .musicHall
            case "录音棚", "studio":
                self = .studio
            case "KTV", "ktv":
                self = .ktv
            case "演唱会", "concert":
                self = .concert
            default:
                self = .custom
            }
        }
    }

    private static let supportedExtensions = Set(["flac", "wav", "mp3", "dsf", "dff", "dsd"])
    private static let defaultPlaylistName = "默认歌单"
    private static let defaultPlaylistEnglishName = "Default Playlist"
    private static let supportedPlaybackRates: [Float] = [0.75, 1.0, 1.25, 1.5, 2.0]

    @Published private(set) var playlists: [PlaylistCollection] = [PlaylistCollection(name: defaultPlaylistName)]
    @Published private(set) var queuedTrackPaths: [String] = []
    @Published var selectedPlaylistID: UUID
    @Published private(set) var currentIndex: Int?
    @Published private(set) var currentPlayingPlaylistID: UUID?
    @Published private(set) var isPlaying = false
    @Published private(set) var duration: TimeInterval = 0
    @Published private(set) var currentTime: TimeInterval = 0
    @Published private(set) var lyrics = LyricsDocument(timedLines: [], plainText: nil)
    @Published private(set) var availableLyricsSources: [LyricsSourceOption] = []
    @Published private(set) var selectedLyricsSourceID: String?
    @Published private(set) var previewLyricsSource: LyricsSourceOption?
    @Published private(set) var onlineLyricsSearchResults: [LyricsSourceOption] = []
    @Published private(set) var isSearchingLyricsOnline = false
    @Published private(set) var didAttemptOnlineLyricsSearch = false
    @Published private(set) var onlineLyricsResultCount = 0
    @Published private(set) var currentLyricIndex: Int?
    @Published private(set) var currentArtwork: NSImage?
    @Published private(set) var availableArtworkSources: [ArtworkOption] = []
    @Published private(set) var selectedArtworkSourceID: String?
    @Published private(set) var previewArtworkSource: ArtworkOption?
    @Published private(set) var onlineArtworkSearchResults: [ArtworkOption] = []
    @Published private(set) var isSearchingArtworkOnline = false
    @Published private(set) var didAttemptOnlineArtworkSearch = false
    @Published private(set) var onlineArtworkResultCount = 0
    @Published private(set) var isBatchScrapingMissingMetadata = false
    @Published private(set) var batchScrapeCompletedCount = 0
    @Published private(set) var batchScrapeTargetCount = 0
    @Published var isDropTargeted = false
    @Published var isDesktopLyricsVisible = false
    @Published var isDesktopLyricsSettingsPresented = false
    @Published var desktopLyricsFontSize: Double = 28
    @Published var desktopLyricsOpacity: Double = 0.9
    @Published var isDesktopLyricsLocked = false
    @Published var desktopLyricsDisplayMode: DesktopLyricsDisplayMode = .dualLine
    @Published var desktopLyricsBackgroundStyle: DesktopLyricsBackgroundStyle = .themed
    @Published var playbackMode: PlaybackMode = .sequential
    @Published var interfaceMode: InterfaceMode = .compact {
        didSet {
            if interfaceMode != .immersive {
                lastStandardInterfaceMode = interfaceMode
            }
        }
    }
    @Published var appLanguage: AppLanguage = .chinese
    @Published var playlistSearchFocusRequest = 0
    @Published var listeningHistoryPresentationRequest = 0
    @Published var appTheme: AppTheme = .system
    @Published private(set) var customBackgroundImage: NSImage?
    @Published private(set) var customBackgroundImagePath: String?
    @Published var isEqualizerEnabled = false {
        didSet { applyEqualizerSettings() }
    }
    @Published var isEqualizerExpanded = false
    @Published var selectedEqualizerPreset: EqualizerPreset = .custom
    @Published private(set) var selectedUserEqualizerPresetID: UUID?
    @Published private(set) var userEqualizerPresets: [SavedEqualizerPreset] = []
    @Published var equalizerBands = PlayerViewModel.makeDefaultEqualizerBands() {
        didSet { applyEqualizerSettings() }
    }
    @Published private(set) var listeningHistory: [ListeningHistoryRecord] = []
    @Published private(set) var playbackRate: Float = 1.0 {
        didSet {
            applyPlaybackRate()
        }
    }
    @Published var volume: Float = 0.8 {
        didSet {
            playerNode.volume = volume
        }
    }

    private let audioEngine = AVAudioEngine()
    private let playerNode = AVAudioPlayerNode()
    private let timePitchNode = AVAudioUnitTimePitch()
    private let equalizerNode = AVAudioUnitEQ(numberOfBands: 10)

    private var currentAudioFile: AVAudioFile?
    private var currentSampleRate: Double = 44_100
    private var currentTrackBitRateKbps: Double?
    private var currentChannelCountValue = 0
    private var currentStartFrame: AVAudioFramePosition = 0
    private var currentFramePosition: AVAudioFramePosition = 0
    private var scheduledPlaybackToken = UUID()
    private var timerCancellable: AnyCancellable?
    private var wasPlayingBeforeDrag = false
    private var supplementalAssetTask: Task<Void, Never>?
    private var cancellables = Set<AnyCancellable>()
    private var isRestoringState = false
    private var securityScopedBookmarks: [String: Data] = [:]
    private var activeSecurityScopedURLs: [String: URL] = [:]
    private var lastStandardInterfaceMode: InterfaceMode = .compact

    private static let appStateDefaultsKey = "ZephyrPlayer.AppState"
    private static let listeningHistoryDefaultsKey = "ZephyrPlayer.ListeningHistory"
    private static let securityScopedBookmarksDefaultsKey = "ZephyrPlayer.SecurityScopedBookmarks"

    override init() {
        let defaultPlaylist = PlaylistCollection(name: Self.defaultPlaylistName)
        _playlists = Published(initialValue: [defaultPlaylist])
        _selectedPlaylistID = Published(initialValue: defaultPlaylist.id)
        super.init()
        restoreListeningHistory()
        restoreSecurityScopedBookmarks()
        configureAudioEngine()
        playerNode.volume = volume
        restorePersistedState()
        preloadSecurityScopedAccessForAllTracks(promptIfNeeded: false)
        applyEqualizerSettings()
        configurePersistence()
        startProgressTimer()
        DispatchQueue.main.async { [weak self] in
            self?.preloadSecurityScopedAccessForAllTracks(promptIfNeeded: true)
        }
    }

    var currentTrack: AudioTrack? {
        guard let currentIndex else { return nil }
        guard let currentPlayingPlaylist else { return nil }
        guard currentPlayingPlaylist.tracks.indices.contains(currentIndex) else { return nil }
        return currentPlayingPlaylist.tracks[currentIndex]
    }

    var playlist: [AudioTrack] {
        currentPlaylist.tracks
    }

    var selectedPlaylistName: String {
        displayName(for: currentPlaylist)
    }

    func displayName(for playlist: PlaylistCollection) -> String {
        if Self.localizedDefaultPlaylistNames.contains(playlist.name) {
            return appLanguage == .english ? Self.defaultPlaylistEnglishName : Self.defaultPlaylistName
        }
        return playlist.name
    }

    var progress: Double {
        guard duration > 0 else { return 0 }
        return currentTime / duration
    }

    var currentBitRateKbps: Int? {
        currentTrackBitRateKbps.map { Int($0.rounded()) }
    }

    var selectedSavedEqualizerPreset: SavedEqualizerPreset? {
        guard let selectedUserEqualizerPresetID else { return nil }
        return userEqualizerPresets.first(where: { $0.id == selectedUserEqualizerPresetID })
    }

    var currentEqualizerPresetDisplayName: String {
        selectedSavedEqualizerPreset?.name ?? selectedEqualizerPreset.title(in: appLanguage)
    }

    var currentChannelCount: Int {
        currentChannelCountValue
    }

    var playbackSampleRate: Double {
        currentSampleRate
    }

    var availablePlaybackRates: [Float] {
        Self.supportedPlaybackRates
    }

    var playbackRateDisplayText: String {
        Self.formattedPlaybackRate(playbackRate)
    }

    var monthlyListeningSummaries: [MonthlyListeningSummary] {
        let calendar = Calendar(identifier: .gregorian)
        let groupedByMonth = Dictionary(grouping: listeningHistory) {
            calendar.date(from: calendar.dateComponents([.year, .month], from: $0.playedAt)) ?? $0.playedAt
        }

        return groupedByMonth
            .map { month, records in
                let groupedTracks = Dictionary(grouping: records, by: \.trackPath)
                let trackSummaries = groupedTracks.compactMap { trackPath, groupedRecords -> ListeningTrackSummary? in
                    guard let latest = groupedRecords.max(by: { $0.playedAt < $1.playedAt }) else { return nil }
                    return ListeningTrackSummary(
                        id: month.formatted(date: .numeric, time: .omitted) + trackPath,
                        trackPath: trackPath,
                        title: latest.title,
                        artist: latest.artist,
                        album: latest.album,
                        playCount: groupedRecords.count,
                        lastPlayedAt: latest.playedAt
                    )
                }
                .sorted {
                    if $0.playCount == $1.playCount {
                        return $0.lastPlayedAt > $1.lastPlayedAt
                    }
                    return $0.playCount > $1.playCount
                }

                return MonthlyListeningSummary(
                    id: Self.monthFormatter.string(from: month),
                    monthStart: month,
                    totalPlays: records.count,
                    tracks: trackSummaries
                )
            }
            .sorted { $0.monthStart > $1.monthStart }
    }

    var yearlyListeningSummaries: [YearlyListeningSummary] {
        let calendar = Calendar(identifier: .gregorian)
        let groupedByYear = Dictionary(grouping: listeningHistory) {
            calendar.component(.year, from: $0.playedAt)
        }

        return groupedByYear
            .map { year, records in
                let groupedTracks = Dictionary(grouping: records, by: \.trackPath)
                let trackSummaries = groupedTracks.compactMap { trackPath, groupedRecords -> ListeningTrackSummary? in
                    guard let latest = groupedRecords.max(by: { $0.playedAt < $1.playedAt }) else { return nil }
                    return ListeningTrackSummary(
                        id: "\(year)-" + trackPath,
                        trackPath: trackPath,
                        title: latest.title,
                        artist: latest.artist,
                        album: latest.album,
                        playCount: groupedRecords.count,
                        lastPlayedAt: latest.playedAt
                    )
                }
                .sorted {
                    if $0.playCount == $1.playCount {
                        return $0.lastPlayedAt > $1.lastPlayedAt
                    }
                    return $0.playCount > $1.playCount
                }

                return YearlyListeningSummary(
                    id: String(year),
                    year: year,
                    totalPlays: records.count,
                    tracks: trackSummaries
                )
            }
            .sorted { $0.year > $1.year }
    }

    var recentListeningRecords: [ListeningHistoryRecord] {
        Array(listeningHistory.prefix(100))
    }

    func totalPlayCount(for track: AudioTrack) -> Int {
        let path = normalizedPath(for: track.url)
        return listeningHistory.filter { normalizedPath(forPath: $0.trackPath) == path }.count
    }

    deinit {
        timerCancellable?.cancel()
        audioEngine.stop()
        activeSecurityScopedURLs.values.forEach { $0.stopAccessingSecurityScopedResource() }
    }

    func openFiles() {
        let panel = NSOpenPanel()
        panel.allowedContentTypes = [
            UTType(filenameExtension: "flac"),
            UTType(filenameExtension: "wav"),
            UTType.mp3,
            UTType(filenameExtension: "dsf"),
            UTType(filenameExtension: "dff"),
            UTType(filenameExtension: "dsd")
        ].compactMap { $0 }
        panel.allowsMultipleSelection = true
        panel.canChooseDirectories = false
        panel.canChooseFiles = true

        if panel.runModal() == .OK {
            addFiles(panel.urls)
        }
    }

    func openFolder() {
        let panel = NSOpenPanel()
        panel.allowedContentTypes = [.folder]
        panel.allowsMultipleSelection = true
        panel.canChooseDirectories = true
        panel.canChooseFiles = false

        if panel.runModal() == .OK {
            addDirectories(panel.urls)
        }
    }

    func addTracks(fromPlaylist sourcePlaylistID: UUID, to destinationPlaylistID: UUID? = nil) {
        guard let sourcePlaylist = playlists.first(where: { $0.id == sourcePlaylistID }) else { return }
        let targetPlaylistID = destinationPlaylistID ?? selectedPlaylistID
        guard targetPlaylistID != sourcePlaylistID else { return }
        guard let destinationIndex = playlists.firstIndex(where: { $0.id == targetPlaylistID }) else { return }

        let existingPaths = Set(playlists[destinationIndex].tracks.map { normalizedPath(for: $0.url) })
        let additions = sourcePlaylist.tracks.filter { !existingPaths.contains(normalizedPath(for: $0.url)) }
        guard !additions.isEmpty else { return }

        let startIndex = playlists[destinationIndex].tracks.count
        playlists[destinationIndex].tracks.append(contentsOf: additions)
        persistSecurityScopedAccess(for: additions.map(\.url))
        enrichMetadataForNewTracks(startingAt: startIndex, in: targetPlaylistID)
    }

    func openCustomBackgroundImage() {
        let panel = NSOpenPanel()
        panel.allowedContentTypes = [.image]
        panel.allowsMultipleSelection = false
        panel.canChooseDirectories = false
        panel.canChooseFiles = true

        if panel.runModal() == .OK, let url = panel.url {
            setCustomBackgroundImage(from: url)
        }
    }

    func clearCustomBackgroundImage() {
        customBackgroundImage = nil
        customBackgroundImagePath = nil
        if appTheme == .customImage {
            appTheme = .system
        }
    }

    func addFiles(_ urls: [URL]) {
        let tracks = urls
            .filter { Self.supportedExtensions.contains($0.pathExtension.lowercased()) }
            .map { AudioTrack(url: $0) }

        persistSecurityScopedAccess(for: urls.filter { !$0.hasDirectoryPath })
        persistSecurityScopedAccess(for: tracks.map(\.url))
        appendTracks(tracks)
    }

    func addDirectories(_ urls: [URL]) {
        persistSecurityScopedAccess(for: urls.filter(\.hasDirectoryPath))
        let tracks = urls.flatMap(scanDirectory)
        persistSecurityScopedAccess(for: tracks.map(\.url))
        appendTracks(tracks)
    }

    func handleDroppedURLs(_ urls: [URL]) {
        let files = urls.filter { Self.supportedExtensions.contains($0.pathExtension.lowercased()) }
        let directories = urls.filter { isDirectory($0) }
        persistSecurityScopedAccess(for: files + directories)
        if !files.isEmpty {
            addFiles(files)
        }
        if !directories.isEmpty {
            addDirectories(directories)
        }
    }

    func importItemProviders(_ providers: [NSItemProvider]) -> Bool {
        let identifier = UTType.fileURL.identifier
        let supported = providers.filter { $0.hasItemConformingToTypeIdentifier(identifier) }
        guard !supported.isEmpty else { return false }

        Task {
            var urls: [URL] = []
            for provider in supported {
                if let url = await loadURL(from: provider) {
                    urls.append(url)
                }
            }

            handleDroppedURLs(urls)
        }

        return true
    }

    var previousLyricLine: String? {
        guard let currentLyricIndex, currentLyricIndex > 0 else { return nil }
        return lyrics.timedLines[currentLyricIndex - 1].text
    }

    var currentLyricLine: String? {
        guard let currentLyricIndex, lyrics.timedLines.indices.contains(currentLyricIndex) else { return nil }
        return lyrics.timedLines[currentLyricIndex].text
    }

    var nextLyricLine: String? {
        guard let currentLyricIndex else { return nil }
        let nextIndex = currentLyricIndex + 1
        guard lyrics.timedLines.indices.contains(nextIndex) else { return nil }
        return lyrics.timedLines[nextIndex].text
    }

    var onlineLyricsSourcesCount: Int {
        onlineLyricsSearchResults.count
    }

    var isSearchingOnlineMetadata: Bool {
        isSearchingLyricsOnline || isSearchingArtworkOnline
    }

    var hasOnlineMetadataResults: Bool {
        !onlineLyricsSearchResults.isEmpty || !onlineArtworkSearchResults.isEmpty
    }

    var hasOnlineMetadataPreview: Bool {
        hasLyricsPreview || hasArtworkPreview
    }

    var batchScrapeProgressText: String {
        guard batchScrapeTargetCount > 0 else {
            return appLanguage.pick("刮削中…", "Scraping...")
        }
        return appLanguage.pick(
            "刮削中 \(batchScrapeCompletedCount)/\(batchScrapeTargetCount)",
            "Scraping \(batchScrapeCompletedCount)/\(batchScrapeTargetCount)"
        )
    }

    var selectedLyricsSource: LyricsSourceOption? {
        guard let selectedLyricsSourceID else { return nil }
        return availableLyricsSources.first(where: { $0.id == selectedLyricsSourceID })
    }

    var displayedLyricsSource: LyricsSourceOption? {
        previewLyricsSource ?? selectedLyricsSource
    }

    var hasLyricsPreview: Bool {
        previewLyricsSource != nil
    }

    func selectLyricsSource(_ sourceID: String) {
        guard availableLyricsSources.contains(where: { $0.id == sourceID }) else { return }
        selectedLyricsSourceID = sourceID
        previewLyricsSource = nil
        syncDisplayedLyrics()
        onlineLyricsResultCount = onlineLyricsSearchResults.count
    }

    func previewLyricsSearchResult(_ sourceID: String) {
        guard let source = onlineLyricsSearchResults.first(where: { $0.id == sourceID }) else { return }
        previewLyricsSource = source
        syncDisplayedLyrics()
    }

    func applyPreviewLyricsSource() {
        guard let previewLyricsSource else { return }

        if !availableLyricsSources.contains(where: { $0.id == previewLyricsSource.id }) {
            availableLyricsSources.append(previewLyricsSource)
        }

        selectedLyricsSourceID = previewLyricsSource.id
        self.previewLyricsSource = nil
        syncDisplayedLyrics()
    }

    func restoreLyricsSourceSelection() {
        previewLyricsSource = nil
        syncDisplayedLyrics()
    }

    func searchLyricsOnlineForCurrentTrack(forceRefresh: Bool = true) {
        guard let track = currentTrack else { return }

        let info = TrackSearchInfo(
            title: track.title,
            artist: track.artist,
            album: track.album,
            duration: duration
        )

        previewLyricsSource = nil
        syncDisplayedLyrics()
        onlineLyricsSearchResults = []
        isSearchingLyricsOnline = true
        didAttemptOnlineLyricsSearch = true
        onlineLyricsResultCount = 0
        let trackPath = track.url.standardizedFileURL.path

        Task { [weak self] in
            guard let self else { return }

            let fetchedSources = await OnlineMetadataService.shared.fetchLyricsSources(
                for: track,
                info: info,
                forceRefresh: forceRefresh
            )

            await MainActor.run {
                self.isSearchingLyricsOnline = false

                guard let currentTrack = self.currentTrack,
                      currentTrack.url.standardizedFileURL.path == trackPath else {
                    return
                }

                self.onlineLyricsSearchResults = fetchedSources
                self.onlineLyricsResultCount = fetchedSources.count
            }
        }
    }

    var onlineArtworkSourcesCount: Int {
        onlineArtworkSearchResults.count
    }

    var selectedArtworkSource: ArtworkOption? {
        guard let selectedArtworkSourceID else { return nil }
        return availableArtworkSources.first(where: { $0.id == selectedArtworkSourceID })
    }

    var displayedArtworkSource: ArtworkOption? {
        previewArtworkSource ?? selectedArtworkSource
    }

    var hasArtworkPreview: Bool {
        previewArtworkSource != nil
    }

    func selectArtworkSource(_ sourceID: String) {
        guard availableArtworkSources.contains(where: { $0.id == sourceID }) else { return }
        selectedArtworkSourceID = sourceID
        previewArtworkSource = nil
        syncDisplayedArtwork()
        onlineArtworkResultCount = onlineArtworkSearchResults.count
    }

    func previewArtworkSearchResult(_ sourceID: String) {
        guard let source = onlineArtworkSearchResults.first(where: { $0.id == sourceID }) else { return }
        previewArtworkSource = source
        syncDisplayedArtwork()
    }

    func applyPreviewArtworkSource() {
        guard let previewArtworkSource else { return }

        if !availableArtworkSources.contains(where: { $0.id == previewArtworkSource.id }) {
            availableArtworkSources.append(previewArtworkSource)
        }

        selectedArtworkSourceID = previewArtworkSource.id
        self.previewArtworkSource = nil
        syncDisplayedArtwork()
    }

    func restoreArtworkSourceSelection() {
        previewArtworkSource = nil
        syncDisplayedArtwork()
    }

    func searchArtworkOnlineForCurrentTrack(forceRefresh: Bool = true) {
        guard let track = currentTrack else { return }

        let info = TrackSearchInfo(
            title: track.title,
            artist: track.artist,
            album: track.album,
            duration: duration
        )

        previewArtworkSource = nil
        syncDisplayedArtwork()
        onlineArtworkSearchResults = []
        isSearchingArtworkOnline = true
        didAttemptOnlineArtworkSearch = true
        onlineArtworkResultCount = 0
        let trackPath = track.url.standardizedFileURL.path

        Task { [weak self] in
            guard let self else { return }

            let fetchedSources = await OnlineMetadataService.shared.fetchArtworkOptions(
                for: track,
                info: info,
                forceRefresh: forceRefresh
            )

            await MainActor.run {
                self.isSearchingArtworkOnline = false

                guard let currentTrack = self.currentTrack,
                      currentTrack.url.standardizedFileURL.path == trackPath else {
                    return
                }

                self.onlineArtworkSearchResults = fetchedSources
                self.onlineArtworkResultCount = fetchedSources.count
            }
        }
    }

    func searchOnlineMetadataForCurrentTrack(forceRefresh: Bool = true) {
        guard currentTrack != nil else { return }
        searchLyricsOnlineForCurrentTrack(forceRefresh: forceRefresh)
        searchArtworkOnlineForCurrentTrack(forceRefresh: forceRefresh)
    }

    func scrapeMissingMetadataInSelectedPlaylist() {
        guard !isBatchScrapingMissingMetadata else { return }

        let tracks = currentPlaylist.tracks
        guard !tracks.isEmpty else {
            presentModalMessage(
                title: appLanguage.pick("当前歌单为空", "Playlist Is Empty"),
                message: appLanguage.pick("先添加歌曲，再执行一键刮削。", "Add tracks before running auto scrape."),
                style: .informational
            )
            return
        }

        isBatchScrapingMissingMetadata = true
        batchScrapeCompletedCount = 0
        batchScrapeTargetCount = tracks.count

        Task { [weak self] in
            guard let self else { return }

            var lyricsSavedCount = 0
            var artworkSavedCount = 0
            var unresolvedCount = 0
            var failureCount = 0
            var touchedCurrentTrack = false

            for (offset, track) in tracks.enumerated() {
                let result = await self.scrapeMissingMetadata(for: track)
                batchScrapeCompletedCount = offset + 1

                if result.lyricsSaved {
                    lyricsSavedCount += 1
                }
                if result.artworkSaved {
                    artworkSavedCount += 1
                }
                if result.hadFailure {
                    failureCount += 1
                }
                if result.wasUnresolved {
                    unresolvedCount += 1
                }
                if currentTrack?.url.standardizedFileURL == track.url.standardizedFileURL,
                   result.lyricsSaved || result.artworkSaved {
                    touchedCurrentTrack = true
                }
            }

            if touchedCurrentTrack, let currentTrack {
                startSupplementalAssetLoad(for: currentTrack, duration: duration)
            }

            isBatchScrapingMissingMetadata = false
            let title = appLanguage.pick("刮削完成", "Scrape Complete")
            let message = appLanguage.pick(
                "已补全歌词 \(lyricsSavedCount) 首，封面 \(artworkSavedCount) 首；未命中 \(unresolvedCount) 首，写入失败 \(failureCount) 首。",
                "Filled lyrics for \(lyricsSavedCount) tracks and artwork for \(artworkSavedCount) tracks; \(unresolvedCount) unresolved, \(failureCount) failed to save."
            )
            presentModalMessage(title: title, message: message, style: .informational)
        }
    }

    func updateEqualizerBandGain(at index: Int, gain: Float) {
        guard equalizerBands.indices.contains(index) else { return }
        if selectedUserEqualizerPresetID != nil {
            selectedUserEqualizerPresetID = nil
        }
        if selectedEqualizerPreset != .custom {
            selectedEqualizerPreset = .custom
        }
        equalizerBands[index].gain = gain
    }

    func resetEqualizer() {
        selectedUserEqualizerPresetID = nil
        selectedEqualizerPreset = .custom
        equalizerBands = Self.makeDefaultEqualizerBands()
    }

    func applyEqualizerPreset(_ preset: EqualizerPreset) {
        selectedUserEqualizerPresetID = nil
        selectedEqualizerPreset = preset
        equalizerBands = Self.equalizerBands(for: preset)
    }

    func applySavedEqualizerPreset(_ id: UUID) {
        guard let preset = userEqualizerPresets.first(where: { $0.id == id }) else { return }
        selectedEqualizerPreset = .custom
        selectedUserEqualizerPresetID = preset.id
        equalizerBands = Self.equalizerBands(forGains: preset.gains)
    }

    func removeSavedEqualizerPreset(_ id: UUID) {
        let wasSelected = selectedUserEqualizerPresetID == id
        userEqualizerPresets.removeAll { $0.id == id }

        guard wasSelected else { return }
        selectedUserEqualizerPresetID = nil
        selectedEqualizerPreset = .custom
    }

    func promptToSaveCurrentEqualizerPreset() {
        let alert = NSAlert()
        alert.messageText = appLanguage.pick("保存均衡器预设", "Save Equalizer Preset")
        alert.informativeText = appLanguage.pick("输入一个名称，用于保存当前播放风格。", "Enter a name to save the current sound profile.")
        alert.alertStyle = .informational
        alert.addButton(withTitle: appLanguage.pick("保存", "Save"))
        alert.addButton(withTitle: appLanguage.pick("取消", "Cancel"))

        let field = NSTextField(string: "")
        field.placeholderString = appLanguage.pick("例如：夜间人声 / 通勤低频", "For example: Night Vocal / Commute Bass")
        field.frame = NSRect(x: 0, y: 0, width: 280, height: 24)
        alert.accessoryView = field

        NSApp.activate(ignoringOtherApps: true)
        let response = alert.runModal()
        guard response == .alertFirstButtonReturn else { return }

        let trimmed = field.stringValue.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else {
            presentModalMessage(
                title: appLanguage.pick("名称不能为空", "Name Required"),
                message: appLanguage.pick("请输入预设名称后再保存。", "Enter a preset name before saving."),
                style: .warning
            )
            return
        }

        let savedName = saveCurrentEqualizerPreset(named: trimmed)
        presentModalMessage(
            title: appLanguage.pick("已保存预设", "Preset Saved"),
            message: appLanguage.pick("当前播放风格已保存为“\(savedName)”。", "The current sound profile was saved as \"\(savedName)\"."),
            style: .informational
        )
    }

    @discardableResult
    func saveCurrentEqualizerPreset(named proposedName: String) -> String {
        let baseName = proposedName.trimmingCharacters(in: .whitespacesAndNewlines)
        let resolvedName = uniqueUserEqualizerPresetName(for: baseName.isEmpty ? appLanguage.pick("我的风格", "My Preset") : baseName)
        let preset = SavedEqualizerPreset(name: resolvedName, gains: equalizerBands.map(\.gain))
        userEqualizerPresets.append(preset)
        selectedEqualizerPreset = .custom
        selectedUserEqualizerPresetID = preset.id
        return resolvedName
    }

    func exportPersonalData() {
        guard let package = makeExportedUserDataPackage() else {
            presentModalMessage(
                title: appLanguage.pick("导出失败", "Export Failed"),
                message: appLanguage.pick("当前数据无法整理为迁移包。", "The current data could not be prepared for export."),
                style: .warning
            )
            return
        }

        let panel = NSSavePanel()
        panel.allowedContentTypes = [.json]
        panel.canCreateDirectories = true
        panel.nameFieldStringValue = "ZephyrPlayer-Profile-\(Self.exportDateFormatter.string(from: Date())).json"

        NSApp.activate(ignoringOtherApps: true)
        guard panel.runModal() == .OK, let url = panel.url else { return }

        do {
            let encoder = JSONEncoder()
            encoder.dateEncodingStrategy = .iso8601
            encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
            let data = try encoder.encode(package)
            try data.write(to: url, options: .atomic)

            presentModalMessage(
                title: appLanguage.pick("导出完成", "Export Complete"),
                message: appLanguage.pick("个人数据已导出到：\n\(url.path)", "Personal data was exported to:\n\(url.path)"),
                style: .informational
            )
        } catch {
            presentModalMessage(
                title: appLanguage.pick("导出失败", "Export Failed"),
                message: error.localizedDescription,
                style: .warning
            )
        }
    }

    func importPersonalData() {
        let panel = NSOpenPanel()
        panel.allowedContentTypes = [.json]
        panel.allowsMultipleSelection = false
        panel.canChooseDirectories = false
        panel.canChooseFiles = true

        NSApp.activate(ignoringOtherApps: true)
        guard panel.runModal() == .OK, let url = panel.url else { return }
        guard confirmPersonalDataImport() else { return }

        do {
            let data = try Data(contentsOf: url)
            let decoder = JSONDecoder()
            decoder.dateDecodingStrategy = .iso8601
            let package = try decoder.decode(ExportedUserDataPackage.self, from: data)
            try applyImportedUserData(package)

            presentModalMessage(
                title: appLanguage.pick("导入完成", "Import Complete"),
                message: appLanguage.pick("个人数据已导入。若音频文件路径发生变化，请重新选择文件夹或音频文件。", "Personal data was imported. If your audio file paths changed, reselect the folders or audio files."),
                style: .informational
            )
        } catch {
            presentModalMessage(
                title: appLanguage.pick("导入失败", "Import Failed"),
                message: error.localizedDescription,
                style: .warning
            )
        }
    }

    @discardableResult
    func createPlaylist() -> PlaylistCollection {
        let name = nextPlaylistName()
        let playlist = PlaylistCollection(name: name)
        playlists.append(playlist)
        selectedPlaylistID = playlist.id
        return playlist
    }

    @discardableResult
    func createPlaylist(named proposedName: String) -> PlaylistCollection {
        let trimmed = proposedName.trimmingCharacters(in: .whitespacesAndNewlines)
        let fallbackName = nextPlaylistName()
        let baseName = trimmed.isEmpty ? fallbackName : trimmed
        let resolvedName = uniquePlaylistName(for: baseName)
        let playlist = PlaylistCollection(name: resolvedName)
        playlists.append(playlist)
        selectedPlaylistID = playlist.id
        return playlist
    }

    func selectPlaylist(_ id: UUID) {
        guard playlists.contains(where: { $0.id == id }) else { return }
        selectedPlaylistID = id
    }

    func removeSelectedPlaylist() {
        removePlaylist(id: selectedPlaylistID)
    }

    func removePlaylist(id: UUID) {
        guard playlists.count > 1 else { return }
        guard let playlistIndex = playlists.firstIndex(where: { $0.id == id }) else { return }

        let removedPlaylist = playlists[playlistIndex]
        let fallbackIndex = playlistIndex == 0 ? 1 : playlistIndex - 1
        let fallbackPlaylistID = playlists[fallbackIndex].id

        playlists.remove(at: playlistIndex)
        playbackQueue.removeAll { $0.playlistID == removedPlaylist.id }

        if selectedPlaylistID == removedPlaylist.id {
            selectedPlaylistID = fallbackPlaylistID
        }

        if currentPlayingPlaylistID == removedPlaylist.id {
            stopPlayback(clearSelection: true)
        }
    }

    func cyclePlaybackMode() {
        let modes = PlaybackMode.allCases
        guard let current = modes.firstIndex(of: playbackMode) else {
            playbackMode = .sequential
            return
        }
        playbackMode = modes[(current + 1) % modes.count]
    }

    func setPlaybackRate(_ rate: Float) {
        playbackRate = Self.nearestSupportedPlaybackRate(to: rate)
    }

    func playbackRateText(for rate: Float) -> String {
        Self.formattedPlaybackRate(rate)
    }

    func toggleInterfaceMode() {
        if interfaceMode == .immersive {
            interfaceMode = lastStandardInterfaceMode
            return
        }
        interfaceMode = interfaceMode == .full ? .compact : .full
    }

    func toggleImmersiveMode() {
        interfaceMode = interfaceMode == .immersive ? lastStandardInterfaceMode : .immersive
    }

    func removeTracks(at offsets: IndexSet) {
        guard let selectedPlaylistIndex else { return }
        var updatedPlaylist = playlists[selectedPlaylistIndex]
        let removedPaths = offsets.compactMap { index in
            updatedPlaylist.tracks.indices.contains(index) ? normalizedPath(for: updatedPlaylist.tracks[index].url) : nil
        }
        let removedCurrent = currentIndex.map { offsets.contains($0) } ?? false
        for index in offsets.sorted(by: >) {
            if updatedPlaylist.tracks.indices.contains(index) {
                updatedPlaylist.tracks.remove(at: index)
            }
        }
        playlists[selectedPlaylistIndex] = updatedPlaylist
        playbackQueue.removeAll { queued in
            queued.playlistID == updatedPlaylist.id && removedPaths.contains(normalizedPath(forPath: queued.trackPath))
        }

        guard !updatedPlaylist.tracks.isEmpty else {
            if currentPlayingPlaylistID == updatedPlaylist.id {
                stopPlayback(clearSelection: true)
            }
            return
        }

        if removedCurrent, currentPlayingPlaylistID == updatedPlaylist.id {
            let nextIndex = min(offsets.first ?? 0, playlist.count - 1)
            playTrack(at: nextIndex, in: updatedPlaylist.id)
            return
        }

        if let currentIndex, currentPlayingPlaylistID == updatedPlaylist.id {
            let shift = offsets.filter { $0 < currentIndex }.count
            self.currentIndex = currentIndex - shift
        }
    }

    func playSelected(track: AudioTrack) {
        guard let index = playlist.firstIndex(of: track) else { return }
        playTrack(at: index, in: selectedPlaylistID)
    }

    func play(track: AudioTrack, in playlistID: UUID) {
        guard let playlistIndex = playlists.firstIndex(where: { $0.id == playlistID }),
              let trackIndex = playlists[playlistIndex].tracks.firstIndex(of: track) else { return }
        playTrack(at: trackIndex, in: playlistID)
    }

    func togglePlayback() {
        if isPlaying {
            pausePlayback()
            return
        }

        if currentAudioFile != nil {
            resumePlayback()
        } else if !playlist.isEmpty {
            playTrack(at: currentIndex ?? 0, in: selectedPlaylistID)
        }
    }

    func playNext() {
        if let queued = resolveNextQueuedTrack() {
            playTrack(at: queued.trackIndex, in: queued.playlistID)
            return
        }
        guard let currentPlayingPlaylist, !currentPlayingPlaylist.tracks.isEmpty else { return }
        guard let nextIndex = resolvedNextIndex(autoAdvance: false) else { return }
        playTrack(at: nextIndex, in: currentPlayingPlaylist.id)
    }

    func playPrevious() {
        guard let currentPlayingPlaylist, !currentPlayingPlaylist.tracks.isEmpty else { return }
        let previousIndex = resolvedPreviousIndex()
        playTrack(at: previousIndex, in: currentPlayingPlaylist.id)
    }

    func seek(to progress: Double) {
        guard duration > 0 else { return }
        let clampedProgress = min(max(progress, 0), 1)
        seekToTime(duration * clampedProgress)
    }

    func seekToTime(_ time: TimeInterval) {
        guard let audioFile = currentAudioFile, duration > 0 else { return }

        let clampedTime = min(max(time, 0), duration)
        let targetFrame = AVAudioFramePosition(clampedTime * currentSampleRate)
        let shouldResume = isPlaying

        currentFramePosition = min(max(targetFrame, 0), audioFile.length)
        currentTime = clampedTime
        schedulePlayback(from: currentFramePosition, playImmediately: shouldResume)
        refreshCurrentLyricIndex()
    }

    func beginScrubbing() {
        wasPlayingBeforeDrag = isPlaying
        if isPlaying {
            pausePlayback()
        }
    }

    func endScrubbing() {
        if wasPlayingBeforeDrag {
            resumePlayback()
        }
    }

    func formatTime(_ seconds: TimeInterval) -> String {
        guard seconds.isFinite else { return "00:00" }
        let totalSeconds = Int(seconds.rounded(.down))
        let minutes = totalSeconds / 60
        let remainingSeconds = totalSeconds % 60
        return String(format: "%02d:%02d", minutes, remainingSeconds)
    }

    func queueTrackNext(_ track: AudioTrack, in playlistID: UUID) {
        guard let playlistIndex = playlists.firstIndex(where: { $0.id == playlistID }),
              playlists[playlistIndex].tracks.contains(track) else { return }

        let normalized = normalizedPath(for: track.url)
        queuedTrackPaths.removeAll { $0 == normalized }
        playbackQueue.removeAll {
            $0.playlistID == playlistID && normalizedPath(forPath: $0.trackPath) == normalized
        }
        playbackQueue.append(QueuedTrack(playlistID: playlistID, trackPath: normalized))
        queuedTrackPaths = playbackQueue.map(\.trackPath)
    }

    func addTrack(_ track: AudioTrack, to destinationPlaylistID: UUID? = nil) {
        let targetPlaylistID = destinationPlaylistID ?? selectedPlaylistID
        guard let destinationIndex = playlists.firstIndex(where: { $0.id == targetPlaylistID }) else { return }

        let normalized = normalizedPath(for: track.url)
        guard !playlists[destinationIndex].tracks.contains(where: {
            normalizedPath(for: $0.url) == normalized
        }) else {
            return
        }

        let startIndex = playlists[destinationIndex].tracks.count
        playlists[destinationIndex].tracks.append(track)
        persistSecurityScopedAccess(for: [track.url])
        enrichMetadataForNewTracks(startingAt: startIndex, in: targetPlaylistID)
    }

    private func appendTracks(_ tracks: [AudioTrack]) {
        guard !tracks.isEmpty else { return }
        guard let selectedPlaylistIndex else { return }

        let existingPaths = Set(playlists[selectedPlaylistIndex].tracks.map { normalizedPath(for: $0.url) })
        let deduplicated = tracks
            .filter { !existingPaths.contains(normalizedPath(for: $0.url)) }
            .sorted { $0.url.lastPathComponent.localizedStandardCompare($1.url.lastPathComponent) == .orderedAscending }

        guard !deduplicated.isEmpty else { return }

        let shouldAutoplay = playlists[selectedPlaylistIndex].tracks.isEmpty && currentAudioFile == nil
        let startIndex = playlists[selectedPlaylistIndex].tracks.count
        playlists[selectedPlaylistIndex].tracks.append(contentsOf: deduplicated)
        enrichMetadataForNewTracks(startingAt: startIndex, in: playlists[selectedPlaylistIndex].id)

        if shouldAutoplay {
            playTrack(at: 0, in: playlists[selectedPlaylistIndex].id)
        }
    }

    private func playTrack(at index: Int, in playlistID: UUID) {
        loadTrack(at: index, in: playlistID, startTime: 0, autoPlay: true, recordHistory: true)
    }

    private func loadTrack(at index: Int, in playlistID: UUID, startTime: TimeInterval, autoPlay: Bool, recordHistory: Bool) {
        guard let playlistIndex = playlists.firstIndex(where: { $0.id == playlistID }) else { return }
        let playlist = playlists[playlistIndex].tracks
        guard playlist.indices.contains(index) else { return }

        do {
            let track = playlist[index]
            let audioFile = try AVAudioFile(forReading: track.url)

            currentAudioFile = audioFile
            currentSampleRate = audioFile.processingFormat.sampleRate
            duration = Double(audioFile.length) / currentSampleRate
            currentChannelCountValue = Int(audioFile.processingFormat.channelCount)
            currentTrackBitRateKbps = estimateBitRate(for: track.url, duration: duration)
            currentPlayingPlaylistID = playlistID
            currentIndex = index
            isPlaying = false
            availableLyricsSources = []
            selectedLyricsSourceID = nil
            previewLyricsSource = nil
            onlineLyricsSearchResults = []
            isSearchingLyricsOnline = false
            didAttemptOnlineLyricsSearch = false
            onlineLyricsResultCount = 0
            lyrics = LyricsDocument(timedLines: [], plainText: nil)
            currentLyricIndex = nil
            availableArtworkSources = []
            selectedArtworkSourceID = nil
            previewArtworkSource = nil
            onlineArtworkSearchResults = []
            isSearchingArtworkOnline = false
            didAttemptOnlineArtworkSearch = false
            onlineArtworkResultCount = 0
            currentArtwork = nil
            let clampedTime = min(max(startTime, 0), duration)
            let startFrame = AVAudioFramePosition(clampedTime * currentSampleRate)
            currentFramePosition = min(max(startFrame, 0), audioFile.length)
            currentTime = clampedTime

            schedulePlayback(from: currentFramePosition, playImmediately: autoPlay)
            startSupplementalAssetLoad(for: track, duration: duration)
            if recordHistory, autoPlay {
                appendListeningHistory(for: track)
            }
        } catch {
            NSSound.beep()
            print("播放音频文件失败: \(error)")
        }
    }

    private func pausePlayback() {
        guard currentAudioFile != nil else { return }
        captureCurrentFramePosition()
        invalidateScheduledCompletion()
        playerNode.stop()
        isPlaying = false
    }

    private func resumePlayback() {
        guard currentAudioFile != nil else { return }
        schedulePlayback(from: currentFramePosition, playImmediately: true)
    }

    private func stopPlayback(clearSelection: Bool = false) {
        invalidateScheduledCompletion()
        playerNode.stop()
        currentAudioFile = nil
        isPlaying = false
        duration = 0
        currentTime = 0
        currentTrackBitRateKbps = nil
        currentChannelCountValue = 0
        currentFramePosition = 0
        currentStartFrame = 0
        availableLyricsSources = []
        selectedLyricsSourceID = nil
        previewLyricsSource = nil
        onlineLyricsSearchResults = []
        isSearchingLyricsOnline = false
        didAttemptOnlineLyricsSearch = false
        onlineLyricsResultCount = 0
        lyrics = LyricsDocument(timedLines: [], plainText: nil)
        currentLyricIndex = nil
        availableArtworkSources = []
        selectedArtworkSourceID = nil
        previewArtworkSource = nil
        onlineArtworkSearchResults = []
        isSearchingArtworkOnline = false
        didAttemptOnlineArtworkSearch = false
        onlineArtworkResultCount = 0
        currentArtwork = nil
        supplementalAssetTask?.cancel()
        supplementalAssetTask = nil
        if clearSelection {
            currentIndex = nil
            currentPlayingPlaylistID = nil
        }
    }

    private func startProgressTimer() {
        timerCancellable = Timer.publish(every: 0.2, on: .main, in: .common)
            .autoconnect()
            .sink { [weak self] _ in
                guard let self else { return }
                guard currentAudioFile != nil else {
                    currentTime = 0
                    return
                }

                if isPlaying {
                    currentTime = currentPlaybackTime()
                    currentFramePosition = currentPlaybackFrame()
                } else {
                    currentTime = Double(currentFramePosition) / currentSampleRate
                }

                currentTime = min(currentTime, duration)
                refreshCurrentLyricIndex()
            }
    }

    private func configureAudioEngine() {
        audioEngine.attach(playerNode)
        audioEngine.attach(timePitchNode)
        audioEngine.attach(equalizerNode)
        audioEngine.connect(playerNode, to: timePitchNode, format: nil)
        audioEngine.connect(timePitchNode, to: equalizerNode, format: nil)
        audioEngine.connect(equalizerNode, to: audioEngine.mainMixerNode, format: nil)

        let frequencies: [Float] = [31, 62, 125, 250, 500, 1_000, 2_000, 4_000, 8_000, 16_000]
        let labels = ["31", "62", "125", "250", "500", "1K", "2K", "4K", "8K", "16K"]

        for index in equalizerNode.bands.indices {
            let band = equalizerNode.bands[index]
            band.filterType = .parametric
            band.frequency = frequencies[index]
            band.bandwidth = 0.8
            band.gain = 0
            band.bypass = false
        }

        equalizerBands = zip(frequencies.indices, zip(frequencies, labels)).map { index, pair in
            EqualizerBandSetting(id: index, frequency: pair.0, label: pair.1, gain: 0)
        }
        applyPlaybackRate()

        do {
            try audioEngine.start()
        } catch {
            print("启动音频引擎失败: \(error)")
        }
    }

    private func applyPlaybackRate() {
        timePitchNode.pitch = 0
        timePitchNode.rate = playbackRate
        timePitchNode.bypass = abs(playbackRate - 1.0) < 0.001
    }

    private func applyEqualizerSettings() {
        equalizerNode.bypass = !isEqualizerEnabled

        for (index, setting) in equalizerBands.enumerated() where equalizerNode.bands.indices.contains(index) {
            let band = equalizerNode.bands[index]
            band.gain = setting.gain
            band.bypass = !isEqualizerEnabled
        }
    }

    private func schedulePlayback(from frame: AVAudioFramePosition, playImmediately: Bool) {
        guard let audioFile = currentAudioFile else { return }

        let clampedFrame = min(max(frame, 0), audioFile.length)
        let remainingFrames = audioFile.length - clampedFrame
        currentFramePosition = clampedFrame
        currentStartFrame = clampedFrame
        currentTime = Double(clampedFrame) / currentSampleRate

        invalidateScheduledCompletion()
        playerNode.stop()

        guard remainingFrames > 0 else {
            isPlaying = false
            return
        }

        let playbackToken = UUID()
        scheduledPlaybackToken = playbackToken

        playerNode.scheduleSegment(
            audioFile,
            startingFrame: clampedFrame,
            frameCount: AVAudioFrameCount(remainingFrames),
            at: nil
        ) { [weak self] in
            Task { @MainActor [weak self] in
                guard let self else { return }
                guard self.scheduledPlaybackToken == playbackToken else { return }
                self.currentFramePosition = audioFile.length
                self.currentTime = self.duration
                self.isPlaying = false
                self.handlePlaybackCompletion(successfully: true)
            }
        }

        do {
            if !audioEngine.isRunning {
                try audioEngine.start()
            }
        } catch {
            NSSound.beep()
            print("启动播放失败: \(error)")
            return
        }

        if playImmediately {
            playerNode.play()
            isPlaying = true
        } else {
            isPlaying = false
        }
    }

    private func invalidateScheduledCompletion() {
        scheduledPlaybackToken = UUID()
    }

    private func captureCurrentFramePosition() {
        currentFramePosition = currentPlaybackFrame()
        currentTime = Double(currentFramePosition) / currentSampleRate
        currentStartFrame = currentFramePosition
    }

    private func currentPlaybackFrame() -> AVAudioFramePosition {
        guard let nodeTime = playerNode.lastRenderTime,
              let playerTime = playerNode.playerTime(forNodeTime: nodeTime) else {
            return currentFramePosition
        }

        let playedFrames = Double(playerTime.sampleTime) * (currentSampleRate / playerTime.sampleRate)
        let absoluteFrame = currentStartFrame + AVAudioFramePosition(playedFrames.rounded())
        return min(max(absoluteFrame, 0), currentAudioFile?.length ?? absoluteFrame)
    }

    private func currentPlaybackTime() -> TimeInterval {
        Double(currentPlaybackFrame()) / currentSampleRate
    }

    private func refreshCurrentLyricIndex() {
        guard !lyrics.timedLines.isEmpty else {
            currentLyricIndex = nil
            return
        }

        let index = lyrics.timedLines.lastIndex { $0.time <= currentTime } ?? 0
        currentLyricIndex = index
    }

    private func deduplicatedLyricsSources(_ sources: [LyricsSourceOption]) -> [LyricsSourceOption] {
        var result: [LyricsSourceOption] = []

        for source in sources where !source.document.isEmpty {
            guard !result.contains(where: { $0.id == source.id || $0.document == source.document }) else { continue }
            result.append(source)
        }

        return result
    }

    private func deduplicatedArtworkSources(_ sources: [ArtworkOption]) -> [ArtworkOption] {
        var result: [ArtworkOption] = []

        for source in sources {
            guard !result.contains(where: { $0.id == source.id }) else { continue }
            result.append(source)
        }

        return result
    }

    private func applyLyricsSources(
        _ sources: [LyricsSourceOption],
        preferredSelection preferredSourceID: String? = nil,
        preserveSelection: Bool = true
    ) {
        let uniqueSources = deduplicatedLyricsSources(sources)
        availableLyricsSources = uniqueSources

        let fallbackID = preserveSelection ? selectedLyricsSourceID : nil
        let selectedID = preferredSourceID ?? fallbackID ?? uniqueSources.first?.id

        if let selectedID,
           uniqueSources.contains(where: { $0.id == selectedID }) {
            selectedLyricsSourceID = selectedID
        } else {
            selectedLyricsSourceID = nil
        }

        syncDisplayedLyrics()
    }

    private func mergeLyricsSources(
        _ sources: [LyricsSourceOption],
        preferredSelection preferredSourceID: String? = nil
    ) {
        applyLyricsSources(
            availableLyricsSources + sources,
            preferredSelection: preferredSourceID,
            preserveSelection: true
        )
    }

    private func applyArtworkSources(
        _ sources: [ArtworkOption],
        preferredSelection preferredSourceID: String? = nil,
        preserveSelection: Bool = true
    ) {
        let uniqueSources = deduplicatedArtworkSources(sources)
        availableArtworkSources = uniqueSources

        let fallbackID = preserveSelection ? selectedArtworkSourceID : nil
        let selectedID = preferredSourceID ?? fallbackID ?? uniqueSources.first?.id

        if let selectedID,
           uniqueSources.contains(where: { $0.id == selectedID }) {
            selectedArtworkSourceID = selectedID
        } else {
            selectedArtworkSourceID = nil
        }

        syncDisplayedArtwork()
    }

    private func mergeArtworkSources(
        _ sources: [ArtworkOption],
        preferredSelection preferredSourceID: String? = nil
    ) {
        applyArtworkSources(
            availableArtworkSources + sources,
            preferredSelection: preferredSourceID,
            preserveSelection: true
        )
    }

    private func syncDisplayedLyrics() {
        if let previewLyricsSource {
            lyrics = previewLyricsSource.document
        } else if let selectedLyricsSource {
            lyrics = selectedLyricsSource.document
        } else {
            lyrics = LyricsDocument(timedLines: [], plainText: nil)
        }

        refreshCurrentLyricIndex()
    }

    private func syncDisplayedArtwork() {
        if let previewArtworkSource {
            currentArtwork = previewArtworkSource.image
        } else if let selectedArtworkSource {
            currentArtwork = selectedArtworkSource.image
        } else {
            currentArtwork = nil
        }
    }

    private func estimateBitRate(for url: URL, duration: TimeInterval) -> Double? {
        guard duration > 0,
              let fileSize = try? url.resourceValues(forKeys: [.fileSizeKey]).fileSize,
              fileSize > 0 else {
            return nil
        }

        return (Double(fileSize) * 8) / duration / 1_000
    }

    private func scanDirectory(_ directory: URL) -> [AudioTrack] {
        guard let enumerator = FileManager.default.enumerator(
            at: directory,
            includingPropertiesForKeys: [.isRegularFileKey],
            options: [.skipsHiddenFiles, .skipsPackageDescendants]
        ) else {
            return []
        }

        var tracks: [AudioTrack] = []
        for case let fileURL as URL in enumerator {
            guard Self.supportedExtensions.contains(fileURL.pathExtension.lowercased()) else { continue }
            tracks.append(AudioTrack(url: fileURL))
        }

        return tracks
    }

    private func normalizedPath(for url: URL) -> String {
        url.standardizedFileURL.path
    }

    private func normalizedPath(forPath path: String) -> String {
        URL(fileURLWithPath: path).standardizedFileURL.path
    }

    private func resolvedNextIndex(autoAdvance: Bool) -> Int? {
        guard let currentPlayingPlaylist, !currentPlayingPlaylist.tracks.isEmpty else { return nil }
        let tracks = currentPlayingPlaylist.tracks

        switch playbackMode {
        case .shuffle:
            guard tracks.count > 1 else { return currentIndex ?? 0 }
            var candidates = Array(tracks.indices)
            if let currentIndex {
                candidates.removeAll { $0 == currentIndex }
            }
            return candidates.randomElement()
        case .listLoop:
            return ((currentIndex ?? -1) + 1) % tracks.count
        case .sequential:
            let proposed = (currentIndex ?? -1) + 1
            if proposed < tracks.count {
                return proposed
            }
            return autoAdvance ? nil : 0
        }
    }

    private func resolvedPreviousIndex() -> Int {
        guard let currentPlayingPlaylist, !currentPlayingPlaylist.tracks.isEmpty else { return 0 }
        let tracks = currentPlayingPlaylist.tracks

        switch playbackMode {
        case .shuffle:
            guard tracks.count > 1 else { return currentIndex ?? 0 }
            var candidates = Array(tracks.indices)
            if let currentIndex {
                candidates.removeAll { $0 == currentIndex }
            }
            return candidates.randomElement() ?? 0
        case .listLoop, .sequential:
            return ((currentIndex ?? tracks.count) - 1 + tracks.count) % tracks.count
        }
    }

    private func handlePlaybackCompletion(successfully: Bool) {
        if successfully {
            if let queued = resolveNextQueuedTrack() {
                playTrack(at: queued.trackIndex, in: queued.playlistID)
                return
            }
            if let nextIndex = resolvedNextIndex(autoAdvance: true) {
                if let currentPlayingPlaylistID {
                    playTrack(at: nextIndex, in: currentPlayingPlaylistID)
                }
            } else {
                currentFramePosition = currentAudioFile?.length ?? currentFramePosition
                currentTime = duration
                isPlaying = false
            }
        } else {
            stopPlayback()
        }
    }

    private func isDirectory(_ url: URL) -> Bool {
        (try? url.resourceValues(forKeys: [.isDirectoryKey]).isDirectory) ?? false
    }

    private func configurePersistence() {
        NotificationCenter.default.publisher(for: NSApplication.willTerminateNotification)
            .sink { [weak self] _ in
                self?.persistAppState(capturingPlaybackPosition: true)
            }
            .store(in: &cancellables)

        Publishers.CombineLatest4($playlists, $selectedPlaylistID, $playbackMode, $interfaceMode)
            .dropFirst()
            .debounce(for: .milliseconds(300), scheduler: RunLoop.main)
            .sink { [weak self] _, _, _, _ in
                self?.persistAppState()
            }
            .store(in: &cancellables)

        $appLanguage
            .dropFirst()
            .debounce(for: .milliseconds(150), scheduler: RunLoop.main)
            .sink { [weak self] _ in
                self?.persistAppState()
            }
            .store(in: &cancellables)

        Publishers.CombineLatest4($volume, $isDesktopLyricsVisible, $desktopLyricsFontSize, $desktopLyricsOpacity)
            .dropFirst()
            .debounce(for: .milliseconds(300), scheduler: RunLoop.main)
            .sink { [weak self] _, _, _, _ in
                self?.persistAppState()
            }
            .store(in: &cancellables)

        $playbackRate
            .dropFirst()
            .debounce(for: .milliseconds(150), scheduler: RunLoop.main)
            .sink { [weak self] _ in
                self?.persistAppState()
            }
            .store(in: &cancellables)

        Publishers.CombineLatest4($isDesktopLyricsLocked, $desktopLyricsDisplayMode, $desktopLyricsBackgroundStyle, $isEqualizerEnabled)
            .dropFirst()
            .debounce(for: .milliseconds(300), scheduler: RunLoop.main)
            .sink { [weak self] _, _, _, _ in
                self?.persistAppState()
            }
            .store(in: &cancellables)

        Publishers.CombineLatest4($isEqualizerExpanded, $selectedEqualizerPreset, $equalizerBands, $selectedUserEqualizerPresetID)
            .dropFirst()
            .debounce(for: .milliseconds(300), scheduler: RunLoop.main)
            .sink { [weak self] _, _, _, _ in
                self?.persistAppState()
            }
            .store(in: &cancellables)

        $userEqualizerPresets
            .dropFirst()
            .debounce(for: .milliseconds(300), scheduler: RunLoop.main)
            .sink { [weak self] _ in
                self?.persistAppState()
            }
            .store(in: &cancellables)

        Publishers.CombineLatest($appTheme, $customBackgroundImagePath)
            .dropFirst()
            .debounce(for: .milliseconds(300), scheduler: RunLoop.main)
            .sink { [weak self] _, _ in
                self?.persistAppState()
            }
            .store(in: &cancellables)
    }

    private func appendListeningHistory(for track: AudioTrack) {
        listeningHistory.insert(ListeningHistoryRecord(track: track), at: 0)
        if listeningHistory.count > 5_000 {
            listeningHistory.removeLast(listeningHistory.count - 5_000)
        }
        persistListeningHistory()
    }

    private func restoreListeningHistory() {
        guard let data = UserDefaults.standard.data(forKey: Self.listeningHistoryDefaultsKey),
              let decoded = try? JSONDecoder().decode([ListeningHistoryRecord].self, from: data) else {
            listeningHistory = []
            return
        }
        listeningHistory = decoded
    }

    private func persistListeningHistory() {
        guard let data = try? JSONEncoder().encode(listeningHistory) else { return }
        UserDefaults.standard.set(data, forKey: Self.listeningHistoryDefaultsKey)
    }

    private func restorePersistedState() {
        guard let data = UserDefaults.standard.data(forKey: Self.appStateDefaultsKey),
              let persisted = try? JSONDecoder().decode(PersistedAppState.self, from: data) else {
            return
        }

        applyPersistedAppState(persisted)
    }

    private func applyPersistedAppState(_ persisted: PersistedAppState) {
        isRestoringState = true
        defer { isRestoringState = false }

        let restoredPlaylists = persisted.playlists.map(\.resolvedPlaylist)
        if !restoredPlaylists.isEmpty {
            playlists = restoredPlaylists
        }

        if playlists.contains(where: { $0.id == persisted.selectedPlaylistID }) {
            selectedPlaylistID = persisted.selectedPlaylistID
        } else if let firstID = playlists.first?.id {
            selectedPlaylistID = firstID
        }

        appLanguage = AppLanguage(rawValue: persisted.appLanguage ?? AppLanguage.chinese.rawValue) ?? .chinese
        playbackMode = PlaybackMode(rawValue: persisted.playbackMode) ?? .sequential
        if let persistedLastMode = persisted.lastStandardInterfaceMode,
           let resolvedMode = InterfaceMode(rawValue: persistedLastMode),
           resolvedMode != .immersive {
            lastStandardInterfaceMode = resolvedMode
        }
        interfaceMode = InterfaceMode(rawValue: persisted.interfaceMode) ?? .compact
        volume = persisted.volume
        setPlaybackRate(persisted.playbackRate ?? 1.0)
        isDesktopLyricsVisible = persisted.isDesktopLyricsVisible
        desktopLyricsFontSize = persisted.desktopLyricsFontSize
        desktopLyricsOpacity = persisted.desktopLyricsOpacity
        isDesktopLyricsLocked = persisted.isDesktopLyricsLocked
        desktopLyricsDisplayMode = DesktopLyricsDisplayMode(rawValue: persisted.desktopLyricsDisplayMode) ?? .dualLine
        desktopLyricsBackgroundStyle = DesktopLyricsBackgroundStyle(rawValue: persisted.desktopLyricsBackgroundStyle) ?? .themed
        isEqualizerEnabled = persisted.isEqualizerEnabled
        isEqualizerExpanded = persisted.isEqualizerExpanded
        selectedEqualizerPreset = EqualizerPreset(persistedValue: persisted.selectedEqualizerPreset)
        userEqualizerPresets = persisted.userEqualizerPresets ?? []
        if let selectedPresetID = persisted.selectedUserEqualizerPresetID,
           userEqualizerPresets.contains(where: { $0.id == selectedPresetID }) {
            selectedUserEqualizerPresetID = selectedPresetID
        } else {
            selectedUserEqualizerPresetID = nil
        }
        appTheme = AppTheme(rawValue: persisted.appTheme) ?? .system
        if persisted.equalizerGains.count == equalizerBands.count {
            equalizerBands = zip(equalizerBands, persisted.equalizerGains).map { band, gain in
                var updated = band
                updated.gain = gain
                return updated
            }
        }
        if let customBackgroundImagePath = persisted.customBackgroundImagePath {
            loadCustomBackgroundImage(fromPath: customBackgroundImagePath)
        }

        playbackQueue = (persisted.queuedTracks ?? []).map {
            QueuedTrack(playlistID: $0.playlistID, trackPath: normalizedPath(forPath: $0.trackPath))
        }
        queuedTrackPaths = playbackQueue.map(\.trackPath)
        preloadSecurityScopedAccessForAllTracks(promptIfNeeded: false)

        restorePlaybackState(persisted.playbackState)
    }

    private func restorePlaybackState(_ playbackState: PersistedPlaybackState) {
        guard let playlistID = playbackState.currentPlayingPlaylistID,
              let trackPath = playbackState.currentTrackPath,
              let playlistIndex = playlists.firstIndex(where: { $0.id == playlistID }) else {
            return
        }

        let normalizedTrackPath = normalizedPath(forPath: trackPath)
        guard let trackIndex = playlists[playlistIndex].tracks.firstIndex(where: { normalizedPath(for: $0.url) == normalizedTrackPath }) else {
            return
        }

        loadTrack(
            at: trackIndex,
            in: playlistID,
            startTime: playbackState.currentTime,
            autoPlay: playbackState.wasPlaying,
            recordHistory: false
        )
    }

    private func persistAppState(capturingPlaybackPosition: Bool = false) {
        guard let state = makePersistedAppState(capturingPlaybackPosition: capturingPlaybackPosition),
              let data = try? JSONEncoder().encode(state) else { return }
        UserDefaults.standard.set(data, forKey: Self.appStateDefaultsKey)
    }

    private func makePersistedAppState(capturingPlaybackPosition: Bool) -> PersistedAppState? {
        guard !isRestoringState else { return nil }

        if capturingPlaybackPosition, currentAudioFile != nil {
            if isPlaying {
                captureCurrentFramePosition()
            } else {
                currentTime = Double(currentFramePosition) / currentSampleRate
            }
        }

        guard let resolvedSelectedPlaylistID = playlists.first(where: { $0.id == selectedPlaylistID })?.id ?? playlists.first?.id else {
            return nil
        }

        let playbackState = PersistedPlaybackState(
            selectedPlaylistID: selectedPlaylistID,
            currentPlayingPlaylistID: currentPlayingPlaylistID,
            currentTrackPath: currentTrack?.url.path,
            currentTime: currentTime,
            wasPlaying: isPlaying
        )

        return PersistedAppState(
            playlists: playlists.map(PersistedPlaylistCollection.init),
            selectedPlaylistID: resolvedSelectedPlaylistID,
            appLanguage: appLanguage.rawValue,
            playbackMode: playbackMode.rawValue,
            interfaceMode: interfaceMode.rawValue,
            lastStandardInterfaceMode: lastStandardInterfaceMode.rawValue,
            volume: volume,
            playbackRate: playbackRate,
            isDesktopLyricsVisible: isDesktopLyricsVisible,
            desktopLyricsFontSize: desktopLyricsFontSize,
            desktopLyricsOpacity: desktopLyricsOpacity,
            isDesktopLyricsLocked: isDesktopLyricsLocked,
            desktopLyricsDisplayMode: desktopLyricsDisplayMode.rawValue,
            desktopLyricsBackgroundStyle: desktopLyricsBackgroundStyle.rawValue,
            isEqualizerEnabled: isEqualizerEnabled,
            isEqualizerExpanded: isEqualizerExpanded,
            selectedEqualizerPreset: selectedEqualizerPreset.rawValue,
            equalizerGains: equalizerBands.map(\.gain),
            appTheme: appTheme.rawValue,
            customBackgroundImagePath: customBackgroundImagePath,
            queuedTracks: playbackQueue.map {
                PersistedQueuedTrack(playlistID: $0.playlistID, trackPath: $0.trackPath)
            },
            userEqualizerPresets: userEqualizerPresets,
            selectedUserEqualizerPresetID: selectedUserEqualizerPresetID,
            playbackState: playbackState
        )
    }

    private func makeExportedUserDataPackage() -> ExportedUserDataPackage? {
        guard let appState = makePersistedAppState(capturingPlaybackPosition: true) else { return nil }
        return ExportedUserDataPackage(
            version: 1,
            exportedAt: Date(),
            appState: appState,
            listeningHistory: listeningHistory,
            securityScopedBookmarks: serializedSecurityScopedBookmarks(),
            backgroundAsset: exportedBackgroundAsset()
        )
    }

    private func serializedSecurityScopedBookmarks() -> [PersistedSecurityScopedBookmark] {
        securityScopedBookmarks.map {
            PersistedSecurityScopedBookmark(path: $0.key, data: $0.value)
        }
        .sorted { $0.path < $1.path }
    }

    private func exportedBackgroundAsset() -> ExportedBackgroundAsset? {
        guard appTheme == .customImage, let customBackgroundImagePath else { return nil }
        guard let data = try? Data(contentsOf: URL(fileURLWithPath: customBackgroundImagePath)) else { return nil }
        return ExportedBackgroundAsset(
            originalFileName: URL(fileURLWithPath: customBackgroundImagePath).lastPathComponent,
            data: data
        )
    }

    private func restoreSecurityScopedBookmarks() {
        guard let data = UserDefaults.standard.data(forKey: Self.securityScopedBookmarksDefaultsKey),
              let bookmarks = try? JSONDecoder().decode([PersistedSecurityScopedBookmark].self, from: data) else {
            return
        }

        securityScopedBookmarks = Dictionary(uniqueKeysWithValues: bookmarks.map { ($0.path, $0.data) })

        var updatedBookmarks = securityScopedBookmarks
        var didUpdate = false

        for (path, bookmarkData) in securityScopedBookmarks {
            var isStale = false
            guard let url = try? URL(
                resolvingBookmarkData: bookmarkData,
                options: [.withSecurityScope, .withoutUI],
                relativeTo: nil,
                bookmarkDataIsStale: &isStale
            ) else {
                updatedBookmarks.removeValue(forKey: path)
                didUpdate = true
                continue
            }

            if url.startAccessingSecurityScopedResource() {
                activeSecurityScopedURLs[path] = url
            }

            if isStale,
               let refreshedBookmark = try? url.bookmarkData(
                options: [.withSecurityScope, .securityScopeAllowOnlyReadAccess],
                includingResourceValuesForKeys: nil,
                relativeTo: nil
               ) {
                updatedBookmarks[path] = refreshedBookmark
                didUpdate = true
            }
        }

        securityScopedBookmarks = updatedBookmarks
        if didUpdate {
            saveSecurityScopedBookmarks()
        }
    }

    private func persistSecurityScopedAccess(for urls: [URL]) {
        guard !urls.isEmpty else { return }

        var didUpdate = false

        for url in urls {
            let normalized = normalizedPath(for: url)
            let bookmarkOwner = url.standardizedFileURL

            if activeSecurityScopedURLs[normalized] == nil, bookmarkOwner.startAccessingSecurityScopedResource() {
                activeSecurityScopedURLs[normalized] = bookmarkOwner
            }

            guard let bookmarkData = try? bookmarkOwner.bookmarkData(
                options: [.withSecurityScope, .securityScopeAllowOnlyReadAccess],
                includingResourceValuesForKeys: nil,
                relativeTo: nil
            ) else {
                continue
            }

            if securityScopedBookmarks[normalized] != bookmarkData {
                securityScopedBookmarks[normalized] = bookmarkData
                didUpdate = true
            }
        }

        if didUpdate {
            saveSecurityScopedBookmarks()
        }
    }

    private func preloadSecurityScopedAccessForAllTracks(promptIfNeeded: Bool) {
        let allTrackURLs = Array(Set(playlists.flatMap(\.tracks).map { normalizedPath(for: $0.url) }))
            .map { URL(fileURLWithPath: $0) }

        guard !allTrackURLs.isEmpty else { return }

        persistSecurityScopedAccess(for: allTrackURLs)

        let unresolved = allTrackURLs.filter { !hasPersistedSecurityScopedAccess(for: $0) }
        guard promptIfNeeded, !unresolved.isEmpty else { return }
        requestSecurityScopedAccessForTracks(unresolved)
    }

    private func hasPersistedSecurityScopedAccess(for url: URL) -> Bool {
        let normalizedTrackPath = normalizedPath(for: url)

        if activeSecurityScopedURLs[normalizedTrackPath] != nil || securityScopedBookmarks[normalizedTrackPath] != nil {
            return true
        }

        return securityScopedBookmarks.keys.contains { bookmarkedPath in
            path(bookmarkedPath, containsDescendantPath: normalizedTrackPath)
        } || activeSecurityScopedURLs.keys.contains { activePath in
            path(activePath, containsDescendantPath: normalizedTrackPath)
        }
    }

    private func path(_ parentPath: String, containsDescendantPath childPath: String) -> Bool {
        let parentURL = URL(fileURLWithPath: parentPath).standardizedFileURL
        let childURL = URL(fileURLWithPath: childPath).standardizedFileURL
        let parentComponents = parentURL.pathComponents
        let childComponents = childURL.pathComponents

        guard parentComponents.count < childComponents.count else { return false }
        return Array(childComponents.prefix(parentComponents.count)) == parentComponents
    }

    private func requestSecurityScopedAccessForTracks(_ missingTracks: [URL]) {
        let panel = NSOpenPanel()
        panel.message = appLanguage.pick(
            "为避免切歌时重复申请权限，请一次性选择当前歌单对应的音频文件或它们所在文件夹。",
            "To avoid repeated permission prompts while switching tracks, select the current playlist files or their parent folders once."
        )
        panel.prompt = appLanguage.pick("授权", "Grant Access")
        panel.allowedContentTypes = [
            .folder,
            UTType(filenameExtension: "flac"),
            UTType(filenameExtension: "wav"),
            UTType.mp3,
            UTType(filenameExtension: "dsf"),
            UTType(filenameExtension: "dff"),
            UTType(filenameExtension: "dsd")
        ].compactMap { $0 }
        panel.allowsMultipleSelection = true
        panel.canChooseDirectories = true
        panel.canChooseFiles = true

        NSApp.activate(ignoringOtherApps: true)
        guard panel.runModal() == .OK else { return }

        persistSecurityScopedAccess(for: panel.urls)
        persistSecurityScopedAccess(for: missingTracks.filter { trackURL in
            panel.urls.contains { selectedURL in
                let standardizedSelected = selectedURL.standardizedFileURL
                let standardizedTrack = trackURL.standardizedFileURL
                return standardizedSelected == standardizedTrack ||
                    path(standardizedSelected.path, containsDescendantPath: standardizedTrack.path)
            }
        })
    }

    private func saveSecurityScopedBookmarks() {
        let payload = serializedSecurityScopedBookmarks()

        guard let data = try? JSONEncoder().encode(payload) else { return }
        UserDefaults.standard.set(data, forKey: Self.securityScopedBookmarksDefaultsKey)
    }

    private func applyImportedUserData(_ package: ExportedUserDataPackage) throws {
        activeSecurityScopedURLs.values.forEach { $0.stopAccessingSecurityScopedResource() }
        activeSecurityScopedURLs.removeAll()

        stopPlayback(clearSelection: true)
        listeningHistory = package.listeningHistory
        persistListeningHistory()

        securityScopedBookmarks = Dictionary(uniqueKeysWithValues: package.securityScopedBookmarks.map { ($0.path, $0.data) })
        saveSecurityScopedBookmarks()
        restoreSecurityScopedBookmarks()

        applyPersistedAppState(package.appState)
        preloadSecurityScopedAccessForAllTracks(promptIfNeeded: true)

        if let backgroundAsset = package.backgroundAsset,
           let storedPath = try? storeImportedBackgroundAsset(backgroundAsset) {
            loadCustomBackgroundImage(fromPath: storedPath)
            appTheme = .customImage
        }

        persistAppState(capturingPlaybackPosition: false)
    }

    private func confirmPersonalDataImport() -> Bool {
        let alert = NSAlert()
        alert.messageText = appLanguage.pick("导入将覆盖当前数据", "Import Will Replace Current Data")
        alert.informativeText = appLanguage.pick(
            "当前歌单、听歌历史、均衡器预设、主题与桌面歌词设置会被导入内容替换。",
            "Your playlists, listening history, equalizer presets, themes, and desktop lyrics settings will be replaced by the imported data."
        )
        alert.alertStyle = .warning
        alert.addButton(withTitle: appLanguage.pick("继续导入", "Continue"))
        alert.addButton(withTitle: appLanguage.pick("取消", "Cancel"))
        NSApp.activate(ignoringOtherApps: true)
        return alert.runModal() == .alertFirstButtonReturn
    }

    private func presentModalMessage(title: String, message: String, style: NSAlert.Style) {
        let alert = NSAlert()
        alert.messageText = title
        alert.informativeText = message
        alert.alertStyle = style
        alert.addButton(withTitle: appLanguage.pick("好", "OK"))
        NSApp.activate(ignoringOtherApps: true)
        alert.runModal()
    }

    private struct BatchScrapeResult {
        let lyricsSaved: Bool
        let artworkSaved: Bool
        let wasUnresolved: Bool
        let hadFailure: Bool
    }

    private func scrapeMissingMetadata(for track: AudioTrack) async -> BatchScrapeResult {
        let embeddedLyrics = await AudioAssetLoader.loadLyricsSources(for: track.url)
        let sidecarLyrics = LyricsParser.loadLyricsSources(for: track)
        let localArtwork = await AudioAssetLoader.loadArtworkAsset(for: track.url)

        let needsLyrics = embeddedLyrics.isEmpty && sidecarLyrics.isEmpty
        let needsArtwork = localArtwork == nil

        guard needsLyrics || needsArtwork else {
            return BatchScrapeResult(
                lyricsSaved: false,
                artworkSaved: false,
                wasUnresolved: false,
                hadFailure: false
            )
        }

        let info = TrackSearchInfo(
            title: track.title,
            artist: track.artist,
            album: track.album,
            duration: nil
        )

        var lyricsSaved = false
        var artworkSaved = false
        var hadFailure = false
        var unresolvedTargets = 0

        if needsLyrics {
            let fetchedLyrics = await OnlineMetadataService.shared.fetchLyricsSources(
                for: track,
                info: info,
                forceRefresh: true
            )

            if let firstLyrics = fetchedLyrics.first {
                do {
                    try saveLyricsSidecar(firstLyrics, for: track)
                    lyricsSaved = true
                } catch {
                    hadFailure = true
                }
            } else {
                unresolvedTargets += 1
            }
        }

        if needsArtwork {
            let fetchedArtwork = await OnlineMetadataService.shared.fetchArtworkOptions(
                for: track,
                info: info,
                forceRefresh: true
            )

            if let firstArtwork = fetchedArtwork.first {
                do {
                    try saveArtworkSidecar(firstArtwork, for: track)
                    artworkSaved = true
                } catch {
                    hadFailure = true
                }
            } else {
                unresolvedTargets += 1
            }
        }

        return BatchScrapeResult(
            lyricsSaved: lyricsSaved,
            artworkSaved: artworkSaved,
            wasUnresolved: unresolvedTargets > 0 && !hadFailure,
            hadFailure: hadFailure
        )
    }

    private func saveLyricsSidecar(_ source: LyricsSourceOption, for track: AudioTrack) throws {
        if !source.document.timedLines.isEmpty {
            let destination = track.parentDirectory
                .appendingPathComponent(track.baseFilename)
                .appendingPathExtension("lrc")
            let content = lrcString(from: source.document.timedLines)
            try content.write(to: destination, atomically: true, encoding: .utf8)
            return
        }

        let plainText = source.document.plainText?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        guard !plainText.isEmpty else {
            throw CocoaError(.fileWriteUnknown)
        }

        let destination = track.parentDirectory
            .appendingPathComponent(track.baseFilename)
            .appendingPathExtension("txt")
        try plainText.write(to: destination, atomically: true, encoding: .utf8)
    }

    private func saveArtworkSidecar(_ artwork: ArtworkOption, for track: AudioTrack) throws {
        let destination = track.parentDirectory
            .appendingPathComponent(track.baseFilename + ".cover")
            .appendingPathExtension("png")

        guard
            let tiff = artwork.image.tiffRepresentation,
            let rep = NSBitmapImageRep(data: tiff),
            let png = rep.representation(using: .png, properties: [:])
        else {
            throw CocoaError(.fileWriteUnknown)
        }

        try png.write(to: destination, options: .atomic)
    }

    private func lrcString(from lines: [TimedLyricLine]) -> String {
        lines.map { line in
            "[\(lrcTimestamp(for: line.time))]\(line.text)"
        }
        .joined(separator: "\n")
    }

    private func lrcTimestamp(for time: TimeInterval) -> String {
        let totalHundredths = Int((time * 100).rounded())
        let minutes = totalHundredths / 6000
        let seconds = (totalHundredths % 6000) / 100
        let hundredths = totalHundredths % 100
        return String(format: "%02d:%02d.%02d", minutes, seconds, hundredths)
    }

    private func startSupplementalAssetLoad(for track: AudioTrack, duration: TimeInterval) {
        supplementalAssetTask?.cancel()
        supplementalAssetTask = Task { [weak self] in
            guard let self else { return }

            let embeddedAssets = await AudioAssetLoader.loadLyricsSourcesAndArtwork(for: track.url)
            guard !Task.isCancelled, self.currentTrack?.url == track.url else { return }

            if !embeddedAssets.lyricsSources.isEmpty {
                self.applyLyricsSources(
                    embeddedAssets.lyricsSources,
                    preferredSelection: embeddedAssets.lyricsSources.first?.id,
                    preserveSelection: false
                )
            }

            let sidecarSources = LyricsParser.loadLyricsSources(for: track)
            if !sidecarSources.isEmpty,
               !Task.isCancelled,
               self.currentTrack?.url == track.url {
                if self.availableLyricsSources.isEmpty {
                    self.applyLyricsSources(
                        sidecarSources,
                        preferredSelection: sidecarSources.first?.id,
                        preserveSelection: false
                    )
                } else {
                    self.mergeLyricsSources(sidecarSources)
                }
            }

            if let artwork = embeddedAssets.artwork {
                self.applyArtworkSources(
                    [
                        ArtworkOption(
                            sourceID: artwork.kind.rawValue,
                            kind: artwork.kind,
                            image: artwork.image,
                            rank: nil,
                            title: track.title,
                            artistName: track.artist,
                            albumName: track.album,
                            providerName: nil
                        )
                    ],
                    preferredSelection: artwork.kind.rawValue,
                    preserveSelection: false
                )
            }

            let lyricsInfo = TrackSearchInfo(
                title: track.title,
                artist: track.artist,
                album: track.album,
                duration: duration
            )

            if self.availableLyricsSources.isEmpty {
                self.didAttemptOnlineLyricsSearch = true
                let fetchedLyricsSources = await OnlineMetadataService.shared.fetchLyricsSources(for: track, info: lyricsInfo)
                if !Task.isCancelled,
                   self.currentTrack?.url == track.url {
                    self.onlineLyricsSearchResults = fetchedLyricsSources
                    self.onlineLyricsResultCount = fetchedLyricsSources.count
                }
            }

            let artworkInfo = TrackSearchInfo(
                title: track.title,
                artist: track.artist,
                album: track.album,
                duration: self.duration
            )
            if self.availableArtworkSources.isEmpty {
                self.didAttemptOnlineArtworkSearch = true
                let fetchedArtworkSources = await OnlineMetadataService.shared.fetchArtworkOptions(for: track, info: artworkInfo)
                if !Task.isCancelled,
                   self.currentTrack?.url == track.url {
                    self.onlineArtworkSearchResults = fetchedArtworkSources
                    self.onlineArtworkResultCount = fetchedArtworkSources.count
                    if fetchedArtworkSources.isEmpty {
                        self.syncDisplayedArtwork()
                    }
                }
            }
        }
    }

    private func enrichMetadataForNewTracks(startingAt startIndex: Int, in playlistID: UUID) {
        guard let playlistIndex = playlists.firstIndex(where: { $0.id == playlistID }) else { return }
        guard playlists[playlistIndex].tracks.indices.contains(startIndex) else { return }

        let targets = Array(playlists[playlistIndex].tracks[startIndex...].enumerated())
        for (offset, track) in targets {
            let index = startIndex + offset
            Task { @MainActor [weak self] in
                guard let self else { return }
                let metadata = await AudioAssetLoader.loadMetadata(for: track.url)
                guard let playlistIndex = self.playlists.firstIndex(where: { $0.id == playlistID }) else { return }
                guard self.playlists[playlistIndex].tracks.indices.contains(index), self.playlists[playlistIndex].tracks[index].url == track.url else { return }

                let updated = self.playlists[playlistIndex].tracks[index].withMetadata(
                    title: metadata.title,
                    artist: metadata.artist,
                    album: metadata.album
                )
                self.playlists[playlistIndex].tracks[index] = updated
            }
        }
    }

    private func loadURL(from provider: NSItemProvider) async -> URL? {
        await withCheckedContinuation { continuation in
            provider.loadItem(forTypeIdentifier: UTType.fileURL.identifier, options: nil) { item, _ in
                if let data = item as? Data,
                   let url = URL(dataRepresentation: data, relativeTo: nil) {
                    continuation.resume(returning: url)
                    return
                }

                if let url = item as? URL {
                    continuation.resume(returning: url)
                    return
                }

                continuation.resume(returning: nil)
            }
        }
    }

    private static func makeDefaultEqualizerBands() -> [EqualizerBandSetting] {
        let frequencies: [Float] = [31, 62, 125, 250, 500, 1_000, 2_000, 4_000, 8_000, 16_000]
        let labels = ["31", "62", "125", "250", "500", "1K", "2K", "4K", "8K", "16K"]

        return zip(frequencies.indices, zip(frequencies, labels)).map { index, pair in
            EqualizerBandSetting(id: index, frequency: pair.0, label: pair.1, gain: 0)
        }
    }

    private static func equalizerBands(forGains gains: [Float]) -> [EqualizerBandSetting] {
        makeDefaultEqualizerBands().enumerated().map { index, band in
            var updated = band
            if gains.indices.contains(index) {
                updated.gain = gains[index]
            }
            return updated
        }
    }

    private static func equalizerBands(for preset: EqualizerPreset) -> [EqualizerBandSetting] {
        let gains: [Float]

        switch preset {
        case .custom:
            gains = Array(repeating: 0, count: 10)
        case .vocal:
            gains = [-2, -1, 0, 2, 3, 4, 4, 3, 1, 0]
        case .bassBoost:
            gains = [5, 4, 3, 2, 1, 0, -1, -2, -2, -2]
        case .pop:
            gains = [-1, 2, 3, 4, 2, 0, -1, -1, 1, 2]
        case .rock:
            gains = [3, 2, 1, 0, -1, 1, 3, 4, 4, 3]
        case .classical:
            gains = [0, 0, -1, -2, 0, 2, 3, 3, 2, 1]
        case .musicHall:
            gains = [2, 2, 1, 0, 0, 1, 2, 3, 3, 2]
        case .studio:
            gains = [0, 0, 1, 1, 0, 0, 1, 1, 0, -1]
        case .ktv:
            gains = [4, 3, 1, -1, 0, 2, 4, 5, 3, 1]
        case .concert:
            gains = [5, 4, 2, 0, -1, 1, 3, 4, 5, 4]
        }

        return equalizerBands(forGains: gains)
    }

    private var selectedPlaylistIndex: Int? {
        playlists.firstIndex(where: { $0.id == selectedPlaylistID })
    }

    private var currentPlaylist: PlaylistCollection {
        playlists[selectedPlaylistIndex ?? 0]
    }

    private var currentPlayingPlaylist: PlaylistCollection? {
        guard let currentPlayingPlaylistID else { return nil }
        return playlists.first(where: { $0.id == currentPlayingPlaylistID })
    }

    private struct QueuedTrack {
        let playlistID: UUID
        let trackPath: String
    }

    private var playbackQueue: [QueuedTrack] = [] {
        didSet {
            queuedTrackPaths = playbackQueue.map(\.trackPath)
        }
    }

    private func nextPlaylistName() -> String {
        let base = appLanguage == .english ? "New Playlist" : "新建歌单"
        var counter = 1
        while playlists.contains(where: { $0.name == "\(base) \(counter)" }) {
            counter += 1
        }
        return "\(base) \(counter)"
    }

    private func uniquePlaylistName(for baseName: String) -> String {
        guard playlists.contains(where: { $0.name == baseName }) else { return baseName }
        var counter = 2
        while playlists.contains(where: { $0.name == "\(baseName) \(counter)" }) {
            counter += 1
        }
        return "\(baseName) \(counter)"
    }

    private func resolveNextQueuedTrack() -> (playlistID: UUID, trackIndex: Int)? {
        while !playbackQueue.isEmpty {
            let queued = playbackQueue.removeFirst()
            guard let playlistIndex = playlists.firstIndex(where: { $0.id == queued.playlistID }) else { continue }
            let normalized = normalizedPath(forPath: queued.trackPath)
            guard let trackIndex = playlists[playlistIndex].tracks.firstIndex(where: {
                normalizedPath(for: $0.url) == normalized
            }) else { continue }
            return (queued.playlistID, trackIndex)
        }
        return nil
    }

    private func setCustomBackgroundImage(from url: URL) {
        guard let image = NSImage(contentsOf: url) else {
            NSSound.beep()
            return
        }
        customBackgroundImage = image
        customBackgroundImagePath = url.path
        appTheme = .customImage
    }

    private func loadCustomBackgroundImage(fromPath path: String) {
        guard let image = NSImage(contentsOfFile: path) else {
            customBackgroundImage = nil
            customBackgroundImagePath = nil
            if appTheme == .customImage {
                appTheme = .system
            }
            return
        }
        customBackgroundImage = image
        customBackgroundImagePath = path
    }

    private func uniqueUserEqualizerPresetName(for baseName: String) -> String {
        guard userEqualizerPresets.contains(where: { $0.name == baseName }) else { return baseName }
        var counter = 2
        while userEqualizerPresets.contains(where: { $0.name == "\(baseName) \(counter)" }) {
            counter += 1
        }
        return "\(baseName) \(counter)"
    }

    private static func nearestSupportedPlaybackRate(to rate: Float) -> Float {
        supportedPlaybackRates.min(by: { abs($0 - rate) < abs($1 - rate) }) ?? 1.0
    }

    private static func formattedPlaybackRate(_ rate: Float) -> String {
        let resolvedRate = nearestSupportedPlaybackRate(to: rate)
        if resolvedRate.rounded() == resolvedRate {
            return String(format: "%.1fx", resolvedRate)
        }
        if (resolvedRate * 10).rounded() == resolvedRate * 10 {
            return String(format: "%.1fx", resolvedRate)
        }
        return String(format: "%.2fx", resolvedRate)
    }

    private func storeImportedBackgroundAsset(_ asset: ExportedBackgroundAsset) throws -> String {
        let baseDirectory = try Self.migrationSupportDirectory()
        let destination = baseDirectory.appendingPathComponent(asset.originalFileName)
        try asset.data.write(to: destination, options: .atomic)
        return destination.path
    }

    private static let monthFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "zh_CN")
        formatter.dateFormat = "yyyy年M月"
        return formatter
    }()

    private static let exportDateFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.dateFormat = "yyyyMMdd-HHmmss"
        return formatter
    }()

    private static func migrationSupportDirectory() throws -> URL {
        let fileManager = FileManager.default
        let baseURL = try fileManager.url(
            for: .applicationSupportDirectory,
            in: .userDomainMask,
            appropriateFor: nil,
            create: true
        )
        let directory = baseURL.appendingPathComponent("ZephyrPlayerMigration", isDirectory: true)
        try fileManager.createDirectory(at: directory, withIntermediateDirectories: true)
        return directory
    }

    private static let localizedDefaultPlaylistNames: Set<String> = [
        defaultPlaylistName,
        defaultPlaylistEnglishName
    ]
}
