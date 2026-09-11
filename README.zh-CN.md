# LingoFloat

[English](README.md) | [简体中文](README.zh-CN.md)

> macOS 本地实时翻译字幕。

[![CI](https://github.com/Whale-Dolphin/LingoFloat/actions/workflows/ci.yml/badge.svg)](https://github.com/Whale-Dolphin/LingoFloat/actions/workflows/ci.yml)
[![Release](https://img.shields.io/github/v/release/Whale-Dolphin/LingoFloat)](https://github.com/Whale-Dolphin/LingoFloat/releases/latest)
[![macOS](https://img.shields.io/badge/macOS-15%2B-black?logo=apple)](https://github.com/Whale-Dolphin/LingoFloat)

LingoFloat 可以直接捕获 Mac 正在播放的音频，在本机完成语音识别，并在全屏
视频上方显示翻译字幕。它适合观看外语剧集、动漫、直播和没有字幕的视频，
无需安装虚拟声卡。

## 主要功能

- 直接捕获 macOS 系统音频。
- 使用 WhisperKit 在本机运行语音识别。
- 自动检测输入语言，也可以手动指定。
- 翻译成中文及 Apple Translation 支持的其他语言。
- 提供可移动、可调整大小的双语 CC HUD。
- 使用全局快捷键开始/停止转录及显示/隐藏 HUD。
- 在主窗口或 HUD 中清除当前上下文。
- 主窗口可以正常截图，CC HUD 默认不进入截图。
- 本地保存字幕历史，默认不保存原始音频。

## 系统要求

- Apple Silicon Mac
- macOS 15 或更高版本
- 推荐的 Whisper `small` 模型约需要 500 MB 空间

## 安装

从 [GitHub Releases](https://github.com/Whale-Dolphin/LingoFloat/releases/latest)
下载最新 DMG，打开后将 LingoFloat 拖入 Applications。

当前版本采用 ad-hoc 签名，尚未经过 Apple notarization。如果 macOS 阻止首次
启动，请打开 **系统设置 → 隐私与安全性**，点击 **仍要打开** 并确认。

## 使用方法

1. 打开 **Settings → Speech Recognition**，选择 Whisper 模型。
2. 将 **From** 设置为 **Auto**，或者手动选择输入语言。
3. 选择需要的 **To** 语言。
4. 点击 **Start**，并授予屏幕与系统音频录制权限。
5. 播放视频，点击 **Show Overlay** 显示 CC HUD。

模型会在第一次使用时下载，并存放在
`~/Library/Application Support/LingoFloat/Models`。

## 从源码构建

使用 Xcode 16 或更高版本打开 `LingoFloat/LingoFloat.xcodeproj`，选择
`LingoFloat` scheme 后运行；也可以使用：

```bash
git clone https://github.com/Whale-Dolphin/LingoFloat.git
cd LingoFloat
LINGOFLOAT_XCODE_DIR=/Applications/Xcode.app/Contents/Developer \
  ./scripts/build-demo.sh
```

数据流和模块结构见 [Docs/architecture.md](Docs/architecture.md)。

## 致谢

- Albond 的 [WhisperCaption](https://github.com/albond/WhisperCaption) ——
  LingoFloat 基于这个采用 MIT 许可的原始项目开发。
- Argmax 的
  [WhisperKit / argmax-oss-swift](https://github.com/argmaxinc/argmax-oss-swift)
  —— 本地语音识别和模型管理。
- OpenAI 的 [Whisper](https://github.com/openai/whisper) —— 通过 WhisperKit
  使用的语音识别模型。
- Hugging Face 的
  [swift-transformers](https://github.com/huggingface/swift-transformers) ——
  WhisperKit 使用的模型和 tokenizer 支持。
- Apple Core Audio Process Taps、Translation、SwiftUI、AppKit 和
  ScreenCaptureKit。

其他 Swift Package 依赖及其准确版本见
[Package.resolved](LingoFloat/LingoFloat.xcodeproj/project.xcworkspace/xcshareddata/swiftpm/Package.resolved)。

## 隐私

选择 WhisperKit 时，语音识别和翻译均在 Mac 本机运行。只有用户主动选择可选
的 Deepgram 或 ElevenLabs 后端时，音频才会发送到远端服务。

## 许可证

LingoFloat 使用 [MIT License](LICENSE)，并保留上游版权声明。
