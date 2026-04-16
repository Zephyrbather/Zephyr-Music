# Zephyr Player

本项目全称AI写，作者没有写一行代码，纯娱乐使用。
Zephyr Player 是一个面向 macOS 的原生本地音乐播放器，基于 `SwiftUI` 和 `AVFoundation` 构建，专注于高品质本地音频播放、歌词体验、歌单管理和桌面场景使用。

## View
完整模式
![完整模式](XcodeApp/Assets.xcassets/AppIcon.appiconset/whole.png)
简洁模式
<img src="XcodeApp/Assets.xcassets/AppIcon.appiconset/simple.png" width="24%" /> <img src="XcodeApp/Assets.xcassets/AppIcon.appiconset/simple-black.png" width="24%" /><img src="XcodeApp/Assets.xcassets/AppIcon.appiconset/simple-white.png" width="24%" /> <img src="XcodeApp/Assets.xcassets/AppIcon.appiconset/simple-diy.png" width="24%" />
## Highlights

- 支持格式：`FLAC`、`WAV`、`MP3`、`DSF`、`DFF`、`DSD`
- 支持拖拽导入、文件夹递归扫描、批量导入
- 支持多歌单、歌单搜索、筛选、排序、下一首播放
- 支持内嵌歌词、同名 `.lrc` / `.txt`、在线歌词补全
- 支持逐行歌词高亮、点击歌词跳转播放时间
- 支持专辑封面读取与在线封面补全
- 支持桌面歌词、菜单栏迷你控制器、播放模式切换
- 支持 10 段均衡器与常用预设
- 支持完整模式 / 简洁模式
- 支持状态恢复与听歌历史统计

## Screenshots

- 可在发布到 GitHub 后补充主界面、简洁模式、桌面歌词、听歌历史等截图

## Requirements

- macOS 13.0+
- Xcode 16+
- Swift 5

## Quick Start

### 使用 Xcode

```bash
git clone https://github.com/Zephyrbather/Zephyr-Music.git
cd music
open MusicPlayer.xcodeproj
```

在 Xcode 中：

1. 选择 `MusicPlayer` Scheme
2. 点击 `Run`

### 使用命令行编译

```bash
xcodebuild -project MusicPlayer.xcodeproj -scheme MusicPlayer -configuration Debug build
```

编译成功后，可在 Xcode 的 `DerivedData/Build/Products/Debug/` 中找到 `Zephyr Player.app`。

## Main Features

### 本地音乐播放

- 支持文件导入、文件夹扫描、拖拽导入
- 支持顺序播放、循环播放、随机播放
- 支持“下一首播放”待播队列

### 歌词系统

- 优先级：内嵌歌词 > 同名 `.lrc` / `.txt` > 在线补全
- 支持带时间轴歌词逐行滚动高亮
- 支持点击歌词跳转时间片
- 支持桌面歌词浮窗与多种显示模式

### 歌单与检索

- 支持多歌单切换
- 支持歌单内关键字搜索
- 支持按艺术家 / 专辑筛选
- 支持排序与匹配高亮
- 支持从其他歌单复制歌曲到当前歌单

### 听歌历史

- 支持最近 100 首
- 支持月度统计
- 支持年度统计
- 支持歌曲播放次数统计

### 个性化

- 支持跟随系统、纯黑、纯白、马卡龙色、自定义图片主题
- 支持桌面歌词透明度、字号、锁定位置
- 支持 10 段均衡器与预设

## Project Structure

```text
.
├── LICENSE
├── MusicPlayer.xcodeproj
├── Package.swift
├── README.md
├── Sources/MusicPlayer
│   ├── AudioAssetLoader.swift
│   ├── AudioTrack.swift
│   ├── ContentView.swift
│   ├── DesktopLyricsWindowController.swift
│   ├── LyricsParser.swift
│   ├── MusicPlayerApp.swift
│   ├── OnlineMetadataService.swift
│   ├── PlayerTheme.swift
│   └── PlayerViewModel.swift
└── XcodeApp
    ├── Assets.xcassets
    └── Info.plist
```

## Notes

- 项目依赖 macOS 原生音频解码能力，个别 `DSD` 文件的可播放性取决于系统支持情况
- 在线歌词和封面补全依赖网络请求，无网络时不影响本地播放
- 听歌历史与应用状态均保存在本地，不上传到外部服务

## License

本项目采用 [MIT License](./LICENSE)。
