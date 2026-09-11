# LingoFloat 测试计划

## 阶段矩阵

| 阶段 | 契约 | fixture | 断言 | 命令 | 频率 | 状态 |
|---|---|---|---|---|---|---|
| 模型安装 | 下载目录只在三个必要 Core ML 组件完整时可用 | 临时模型目录 | 缺组件拒绝、完整目录接受、variant 匹配 | `./scripts/test.sh` | 每次修改 | 已实现并通过 |
| 切句 | 引擎 partial/final 映射为不重不漏的 bubble | 固定 Caption 流 | ID 稳定、边界和剩余文本正确 | `./scripts/test.sh` | 每次修改 | 已实现并通过 |
| Caption 状态 | 更新、翻译和持久化保持一致 | 临时 history 目录 | 翻译不乱序、会话可重载 | `./scripts/test.sh` | 每次修改 | 已实现并通过 |
| 自动源语言 | 空语言选择持久化为 Auto；ASR 检测结果驱动明确的源→目标翻译会话 | 隔离 UserDefaults、英/日云端响应、Caption fixture | Whisper 不强制语言；Deepgram 使用 `multi`；ElevenLabs 开启检测；只为系统字幕和非目标语建立翻译配置 | `./scripts/test.sh` 中 `LanguageSettingsTests`、云端 Engine tests、`CaptionTranslatorTests` | 每次语言链路修改 | 已实现并通过 |
| 清除上下文 | Clear 保存当前会话后开启空白会话，并重置识别/切句缓冲 | 临时 history + 固定 Caption | 当前字幕立即为空、旧字幕仍可从 History 读取、新会话 ID 不同 | `./scripts/test.sh` 中 `CaptionStreamTests` | 每次会话状态修改 | 逻辑回归与安装版主窗口/HUD 交互通过 |
| 系统捕获 | 输出 16 kHz mono Float32 PCM | 本机播放已知日语音频 | 非静音、进入 Listening、ASR 收到日语、停止后释放 | 实机 checklist | 发布前 | 2026-09-11 安装版实机链路通过 |
| 本地 ASR | PCM 产生有序英/日 caption | 代表性短音频 + WhisperKit 模型 | 非空、WER/CER 和延迟达标 | benchmark target | 模型变更 | 建议补充 |
| 预加载接管 | Start 接管仍在加载的 Whisper 引擎后，原预加载任务不得关闭字幕 AsyncStream | 预加载所有权四种状态 + 真实快速启动 | 已接管/仍属于预加载池时不关闭；仅陈旧且未接管时释放；实际字幕进入 UI | `CaptionStreamTests` + 实机快速启动 | 每次引擎生命周期修改 | 已补所有权回归；实机验证见本次发布记录 |
| 快速启动恢复 | 预加载与 Start 同时调用 `prepare()` 时只加载一次；Core Audio 启动异常不能卡死主窗口 | 安装版启动后立即 Start + 先启动后播放的系统音频 | 单次 Whisper ready；`tapautostart=false` 使无声时也立即进入 Listening；主窗口持续响应；10 秒未启动则显示错误并允许重试；正常路径产生原文和译文 | 全量单测 + 安装版日志、UI 与会话产物检查 | 每次模型或音频生命周期修改 | 2026-09-11 安装版实机 E2E 通过：2 条日语均生成中文翻译 |
| 翻译调度 | 不重复提交未变化的 partial；跨语言共用每秒 2 次上限；临时失败退避重试 | 固定 Caption 流、可推进的时钟、可控翻译函数 | 1,000 次轮询只调用一次；取消不拉黑；3 次失败后停自动重试；手动重试恢复；旧结果不污染 Clear 后的会话 | `CaptionTranslatorTests` | 每次翻译修改 | 12 项专项回归通过 |
| Apple 翻译 | stable 源文经真实模型得到对应中文 | 4 条公开创作的日语日常句子、已安装的系统语言模型 | 非空中文、源文更新重新翻译、结果持久化 | 下方 opt-in 命令 | 本机发布前 | macOS 27 / M4 Pro 实测通过；含全套 143 项测试，0 失败 |
| Overlay | 最新两条系统字幕显示在全屏上层 | 测试进程注入 Caption fixture | 原文译文可见、鼠标穿透 | XCUITest + 人工全屏 | 每次 UI 修改 | 建议补充 |
| HUD 窗口 | 鼠标拖拽决定尺寸，字幕不能反向撑大窗口 | 真实 NSPanel / NSHostingView + 原生鼠标事件，注入屏幕鼠标坐标 | 八方向往返和排队事件无累计偏移、64–600pt 限制、长字幕更新不改尺寸、双屏保存不跳位、启动恢复尺寸、四角 alpha 为 0 | `./scripts/test.sh` 中 `CCHUDWindowTests` | 每次 HUD 修改 | 9 项专项回归通过；附原生视图 PNG |
| 总链路 | 系统播放贯穿捕获、ASR、翻译和浮层 | 约 30 秒 Kyoko 日语测试语音，经真实 Start 启动 | 转录和对应中文可见、无翻译失败/限流 | 实机 E2E | 发布前 | 日译中短时 smoke 通过：检查时 5/5 条有译文，原会话 2/2 条恢复；未测量 P50/P95、60 分钟稳定性和识别质量 |

## 端到端边界

真实入口是 `LingoFloat.app` 的 **Start** 按钮；输入是由播放器输出到当前
macOS 音频设备的短视频。关键阶段必须使用真实 Core Audio Process Tap、
真实 WhisperKit 模型和 Apple Translation。最终检查悬浮窗里的原文、译文、
顺序和端到端时间。模型下载和 TCC 权限不能 mock。

每次 PR 的快速 E2E 可以在捕获边界注入 WAV，并允许用确定性翻译 fake；但
不得 mock 重采样、切句、CaptionStream 或最终渲染。产品入口不提供写死字幕；
UI fixture 只用于自动化测试，不替代真实 E2E。

## 翻译故障回归

2026-09-11 的实际故障日志为 `Translation rate limit reached`，系统错误
`TranslationErrorDomain Code=15`。旧调度器对未变化的 partial 重复请求，
10 秒内产生 326 次调用，并把取消/临时错误记录为永久失败。

实际 Apple 模型集成测试要求 macOS 26.4+，并预先在 App 中安装日语和中文；
默认单元测试不下载模型。以下命令开启真实模型测试：

```sh
env DEVELOPER_DIR=/Applications/Xcode-beta.app/Contents/Developer \
  TEST_RUNNER_LINGOFLOAT_REAL_TRANSLATION=1 xcodebuild \
  -project LingoFloat/LingoFloat.xcodeproj -scheme LingoFloat \
  -destination 'platform=macOS,arch=arm64' \
  -clonedSourcePackagesDirPath .build/SourcePackages \
  -derivedDataPath .build/TranslationTests \
  -only-testing:LingoFloatTests/CaptionTranslatorTests \
  CODE_SIGNING_ALLOWED=NO test
```

确定性调度测试仅替换 Apple API 响应，保留真实 CaptionStream、切换会话和
磁盘持久化路径。opt-in 测试进一步接入真实 Apple `lowLatency` 翻译模型；
系统音频捕获到 HUD 的总链路仍需通过真实 App 的 Start 入口验证。

## 第一版发布门槛

- Debug build 和单元测试通过。
- 首次 Start 能下载所选模型，失败可重试；已下载模型可以离线加载。
- 实机系统音频连续运行 60 分钟不停止，耳机切换后可以恢复。
- 原文首次出现 P95 ≤ 2.5 秒，稳定双语字幕 P95 ≤ 4 秒。
- 英语使用 WER、日语使用 CER；结果必须按清晰对白、音乐背景和快速对白
  三个 slice 分开报告。
