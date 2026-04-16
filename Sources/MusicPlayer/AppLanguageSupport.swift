import Foundation

extension PlayerViewModel.AppLanguage {
    func pick(_ chinese: String, _ english: String) -> String {
        self == .chinese ? chinese : english
    }

    var localeIdentifier: String {
        switch self {
        case .chinese:
            return "zh_CN"
        case .english:
            return "en_US"
        }
    }
}

extension PlayerViewModel.AppLanguage {
    func title(for option: PlayerViewModel.AppLanguage) -> String {
        switch option {
        case .chinese:
            return pick("简体中文", "Simplified Chinese")
        case .english:
            return "English"
        }
    }
}

extension PlayerViewModel.AppTheme {
    func title(in language: PlayerViewModel.AppLanguage) -> String {
        switch self {
        case .system:
            return language.pick("跟随系统", "Follow System")
        case .pureBlack:
            return language.pick("纯黑", "Pure Black")
        case .pureWhite:
            return language.pick("纯白", "Pure White")
        case .pastelBlue:
            return language.pick("淡蓝", "Pastel Blue")
        case .pastelPurple:
            return language.pick("淡紫", "Pastel Purple")
        case .pastelGreen:
            return language.pick("淡绿", "Pastel Green")
        case .customImage:
            return language.pick("自定义图片", "Custom Image")
        }
    }
}

extension PlayerViewModel.DesktopLyricsDisplayMode {
    func title(in language: PlayerViewModel.AppLanguage) -> String {
        switch self {
        case .currentOnly:
            return language.pick("当前一句", "Current Line")
        case .dualLine:
            return language.pick("两句横排", "Dual Line")
        case .threeLines:
            return language.pick("三句模式", "Three-Line Mode")
        }
    }
}

extension PlayerViewModel.DesktopLyricsBackgroundStyle {
    func title(in language: PlayerViewModel.AppLanguage) -> String {
        switch self {
        case .themed:
            return language.pick("主题色背景", "Theme Background")
        case .transparent:
            return language.pick("纯透明背景", "Transparent Background")
        }
    }
}

extension PlayerViewModel.PlaybackMode {
    func title(in language: PlayerViewModel.AppLanguage) -> String {
        switch self {
        case .sequential:
            return language.pick("顺序播放", "Sequential")
        case .listLoop:
            return language.pick("循环播放", "Loop")
        case .shuffle:
            return language.pick("随机播放", "Shuffle")
        }
    }
}

extension PlayerViewModel.InterfaceMode {
    func title(in language: PlayerViewModel.AppLanguage) -> String {
        switch self {
        case .full:
            return language.pick("完整模式", "Full Mode")
        case .compact:
            return language.pick("简洁模式", "Compact Mode")
        }
    }
}

extension PlayerViewModel.EqualizerPreset {
    func title(in language: PlayerViewModel.AppLanguage) -> String {
        switch self {
        case .custom:
            return language.pick("自定义", "Custom")
        case .vocal:
            return language.pick("人声增强", "Vocal Boost")
        case .bassBoost:
            return language.pick("低音增强", "Bass Boost")
        case .pop:
            return language.pick("流行", "Pop")
        case .rock:
            return language.pick("摇滚", "Rock")
        case .classical:
            return language.pick("古典", "Classical")
        }
    }
}
