import Foundation

struct LyricsDocument {
    let timedLines: [TimedLyricLine]
    let plainText: String?

    var isEmpty: Bool {
        timedLines.isEmpty && (plainText?.isEmpty ?? true)
    }
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
        for fileExtension in ["lrc", "txt"] {
            let candidate = track.parentDirectory
                .appendingPathComponent(track.baseFilename)
                .appendingPathExtension(fileExtension)

            guard FileManager.default.fileExists(atPath: candidate.path) else { continue }
            if let content = try? String(contentsOf: candidate, encoding: .utf8) {
                let document = document(from: content)
                if !document.isEmpty {
                    return document
                }
            }
        }

        return LyricsDocument(timedLines: [], plainText: nil)
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
