# LingoFloat

[English](README.md) | [简体中文](README.zh-CN.md)

> Local, real-time translation subtitles for macOS.

[![CI](https://github.com/Whale-Dolphin/LingoFloat/actions/workflows/ci.yml/badge.svg)](https://github.com/Whale-Dolphin/LingoFloat/actions/workflows/ci.yml)
[![Release](https://img.shields.io/github/v/release/Whale-Dolphin/LingoFloat)](https://github.com/Whale-Dolphin/LingoFloat/releases/latest)
[![macOS](https://img.shields.io/badge/macOS-15%2B-black?logo=apple)](https://github.com/Whale-Dolphin/LingoFloat)

LingoFloat captures audio playing on your Mac, transcribes it locally, and
displays translated subtitles above full-screen video. It is designed for
watching foreign-language shows, anime, live streams, and videos without
subtitles. No virtual audio device is required.

## Features

- Capture macOS system audio directly.
- Run speech recognition locally with WhisperKit.
- Automatically detect the source language or select it manually.
- Translate into Chinese and other languages supported by Apple Translation.
- Display a movable and resizable bilingual CC HUD.
- Start or stop transcription and toggle the HUD with global shortcuts.
- Clear the current context from either the main window or the HUD.
- Keep the main window visible in screenshots while excluding the CC HUD.
- Store transcript history locally without saving raw audio by default.

## Requirements

- Apple Silicon Mac
- macOS 15 or later
- About 500 MB of free space for the recommended Whisper `small` model

## Installation

Download the latest DMG from
[GitHub Releases](https://github.com/Whale-Dolphin/LingoFloat/releases/latest),
open it, and drag LingoFloat into Applications.

The current build is ad-hoc signed and not Apple-notarized. If macOS blocks the
first launch, open **System Settings → Privacy & Security**, click
**Open Anyway**, and confirm.

## Usage

1. Open **Settings → Speech Recognition** and select a Whisper model.
2. Set **From** to **Auto** or choose the spoken language.
3. Select the desired **To** language.
4. Click **Start** and grant Screen & System Audio Recording permission.
5. Play a video and click **Show Overlay** to display the CC HUD.

The selected model is downloaded on first use and stored under
`~/Library/Application Support/LingoFloat/Models`.

## Build from source

Open `LingoFloat/LingoFloat.xcodeproj` in Xcode 16 or later and run the
`LingoFloat` scheme, or use:

```bash
git clone https://github.com/Whale-Dolphin/LingoFloat.git
cd LingoFloat
LINGOFLOAT_XCODE_DIR=/Applications/Xcode.app/Contents/Developer \
  ./scripts/build-demo.sh
```

See [Docs/architecture.md](Docs/architecture.md) for the data flow and module
layout.

## Acknowledgements

- [WhisperCaption](https://github.com/albond/WhisperCaption) by Albond — the
  original MIT-licensed project on which LingoFloat was based.
- [WhisperKit / argmax-oss-swift](https://github.com/argmaxinc/argmax-oss-swift)
  by Argmax — on-device speech recognition and model management.
- [Whisper](https://github.com/openai/whisper) by OpenAI — speech recognition
  models used through WhisperKit.
- [swift-transformers](https://github.com/huggingface/swift-transformers) by
  Hugging Face — model and tokenizer support used through WhisperKit.
- Apple Core Audio Process Taps, Translation, SwiftUI, AppKit, and
  ScreenCaptureKit.

Additional resolved Swift package dependencies and their exact versions are
listed in
[Package.resolved](LingoFloat/LingoFloat.xcodeproj/project.xcworkspace/xcshareddata/swiftpm/Package.resolved).

## Privacy

With WhisperKit selected, speech recognition and translation run on the Mac.
Audio is sent to a remote service only when the user explicitly selects the
optional Deepgram or ElevenLabs backend.

## License

LingoFloat is available under the [MIT License](LICENSE). Upstream copyright
notices are retained.
