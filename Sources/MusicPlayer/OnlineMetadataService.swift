import AppKit
import AVFoundation
import CryptoKit
import Foundation

struct TrackSearchInfo {
    let title: String
    let artist: String?
    let album: String?
    let duration: TimeInterval?
}

actor OnlineMetadataService {
    static let shared = OnlineMetadataService()

    private let session: URLSession
    private let fileManager = FileManager.default
    private let lyricsDirectory: URL
    private let artworkDirectory: URL

    init() {
        let configuration = URLSessionConfiguration.default
        configuration.timeoutIntervalForRequest = 12
        configuration.timeoutIntervalForResource = 20
        configuration.httpAdditionalHeaders = [
            "User-Agent": "Zephyr Player/1.0 (macOS)"
        ]
        session = URLSession(configuration: configuration)

        let appSupport = fileManager.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
        let cacheRoot = appSupport.appendingPathComponent("Zephyr Player", isDirectory: true)
        lyricsDirectory = cacheRoot.appendingPathComponent("LyricsCache", isDirectory: true)
        artworkDirectory = cacheRoot.appendingPathComponent("ArtworkCache", isDirectory: true)

        try? fileManager.createDirectory(at: lyricsDirectory, withIntermediateDirectories: true)
        try? fileManager.createDirectory(at: artworkDirectory, withIntermediateDirectories: true)
    }

    func fetchLyrics(for track: AudioTrack, info: TrackSearchInfo) async -> LyricsDocument? {
        await fetchLyricsSources(for: track, info: info).first?.document
    }

    func fetchLyricsSources(
        for track: AudioTrack,
        info: TrackSearchInfo,
        forceRefresh: Bool = false
    ) async -> [LyricsSourceOption] {
        let cacheURL = lyricsDirectory.appendingPathComponent(cacheKey(for: track)).appendingPathExtension("json")
        if !forceRefresh,
           let cached = loadCachedLyricsSources(from: cacheURL),
           !cached.isEmpty {
            return cached
        }

        let searchInfos = lyricsSearchInfos(for: info)
        var collected: [LyricsSourceOption] = []

        for searchInfo in searchInfos {
            collected += await fetchLRCLIBSources(queryInfo: searchInfo, rankingInfo: info)
            if deduplicatedLyricsSources(collected).count >= 4 {
                break
            }
        }

        if deduplicatedLyricsSources(collected).count < 6 {
            for searchInfo in searchInfos {
                collected += await fetchNeteaseLyricsSources(for: searchInfo, rankingInfo: info)
                if deduplicatedLyricsSources(collected).count >= 6 {
                    break
                }
            }
        }

        if deduplicatedLyricsSources(collected).count < 8 {
            for searchInfo in searchInfos {
                collected += await fetchMegalobizSources(for: searchInfo, rankingInfo: info)
                if deduplicatedLyricsSources(collected).count >= 8 {
                    break
                }
            }
        }

        if deduplicatedLyricsSources(collected).count < 9 {
            collected += await fetchLyricsOVHSources(for: info, rankingInfo: info)
        }

        let rankedSources = rankedLyricsSources(from: collected, info: info)
        guard !rankedSources.isEmpty else { return [] }

        cacheLyricsSources(rankedSources, to: cacheURL)
        return rankedSources
    }

    func fetchArtwork(for track: AudioTrack, info: TrackSearchInfo) async -> NSImage? {
        await fetchArtworkOptions(for: track, info: info).first?.image
    }

    func fetchArtworkOptions(
        for track: AudioTrack,
        info: TrackSearchInfo,
        forceRefresh: Bool = false
    ) async -> [ArtworkOption] {
        _ = track

        let alternateInfo = cleanedTrackSearchInfo(from: info)
        var candidates = await fetchMusicBrainzArtworkCandidates(queryInfo: info, rankingInfo: info)

        if deduplicatedArtworkCandidates(candidates).count < 4 {
            candidates += await fetchMusicBrainzArtworkCandidates(queryInfo: alternateInfo, rankingInfo: info)
        }

        candidates += await fetchITunesArtworkCandidates(for: alternateInfo ?? info, rankingInfo: info)

        if deduplicatedArtworkCandidates(candidates).count < 8 {
            candidates += await fetchDeezerArtworkCandidates(for: alternateInfo ?? info, rankingInfo: info)
        }

        let rankedCandidates = rankedArtworkCandidates(from: candidates)
        guard !rankedCandidates.isEmpty else { return [] }

        var options: [ArtworkOption] = []
        for (offset, candidate) in rankedCandidates.enumerated() {
            guard let option = await loadArtworkOption(for: candidate, rank: offset + 1, forceRefresh: forceRefresh) else {
                continue
            }
            options.append(option)
        }

        return options
    }

    private func fetchLRCLIBSources(
        queryInfo: TrackSearchInfo?,
        rankingInfo: TrackSearchInfo
    ) async -> [LyricsSourceOption] {
        guard let queryInfo,
              let requestURL = lyricsSearchURL(for: queryInfo) else {
            return []
        }

        do {
            let (data, response) = try await session.data(from: requestURL)
            guard let http = response as? HTTPURLResponse, (200..<300).contains(http.statusCode) else { return [] }
            let payload = try JSONDecoder().decode([LyricsCandidate].self, from: data)
            let matches = bestLyricsMatches(from: payload, info: rankingInfo)
            return matches.enumerated().compactMap { offset, candidate in
                lyricsSource(from: candidate, rank: offset + 1, providerName: "LRCLIB")
            }
        } catch {
            return []
        }
    }

    private func fetchLyricsOVHSources(
        for info: TrackSearchInfo,
        rankingInfo: TrackSearchInfo
    ) async -> [LyricsSourceOption] {
        let pairs = lyricsOVHPairs(for: info)
        guard !pairs.isEmpty else { return [] }

        var sources: [LyricsSourceOption] = []

        for pair in pairs {
            do {
                let baseURL = URL(string: "https://api.lyrics.ovh/v1")!
                let requestURL = baseURL
                    .appendingPathComponent(pair.artist)
                    .appendingPathComponent(pair.title)
                let (data, response) = try await session.data(from: requestURL)
                guard let http = response as? HTTPURLResponse, (200..<300).contains(http.statusCode) else { continue }
                let payload = try JSONDecoder().decode(LyricsOVHResponse.self, from: data)
                let text = LyricsParser.document(from: payload.lyrics ?? "")
                guard !text.isEmpty else { continue }

                sources.append(
                    LyricsSourceOption(
                        sourceID: lyricsOVHSourceID(artist: pair.artist, title: pair.title),
                        kind: text.timedLines.isEmpty ? .onlinePlain : .onlineSynced,
                        document: text,
                        rank: nil,
                        trackName: pair.title,
                        artistName: pair.artist,
                        albumName: info.album,
                        providerName: "lyrics.ovh"
                    )
                )
            } catch {
                continue
            }
        }

        return rankedLyricsSources(from: sources, info: rankingInfo)
    }

    private func fetchNeteaseLyricsSources(
        for info: TrackSearchInfo,
        rankingInfo: TrackSearchInfo
    ) async -> [LyricsSourceOption] {
        guard let request = neteaseSearchRequest(for: info) else { return [] }

        do {
            let (data, response) = try await session.data(for: request)
            guard let http = response as? HTTPURLResponse, (200..<300).contains(http.statusCode) else { return [] }
            let payload = try JSONDecoder().decode(NetEaseSearchResponse.self, from: data)

            let matches = (payload.result?.songs ?? [])
                .sorted { lhs, rhs in
                    let leftScore = neteaseSongScore(lhs, info: rankingInfo)
                    let rightScore = neteaseSongScore(rhs, info: rankingInfo)
                    if leftScore == rightScore {
                        return lhs.id < rhs.id
                    }
                    return leftScore > rightScore
                }
                .prefix(6)

            var sources: [LyricsSourceOption] = []

            for song in matches {
                guard let lyricsURL = neteaseLyricsURL(for: song.id) else { continue }

                do {
                    let (lyricsData, lyricsResponse) = try await session.data(from: lyricsURL)
                    guard let lyricsHTTP = lyricsResponse as? HTTPURLResponse, (200..<300).contains(lyricsHTTP.statusCode) else { continue }
                    let lyricsPayload = try JSONDecoder().decode(NetEaseLyricsResponse.self, from: lyricsData)
                    let rawLyrics = normalizedMultilineText(from: lyricsPayload.lrc?.lyric)
                    guard !rawLyrics.isEmpty else { continue }

                    let document = LyricsParser.document(from: rawLyrics)
                    guard !document.isEmpty else { continue }

                    let artistNames = song.artists?.compactMap(\.name).joined(separator: ", ")
                    let providerName = "NetEase"
                    sources.append(
                        LyricsSourceOption(
                            sourceID: "online-netease-\(song.id)-\(document.timedLines.isEmpty ? LyricsSourceKind.onlinePlain.rawValue : LyricsSourceKind.onlineSynced.rawValue)",
                            kind: document.timedLines.isEmpty ? .onlinePlain : .onlineSynced,
                            document: document,
                            rank: nil,
                            trackName: song.name,
                            artistName: normalizedSearchComponent(artistNames).isEmpty ? nil : normalizedSearchComponent(artistNames),
                            albumName: normalizedSearchComponent(song.album?.name).isEmpty ? nil : normalizedSearchComponent(song.album?.name),
                            providerName: providerName
                        )
                    )
                } catch {
                    continue
                }
            }

            return rankedLyricsSources(from: sources, info: rankingInfo)
        } catch {
            return []
        }
    }

    private func fetchMegalobizSources(
        for info: TrackSearchInfo,
        rankingInfo: TrackSearchInfo
    ) async -> [LyricsSourceOption] {
        guard let searchURL = megalobizSearchURL(for: info) else { return [] }

        do {
            let (data, response) = try await session.data(from: searchURL)
            guard let http = response as? HTTPURLResponse, (200..<300).contains(http.statusCode) else { return [] }
            let html = decodedWebPage(from: data)
            let resultURLs = megalobizResultURLs(from: html)

            guard !resultURLs.isEmpty else { return [] }

            var sources: [LyricsSourceOption] = []

            for resultURL in resultURLs.prefix(4) {
                do {
                    let (lyricsData, lyricsResponse) = try await session.data(from: resultURL)
                    guard let lyricsHTTP = lyricsResponse as? HTTPURLResponse, (200..<400).contains(lyricsHTTP.statusCode) else { continue }
                    let lyricsHTML = decodedWebPage(from: lyricsData)
                    guard let rawLyrics = extractMegalobizLyrics(from: lyricsHTML) else { continue }

                    let document = LyricsParser.document(from: rawLyrics)
                    guard !document.isEmpty else { continue }

                    let kind: LyricsSourceKind = document.timedLines.isEmpty ? .onlinePlain : .onlineSynced
                    sources.append(
                        LyricsSourceOption(
                            sourceID: megalobizSourceID(for: resultURL),
                            kind: kind,
                            document: document,
                            rank: nil,
                            trackName: info.title,
                            artistName: info.artist,
                            albumName: info.album,
                            providerName: "Megalobiz"
                        )
                    )
                } catch {
                    continue
                }
            }

            return rankedLyricsSources(from: sources, info: rankingInfo)
        } catch {
            return []
        }
    }

    private func fetchMusicBrainzArtworkCandidates(
        queryInfo: TrackSearchInfo?,
        rankingInfo: TrackSearchInfo
    ) async -> [ArtworkLookupCandidate] {
        guard let queryInfo,
              let searchURL = musicBrainzArtworkSearchURL(for: queryInfo) else {
            return []
        }

        do {
            let (data, response) = try await session.data(from: searchURL)
            guard let http = response as? HTTPURLResponse, (200..<300).contains(http.statusCode) else { return [] }
            let result = try JSONDecoder().decode(MusicBrainzReleaseGroupResponse.self, from: data)
            let groups = bestReleaseGroups(from: result.releaseGroups, info: rankingInfo)

            return groups.compactMap { group in
                let artistName = group.artistCredit?.first?.name
                let score = releaseGroupScore(group, info: rankingInfo) + 24
                let imageURL = URL(string: "https://coverartarchive.org/release-group/\(group.id)/front-500")!

                return ArtworkLookupCandidate(
                    sourceID: "coverartarchive-\(group.id)",
                    cacheKey: group.id,
                    imageURL: imageURL,
                    title: group.title,
                    artistName: artistName,
                    albumName: group.title,
                    providerName: "Cover Art Archive",
                    score: score
                )
            }
        } catch {
            return []
        }
    }

    private func fetchITunesArtworkCandidates(
        for info: TrackSearchInfo,
        rankingInfo: TrackSearchInfo
    ) async -> [ArtworkLookupCandidate] {
        guard let searchURL = iTunesArtworkSearchURL(for: info) else { return [] }

        do {
            let (data, response) = try await session.data(from: searchURL)
            guard let http = response as? HTTPURLResponse, (200..<300).contains(http.statusCode) else { return [] }
            let payload = try JSONDecoder().decode(ITunesSearchResponse.self, from: data)

            return payload.results.compactMap { item in
                guard let artworkURL = highResolutionITunesArtworkURL(from: item.artworkURL) else { return nil }
                let score = iTunesArtworkScore(item, info: rankingInfo)
                let sourceID = item.trackID.map { "itunes-\($0)" } ?? "itunes-\(artworkURL.absoluteString)"

                return ArtworkLookupCandidate(
                    sourceID: sourceID,
                    cacheKey: sourceID,
                    imageURL: artworkURL,
                    title: item.collectionName ?? item.trackName,
                    artistName: item.artistName,
                    albumName: item.collectionName,
                    providerName: "iTunes",
                    score: score + 18
                )
            }
        } catch {
            return []
        }
    }

    private func fetchDeezerArtworkCandidates(
        for info: TrackSearchInfo,
        rankingInfo: TrackSearchInfo
    ) async -> [ArtworkLookupCandidate] {
        guard let searchURL = deezerArtworkSearchURL(for: info) else { return [] }

        do {
            let (data, response) = try await session.data(from: searchURL)
            guard let http = response as? HTTPURLResponse, (200..<300).contains(http.statusCode) else { return [] }
            let payload = try JSONDecoder().decode(DeezerSearchResponse.self, from: data)

            return payload.data.compactMap { item in
                guard let artworkURL = item.album.bestCoverURL else { return nil }
                let score = deezerArtworkScore(item, info: rankingInfo)

                return ArtworkLookupCandidate(
                    sourceID: "deezer-\(item.id)",
                    cacheKey: "deezer-\(item.id)",
                    imageURL: artworkURL,
                    title: item.album.title ?? item.title,
                    artistName: item.artist.name,
                    albumName: item.album.title,
                    providerName: "Deezer",
                    score: score + 12
                )
            }
        } catch {
            return []
        }
    }

    private func lyricsSearchURL(for info: TrackSearchInfo) -> URL? {
        let title = normalizedSearchComponent(info.title)
        guard !title.isEmpty else { return nil }

        var components = URLComponents(string: "https://lrclib.net/api/search")
        var queryItems = [URLQueryItem(name: "track_name", value: title)]

        let artist = normalizedSearchComponent(info.artist)
        if !artist.isEmpty {
            queryItems.append(URLQueryItem(name: "artist_name", value: artist))
        }
        let album = normalizedSearchComponent(info.album)
        if !album.isEmpty {
            queryItems.append(URLQueryItem(name: "album_name", value: album))
        }

        components?.queryItems = queryItems
        return components?.url
    }

    private func musicBrainzArtworkSearchURL(for info: TrackSearchInfo) -> URL? {
        let artist = normalizedSearchComponent(info.artist)
        guard !artist.isEmpty else { return nil }

        let albumOrTitle = normalizedSearchComponent((info.album?.isEmpty == false ? info.album : info.title))
        guard !albumOrTitle.isEmpty else { return nil }

        var components = URLComponents(string: "https://musicbrainz.org/ws/2/release-group/")
        components?.queryItems = [
            URLQueryItem(name: "query", value: "releasegroup:\(escapedQuery(albumOrTitle)) AND artist:\(escapedQuery(artist))"),
            URLQueryItem(name: "fmt", value: "json"),
            URLQueryItem(name: "limit", value: "6")
        ]
        return components?.url
    }

    private func iTunesArtworkSearchURL(for info: TrackSearchInfo) -> URL? {
        let titleOrAlbum = normalizedSearchComponent((info.album?.isEmpty == false ? info.album : info.title))
        guard !titleOrAlbum.isEmpty else { return nil }

        let artist = normalizedSearchComponent(info.artist)
        let term = [artist, titleOrAlbum]
            .compactMap { $0 }
            .filter { !$0.isEmpty }
            .joined(separator: " ")
        guard !term.isEmpty else { return nil }

        var components = URLComponents(string: "https://itunes.apple.com/search")
        components?.queryItems = [
            URLQueryItem(name: "term", value: term),
            URLQueryItem(name: "entity", value: "song"),
            URLQueryItem(name: "limit", value: "10")
        ]
        return components?.url
    }

    private func deezerArtworkSearchURL(for info: TrackSearchInfo) -> URL? {
        let title = normalizedSearchComponent(info.title)
        guard !title.isEmpty else { return nil }

        var parts: [String] = []
        let artist = normalizedSearchComponent(info.artist)
        if !artist.isEmpty {
            parts.append("artist:\"\(artist)\"")
        }
        let album = normalizedSearchComponent(info.album)
        if !album.isEmpty {
            parts.append("album:\"\(album)\"")
        }
        parts.append("track:\"\(title)\"")

        var components = URLComponents(string: "https://api.deezer.com/search")
        components?.queryItems = [
            URLQueryItem(name: "q", value: parts.joined(separator: " ")),
            URLQueryItem(name: "limit", value: "10")
        ]
        return components?.url
    }

    private func neteaseSearchRequest(for info: TrackSearchInfo) -> URLRequest? {
        let title = normalizedSearchComponent(info.title)
        guard !title.isEmpty else { return nil }

        let artist = normalizedSearchComponent(info.artist)
        let term = [artist, title]
            .filter { !$0.isEmpty }
            .joined(separator: " ")
        guard !term.isEmpty else { return nil }

        var body = URLComponents()
        body.queryItems = [
            URLQueryItem(name: "s", value: term),
            URLQueryItem(name: "type", value: "1"),
            URLQueryItem(name: "offset", value: "0"),
            URLQueryItem(name: "limit", value: "8")
        ]

        guard let requestURL = URL(string: "https://music.163.com/api/search/get/web") else { return nil }
        var request = URLRequest(url: requestURL)
        request.httpMethod = "POST"
        request.setValue("application/x-www-form-urlencoded; charset=utf-8", forHTTPHeaderField: "Content-Type")
        request.setValue("https://music.163.com", forHTTPHeaderField: "Origin")
        request.setValue("https://music.163.com/", forHTTPHeaderField: "Referer")
        request.httpBody = body.percentEncodedQuery?.data(using: .utf8)
        return request
    }

    private func neteaseLyricsURL(for songID: Int) -> URL? {
        var components = URLComponents(string: "https://music.163.com/api/song/lyric")
        components?.queryItems = [
            URLQueryItem(name: "id", value: String(songID)),
            URLQueryItem(name: "lv", value: "-1"),
            URLQueryItem(name: "kv", value: "-1"),
            URLQueryItem(name: "tv", value: "-1")
        ]
        return components?.url
    }

    private func megalobizSearchURL(for info: TrackSearchInfo) -> URL? {
        let title = normalizedSearchComponent(info.title)
        guard !title.isEmpty else { return nil }

        let artist = normalizedSearchComponent(info.artist)
        let query = [artist, title]
            .filter { !$0.isEmpty }
            .joined(separator: " ")
        guard !query.isEmpty else { return nil }

        var components = URLComponents(string: "https://www.megalobiz.com/search/all")
        components?.queryItems = [
            URLQueryItem(name: "qry", value: query)
        ]
        return components?.url
    }

    private func escapedQuery(_ string: String) -> String {
        string
            .replacingOccurrences(of: "\"", with: "\\\"")
            .split(separator: " ")
            .map { "\"\($0)\"" }
            .joined(separator: " ")
    }

    private func bestLyricsMatches(from payload: [LyricsCandidate], info: TrackSearchInfo) -> [LyricsCandidate] {
        payload
            .enumerated()
            .sorted { lhs, rhs in
                let leftScore = score(lhs.element, info: info)
                let rightScore = score(rhs.element, info: info)
                if leftScore == rightScore {
                    return lhs.offset < rhs.offset
                }
                return leftScore > rightScore
            }
            .prefix(8)
            .map(\.element)
    }

    private func score(_ candidate: LyricsCandidate, info: TrackSearchInfo) -> Int {
        var value = 0
        if sameNormalized(candidate.trackName, info.title) {
            value += 10
        } else if fuzzyMatch(candidate.trackName, info.title) {
            value += 4
        }
        if sameNormalized(candidate.artistName, info.artist) {
            value += 8
        } else if fuzzyMatch(candidate.artistName, info.artist) {
            value += 3
        }
        if sameNormalized(candidate.albumName, info.album) {
            value += 4
        }
        if let duration = info.duration, abs((candidate.duration ?? duration) - duration) < 3 {
            value += 2
        }
        if candidate.syncedLyrics?.isEmpty == false {
            value += 3
        }
        return value
    }

    private func lyricsSourceScore(_ source: LyricsSourceOption, info: TrackSearchInfo) -> Int {
        var value = 0
        if sameNormalized(source.trackName, info.title) {
            value += 10
        } else if fuzzyMatch(source.trackName, info.title) {
            value += 4
        }
        if sameNormalized(source.artistName, info.artist) {
            value += 8
        } else if fuzzyMatch(source.artistName, info.artist) {
            value += 3
        }
        if sameNormalized(source.albumName, info.album) {
            value += 4
        }
        if source.kind == .onlineSynced {
            value += 3
        }
        if source.providerName == "LRCLIB" {
            value += 2
        } else if source.providerName == "NetEase" {
            value += 2
        } else if source.providerName == "Megalobiz" {
            value += 1
        }
        return value
    }

    private func bestReleaseGroups(from groups: [MusicBrainzReleaseGroup], info: TrackSearchInfo) -> [MusicBrainzReleaseGroup] {
        groups
            .enumerated()
            .sorted { lhs, rhs in
                let leftScore = releaseGroupScore(lhs.element, info: info)
                let rightScore = releaseGroupScore(rhs.element, info: info)
                if leftScore == rightScore {
                    return lhs.offset < rhs.offset
                }
                return leftScore > rightScore
            }
            .prefix(8)
            .map(\.element)
    }

    private func releaseGroupScore(_ group: MusicBrainzReleaseGroup, info: TrackSearchInfo) -> Int {
        var value = group.score ?? 0
        if sameNormalized(group.title, info.album) {
            value += 34
        } else if fuzzyMatch(group.title, info.album) {
            value += 12
        }
        if sameNormalized(group.title, info.title) {
            value += 10
        }
        let artistName = group.artistCredit?.first?.name
        if sameNormalized(artistName, info.artist) {
            value += 22
        } else if fuzzyMatch(artistName, info.artist) {
            value += 6
        }
        return value
    }

    private func iTunesArtworkScore(_ item: ITunesTrackResult, info: TrackSearchInfo) -> Int {
        var value = 0
        if sameNormalized(item.collectionName, info.album) {
            value += 28
        } else if fuzzyMatch(item.collectionName, info.album) {
            value += 10
        }
        if sameNormalized(item.trackName, info.title) {
            value += 16
        } else if fuzzyMatch(item.trackName, info.title) {
            value += 6
        }
        if sameNormalized(item.artistName, info.artist) {
            value += 22
        } else if fuzzyMatch(item.artistName, info.artist) {
            value += 6
        }
        return value
    }

    private func deezerArtworkScore(_ item: DeezerTrackResult, info: TrackSearchInfo) -> Int {
        var value = 0
        if sameNormalized(item.album.title, info.album) {
            value += 28
        } else if fuzzyMatch(item.album.title, info.album) {
            value += 10
        }
        if sameNormalized(item.title, info.title) {
            value += 16
        } else if fuzzyMatch(item.title, info.title) {
            value += 6
        }
        if sameNormalized(item.artist.name, info.artist) {
            value += 22
        } else if fuzzyMatch(item.artist.name, info.artist) {
            value += 6
        }
        return value
    }

    private func neteaseSongScore(_ song: NetEaseSong, info: TrackSearchInfo) -> Int {
        var value = 0
        if sameNormalized(song.name, info.title) {
            value += 18
        } else if fuzzyMatch(song.name, info.title) {
            value += 8
        }

        let artistName = song.artists?.compactMap(\.name).joined(separator: ", ")
        if sameNormalized(artistName, info.artist) {
            value += 16
        } else if fuzzyMatch(artistName, info.artist) {
            value += 6
        }

        if sameNormalized(song.album?.name, info.album) {
            value += 8
        } else if fuzzyMatch(song.album?.name, info.album) {
            value += 3
        }

        return value
    }

    private func normalized(_ value: String?) -> String {
        (value ?? "")
            .folding(options: [.diacriticInsensitive, .caseInsensitive], locale: .current)
            .replacingOccurrences(of: #"[^\p{L}\p{N}]+"#, with: " ", options: .regularExpression)
            .replacingOccurrences(of: #"\s+"#, with: " ", options: .regularExpression)
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private func sameNormalized(_ lhs: String?, _ rhs: String?) -> Bool {
        let left = normalized(lhs)
        let right = normalized(rhs)
        return !left.isEmpty && left == right
    }

    private func fuzzyMatch(_ lhs: String?, _ rhs: String?) -> Bool {
        let left = normalized(lhs)
        let right = normalized(rhs)
        guard !left.isEmpty, !right.isEmpty else { return false }
        return left.contains(right) || right.contains(left)
    }

    private func normalizedSearchComponent(_ value: String?) -> String {
        (value ?? "")
            .replacingOccurrences(of: #"\s+"#, with: " ", options: .regularExpression)
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private func normalizedMultilineText(from value: String?) -> String {
        (value ?? "")
            .replacingOccurrences(of: "\r\n", with: "\n")
            .replacingOccurrences(of: "\r", with: "\n")
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private func lyricsSearchInfos(for info: TrackSearchInfo) -> [TrackSearchInfo] {
        var results = [info]

        if let cleaned = cleanedTrackSearchInfo(from: info) {
            let existingKeys = Set(results.map(lyricsSearchInfoKey(for:)))
            if !existingKeys.contains(lyricsSearchInfoKey(for: cleaned)) {
                results.append(cleaned)
            }
        }

        return results
    }

    private func cleanedTrackSearchInfo(from info: TrackSearchInfo) -> TrackSearchInfo? {
        let cleanedTitle = cleanedTrackTitle(info.title)
        let cleanedArtist = cleanedArtistName(info.artist)
        let cleanedAlbum = cleanedAlbumName(info.album)

        guard
            cleanedTitle != info.title ||
            cleanedArtist != info.artist ||
            cleanedAlbum != info.album
        else {
            return nil
        }

        return TrackSearchInfo(
            title: cleanedTitle,
            artist: cleanedArtist,
            album: cleanedAlbum,
            duration: info.duration
        )
    }

    private func cleanedTrackTitle(_ title: String) -> String {
        var value = normalizedSearchComponent(title)
        let patterns = [
            #"(?i)\s+(feat\.?|ft\.?|with)\s+.+$"#,
            #"(?i)\s*[-–—]\s*(live|remaster(?:ed)?|karaoke|instrumental|伴奏|version|ver\.?)\s*$"#,
            #"\s*[\(\[（【][^\)\]）】]+[\)\]）】]\s*$"#
        ]

        for pattern in patterns {
            let candidate = value.replacingOccurrences(of: pattern, with: "", options: .regularExpression)
                .trimmingCharacters(in: .whitespacesAndNewlines)
            if !candidate.isEmpty {
                value = candidate
            }
        }

        return normalizedSearchComponent(value)
    }

    private func cleanedArtistName(_ artist: String?) -> String? {
        guard var value = artist?.trimmingCharacters(in: .whitespacesAndNewlines), !value.isEmpty else { return artist }
        let patterns = [
            #"(?i)\s+(feat\.?|ft\.?|with)\s+.+$"#
        ]

        for pattern in patterns {
            let candidate = value.replacingOccurrences(of: pattern, with: "", options: .regularExpression)
                .trimmingCharacters(in: .whitespacesAndNewlines)
            if !candidate.isEmpty {
                value = candidate
            }
        }

        return normalizedSearchComponent(value)
    }

    private func cleanedAlbumName(_ album: String?) -> String? {
        guard var value = album?.trimmingCharacters(in: .whitespacesAndNewlines), !value.isEmpty else { return album }
        let patterns = [
            #"(?i)\s*[-–—]\s*(deluxe|expanded|anniversary|edition|version).*$"#,
            #"\s*[\(\[（【][^\)\]）】]+[\)\]）】]\s*$"#
        ]

        for pattern in patterns {
            let candidate = value.replacingOccurrences(of: pattern, with: "", options: .regularExpression)
                .trimmingCharacters(in: .whitespacesAndNewlines)
            if !candidate.isEmpty {
                value = candidate
            }
        }

        return normalizedSearchComponent(value)
    }

    private func lyricsSearchInfoKey(for info: TrackSearchInfo) -> String {
        [
            normalized(info.title),
            normalized(info.artist),
            normalized(info.album)
        ].joined(separator: "|")
    }

    private func lyricsOVHPairs(for info: TrackSearchInfo) -> [(artist: String, title: String)] {
        let artist = normalizedSearchComponent(info.artist)
        guard !artist.isEmpty else { return [] }
        let title = normalizedSearchComponent(info.title)
        guard !title.isEmpty else { return [] }

        var pairs: [(artist: String, title: String)] = [(artist, title)]
        let cleanedTitle = cleanedTrackTitle(title)
        let cleanedArtist = cleanedArtistName(artist) ?? artist

        if cleanedArtist != artist || cleanedTitle != title {
            pairs.append((cleanedArtist, cleanedTitle))
        }

        var seen = Set<String>()
        return pairs.filter { pair in
            let key = normalized(pair.artist) + "|" + normalized(pair.title)
            return seen.insert(key).inserted
        }
    }

    private func lyricsOVHSourceID(artist: String, title: String) -> String {
        let key = normalized(artist) + "|" + normalized(title)
        return "online-lyricsovh-\(SHA256.hash(data: Data(key.utf8)).compactMap { String(format: "%02x", $0) }.joined())"
    }

    private func megalobizResultURLs(from html: String) -> [URL] {
        let absolutePattern = #"https://www\.megalobiz\.com/lrc/maker/[^\s"'<>]+?\.html"#
        let relativePattern = #"/lrc/maker/[^\s"'<>]+?\.html"#

        var urls: [URL] = []
        var seen = Set<String>()

        for match in regexMatches(in: html, pattern: absolutePattern) {
            guard seen.insert(match).inserted, let url = URL(string: match) else { continue }
            urls.append(url)
        }

        for match in regexMatches(in: html, pattern: relativePattern) {
            let absolute = "https://www.megalobiz.com\(match)"
            guard seen.insert(absolute).inserted, let url = URL(string: absolute) else { continue }
            urls.append(url)
        }

        return urls
    }

    private func extractMegalobizLyrics(from html: String) -> String? {
        let patterns = [
            #"entity_decode\('((?:\\.|[^'])*)'\)"#,
            #"entity_decode\(\"((?:\\.|[^\"])*)\"\)"#,
            #"<textarea[^>]*>(.*?)</textarea>"#
        ]

        for pattern in patterns {
            guard let encoded = firstCapturedGroup(
                in: html,
                pattern: pattern,
                options: [.dotMatchesLineSeparators, .caseInsensitive]
            ) else {
                continue
            }

            let decoded = decodedHTMLFragment(from: decodeEscapedWebString(encoded))
            let normalizedLyrics = normalizedMultilineText(from: decoded)
            guard !normalizedLyrics.isEmpty else { continue }
            return normalizedLyrics
        }

        return nil
    }

    private func megalobizSourceID(for url: URL) -> String {
        let key = url.absoluteString
        return "online-megalobiz-\(SHA256.hash(data: Data(key.utf8)).compactMap { String(format: "%02x", $0) }.joined())"
    }

    private func highResolutionITunesArtworkURL(from rawValue: String?) -> URL? {
        guard var rawValue, !rawValue.isEmpty else { return nil }

        let replacements = [
            ("100x100bb", "600x600bb"),
            ("100x100-999", "600x600-999"),
            ("60x60bb", "600x600bb"),
            ("200x200bb", "600x600bb")
        ]

        for replacement in replacements {
            rawValue = rawValue.replacingOccurrences(of: replacement.0, with: replacement.1)
        }

        return URL(string: rawValue)
    }

    private func rankedLyricsSources(from sources: [LyricsSourceOption], info: TrackSearchInfo) -> [LyricsSourceOption] {
        deduplicatedLyricsSources(sources)
            .enumerated()
            .sorted { lhs, rhs in
                let leftScore = lyricsSourceScore(lhs.element, info: info)
                let rightScore = lyricsSourceScore(rhs.element, info: info)
                if leftScore == rightScore {
                    return lhs.offset < rhs.offset
                }
                return leftScore > rightScore
            }
            .prefix(8)
            .enumerated()
            .map { offset, element in
                rankedLyricsSource(element.element, rank: offset + 1)
            }
    }

    private func deduplicatedLyricsSources(_ sources: [LyricsSourceOption]) -> [LyricsSourceOption] {
        var result: [LyricsSourceOption] = []

        for source in sources where !source.document.isEmpty {
            guard !result.contains(where: { $0.id == source.id || $0.document == source.document }) else { continue }
            result.append(source)
        }

        return result
    }

    private func rankedLyricsSource(_ source: LyricsSourceOption, rank: Int) -> LyricsSourceOption {
        LyricsSourceOption(
            sourceID: source.sourceID ?? source.id,
            kind: source.kind,
            document: source.document,
            rank: rank,
            trackName: source.trackName,
            artistName: source.artistName,
            albumName: source.albumName,
            providerName: source.providerName
        )
    }

    private func rankedArtworkCandidates(from candidates: [ArtworkLookupCandidate]) -> [ArtworkLookupCandidate] {
        deduplicatedArtworkCandidates(candidates)
            .sorted { lhs, rhs in
                if lhs.score == rhs.score {
                    return lhs.providerName < rhs.providerName
                }
                return lhs.score > rhs.score
            }
            .prefix(10)
            .map { $0 }
    }

    private func deduplicatedArtworkCandidates(_ candidates: [ArtworkLookupCandidate]) -> [ArtworkLookupCandidate] {
        var result: [ArtworkLookupCandidate] = []
        var seenIDs = Set<String>()
        var seenSemanticKeys = Set<String>()

        for candidate in candidates {
            guard seenIDs.insert(candidate.sourceID).inserted else { continue }

            let semanticKey = [
                normalized(candidate.artistName),
                normalized(candidate.albumName ?? candidate.title),
                normalized(candidate.providerName)
            ].joined(separator: "|")

            if !semanticKey.replacingOccurrences(of: "|", with: "").isEmpty,
               !seenSemanticKeys.insert(semanticKey).inserted {
                continue
            }

            result.append(candidate)
        }

        return result
    }

    private func cropToSquare(_ image: NSImage) -> NSImage {
        guard let tiff = image.tiffRepresentation,
              let source = NSBitmapImageRep(data: tiff) else {
            return image
        }

        let side = min(source.pixelsWide, source.pixelsHigh)
        let x = (source.pixelsWide - side) / 2
        let y = (source.pixelsHigh - side) / 2
        let rect = NSRect(x: x, y: y, width: side, height: side)

        let result = NSImage(size: NSSize(width: side, height: side))
        result.lockFocus()
        source.draw(
            in: NSRect(origin: .zero, size: result.size),
            from: rect,
            operation: .copy,
            fraction: 1.0,
            respectFlipped: true,
            hints: nil
        )
        result.unlockFocus()
        return result
    }

    private func loadArtworkOption(
        for candidate: ArtworkLookupCandidate,
        rank: Int,
        forceRefresh: Bool
    ) async -> ArtworkOption? {
        let hashedKey = SHA256.hash(data: Data(candidate.cacheKey.utf8))
            .compactMap { String(format: "%02x", $0) }
            .joined()
        let cacheURL = artworkDirectory.appendingPathComponent(hashedKey).appendingPathExtension("png")

        if !forceRefresh, let image = NSImage(contentsOf: cacheURL) {
            return ArtworkOption(
                sourceID: candidate.sourceID,
                kind: .online,
                image: image,
                rank: rank,
                title: candidate.title,
                artistName: candidate.artistName,
                albumName: candidate.albumName,
                providerName: candidate.providerName
            )
        }

        do {
            let (imageData, imageResponse) = try await session.data(from: candidate.imageURL)
            guard let imageHTTP = imageResponse as? HTTPURLResponse, (200..<400).contains(imageHTTP.statusCode) else { return nil }
            guard let rawImage = NSImage(data: imageData) else { return nil }

            let cropped = cropToSquare(rawImage)
            saveArtwork(cropped, to: cacheURL)
            return ArtworkOption(
                sourceID: candidate.sourceID,
                kind: .online,
                image: cropped,
                rank: rank,
                title: candidate.title,
                artistName: candidate.artistName,
                albumName: candidate.albumName,
                providerName: candidate.providerName
            )
        } catch {
            return nil
        }
    }

    private func loadCachedLyricsSources(from url: URL) -> [LyricsSourceOption]? {
        guard
            let data = try? Data(contentsOf: url),
            let cached = try? JSONDecoder().decode(CachedLyrics.self, from: data)
        else {
            return nil
        }

        if let sources = cached.sources, !sources.isEmpty {
            return sources
        }

        let legacy = LyricsDocument(
            timedLines: cached.timedLines ?? [],
            plainText: cached.plainText
        )
        guard !legacy.isEmpty else { return nil }

        let inferredKind: LyricsSourceKind = legacy.timedLines.isEmpty ? .onlinePlain : .onlineSynced
        return [
            LyricsSourceOption(
                sourceID: "online-legacy",
                kind: inferredKind,
                document: legacy,
                rank: 1,
                providerName: "LRCLIB"
            )
        ]
    }

    private func cacheLyricsSources(_ sources: [LyricsSourceOption], to url: URL) {
        let cached = CachedLyrics(
            sources: sources,
            timedLines: sources.first?.document.timedLines,
            plainText: sources.first?.document.plainText
        )
        guard let data = try? JSONEncoder().encode(cached) else { return }
        try? data.write(to: url)
    }

    private func lyricsSource(
        from candidate: LyricsCandidate,
        rank: Int,
        providerName: String
    ) -> LyricsSourceOption? {
        if let synced = candidate.syncedLyrics, !synced.isEmpty {
            let lines = LyricsParser.parseSyncedLyrics(synced)
            let document = LyricsDocument(timedLines: lines, plainText: lines.isEmpty ? synced : nil)
            if !document.isEmpty {
                return LyricsSourceOption(
                    sourceID: onlineSourceID(for: candidate, kind: .onlineSynced, rank: rank, providerName: providerName),
                    kind: .onlineSynced,
                    document: document,
                    rank: rank,
                    trackName: candidate.trackName,
                    artistName: candidate.artistName,
                    albumName: candidate.albumName,
                    providerName: providerName
                )
            }
        }

        if let plain = candidate.plainLyrics, !plain.isEmpty {
            let document = LyricsDocument(timedLines: [], plainText: plain)
            if !document.isEmpty {
                return LyricsSourceOption(
                    sourceID: onlineSourceID(for: candidate, kind: .onlinePlain, rank: rank, providerName: providerName),
                    kind: .onlinePlain,
                    document: document,
                    rank: rank,
                    trackName: candidate.trackName,
                    artistName: candidate.artistName,
                    albumName: candidate.albumName,
                    providerName: providerName
                )
            }
        }

        return nil
    }

    private func onlineSourceID(
        for candidate: LyricsCandidate,
        kind: LyricsSourceKind,
        rank: Int,
        providerName: String
    ) -> String {
        let providerKey = normalized(providerName).replacingOccurrences(of: " ", with: "-")
        if let id = candidate.id {
            return "online-\(providerKey)-\(kind.rawValue)-\(id)"
        }
        return "online-\(providerKey)-\(kind.rawValue)-\(rank)"
    }

    private func saveArtwork(_ image: NSImage, to url: URL) {
        guard
            let tiff = image.tiffRepresentation,
            let rep = NSBitmapImageRep(data: tiff),
            let png = rep.representation(using: .png, properties: [:])
        else {
            return
        }

        try? png.write(to: url)
    }

    private func cacheKey(for track: AudioTrack) -> String {
        let data = Data(track.url.standardizedFileURL.path.utf8)
        return SHA256.hash(data: data).map { String(format: "%02x", $0) }.joined()
    }

    private func decodedWebPage(from data: Data) -> String {
        if let string = String(data: data, encoding: .utf8) {
            return string
        }
        return String(decoding: data, as: UTF8.self)
    }

    private func regexMatches(
        in string: String,
        pattern: String,
        options: NSRegularExpression.Options = []
    ) -> [String] {
        guard let regex = try? NSRegularExpression(pattern: pattern, options: options) else { return [] }
        let range = NSRange(string.startIndex..<string.endIndex, in: string)
        return regex.matches(in: string, range: range).compactMap { match in
            guard let foundRange = Range(match.range(at: 0), in: string) else { return nil }
            return String(string[foundRange])
        }
    }

    private func firstCapturedGroup(
        in string: String,
        pattern: String,
        options: NSRegularExpression.Options = [],
        group: Int = 1
    ) -> String? {
        guard let regex = try? NSRegularExpression(pattern: pattern, options: options) else { return nil }
        let range = NSRange(string.startIndex..<string.endIndex, in: string)
        guard let match = regex.firstMatch(in: string, range: range),
              match.numberOfRanges > group,
              let foundRange = Range(match.range(at: group), in: string) else {
            return nil
        }
        return String(string[foundRange])
    }

    private func decodeEscapedWebString(_ value: String) -> String {
        var result = value
            .replacingOccurrences(of: "\\r\\n", with: "\n")
            .replacingOccurrences(of: "\\n", with: "\n")
            .replacingOccurrences(of: "\\r", with: "\n")
            .replacingOccurrences(of: "\\t", with: "\t")
            .replacingOccurrences(of: "\\/", with: "/")
            .replacingOccurrences(of: "\\'", with: "'")
            .replacingOccurrences(of: "\\\"", with: "\"")

        result = decodeUnicodeEscapes(in: result)
        return result
    }

    private func decodeUnicodeEscapes(in value: String) -> String {
        guard let regex = try? NSRegularExpression(pattern: #"\\u([0-9a-fA-F]{4})"#) else { return value }

        let mutable = NSMutableString(string: value)
        let matches = regex.matches(in: value, range: NSRange(location: 0, length: mutable.length))

        for match in matches.reversed() {
            let hex = mutable.substring(with: match.range(at: 1))
            guard let scalarValue = UInt32(hex, radix: 16), let scalar = UnicodeScalar(scalarValue) else {
                continue
            }
            mutable.replaceCharacters(in: match.range(at: 0), with: String(scalar))
        }

        return mutable as String
    }

    private func decodedHTMLFragment(from html: String) -> String {
        let normalizedHTML = html.replacingOccurrences(
            of: #"<br\s*/?>"#,
            with: "\n",
            options: [.regularExpression, .caseInsensitive]
        )

        guard let data = normalizedHTML.data(using: .utf8),
              let attributed = try? NSAttributedString(
                data: data,
                options: [
                    .documentType: NSAttributedString.DocumentType.html,
                    .characterEncoding: String.Encoding.utf8.rawValue
                ],
                documentAttributes: nil
              ) else {
            return normalizedHTML
        }

        return attributed.string
    }
}

private struct CachedLyrics: Codable {
    let sources: [LyricsSourceOption]?
    let timedLines: [TimedLyricLine]?
    let plainText: String?
}

private struct LyricsCandidate: Codable {
    let id: Int?
    let trackName: String?
    let artistName: String?
    let albumName: String?
    let duration: TimeInterval?
    let plainLyrics: String?
    let syncedLyrics: String?
}

private struct LyricsOVHResponse: Codable {
    let lyrics: String?
}

private struct NetEaseSearchResponse: Codable {
    let result: NetEaseSearchResult?
}

private struct NetEaseSearchResult: Codable {
    let songs: [NetEaseSong]?
}

private struct NetEaseSong: Codable {
    let id: Int
    let name: String?
    let artists: [NetEaseArtist]?
    let album: NetEaseAlbum?

    enum CodingKeys: String, CodingKey {
        case id
        case name
        case artists
        case album = "al"
    }
}

private struct NetEaseArtist: Codable {
    let name: String?
}

private struct NetEaseAlbum: Codable {
    let name: String?
}

private struct NetEaseLyricsResponse: Codable {
    let lrc: NetEaseLyricPayload?
}

private struct NetEaseLyricPayload: Codable {
    let lyric: String?
}

private struct ArtworkLookupCandidate {
    let sourceID: String
    let cacheKey: String
    let imageURL: URL
    let title: String?
    let artistName: String?
    let albumName: String?
    let providerName: String
    let score: Int
}

private struct MusicBrainzReleaseGroupResponse: Codable {
    let releaseGroups: [MusicBrainzReleaseGroup]

    enum CodingKeys: String, CodingKey {
        case releaseGroups = "release-groups"
    }
}

private struct MusicBrainzReleaseGroup: Codable {
    let id: String
    let title: String
    let score: Int?
    let artistCredit: [MusicBrainzArtistCredit]?

    enum CodingKeys: String, CodingKey {
        case id
        case title
        case score
        case artistCredit = "artist-credit"
    }
}

private struct MusicBrainzArtistCredit: Codable {
    let name: String?
}

private struct ITunesSearchResponse: Codable {
    let results: [ITunesTrackResult]
}

private struct ITunesTrackResult: Codable {
    let trackID: Int?
    let trackName: String?
    let artistName: String?
    let collectionName: String?
    let artworkURL: String?

    enum CodingKeys: String, CodingKey {
        case trackID = "trackId"
        case trackName
        case artistName
        case collectionName
        case artworkURL = "artworkUrl100"
    }
}

private struct DeezerSearchResponse: Codable {
    let data: [DeezerTrackResult]
}

private struct DeezerTrackResult: Codable {
    let id: Int
    let title: String?
    let artist: DeezerArtist
    let album: DeezerAlbum
}

private struct DeezerArtist: Codable {
    let name: String?
}

private struct DeezerAlbum: Codable {
    let title: String?
    let coverXL: String?
    let coverBig: String?
    let coverMedium: String?

    enum CodingKeys: String, CodingKey {
        case title
        case coverXL = "cover_xl"
        case coverBig = "cover_big"
        case coverMedium = "cover_medium"
    }

    var bestCoverURL: URL? {
        if let coverXL, let url = URL(string: coverXL) {
            return url
        }
        if let coverBig, let url = URL(string: coverBig) {
            return url
        }
        if let coverMedium, let url = URL(string: coverMedium) {
            return url
        }
        return nil
    }
}
