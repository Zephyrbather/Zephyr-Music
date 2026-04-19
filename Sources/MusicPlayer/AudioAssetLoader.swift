import AppKit
import AVFoundation
import Foundation

struct TrackAssetMetadata {
    let title: String?
    let artist: String?
    let album: String?
}

struct LoadedArtworkAsset {
    let image: NSImage
    let kind: ArtworkSourceKind
}

enum AudioAssetLoader {
    static func loadLyrics(for url: URL) async -> LyricsDocument {
        let asset = AVURLAsset(url: url)
        return await loadLyricsSources(from: asset).first?.document ?? LyricsDocument(timedLines: [], plainText: nil)
    }

    static func loadLyricsSources(for url: URL) async -> [LyricsSourceOption] {
        let asset = AVURLAsset(url: url)
        return await loadLyricsSources(from: asset)
    }

    static func loadLyricsSourcesAndArtwork(for url: URL) async -> (lyricsSources: [LyricsSourceOption], artwork: LoadedArtworkAsset?) {
        let asset = AVURLAsset(url: url)
        async let lyricsSources = loadLyricsSources(from: asset)
        async let artwork = loadArtworkAsset(from: asset)
        return await (lyricsSources, artwork)
    }

    static func loadMetadata(for url: URL) async -> TrackAssetMetadata {
        let asset = AVURLAsset(url: url)
        let items = (try? await asset.load(.commonMetadata)) ?? []

        var title: String?
        var artist: String?
        var album: String?

        for item in items {
            switch item.commonKey?.rawValue {
            case AVMetadataKey.commonKeyTitle.rawValue:
                if title == nil {
                    title = try? await item.load(.stringValue)
                }
            case AVMetadataKey.commonKeyArtist.rawValue:
                if artist == nil {
                    artist = try? await item.load(.stringValue)
                }
            case AVMetadataKey.commonKeyAlbumName.rawValue:
                if album == nil {
                    album = try? await item.load(.stringValue)
                }
            default:
                break
            }
        }

        return TrackAssetMetadata(title: title, artist: artist, album: album)
    }

    static func loadArtwork(for url: URL) async -> NSImage? {
        let asset = AVURLAsset(url: url)
        return await loadArtworkAsset(from: asset)?.image
    }

    static func loadArtworkAsset(for url: URL) async -> LoadedArtworkAsset? {
        let asset = AVURLAsset(url: url)
        return await loadArtworkAsset(from: asset)
    }

    private static func loadLyricsSources(from asset: AVURLAsset) async -> [LyricsSourceOption] {
        var sources: [LyricsSourceOption] = []
        if let directLyrics = try? await asset.load(.lyrics),
           let document = lyricsDocument(from: directLyrics),
           !document.isEmpty {
            sources.append(
                LyricsSourceOption(
                    sourceID: LyricsSourceKind.embedded.rawValue,
                    kind: .embedded,
                    document: document
                )
            )
        }

        if sources.isEmpty {
            let formats = (try? await asset.load(.availableMetadataFormats)) ?? []
            for format in formats {
                let items = (try? await asset.loadMetadata(for: format)) ?? []
                for item in items {
                    if let candidate = await lyricCandidate(from: item),
                       let document = lyricsDocument(from: candidate),
                       !document.isEmpty {
                        sources.append(
                            LyricsSourceOption(
                                sourceID: LyricsSourceKind.embedded.rawValue,
                                kind: .embedded,
                                document: document
                            )
                        )
                        break
                    }
                }

                if !sources.isEmpty {
                    break
                }
            }
        }

        return sources
    }

    private static func loadArtworkAsset(from asset: AVURLAsset) async -> LoadedArtworkAsset? {
        let items = (try? await asset.load(.commonMetadata)) ?? []

        for item in items where item.commonKey?.rawValue == AVMetadataKey.commonKeyArtwork.rawValue {
            if let data = try? await item.load(.dataValue),
               let image = NSImage(data: data) {
                return LoadedArtworkAsset(image: image, kind: .embedded)
            }
        }

        if let sidecarArtwork = loadSidecarArtwork(for: asset.url) {
            return sidecarArtwork
        }

        return nil
    }

    private static func loadSidecarArtwork(for url: URL) -> LoadedArtworkAsset? {
        for candidate in artworkSidecarCandidates(for: url) {
            guard FileManager.default.fileExists(atPath: candidate.path) else { continue }
            guard let image = NSImage(contentsOf: candidate) else { continue }
            return LoadedArtworkAsset(image: image, kind: .sidecar)
        }

        return nil
    }

    private static func artworkSidecarCandidates(for url: URL) -> [URL] {
        let base = url.deletingPathExtension()
        let directory = url.deletingLastPathComponent()
        let filename = base.lastPathComponent

        let names = [
            "\(filename).cover.png",
            "\(filename).cover.jpg",
            "\(filename).cover.jpeg",
            "\(filename).cover.webp",
            "\(filename).png",
            "\(filename).jpg",
            "\(filename).jpeg",
            "\(filename).webp"
        ]

        return names.map { directory.appendingPathComponent($0) }
    }

    private static func lyricCandidate(from item: AVMetadataItem) async -> String? {
        let identifier = item.identifier?.rawValue.lowercased() ?? ""
        let keyString = (item.key as? String)?.lowercased() ?? ""
        let commonKey = item.commonKey?.rawValue.lowercased() ?? ""

        guard isLikelyLyricsField(identifier: identifier, key: keyString, commonKey: commonKey) else {
            return nil
        }

        if let value = try? await item.load(.stringValue),
           let trimmed = sanitizedLyrics(value) {
            return trimmed
        }

        if let data = try? await item.load(.dataValue),
           let decoded = decodeLyricsData(data),
           let trimmed = sanitizedLyrics(decoded) {
            return trimmed
        }

        return nil
    }

    private static func isLikelyLyricsField(identifier: String, key: String, commonKey: String) -> Bool {
        let candidates = [identifier, key, commonKey]

        if candidates.contains(where: { $0.contains("lyrics") || $0.contains("lyric") }) {
            return true
        }

        if candidates.contains(where: { $0.contains("uslt") || $0.contains("sylt") }) {
            return true
        }

        if identifier.contains("usercomment") || key == "lyrics" || key == "unsyncedlyrics" || key == "syncedlyrics" {
            return true
        }

        return false
    }

    private static func decodeLyricsData(_ data: Data) -> String? {
        let encodings: [String.Encoding] = [.utf8, .utf16, .utf16LittleEndian, .utf16BigEndian, .isoLatin1]
        for encoding in encodings {
            if let value = String(data: data, encoding: encoding),
               !value.trimmingCharacters(in: .whitespacesAndNewlines.union(.controlCharacters)).isEmpty {
                return value
            }
        }

        return nil
    }

    private static func lyricsDocument(from content: String) -> LyricsDocument? {
        let document = LyricsParser.document(from: content)
        return document.isEmpty ? nil : document
    }

    private static func sanitizedLyrics(_ value: String) -> String? {
        let trimmed = value
            .replacingOccurrences(of: "\u{0}", with: "")
            .trimmingCharacters(in: .whitespacesAndNewlines.union(.controlCharacters))

        return trimmed.isEmpty ? nil : trimmed
    }
}
