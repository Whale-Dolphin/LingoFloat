import SwiftUI

/// Engine selector (Whisper / Deepgram / ElevenLabs), per-engine
/// configuration, language pool driven by the active engine's
/// `supportedLanguages`, and an inline warning when the user's selection
/// has languages the engine can't honour cleanly.
struct SpeechRecognitionSection: View {

    @Environment(SettingsStore.self) private var store
    @Environment(CaptionStream.self) private var stream
    private let descriptor = SettingsCategoryID.speech.descriptor

    var body: some View {
        @Bindable var store = store

        SectionShell(descriptor: descriptor) {

            SettingsCard(
                title: "Engine",
                footer: "WhisperKit runs on-device (free, private). Deepgram Nova-3 streams to the cloud (<300 ms latency, multilingual). ElevenLabs Scribe v2 Realtime — 150 ms latency, 90+ languages. Changes apply on next Start."
            ) {
                HStack {
                    SettingsRowLabel(
                        title: "Speech-to-text engine",
                        subtitle: engineSubtitle
                    )
                    Spacer()
                    Picker("", selection: $store.transcriptionEngine) {
                        ForEach(TranscriptionEngineKind.allCases) { e in
                            Text(e.displayName).tag(e)
                        }
                    }
                    .labelsHidden()
                    .pickerStyle(.menu)
                    .fixedSize()
                }
            }

            if store.transcriptionEngine == .whisper {
                WhisperCard()
            }

            if store.transcriptionEngine == .elevenlabs {
                APIKeyCard(
                    title: "ElevenLabs",
                    placeholder: "xi-…",
                    footer: "Stored in your login keychain. Used as `xi-api-key` to mint single-use tokens for the Scribe v2 Realtime WebSocket. Get one at elevenlabs.io → API Keys.",
                    keyBinding: $store.elevenLabsAPIKey,
                    missingMessage: "ElevenLabs key not set — engine won't start."
                )
            }

            if store.transcriptionEngine == .deepgram {
                APIKeyCard(
                    title: "Deepgram",
                    placeholder: "dg-…",
                    footer: "Stored in your login keychain. Used as the WebSocket subprotocol header against `wss://api.deepgram.com/v1/listen`. Get one at console.deepgram.com → API Keys.",
                    keyBinding: $store.deepgramAPIKey,
                    missingMessage: "Deepgram key not set — engine won't start."
                )
            }

            LanguageCard(stream: stream, engine: store.transcriptionEngine)

            VocabularyHintCard()
        }
    }

    private var engineSubtitle: String {
        switch store.transcriptionEngine {
        case .whisper:    return "Local model — no network, no cost."
        case .deepgram:   return "Cloud streaming — requires an API key."
        case .elevenlabs: return "Cloud streaming — requires an API key."
        }
    }
}

// MARK: - Whisper card

private struct WhisperCard: View {

    @Environment(SettingsStore.self) private var store

    var body: some View {
        @Bindable var store = store

        SettingsCard(
            title: "WhisperKit",
            footer: "The selected model and tokenizer download automatically on the first Start, then stay on this Mac for offline use."
        ) {
            VStack(spacing: 0) {
                HStack {
                    SettingsRowLabel(
                        title: "Model variant",
                        subtitle: "`medium` is markedly more accurate on technical terms with a non-native accent; on Apple Silicon (M2 Pro+) it runs in real time. Changes apply on next Start."
                    )
                    Spacer()
                    Picker("", selection: $store.whisperModel) {
                        ForEach(WhisperModel.allCases) { m in
                            Text("\(m.displayName) — \(m.displaySize)").tag(m)
                        }
                    }
                    .labelsHidden()
                    .pickerStyle(.menu)
                    .fixedSize()
                }

                SettingsRowDivider()

                HStack {
                    SettingsRowLabel(
                        title: "Local model",
                        subtitle: "Stored in LingoFloat's Application Support folder; no command-line setup required."
                    )
                    Spacer()
                    Label(modelStatus, systemImage: modelStatusSymbol)
                        .font(.callout.weight(.medium))
                        .foregroundStyle(isSelectedModelInstalled ? .green : .secondary)
                }
            }
        }
    }

    private var isSelectedModelInstalled: Bool {
        guard let folder = store.whisperModelFolderURL else { return false }
        return WhisperModelInstaller.folderMatches(folder, model: store.whisperModel)
            && WhisperModelInstaller.isCompleteModelFolder(folder)
    }

    private var modelStatus: String {
        isSelectedModelInstalled ? "Installed" : "Downloads on Start"
    }

    private var modelStatusSymbol: String {
        isSelectedModelInstalled ? "checkmark.circle.fill" : "arrow.down.circle"
    }
}

// MARK: - Language card

private struct LanguageCard: View {

    let stream: CaptionStream
    let engine: TranscriptionEngineKind

    private var supportedLanguages: [Language] {
        switch engine {
        case .whisper:    return WhisperEngine.supportedLanguages
        case .deepgram:   return DeepgramEngine.supportedLanguages
        case .elevenlabs: return ElevenLabsEngine.supportedLanguages
        }
    }

    /// Languages the user has selected that the active engine can't honour.
    private var unsupported: Set<Language> {
        stream.languages.unsupported(by: supportedLanguages)
    }

    /// Special-case warning text: Deepgram Nova-3 multilingual doesn't
    /// cover Ukrainian — the engine falls back to monolingual `uk` and
    /// drops code-switching across the other languages.
    private var deepgramUkrainianWarning: String? {
        guard engine == .deepgram,
              stream.languages.selectedLanguages.contains(.uk),
              stream.languages.selectedLanguages.count > 1
        else { return nil }
        return "Deepgram Nova-3 multilingual doesn't support Ukrainian. The session will run monolingual `uk` and miss code-switching with the other selected languages."
    }

    var body: some View {
        SettingsCard(
            title: "Languages",
            footer: "Pick one to lock the engine to a single language; pick multiple to enable auto-detect within the set. Empty selection = engine default / auto-detect across everything."
        ) {
            VStack(alignment: .leading, spacing: 12) {
                let columns = [GridItem(.adaptive(minimum: 120), spacing: 8)]
                LazyVGrid(columns: columns, alignment: .leading, spacing: 8) {
                    ForEach(supportedLanguages) { lang in
                        LanguageChip(
                            language: lang,
                            isSelected: stream.languages.selectedLanguages.contains(lang),
                            toggle: {
                                var set = stream.languages.selectedLanguages
                                if set.contains(lang) {
                                    set.remove(lang)
                                } else {
                                    set.insert(lang)
                                }
                                stream.languages.selectedLanguages = set
                            }
                        )
                    }
                }

                if !unsupported.isEmpty {
                    let list = unsupported
                        .map { $0.displayName }
                        .sorted()
                        .joined(separator: ", ")
                    Label(
                        "Selected language(s) not supported by the active engine: \(list).",
                        systemImage: "exclamationmark.triangle.fill"
                    )
                    .font(.caption)
                    .foregroundStyle(.orange)
                }

                if let warning = deepgramUkrainianWarning {
                    Label(warning, systemImage: "info.circle")
                        .font(.caption)
                        .foregroundStyle(.orange)
                }
            }
        }
    }
}

private struct LanguageChip: View {
    let language: Language
    let isSelected: Bool
    let toggle: () -> Void

    var body: some View {
        Button(action: toggle) {
            HStack(spacing: 6) {
                Text(language.badge)
                    .font(.caption.monospaced())
                    .foregroundStyle(.secondary)
                Text(language.displayName)
                    .font(.callout)
                    .lineLimit(1)
                Spacer(minLength: 0)
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 6)
            .background(
                RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .fill(isSelected ? Color.accentColor.opacity(0.18) : Color.primary.opacity(0.05))
            )
            .overlay(
                RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .strokeBorder(isSelected ? Color.accentColor : Color.primary.opacity(0.12), lineWidth: isSelected ? 1.5 : 0.5)
            )
        }
        .buttonStyle(.plain)
    }
}

// MARK: - Vocabulary hint card

private struct VocabularyHintCard: View {

    @Environment(SettingsStore.self) private var store

    var body: some View {
        @Bindable var store = store
        SettingsCard(
            title: "Vocabulary hint",
            footer: "Comma-separated jargon, names, or acronyms primed into the active engine. WhisperKit uses it as `promptTokens`; Deepgram as `keyterm` (cap 100); ElevenLabs as `keyterms` (cap 50 entries × 20 chars). Helps recognition of domain terms under non-native pronunciation."
        ) {
            VStack(alignment: .leading, spacing: 8) {
                TextEditor(text: $store.whisperVocabularyHint)
                    .font(.system(.caption, design: .monospaced))
                    .frame(minHeight: 90, maxHeight: 150)
                    .scrollContentBackground(.hidden)
                    .padding(8)
                    .background(
                        RoundedRectangle(cornerRadius: 8, style: .continuous)
                            .fill(Color.primary.opacity(0.04))
                    )
                    .overlay(
                        RoundedRectangle(cornerRadius: 8, style: .continuous)
                            .strokeBorder(Color.primary.opacity(0.08), lineWidth: 0.5)
                    )
            }
        }
    }
}

// MARK: - Recommended models sheet

private struct RecommendedModelsSheet: View {
    @Binding var isPresented: Bool

    private static let browseURL = URL(string: "https://huggingface.co/models?library=whisperkit")!

    /// Three `hf download` commands that were run locally against the
    /// current `argmaxinc/whisperkit-coreml` (CoreML `.mlmodelc` releases)
    /// and `openai/whisper-small` tokenizer with `huggingface_hub 0.36`.
    /// Each command was confirmed to land the listed file count at the
    /// destination shown. Only the verified set is included — pre-install
    /// instructions, legacy CLI fall-backs, and "swap" hints were dropped.
    private static let setupInstructions: String = """
    Requires the Hugging Face `hf` CLI. Model files arrive as compiled
    CoreML (`.mlmodelc`); no extra build step.

    Small model — 19 files, ~500 MB:
       hf download argmaxinc/whisperkit-coreml \\
         --include "openai_whisper-small/*" \\
         --local-dir ~/Documents/WhisperKit
       # Lands at: ~/Documents/WhisperKit/openai_whisper-small/

    Medium model — 20 files, ~1.4 GB:
       hf download argmaxinc/whisperkit-coreml \\
         --include "openai_whisper-medium/*" \\
         --local-dir ~/Documents/WhisperKit
       # Lands at: ~/Documents/WhisperKit/openai_whisper-medium/

    Tokenizer — 12 files, ~4 MB. The --exclude trims the upstream PyTorch /
    TF / Flax / safetensors weights (~3 GB) that WhisperKit doesn't use:
       hf download openai/whisper-small \\
         --exclude "model.safetensors" "pytorch_model.bin" \\
                   "tf_model.h5" "flax_model.msgpack" \\
         --local-dir ~/Documents/WhisperKit/tokenizers/whisper-small

    In LingoFloat → Settings → Speech Recognition:
       Model folder     → ~/Documents/WhisperKit/openai_whisper-small
                          (or ~/Documents/WhisperKit/openai_whisper-medium)
       Tokenizer folder → ~/Documents/WhisperKit/tokenizers/whisper-small
    """

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack {
                Text("Recommended models")
                    .font(.title3.weight(.semibold))
                Spacer()
                Button("Done") { isPresented = false }
                    .keyboardShortcut(.defaultAction)
            }

            ScrollView {
                VStack(alignment: .leading, spacing: 16) {

                    // 1. Setup instructions (copy-paste block).
                    Text(Self.setupInstructions)
                        .font(.system(.caption, design: .monospaced))
                        .textSelection(.enabled)
                        .frame(maxWidth: .infinity, alignment: .leading)

                    Divider()

                    // 2. Browse other models — direct link to the Hugging Face
                    // filter for any model converted to the WhisperKit format.
                    VStack(alignment: .leading, spacing: 6) {
                        Label("Browse other compatible models", systemImage: "magnifyingglass")
                            .font(.callout.weight(.semibold))
                        Link(
                            "huggingface.co/models?library=whisperkit",
                            destination: Self.browseURL
                        )
                        .font(.system(.callout, design: .monospaced))
                        Text("Hugging Face's filter for every model published in the WhisperKit format. Pick one, download its folder, and point the Model folder picker at it. The tokenizer requirement is the same as the small/medium examples above.")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .fixedSize(horizontal: false, vertical: true)
                    }

                    Divider()

                    // 3. Performance note — match user expectations to hardware.
                    VStack(alignment: .leading, spacing: 6) {
                        Label("Model size vs performance", systemImage: "speedometer")
                            .font(.callout.weight(.semibold))
                        Text("`small` (~500 MB) runs at roughly real time on Apple-silicon Macs and is the safe default. Larger models — `medium` (~1.5 GB), `large-v3` (~3 GB) — produce more accurate transcripts, especially with proper nouns and technical vocabulary, but they cost more CPU and RAM. On older Intel Macs, low-memory configurations, or while other heavy apps are running, larger models may fall behind real-time speech — symptoms are growing latency, duplicated phrases, or Whisper looping on filler words. Start with `small`, only step up if your machine has the headroom.")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }
            }
            .frame(minHeight: 380)
        }
        .padding(20)
        .frame(width: 600, height: 560)
    }
}

// MARK: - API key card

struct APIKeyCard: View {

    let title: String
    let placeholder: String
    let footer: String
    @Binding var keyBinding: String
    let missingMessage: String

    var body: some View {
        SettingsCard(title: title, footer: footer) {
            VStack(spacing: 0) {
                HStack {
                    SettingsRowLabel(title: "API key", subtitle: nil)
                    Spacer()
                    SecureField(placeholder, text: $keyBinding)
                        .textFieldStyle(.roundedBorder)
                        .frame(minWidth: 280, maxWidth: 320)
                }

                SettingsRowDivider()

                if keyBinding.isEmpty {
                    Label(missingMessage, systemImage: "exclamationmark.triangle.fill")
                        .font(.caption)
                        .foregroundStyle(.orange)
                } else {
                    Label("Key saved to Keychain.", systemImage: "checkmark.seal.fill")
                        .font(.caption)
                        .foregroundStyle(.green)
                }
            }
        }
    }
}
