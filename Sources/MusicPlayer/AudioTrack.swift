import Foundation

struct AudioTrack: Identifiable, Equatable {
    let id = UUID()
    let url: URL
    let artist: String?
    let album: String?
    private let storedTitle: String

    init(url: URL, title: String? = nil, artist: String? = nil, album: String? = nil) {
        self.url = url

        let fallbackName = url.deletingPathExtension().lastPathComponent
        var resolvedTitle = title?.nilIfEmpty
        var resolvedArtist = artist?.nilIfEmpty

        if resolvedTitle == nil || resolvedArtist == nil {
            let parts = fallbackName.components(separatedBy: " - ")
            if parts.count >= 2 {
                resolvedArtist = resolvedArtist ?? parts.first?.trimmingCharacters(in: .whitespacesAndNewlines)
                resolvedTitle = resolvedTitle ?? parts.dropFirst().joined(separator: " - ").trimmingCharacters(in: .whitespacesAndNewlines)
            }
        }

        self.artist = resolvedArtist
        self.album = (album?.nilIfEmpty) ?? url.deletingLastPathComponent().lastPathComponent.nilIfEmpty
        self.storedTitle = resolvedTitle ?? fallbackName
    }

    var title: String {
        storedTitle
    }

    var fileExtension: String {
        url.pathExtension.uppercased()
    }

    var baseFilename: String {
        url.deletingPathExtension().lastPathComponent
    }

    var parentDirectory: URL {
        url.deletingLastPathComponent()
    }

    func withMetadata(title: String?, artist: String?, album: String?) -> AudioTrack {
        AudioTrack(url: url, title: title ?? storedTitle, artist: artist ?? self.artist, album: album ?? self.album)
    }
}

private extension String {
    var nilIfEmpty: String? {
        let trimmed = trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : trimmed
    }
}
