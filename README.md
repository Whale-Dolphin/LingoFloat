# LingoFloat

> macOS 本地实时翻译字幕：内录系统音频，自动识别英语、日语等语音并翻译成
> 中文，适合看美剧、动漫、直播和没有字幕的视频。

[![CI](https://github.com/Whale-Dolphin/LingoFloat/actions/workflows/ci.yml/badge.svg)](https://github.com/Whale-Dolphin/LingoFloat/actions/workflows/ci.yml)
[![Release](https://img.shields.io/github/v/release/Whale-Dolphin/LingoFloat)](https://github.com/Whale-Dolphin/LingoFloat/releases/latest)
[![macOS](https://img.shields.io/badge/macOS-15%2B-black?logo=apple)](https://github.com/Whale-Dolphin/LingoFloat)

LingoFloat 是一个面向观影场景的 macOS 本地实时翻译应用：直接捕获 Mac
正在播放的系统音频，在本机完成语音识别，再把字幕翻译成指定语言并显示在
全屏视频上方。无需 BlackHole 等虚拟声卡。

当前仓库是第一版可运行 MVP。它基于 MIT 许可的
[WhisperCaption](https://github.com/albond/WhisperCaption) `v1.0.1` 开始开发，
保留了成熟的 Core Audio Process Tap、WhisperKit、Apple Translation 和
`NSPanel` 悬浮字幕实现，并建立了独立的产品名、Bundle ID 与数据空间。

## 主要功能

- 点击 **Start** 即进入真实链路：首次运行自动下载所选 WhisperKit 模型，
  然后执行系统音频 → 16 kHz PCM → WhisperKit → Apple Translation →
  双语悬浮字幕。应用不再提供写死字幕的假体验入口。
- **From: Auto** 自动检测输入语言，输出语言可指定为中文或其他 Apple
  Translation 支持的语言。
- 主窗口和悬浮 HUD 都有 **Clear**，可以清空当前上下文并从头显示；旧内容仍
  保留在 History。
- 支持全局快捷键开始/停止转录和显示/隐藏 HUD。
- 默认不捕获麦克风；这些选项可以在 Settings 中调整。
- 默认允许截图。翻译请求会去重、限频并自动重试临时错误；持续失败时可点击
  **Retry translation** 恢复。
- 系统音频不经过 BlackHole 等虚拟声卡，也不会默认保存原始音频。

## 安装

Apple Silicon Mac 可以从 [GitHub Releases](https://github.com/Whale-Dolphin/LingoFloat/releases/latest)
下载 `LingoFloat-*.dmg`，拖入 Applications 后使用。

当前预编译版本采用 ad-hoc 签名，尚未经过 Apple notarization。第一次打开时，
请在 **系统设置 → 隐私与安全性** 中选择 **仍要打开**。Release 同时提供
`.dmg.sha256`；下载后可以校验：

```bash
shasum -a 256 -c LingoFloat-1.1.1.dmg.sha256
```

## 本地构建

要求 macOS 15 或更高版本，以及 Xcode 16 或更高版本。本机当前完整 Xcode
位于 `/Applications/Xcode-beta.app`，所以命令显式使用这个路径，不修改全局
`xcode-select`：

```bash
git clone https://github.com/Whale-Dolphin/LingoFloat.git
cd LingoFloat
./scripts/build-demo.sh
open .build/DerivedData/Build/Products/Debug/LingoFloat.app
```

也可以直接打开
`LingoFloat/LingoFloat.xcodeproj`，选择 `LingoFloat` scheme 后按 Run。

## 使用真实本地识别

LingoFloat 负责管理模型，不要求用户安装 Hugging Face CLI 或手工选择目录：

1. 打开 **Settings → Speech Recognition**，选择 `small` 或 `medium`。
2. 播放视频并点击 **Start**。
3. 首次运行会从 `argmaxinc/whisperkit-coreml` 下载模型；`small` 约 500 MB。
4. 按 macOS 提示授权 **Screen & System Audio Recording**，必要时重启应用。
5. 下载完成后模型保存在 `~/Library/Application Support/LingoFloat/Models`，
   后续可以离线启动识别。

真实识别依赖目标 Mac 上的模型、权限和正在播放的音频，因此单元测试不能
替代真实音频端到端验证。测试与实机验证边界见
[`Docs/test-plan.md`](Docs/test-plan.md)。

## 工程结构

```text
LingoFloat/
├── LingoFloat/
│   ├── Capture/          # 系统音频与麦克风采集
│   ├── LiveCaption/      # ASR、切句、翻译和字幕状态
│   ├── Window/           # 全屏悬浮字幕 NSPanel
│   ├── Settings/         # 本地设置和模型路径
│   └── LingoFloatApp.swift
├── LingoFloatTests/
└── LingoFloatUITests/
```

详细数据流和模块边界见 [`Docs/architecture.md`](Docs/architecture.md)。

## 隐私与许可

选择 WhisperKit 时，ASR 与 Apple Translation 均在本机运行；首次模型下载会
访问 Hugging Face。只有主动选择 Deepgram 或 ElevenLabs 后端时，音频才会
发送给对应服务商。

项目使用 [MIT License](LICENSE)。上游版权和完整提交历史保留在仓库中；远端
被命名为 `upstream`，避免把个人改动误推送到原项目。
