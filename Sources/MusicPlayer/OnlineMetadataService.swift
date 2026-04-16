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
        let cacheURL = lyricsDirectory.appendingPathComponent(cacheKey(for: track)).appendingPathExtension("json")
        if let cached = loadCachedLyrics(from: cacheURL) {
            return cached
        }

        guard let requestURL = lyricsSearchURL(for: info) else { return nil }

        do {
            let (data, response) = try await session.data(from: requestURL)
            guard let http = response as? HTTPURLResponse, (200..<300).contains(http.statusCode) else { return nil }
            let payload = try JSONDecoder().decode([LyricsCandidate].self, from: data)
            guard let best = bestLyricsMatch(from: payload, info: info) else { return nil }

            let document: LyricsDocument
            if let synced = best.syncedLyrics, !synced.isEmpty {
                let lines = LyricsParser.parseSyncedLyrics(synced)
                document = LyricsDocument(timedLines: lines, plainText: lines.isEmpty ? synced : nil)
            } else if let plain = best.plainLyrics, !plain.isEmpty {
                document = LyricsDocument(timedLines: [], plainText: plain)
            } else {
                return nil
            }

            cacheLyrics(document, to: cacheURL)
            return document
        } catch {
            return nil
        }
    }

    func fetchArtwork(for track: AudioTrack, info: TrackSearchInfo) async -> NSImage? {
        let cacheURL = artworkDirectory.appendingPathComponent(cacheKey(for: track)).appendingPathExtension("png")
        if let image = NSImage(contentsOf: cacheURL) {
            return image
        }

        guard let searchURL = artworkSearchURL(for: info) else { return nil }

        do {
            let (data, response) = try await session.data(from: searchURL)
            guard let http = response as? HTTPURLResponse, (200..<300).contains(http.statusCode) else { return nil }
            let result = try JSONDecoder().decode(MusicBrainzReleaseGroupResponse.self, from: data)
            guard let releaseGroup = bestReleaseGroup(from: result.releaseGroups, info: info) else { return nil }

            let frontURL = URL(string: "https://coverartarchive.org/release-group/\(releaseGroup.id)/front-500")!
            let (imageData, imageResponse) = try await session.data(from: frontURL)
            guard let imageHTTP = imageResponse as? HTTPURLResponse, (200..<400).contains(imageHTTP.statusCode) else { return nil }
            guard let rawImage = NSImage(data: imageData) else { return nil }

            let cropped = cropToSquare(rawImage)
            saveArtwork(cropped, to: cacheURL)
            return cropped
        } catch {
            return nil
        }
    }

    private func lyricsSearchURL(for info: TrackSearchInfo) -> URL? {
        guard !info.title.isEmpty else { return nil }

        var components = URLComponents(string: "https://lrclib.net/api/search")
        var queryItems = [URLQueryItem(name: "track_name", value: info.title)]
        if let artist = info.artist, !artist.isEmpty {
            queryItems.append(URLQueryItem(name: "artist_name", value: artist))
        }
        if let album = info.album, !album.isEmpty {
            queryItems.append(URLQueryItem(name: "album_name", value: album))
        }
        components?.queryItems = queryItems
        return components?.url
    }

    private func artworkSearchURL(for info: TrackSearchInfo) -> URL? {
        guard let artist = info.artist, !artist.isEmpty else { return nil }
        let albumOrTitle = (info.album?.isEmpty == false ? info.album! : info.title)
        guard !albumOrTitle.isEmpty else { return nil }

        var components = URLComponents(string: "https://musicbrainz.org/ws/2/release-group/")
        components?.queryItems = [
            URLQueryItem(name: "query", value: "releasegroup:\(escapedQuery(albumOrTitle)) AND artist:\(escapedQuery(artist))"),
            URLQueryItem(name: "fmt", value: "json"),
            URLQueryItem(name: "limit", value: "5")
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

    private func bestLyricsMatch(from payload: [LyricsCandidate], info: TrackSearchInfo) -> LyricsCandidate? {
        payload.max { lhs, rhs in
            score(lhs, info: info) < score(rhs, info: info)
        }
    }

    private func score(_ candidate: LyricsCandidate, info: TrackSearchInfo) -> Int {
        var value = 0
        if normalized(candidate.trackName) == normalized(info.title) {
            value += 6
        }
        if normalized(candidate.artistName) == normalized(info.artist) {
            value += 5
        }
        if normalized(candidate.albumName) == normalized(info.album) {
            value += 3
        }
        if let duration = info.duration, abs((candidate.duration ?? duration) - duration) < 3 {
            value += 2
        }
        if candidate.syncedLyrics?.isEmpty == false {
            value += 2
        }
        return value
    }

    private func bestReleaseGroup(from groups: [MusicBrainzReleaseGroup], info: TrackSearchInfo) -> MusicBrainzReleaseGroup? {
        groups.max { lhs, rhs in
            releaseGroupScore(lhs, info: info) < releaseGroupScore(rhs, info: info)
        }
    }

    private func releaseGroupScore(_ group: MusicBrainzReleaseGroup, info: TrackSearchInfo) -> Int {
        var value = group.score ?? 0
        if normalized(group.title) == normalized(info.album) {
            value += 30
        }
        let artistName = group.artistCredit?.first?.name
        if normalized(artistName) == normalized(info.artist) {
            value += 20
        }
        return value
    }

    private func normalized(_ value: String?) -> String {
        (value ?? "")
            .folding(options: [.diacriticInsensitive, .caseInsensitive], locale: .current)
            .trimmingCharacters(in: .whitespacesAndNewlines)
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

    private func loadCachedLyrics(from url: URL) -> LyricsDocument? {
        guard
            let data = try? Data(contentsOf: url),
            let cached = try? JSONDecoder().decode(CachedLyrics.self, from: data)
        else {
            return nil
        }
        return LyricsDocument(timedLines: cached.timedLines, plainText: cached.plainText)
    }

    private func cacheLyrics(_ document: LyricsDocument, to url: URL) {
        let cached = CachedLyrics(timedLines: document.timedLines, plainText: document.plainText)
        guard let data = try? JSONEncoder().encode(cached) else { return }
        try? data.write(to: url)
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
}

private struct CachedLyrics: Codable {
    let timedLines: [TimedLyricLine]
    let plainText: String?
}

private struct LyricsCandidate: Codable {
    let trackName: String?
    let artistName: String?
    let albumName: String?
    let duration: TimeInterval?
    let plainLyrics: String?
    let syncedLyrics: String?
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
