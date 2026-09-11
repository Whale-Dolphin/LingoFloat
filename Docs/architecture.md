# LingoFloat 第一版架构

## 产品边界

第一版只服务“在 Mac 上看外语视频”的核心路径：系统音频输入、本地 ASR、
中文翻译和全屏悬浮字幕。麦克风、云端 ASR、截图和历史记录仍由上游代码保留，
但不是当前产品主线。

## 数据流

```text
Core Audio Process Tap
  → AudioConverter（16 kHz / mono / Float32）
  → CaptionStream（有界实时协调）
  → TranscriptionEngine
      ├─ WhisperEngine（本地）
      ├─ DeepgramEngine（可选云端）
      └─ ElevenLabsEngine（可选云端）
  → BubbleSplitter（partial/final 与切句）
  → CaptionTranslator（Apple Translation）
  → Caption
      ├─ ContentView（主窗口）
      └─ CCHUDController + CCHUDView（悬浮字幕）
```

首次点击 Start 时，`WhisperModelInstaller` 使用 WhisperKit 官方下载 API 把所选
模型写入 Application Support，并把通过完整性检查的模型目录交给
`CaptionStream`。生产界面没有写死字幕入口；可用性只以真实音频链路为准。

## 模块职责

| 目录 | 职责 | 不负责 |
|---|---|---|
| `Capture/` | 设备选择、系统音频 tap、PCM 转换 | 文本识别、字幕 UI |
| `LiveCaption/` | 模型安装、引擎协议、识别、切句、翻译和 caption 状态 | 窗口位置 |
| `Window/` | 全屏浮层、位置、透明度、跨 Space 行为 | ASR 调度 |
| `Settings/` | 本地偏好、模型选择和语言选择 | 模型文件传输 |
| `History/` | 文本和截图会话持久化 | 原始音频保存 |

## 核心契约

- 捕获层向引擎提供 `16 kHz mono Float32` 样本。
- `TranscriptionEngine` 通过同一 `Caption.id` 更新 partial，final 后不再修改。
- 翻译结果必须同时匹配 caption ID 和发起请求时的源文本文本；过期结果丢弃。
- UI 只读 `CaptionStream.captions`，不直接调用捕获或模型实现。
- 模型目录必须通过必要 Core ML 组件和非空权重检查后才能进入加载阶段。

## 下一轮结构演进

当前先沿用上游结构以保持可编译。稳定前缀算法落地时，再把
`CaptionStream` 中的流式策略拆到具名的 `StablePrefixCommitter.swift`；只有
真实出现第二种本地翻译实现后，才抽取独立 `TranslationEngine` 协议，避免
在 MVP 阶段预先制造空抽象。

## 仓库结构审计

发布前审计显示，目录已经按业务职责分域，不需要为了形式继续增加层级：

| 对象 | 审计证据 | 结论 |
|---|---|---|
| `ContentView.swift` | 原约 1,226 行，其中旧界面组件均为文件私有且无外部引用 | 收缩为 `CinemaDashboard` 的薄入口，删除不可达旧 UI |
| `CaptionStream.swift` | 约 953 行，集中管理捕获、ASR、切句、会话和泵生命周期 | 暂不拆；等稳定前缀策略成为独立变化点后再抽取 |
| `SettingsStore.swift` | 约 801 行，集中定义持久化偏好及其约束 | 暂不拆；保持单一持久化入口 |
| `CinemaDashboard.swift` | 约 725 行，主窗口及其私有展示组件 | 保持同文件，避免发布前进行纯搬家式重构 |

命名继续采用具体职责名，例如 `BubbleSplitter.swift`、`CaptionTranslator.swift`
和 `WhisperModelInstaller.swift`；不新增 `Utils.swift`、`Helpers.swift` 等无边界
容器。构建物进入 `.build/` 或 `build/`，本地签名配置只放在被忽略的
`LingoFloat/Local.xcconfig`。

| 阶段 | 内容 | 依赖 | 风险 |
|---|---|---|---|
| 已完成 | 正式迁移 `WhisperCaption/` → `LingoFloat/`，清除不可达旧 UI | 完整测试与 Release 构建 | 低 |
| 后续 | 从 `CaptionStream` 抽取稳定前缀提交策略 | 算法和契约先稳定 | 中 |
| 按需 | 新增第二个本地翻译实现后再定义 `TranslationEngine` | 出现真实复用需求 | 中 |
