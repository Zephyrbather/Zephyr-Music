import AppKit
import Foundation

enum ArtworkSourceKind: String, CaseIterable, Identifiable {
    case embedded
    case sidecar
    case online

    var id: String { rawValue }

    var isOnline: Bool {
        self == .online
    }
}

struct ArtworkOption: Identifiable, Equatable {
    let sourceID: String
    let kind: ArtworkSourceKind
    let image: NSImage
    let rank: Int?
    let title: String?
    let artistName: String?
    let albumName: String?
    let providerName: String?

    var id: String { sourceID }

    static func == (lhs: ArtworkOption, rhs: ArtworkOption) -> Bool {
        lhs.sourceID == rhs.sourceID
    }
}
