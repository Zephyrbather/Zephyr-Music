import AppKit
import AVFoundation
import Foundation

struct TrackAssetMetadata {
    let title: String?
    let artist: String?
    let album: String?
}

enum AudioAssetLoader {
    static func loadLyrics(for url: URL) async -> LyricsDocument {
        let asset = AVURLAsset(url: url)

        if let directLyrics = try? await asset.load(.lyrics),
           let document = lyricsDocument(from: directLyrics),
           !document.isEmpty {
            return document
        }

        let formats = (try? await asset.load(.availableMetadataFormats)) ?? []
        for format in formats {
            let items = (try? await asset.loadMetadata(for: format)) ?? []
            for item in items {
                if let candidate = await lyricCandidate(from: item),
                   let document = lyricsDocument(from: candidate),
                   !document.isEmpty {
                    return document
                }
            }
        }

        return LyricsDocument(timedLines: [], plainText: nil)
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
        let items = (try? await asset.load(.commonMetadata)) ?? []

        for item in items where item.commonKey?.rawValue == AVMetadataKey.commonKeyArtwork.rawValue {
            if let data = try? await item.load(.dataValue),
               let image = NSImage(data: data) {
                return image
            }
        }

        return nil
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
