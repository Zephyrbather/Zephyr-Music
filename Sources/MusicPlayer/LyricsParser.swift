import Foundation

struct LyricsDocument: Equatable, Codable {
    let timedLines: [TimedLyricLine]
    let plainText: String?

    var isEmpty: Bool {
        timedLines.isEmpty && (plainText?.isEmpty ?? true)
    }
}

enum LyricsSourceKind: String, CaseIterable, Codable, Identifiable {
    case embedded
    case sidecarLRC
    case sidecarTXT
    case onlineSynced
    case onlinePlain

    var id: String { rawValue }

    var isOnline: Bool {
        switch self {
        case .onlineSynced, .onlinePlain:
            return true
        default:
            return false
        }
    }
}

struct LyricsSourceOption: Identifiable, Equatable, Codable {
    let sourceID: String?
    let kind: LyricsSourceKind
    let document: LyricsDocument
    let rank: Int?
    let trackName: String?
    let artistName: String?
    let albumName: String?
    let providerName: String?

    init(
        sourceID: String? = nil,
        kind: LyricsSourceKind,
        document: LyricsDocument,
        rank: Int? = nil,
        trackName: String? = nil,
        artistName: String? = nil,
        albumName: String? = nil,
        providerName: String? = nil
    ) {
        self.sourceID = sourceID
        self.kind = kind
        self.document = document
        self.rank = rank
        self.trackName = trackName
        self.artistName = artistName
        self.albumName = albumName
        self.providerName = providerName
    }

    var id: String { sourceID ?? kind.rawValue }
}

struct TimedLyricLine: Identifiable, Equatable, Codable {
    let id: UUID
    let time: TimeInterval
    let text: String

    init(id: UUID = UUID(), time: TimeInterval, text: String) {
        self.id = id
        self.time = time
        self.text = text
    }
}

enum LyricsParser {
    static func document(from content: String) -> LyricsDocument {
        let parsed = parseLRC(content)
        if !parsed.isEmpty {
            return LyricsDocument(timedLines: parsed, plainText: nil)
        }

        let text = normalizedPlainText(from: content)
        return LyricsDocument(timedLines: [], plainText: text.isEmpty ? nil : text)
    }

    static func loadLyrics(for track: AudioTrack) -> LyricsDocument {
        loadLyricsSources(for: track).first?.document ?? LyricsDocument(timedLines: [], plainText: nil)
    }

    static func loadLyricsSources(for track: AudioTrack) -> [LyricsSourceOption] {
        var sources: [LyricsSourceOption] = []

        for (fileExtension, kind) in [("lrc", LyricsSourceKind.sidecarLRC), ("txt", .sidecarTXT)] {
            let candidate = track.parentDirectory
                .appendingPathComponent(track.baseFilename)
                .appendingPathExtension(fileExtension)

            guard FileManager.default.fileExists(atPath: candidate.path) else { continue }
            if let content = try? String(contentsOf: candidate, encoding: .utf8) {
                let document = document(from: content)
                guard !document.isEmpty else { continue }

                let source = LyricsSourceOption(
                    sourceID: kind.rawValue,
                    kind: kind,
                    document: document
                )
                guard !sources.contains(where: { $0.id == source.id || $0.document == source.document }) else { continue }
                sources.append(source)
            }
        }

        return sources
    }

    static func parseSyncedLyrics(_ content: String) -> [TimedLyricLine] {
        parseLRC(content)
    }

    private static func parseLRC(_ content: String) -> [TimedLyricLine] {
        let pattern = #"\[(\d{1,2}):(\d{2})(?:\.(\d{1,2}))?\]"#
        guard let regex = try? NSRegularExpression(pattern: pattern) else { return [] }

        var lines: [TimedLyricLine] = []

        for rawLine in content.components(separatedBy: .newlines) {
            let line = rawLine.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !line.isEmpty else { continue }

            let nsRange = NSRange(line.startIndex..<line.endIndex, in: line)
            let matches = regex.matches(in: line, options: [], range: nsRange)
            guard !matches.isEmpty else { continue }

            let lyricText = regex.stringByReplacingMatches(in: line, options: [], range: nsRange, withTemplate: "")
                .trimmingCharacters(in: .whitespacesAndNewlines)
            guard !lyricText.isEmpty else { continue }

            for match in matches {
                guard
                    let minuteRange = Range(match.range(at: 1), in: line),
                    let secondRange = Range(match.range(at: 2), in: line),
                    let minutes = Double(line[minuteRange]),
                    let seconds = Double(line[secondRange])
                else {
                    continue
                }

                var fraction: Double = 0
                if let fractionRange = Range(match.range(at: 3), in: line) {
                    let raw = String(line[fractionRange])
                    let divisor = raw.count == 1 ? 10.0 : 100.0
                    fraction = (Double(raw) ?? 0) / divisor
                }

                let time = (minutes * 60) + seconds + fraction
                lines.append(TimedLyricLine(time: time, text: lyricText))
            }
        }

        return lines.sorted { $0.time < $1.time }
    }

    private static func normalizedPlainText(from content: String) -> String {
        content
            .components(separatedBy: .newlines)
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
            .joined(separator: "\n")
    }
}
