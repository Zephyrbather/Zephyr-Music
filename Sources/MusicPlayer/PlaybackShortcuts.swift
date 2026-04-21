import AppKit
import Carbon.HIToolbox
import IOKit.hidsystem

enum PlaybackShortcutAction: String, CaseIterable, Identifiable, Codable {
    case previousTrack
    case playPause
    case nextTrack

    var id: String { rawValue }

    func title(in language: PlayerViewModel.AppLanguage) -> String {
        switch self {
        case .previousTrack:
            return language.pick("上一首", "Previous")
        case .playPause:
            return language.pick("播放 / 暂停", "Play / Pause")
        case .nextTrack:
            return language.pick("下一首", "Next")
        }
    }
}

enum PlaybackMediaKey: String, Codable, Equatable {
    case previousTrack
    case playPause
    case nextTrack

    var systemKeyType: Int32 {
        switch self {
        case .previousTrack:
            return NX_KEYTYPE_REWIND
        case .playPause:
            return NX_KEYTYPE_PLAY
        case .nextTrack:
            return NX_KEYTYPE_FAST
        }
    }

    func displayText(in language: PlayerViewModel.AppLanguage) -> String {
        switch self {
        case .previousTrack:
            return language.pick("媒体键 F7", "Media Key F7")
        case .playPause:
            return language.pick("媒体键 F8", "Media Key F8")
        case .nextTrack:
            return language.pick("媒体键 F9", "Media Key F9")
        }
    }
}

struct PlaybackShortcut: Codable, Equatable {
    enum Kind: String, Codable {
        case mediaKey
        case keyCode
    }

    let kind: Kind
    let mediaKey: PlaybackMediaKey?
    let keyCode: UInt16?
    let modifierFlagsRawValue: UInt?
    let keyDisplay: String?

    static func mediaKey(_ mediaKey: PlaybackMediaKey) -> PlaybackShortcut {
        PlaybackShortcut(
            kind: .mediaKey,
            mediaKey: mediaKey,
            keyCode: nil,
            modifierFlagsRawValue: nil,
            keyDisplay: nil
        )
    }

    static func keyCode(_ keyCode: UInt16, modifiers: NSEvent.ModifierFlags, keyDisplay: String) -> PlaybackShortcut {
        PlaybackShortcut(
            kind: .keyCode,
            mediaKey: nil,
            keyCode: keyCode,
            modifierFlagsRawValue: sanitizedModifierFlags(from: modifiers).rawValue,
            keyDisplay: keyDisplay
        )
    }

    var modifierFlags: NSEvent.ModifierFlags {
        guard let modifierFlagsRawValue else { return [] }
        return NSEvent.ModifierFlags(rawValue: modifierFlagsRawValue)
    }

    func displayText(in language: PlayerViewModel.AppLanguage) -> String {
        switch kind {
        case .mediaKey:
            return mediaKey?.displayText(in: language) ?? language.pick("未设置", "Not Set")
        case .keyCode:
            let modifiers = Self.modifierSymbols(for: modifierFlags)
            let key = keyDisplay ?? language.pick("未设置", "Not Set")
            return modifiers + key
        }
    }

    func matches(_ event: PlaybackShortcutEventSnapshot) -> Bool {
        switch kind {
        case .mediaKey:
            guard case let .mediaKey(eventMediaKey) = event.kind else { return false }
            return mediaKey == eventMediaKey
        case .keyCode:
            guard case let .keyDown(eventKeyCode, modifierFlagsRawValue, _, isRepeat) = event.kind,
                  !isRepeat,
                  let keyCode else {
                return false
            }
            return eventKeyCode == keyCode && modifierFlagsRawValue == modifierFlags.rawValue
        }
    }

    static func fromCaptureEvent(_ event: PlaybackShortcutEventSnapshot) -> PlaybackShortcutCaptureResult? {
        switch event.kind {
        case let .mediaKey(mediaKey):
            return .captured(.mediaKey(mediaKey))
        case let .keyDown(keyCode, modifierFlagsRawValue, keyDisplay, isRepeat):
            guard !isRepeat else { return nil }

            if keyCode == UInt16(kVK_Escape) {
                return .cancelled
            }

            let modifiers = NSEvent.ModifierFlags(rawValue: modifierFlagsRawValue)
            guard !modifiers.isEmpty || isStandaloneFunctionKey(keyCode) else {
                return .rejected
            }

            return .captured(.keyCode(keyCode, modifiers: modifiers, keyDisplay: keyDisplay))
        }
    }

    static func sanitizedModifierFlags(from flags: NSEvent.ModifierFlags) -> NSEvent.ModifierFlags {
        flags.intersection([.command, .option, .control, .shift, .function])
    }

    static func mediaKey(from event: NSEvent) -> PlaybackMediaKey? {
        guard event.type == .systemDefined, event.subtype.rawValue == 8 else {
            return nil
        }

        let data = Int(event.data1)
        let keyType = Int32((data & 0xFFFF0000) >> 16)
        let keyFlags = (data & 0x0000FFFF)
        let keyState = ((keyFlags & 0xFF00) >> 8) == 0xA

        guard keyState else { return nil }

        switch keyType {
        case NX_KEYTYPE_REWIND:
            return .previousTrack
        case NX_KEYTYPE_PLAY:
            return .playPause
        case NX_KEYTYPE_FAST:
            return .nextTrack
        default:
            return nil
        }
    }

    private static func modifierSymbols(for flags: NSEvent.ModifierFlags) -> String {
        var result = ""
        if flags.contains(.control) { result += "⌃" }
        if flags.contains(.option) { result += "⌥" }
        if flags.contains(.shift) { result += "⇧" }
        if flags.contains(.command) { result += "⌘" }
        if flags.contains(.function) { result += "fn " }
        return result
    }

    static func keyDisplayName(for event: NSEvent) -> String {
        if let specialKeyName = specialKeyDisplayName(for: event.keyCode) {
            return specialKeyName
        }

        let fallback = event.charactersIgnoringModifiers?
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .uppercased()

        if let fallback, !fallback.isEmpty {
            return fallback
        }

        return "Key \(event.keyCode)"
    }

    private static func specialKeyDisplayName(for keyCode: UInt16) -> String? {
        switch Int(keyCode) {
        case kVK_Space:
            return "Space"
        case kVK_Return:
            return "Return"
        case kVK_Tab:
            return "Tab"
        case kVK_Delete:
            return "Delete"
        case kVK_ForwardDelete:
            return "Forward Delete"
        case kVK_LeftArrow:
            return "Left Arrow"
        case kVK_RightArrow:
            return "Right Arrow"
        case kVK_UpArrow:
            return "Up Arrow"
        case kVK_DownArrow:
            return "Down Arrow"
        case kVK_Home:
            return "Home"
        case kVK_End:
            return "End"
        case kVK_PageUp:
            return "Page Up"
        case kVK_PageDown:
            return "Page Down"
        case kVK_F1:
            return "F1"
        case kVK_F2:
            return "F2"
        case kVK_F3:
            return "F3"
        case kVK_F4:
            return "F4"
        case kVK_F5:
            return "F5"
        case kVK_F6:
            return "F6"
        case kVK_F7:
            return "F7"
        case kVK_F8:
            return "F8"
        case kVK_F9:
            return "F9"
        case kVK_F10:
            return "F10"
        case kVK_F11:
            return "F11"
        case kVK_F12:
            return "F12"
        case kVK_F13:
            return "F13"
        case kVK_F14:
            return "F14"
        case kVK_F15:
            return "F15"
        case kVK_F16:
            return "F16"
        case kVK_F17:
            return "F17"
        case kVK_F18:
            return "F18"
        case kVK_F19:
            return "F19"
        case kVK_F20:
            return "F20"
        default:
            return nil
        }
    }

    private static func isStandaloneFunctionKey(_ keyCode: UInt16) -> Bool {
        switch Int(keyCode) {
        case kVK_F1, kVK_F2, kVK_F3, kVK_F4, kVK_F5, kVK_F6, kVK_F7, kVK_F8, kVK_F9, kVK_F10,
             kVK_F11, kVK_F12, kVK_F13, kVK_F14, kVK_F15, kVK_F16, kVK_F17, kVK_F18, kVK_F19, kVK_F20:
            return true
        default:
            return false
        }
    }
}

struct PlaybackShortcutEventSnapshot: Sendable {
    enum Kind: Sendable {
        case mediaKey(PlaybackMediaKey)
        case keyDown(keyCode: UInt16, modifierFlagsRawValue: UInt, keyDisplay: String, isRepeat: Bool)
    }

    let kind: Kind

    init?(_ event: NSEvent) {
        if let mediaKey = PlaybackShortcut.mediaKey(from: event) {
            kind = .mediaKey(mediaKey)
            return
        }

        guard event.type == .keyDown else {
            return nil
        }

        kind = .keyDown(
            keyCode: event.keyCode,
            modifierFlagsRawValue: PlaybackShortcut.sanitizedModifierFlags(from: event.modifierFlags).rawValue,
            keyDisplay: PlaybackShortcut.keyDisplayName(for: event),
            isRepeat: event.isARepeat
        )
    }
}

enum PlaybackShortcutCaptureResult: Equatable {
    case captured(PlaybackShortcut)
    case cancelled
    case rejected
}

struct PlaybackShortcutConfiguration: Codable, Equatable {
    var previousTrack: PlaybackShortcut
    var playPause: PlaybackShortcut
    var nextTrack: PlaybackShortcut

    static let defaultValue = PlaybackShortcutConfiguration(
        previousTrack: .mediaKey(.previousTrack),
        playPause: .mediaKey(.playPause),
        nextTrack: .mediaKey(.nextTrack)
    )

    subscript(action: PlaybackShortcutAction) -> PlaybackShortcut {
        get {
            switch action {
            case .previousTrack:
                return previousTrack
            case .playPause:
                return playPause
            case .nextTrack:
                return nextTrack
            }
        }
        set {
            switch action {
            case .previousTrack:
                previousTrack = newValue
            case .playPause:
                playPause = newValue
            case .nextTrack:
                nextTrack = newValue
            }
        }
    }
}

final class PlaybackShortcutMonitor {
    private weak var viewModel: PlayerViewModel?
    private var keyDownMonitor: Any?
    private var systemDefinedMonitor: Any?

    init(viewModel: PlayerViewModel) {
        self.viewModel = viewModel
    }

    func start() {
        guard keyDownMonitor == nil, systemDefinedMonitor == nil else { return }

        keyDownMonitor = NSEvent.addLocalMonitorForEvents(matching: [.keyDown]) { [weak self] event in
            guard let self else { return event }
            return self.viewModel?.handlePlaybackShortcutEvent(event) == true ? nil : event
        }

        systemDefinedMonitor = NSEvent.addLocalMonitorForEvents(matching: [.systemDefined]) { [weak self] event in
            guard let self else { return event }
            return self.viewModel?.handlePlaybackShortcutEvent(event) == true ? nil : event
        }
    }

    deinit {
        stop()
    }

    private func stop() {
        if let keyDownMonitor {
            NSEvent.removeMonitor(keyDownMonitor)
        }
        if let systemDefinedMonitor {
            NSEvent.removeMonitor(systemDefinedMonitor)
        }
        keyDownMonitor = nil
        systemDefinedMonitor = nil
    }
}
