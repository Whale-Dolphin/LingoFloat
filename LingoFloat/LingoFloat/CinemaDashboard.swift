import AppKit
import SwiftUI
import Translation

/// Compact controller for the watch-a-video workflow. It keeps operational
/// state visible and gives the transcript visual priority instead of presenting
/// captions as a two-sided chat conversation.
struct CinemaDashboard: View {
    @Environment(CaptionStream.self) private var stream
    @Environment(SettingsStore.self) private var settings
    @Environment(ChatHistoryStore.self) private var history
    @Environment(\.captionTranslator) private var translator

    private var orderedCaptions: [Caption] {
        stream.captions.sorted { $0.startedAt < $1.startedAt }
    }

    var body: some View {
        VStack(spacing: 0) {
            CinemaToolbar(stream: stream, history: history)
            if let translator, let issue = translator.translationIssue {
                HStack {
                    Label(issue, systemImage: "exclamationmark.bubble")
                    Spacer()
                    Button("Retry translation") { translator.retryTranslations() }
                        .accessibilityIdentifier("retry-translation-button")
                }
                .font(.caption)
                .foregroundStyle(.orange)
                .padding(.horizontal, 16)
                .padding(.bottom, 8)
                .accessibilityIdentifier("translation-issue")
            }
            Divider().opacity(0.45)
            CaptionWorkspace(stream: stream, captions: orderedCaptions)
            Divider().opacity(0.45)
            CinemaControlStrip(stream: stream, settings: settings)
        }
        .background(Color(nsColor: .windowBackgroundColor))
    }
}

// MARK: - Toolbar

private struct CinemaToolbar: View {
    @Bindable var stream: CaptionStream
    let history: ChatHistoryStore

    @Environment(SettingsStore.self) private var settings
    @Environment(\.openSettings) private var openSettings

    var body: some View {
        HStack(spacing: 12) {
            Image(nsImage: NSApplication.shared.applicationIconImage)
                .resizable()
                .scaledToFit()
                .frame(width: 26, height: 26)

            VStack(alignment: .leading, spacing: 1) {
                Text("Live Captions")
                    .font(.system(size: 15, weight: .semibold))
                CinemaStatusLabel(state: stream.state, elapsed: stream.elapsedSeconds)
            }

            Spacer(minLength: 8)

            LanguageRoute(stream: stream, settings: settings)

            Button {
                stream.clearContext()
            } label: {
                Label("Clear", systemImage: "xmark.circle")
            }
            .buttonStyle(.borderless)
            .font(.caption.weight(.medium))
            .help("Save this transcript to History and start with an empty display")
            .accessibilityIdentifier("clear-context-button")
            .disabled(stream.captions.isEmpty)

            SessionMenu(stream: stream, history: history)

            Button {
                openSettings()
            } label: {
                Image(systemName: "gearshape")
            }
            .buttonStyle(.borderless)
            .font(.system(size: 14, weight: .medium))
            .help("Settings")

            StartStopButton(stream: stream)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 11)
        .background(.bar)
    }
}

private struct CinemaStatusLabel: View {
    let state: CaptionStream.State
    let elapsed: TimeInterval

    var body: some View {
        HStack(spacing: 5) {
            Circle()
                .fill(color)
                .frame(width: 6, height: 6)
            Text(label)
                .lineLimit(1)
            if state.isRunning {
                Text(Self.elapsedFormatter.string(from: elapsed) ?? "00:00")
                    .monospacedDigit()
                    .contentTransition(.numericText())
            }
        }
        .font(.caption)
        .foregroundStyle(.secondary)
        .accessibilityIdentifier("caption-status")
    }

    private var label: String {
        switch state {
        case .idle: return "Ready"
        case .checkingPermissions: return "Requesting audio access"
        case .loadingModel: return "Preparing model"
        case .starting: return "Starting"
        case .running: return "Listening"
        case .stopping: return "Stopping"
        case .error: return "Needs attention"
        }
    }

    private var color: Color {
        switch state {
        case .idle: return .secondary
        case .checkingPermissions, .loadingModel, .starting, .stopping: return .orange
        case .running: return .red
        case .error: return .orange
        }
    }

    private static let elapsedFormatter: DateComponentsFormatter = {
        let formatter = DateComponentsFormatter()
        formatter.allowedUnits = [.minute, .second]
        formatter.zeroFormattingBehavior = [.pad]
        return formatter
    }()
}

private struct LanguageRoute: View {
    let stream: CaptionStream
    let settings: SettingsStore
    @State private var supportedTargets: [Language] = [.en, .zh, .ja]

    private var source: Language? {
        let selected = stream.languages.selectedLanguages
        return selected.count == 1 ? selected.first : nil
    }

    var body: some View {
        HStack(spacing: 6) {
            Menu {
                Button {
                    stream.languages.selectedLanguages = []
                    settings.translationEnabled = true
                } label: {
                    if source == nil {
                        Label("Auto detect", systemImage: "checkmark")
                    } else {
                        Text("Auto detect")
                    }
                }

                Divider()

                ForEach(Language.allCases.sorted(by: { $0.displayName < $1.displayName })) { language in
                    Button {
                        stream.languages.selectedLanguages = [language]
                        settings.translationEnabled = true
                    } label: {
                        if language == source {
                            Label(language.displayName, systemImage: "checkmark")
                        } else {
                            Text(language.displayName)
                        }
                    }
                    .disabled(language == settings.translationTargetLanguage)
                }
            } label: {
                routeLabel(title: "From", value: source?.displayName ?? "Auto")
            }
            .menuStyle(.borderlessButton)
            .accessibilityIdentifier("source-language-picker")

            Image(systemName: "arrow.right")
                .font(.caption2.weight(.semibold))
                .foregroundStyle(.tertiary)

            Menu {
                Button {
                    settings.translationEnabled = false
                } label: {
                    if !settings.translationEnabled {
                        Label("No translation", systemImage: "checkmark")
                    } else {
                        Text("No translation")
                    }
                }

                Divider()

                ForEach(supportedTargets) { language in
                    Button {
                        settings.translationTargetLanguage = language
                        settings.translationEnabled = true
                    } label: {
                        if settings.translationEnabled,
                           language == settings.translationTargetLanguage {
                            Label(language.displayName, systemImage: "checkmark")
                        } else {
                            Text(language.displayName)
                        }
                    }
                    .disabled(language == source)
                }
            } label: {
                if settings.translationEnabled {
                    routeLabel(title: "To", value: settings.translationTargetLanguage.displayName)
                } else {
                    HStack(spacing: 4) {
                        Text("No translation")
                        Image(systemName: "chevron.down")
                            .font(.system(size: 8, weight: .semibold))
                    }
                }
            }
            .menuStyle(.borderlessButton)
            .accessibilityIdentifier("target-language-picker")
        }
        .font(.caption.weight(.medium))
        .foregroundStyle(.secondary)
        .lineLimit(1)
        .help("Choose the spoken language and the translation language")
        .task { await loadSupportedTargets() }
    }

    private func routeLabel(title: String, value: String) -> some View {
        HStack(spacing: 4) {
            Text("\(title): \(value)")
            Image(systemName: "chevron.down")
                .font(.system(size: 8, weight: .semibold))
        }
    }

    private func loadSupportedTargets() async {
        let locales = await CaptionTranslator.languageAvailability().supportedLanguages
        let codes = Set(locales.compactMap { $0.languageCode?.identifier })
        let available = Language.allCases
            .filter { codes.contains($0.bcp47) }
            .sorted { $0.displayName < $1.displayName }
        if !available.isEmpty {
            supportedTargets = available
        }
    }
}

private struct SessionMenu: View {
    @Bindable var stream: CaptionStream
    let history: ChatHistoryStore

    var body: some View {
        Menu {
            Button {
                stream.newSession()
            } label: {
                Label("New transcript", systemImage: "square.and.pencil")
            }
            .disabled(stream.state.isBusy)

            if !history.index.isEmpty {
                Divider()
                Section("Recent transcripts") {
                    ForEach(history.index.prefix(12)) { metadata in
                        Button {
                            stream.activate(sessionID: metadata.id)
                        } label: {
                            if metadata.id == stream.activeSession.id {
                                Label(metadata.displayName, systemImage: "checkmark")
                            } else {
                                Text(metadata.displayName)
                            }
                        }
                        .disabled(stream.state.isBusy && metadata.id != stream.activeSession.id)
                    }
                }
            }
        } label: {
            Image(systemName: "clock.arrow.circlepath")
        }
        .menuStyle(.borderlessButton)
        .menuIndicator(.hidden)
        .font(.system(size: 14, weight: .medium))
        .help("Transcript history")
    }
}

private struct StartStopButton: View {
    @Bindable var stream: CaptionStream

    var body: some View {
        Button {
            Task { await stream.toggle() }
        } label: {
            Label(label, systemImage: symbol)
                .font(.callout.weight(.semibold))
        }
        .buttonStyle(.borderedProminent)
        .controlSize(.regular)
        .tint(stream.state.isRunning ? .red : .accentColor)
        .disabled(stream.state.isBusy)
        .keyboardShortcut(.return, modifiers: [])
        .accessibilityIdentifier("start-stop-button")
    }

    private var label: String {
        switch stream.state {
        case .running: return "Stop"
        case .error: return "Retry"
        case .checkingPermissions, .loadingModel, .starting, .stopping: return "Working"
        case .idle: return "Start"
        }
    }

    private var symbol: String {
        switch stream.state {
        case .running: return "stop.fill"
        case .error: return "arrow.clockwise"
        default: return "play.fill"
        }
    }
}

// MARK: - Caption workspace

private struct CaptionWorkspace: View {
    let stream: CaptionStream
    let captions: [Caption]

    var body: some View {
        Group {
            switch stream.state {
            case .loadingModel(let progress, let message):
                ModelProgressState(progress: progress, message: message)
            case .error(let message):
                InlineErrorState(message: message, retry: {
                    stream.dismissError()
                    Task { await stream.start() }
                })
            default:
                if captions.isEmpty {
                    ReadyState(isRunning: stream.state.isRunning)
                } else {
                    FocusedTranscript(captions: captions)
                }
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Color(nsColor: .textBackgroundColor).opacity(0.22))
    }
}

private struct ReadyState: View {
    let isRunning: Bool

    var body: some View {
        VStack(spacing: 10) {
            Image(systemName: isRunning ? "waveform" : "captions.bubble")
                .font(.system(size: 28, weight: .regular))
                .foregroundStyle(isRunning ? Color.accentColor : Color.secondary)
                .symbolEffect(.variableColor.iterative, options: .repeating, isActive: isRunning)

            Text(isRunning ? "Listening to system audio" : "Ready for live captions")
                .font(.system(size: 19, weight: .semibold))

            Text(isRunning
                ? "Play a video or other audio on this Mac. Speech will appear here."
                : "Press Start, then play your video. The first start may prepare the local model.")
                .font(.callout)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .frame(maxWidth: 430)
        }
        .padding(28)
    }
}

private struct ModelProgressState: View {
    let progress: Double
    let message: String

    var body: some View {
        VStack(spacing: 12) {
            Text("Preparing on-device captions")
                .font(.system(size: 19, weight: .semibold))
            Text(message)
                .font(.callout)
                .foregroundStyle(.secondary)
            ProgressView(value: max(0, min(progress, 1)))
                .progressViewStyle(.linear)
                .frame(maxWidth: 320)
            Text("The model stays on this Mac after the first download.")
                .font(.caption)
                .foregroundStyle(.tertiary)
        }
        .padding(28)
    }
}

private struct InlineErrorState: View {
    let message: String
    let retry: () -> Void

    @Environment(\.openSettings) private var openSettings

    var body: some View {
        VStack(spacing: 12) {
            Image(systemName: "exclamationmark.circle")
                .font(.system(size: 25, weight: .medium))
                .foregroundStyle(.orange)
            Text("Captions could not start")
                .font(.system(size: 18, weight: .semibold))
            ScrollView {
                Text(message)
                    .font(.callout)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
                    .textSelection(.enabled)
            }
            .frame(maxWidth: 470, maxHeight: 84)
            HStack {
                Button("Settings") { openSettings() }
                    .buttonStyle(.bordered)
                Button("Retry", action: retry)
                    .buttonStyle(.borderedProminent)
            }
        }
        .padding(24)
    }
}

private struct FocusedTranscript: View {
    let captions: [Caption]
    @Environment(SettingsStore.self) private var settings

    var body: some View {
        ScrollViewReader { proxy in
            ScrollView {
                LazyVStack(alignment: .leading, spacing: 0) {
                    ForEach(Array(captions.enumerated()), id: \.element.id) { index, caption in
                        CinemaCaptionLine(
                            caption: caption,
                            isCurrent: index == captions.count - 1
                        )
                        .id(caption.id)

                        if index < captions.count - 1 {
                            Divider()
                                .padding(.leading, 42)
                                .opacity(0.32)
                        }
                    }
                }
                .padding(.horizontal, 18)
                .padding(.vertical, 12)
            }
            .onAppear { scrollToLatest(proxy) }
            .onChange(of: captions.last?.updatedAt) { _, _ in scrollToLatest(proxy) }
            .onChange(of: captions.count) { _, _ in scrollToLatest(proxy) }
        }
    }

    private func scrollToLatest(_ proxy: ScrollViewProxy) {
        guard settings.autoScrollMainHUD, let latest = captions.last else { return }
        proxy.scrollTo(latest.id, anchor: .bottom)
    }
}

private struct CinemaCaptionLine: View {
    let caption: Caption
    let isCurrent: Bool

    private var translation: String? {
        guard let value = caption.translation?.trimmingCharacters(in: .whitespacesAndNewlines),
              !value.isEmpty else { return nil }
        return value
    }

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            Image(systemName: caption.source == .system ? "speaker.wave.2" : "mic")
                .font(.system(size: 12, weight: .medium))
                .foregroundStyle(isCurrent ? Color.accentColor : Color.secondary)
                .frame(width: 22, height: 22)

            VStack(alignment: .leading, spacing: isCurrent ? 7 : 4) {
                HStack(spacing: 6) {
                    Text(caption.source == .system ? "SYSTEM AUDIO" : "MICROPHONE")
                    if let language = caption.language {
                        Text("· \(language.badge)")
                    }
                    if !caption.isFinal {
                        Text("· LISTENING")
                    }
                }
                .font(.system(size: 9, weight: .semibold))
                .tracking(0.8)
                .foregroundStyle(.tertiary)

                if let translation {
                    Text(translation)
                        .font(.system(size: isCurrent ? 24 : 16, weight: isCurrent ? .semibold : .medium))
                        .foregroundStyle(isCurrent ? .primary : .secondary)
                        .textSelection(.enabled)

                    Text(caption.text)
                        .font(.system(size: isCurrent ? 14 : 12))
                        .foregroundStyle(.secondary)
                        .textSelection(.enabled)
                } else {
                    Text(caption.text)
                        .font(.system(size: isCurrent ? 22 : 15, weight: isCurrent ? .medium : .regular))
                        .foregroundStyle(isCurrent ? .primary : .secondary)
                        .textSelection(.enabled)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .padding(.vertical, isCurrent ? 15 : 11)
        .padding(.horizontal, isCurrent ? 12 : 0)
        .background {
            if isCurrent {
                RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .fill(Color.primary.opacity(0.045))
            }
        }
        .animation(.easeOut(duration: 0.18), value: isCurrent)
    }
}

// MARK: - Control strip

private struct CinemaControlStrip: View {
    let stream: CaptionStream
    let settings: SettingsStore

    var body: some View {
        HStack(spacing: 16) {
            SystemAudioControl(stream: stream)
            ModelReadout(settings: settings)

            Spacer(minLength: 6)

            Button {
                IntentActions.shared.toggleCCHUD?()
            } label: {
                Label(
                    settings.ccHUDVisible ? "Hide Overlay" : "Show Overlay",
                    systemImage: settings.ccHUDVisible ? "captions.bubble.fill" : "captions.bubble"
                )
            }
            .buttonStyle(.bordered)
            .controlSize(.regular)
            .help("Toggle the always-on-top movie subtitle strip")
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 10)
        .background(.bar)
    }
}

private struct SystemAudioControl: View {
    let stream: CaptionStream
    @State private var devices: [AudioDevice] = []

    private var selectedDeviceName: String {
        guard let uid = stream.routing.preferredOutputUID,
              let device = devices.first(where: { $0.uid == uid }) else {
            return "System Audio"
        }
        return device.name
    }

    var body: some View {
        HStack(spacing: 9) {
            Menu {
                Button {
                    stream.routing.preferredOutputUID = nil
                } label: {
                    if stream.routing.preferredOutputUID == nil {
                        Label("System default", systemImage: "checkmark")
                    } else {
                        Text("System default")
                    }
                }

                if !devices.isEmpty {
                    Divider()
                    ForEach(devices) { device in
                        Button {
                            stream.routing.preferredOutputUID = device.uid
                        } label: {
                            if stream.routing.preferredOutputUID == device.uid {
                                Label(device.name, systemImage: "checkmark")
                            } else {
                                Text(device.name)
                            }
                        }
                    }
                }
            } label: {
                HStack(spacing: 5) {
                    Image(systemName: "speaker.wave.2.fill")
                    Text(selectedDeviceName)
                        .lineLimit(1)
                    Image(systemName: "chevron.down")
                        .font(.caption2.weight(.semibold))
                }
                .font(.caption.weight(.medium))
            }
            .menuStyle(.borderlessButton)
            .menuIndicator(.hidden)
            .frame(maxWidth: 150)

            AudioLevelBars(level: stream.systemLevel)
        }
        .onAppear { devices = AudioDevices.devices(for: .output) }
    }
}

private struct AudioLevelBars: View {
    let level: Float

    private var fraction: Double {
        min(max(Double(level) * 4, 0), 1).squareRoot()
    }

    var body: some View {
        HStack(alignment: .center, spacing: 2) {
            ForEach(0..<5, id: \.self) { index in
                Capsule(style: .continuous)
                    .fill(fraction > Double(index) / 5 ? Color.accentColor : Color.secondary.opacity(0.18))
                    .frame(width: 3, height: CGFloat(5 + index * 2))
            }
        }
        .frame(width: 24, height: 15)
        .animation(.linear(duration: 0.08), value: fraction)
        .accessibilityLabel("System audio level")
    }
}

private struct ModelReadout: View {
    let settings: SettingsStore
    @State private var diskSize: String?

    var body: some View {
        HStack(spacing: 6) {
            Image(systemName: settings.transcriptionEngine == .whisper ? "cpu" : "cloud")
                .foregroundStyle(.secondary)
            Text(label)
                .lineLimit(1)
        }
        .font(.caption)
        .foregroundStyle(.secondary)
        .task(id: modelPath) {
            diskSize = await resolvedDiskSize()
        }
        .help(modelHelp)
    }

    private var modelPath: String? {
        settings.whisperModelFolderPath
    }

    private var isInstalled: Bool {
        guard settings.transcriptionEngine == .whisper,
              let folder = settings.whisperModelFolderURL else { return false }
        return WhisperModelInstaller.folderMatches(folder, model: settings.whisperModel)
            && WhisperModelInstaller.isCompleteModelFolder(folder)
    }

    private var label: String {
        switch settings.transcriptionEngine {
        case .whisper:
            let name = settings.whisperModel == .small ? "Whisper Small" : "Whisper Medium"
            if isInstalled {
                return [name, diskSize, "Installed"].compactMap { $0 }.joined(separator: " · ")
            }
            return "\(name) · Downloads on Start"
        case .deepgram:
            return "Deepgram Nova-3 · Cloud"
        case .elevenlabs:
            return "ElevenLabs Scribe v2 · Cloud"
        }
    }

    private var modelHelp: String {
        if let path = settings.whisperModelFolderPath, isInstalled {
            return "Local model: \(path)"
        }
        return "The selected local model downloads automatically when you press Start"
    }

    private func resolvedDiskSize() async -> String? {
        guard isInstalled, let folder = settings.whisperModelFolderURL else { return nil }
        return await Task.detached(priority: .utility) {
            Self.formattedDiskSize(at: folder)
        }.value
    }

    private nonisolated static func formattedDiskSize(at folder: URL) -> String? {
        guard let enumerator = FileManager.default.enumerator(
            at: folder,
            includingPropertiesForKeys: [.isRegularFileKey, .fileSizeKey],
            options: [.skipsHiddenFiles]
        ) else { return nil }

        var total: Int64 = 0
        for case let file as URL in enumerator {
            guard let values = try? file.resourceValues(forKeys: [.isRegularFileKey, .fileSizeKey]),
                  values.isRegularFile == true else { continue }
            total += Int64(values.fileSize ?? 0)
        }

        let formatter = ByteCountFormatter()
        formatter.countStyle = .file
        formatter.allowedUnits = [.useMB, .useGB]
        return formatter.string(fromByteCount: total)
    }
}
