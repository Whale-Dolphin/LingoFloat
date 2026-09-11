import Foundation
import OSLog
import Observation
import SwiftUI
import Translation

/// Auto-translates SYSTEM-side captions through Apple's on-device
/// Translation framework when the user has opted in via Settings →
/// Translation (or the top-level "Translation" menu).
///
/// Lives at app scope, alongside `CaptionStream` and `SettingsStore`.
/// The translation engine uses SwiftUI's `.translationTask` for download
/// prompts and compatibility with macOS 15, so
/// `TranslationHostView` mounts one invisible View per source language
/// and hands us the session on each (re)configuration.
///
/// Why one session per source language (not source:nil auto-detect):
///   Passing `source: nil` causes Apple's framework to show a system
///   dialog — "The language could not be automatically detected" — when
///   it's unsure about the input. Using explicit source languages derived
///   from the active language selection avoids the dialog entirely and
///   produces better translations.
///
/// Lifecycle:
///   1. User flips Translation ON in Settings or the menu.
///      → `recomputeConfigurations()` builds one
///        `TranslationSession.Configuration(source: <lang>, target: <target>)`
///        for each source language in the active selection (excluding the
///        target itself, e.g. target→target would be useless).
///      → `TranslationHostView` renders one `TranslationPairView` per
///        entry; each mounts a `.translationTask` and calls our
///        `run(session:source:)` when the session opens.
///   2. `run(session:source:)` loops while not cancelled:
///        - Translates changed text at a bounded rate, newest captions first.
///        - Backs off on temporary failures and recreates the Apple session.
///   3. User changes target language → configurations recompute →
///      SwiftUI cancels old sessions, opens new ones with new target.
///   4. User changes language selection → configurations recompute →
///      sessions for removed source languages close; new ones open.
///   5. User toggles Translation OFF → `configurations` empties →
///      all sessions close; existing translations remain visible.
///
/// Skipped captions (never enqueued):
///   - mic side — translation is a "what the other side just said" feature;
///   - source language equals target — excluded from sessions entirely;
///   - finalized + already translated to current target — idempotent.
///
/// Interim captions are translated only when their source text changes.
/// Requests across all source sessions share a two-per-second ceiling;
/// interim text below four visible characters waits for more speech.
@MainActor
@Observable
final class CaptionTranslator {

    @ObservationIgnored private let log = Log.CaptionTranslator

    @ObservationIgnored private weak var stream: CaptionStream?
    @ObservationIgnored private weak var settings: SettingsStore?

    /// One configuration per source language. The key is the source
    /// language; the value is `Configuration(source: <lang>, target: <target>)`.
    /// Empty means "Translation is off or no sessions needed".
    /// `TranslationHostView` observes this to mount/unmount `.translationTask`
    /// modifiers — one per entry — so each source language gets its own
    /// Apple session with an explicit source locale.
    private(set) var configurations: [Language: TranslationSession.Configuration] = [:]

    /// Caption IDs currently being translated (any session). Shared across
    /// all sessions so two sessions don't translate the same caption race.
    @ObservationIgnored private var inFlight: Set<UUID> = []

    private struct Input: Equatable {
        let text: String
        let source: Language
        let target: Language
    }

    private struct Failure {
        let input: Input
        let isFinal: Bool
        let attempts: Int
        let retryAt: Date
        let unsupported: Bool
    }

    @ObservationIgnored private var succeeded: [UUID: Input] = [:]
    @ObservationIgnored private var failures: [UUID: Failure] = [:]
    @ObservationIgnored private var sourceRetryAt: [Language: Date] = [:]
    @ObservationIgnored private var nextRequestAt = Date.distantPast
    @ObservationIgnored private var generation = 0
    @ObservationIgnored private var activeSessionID: String?
    private(set) var issues: [Language: String] = [:]

    var translationIssue: String? {
        issues.keys.sorted { $0.rawValue < $1.rawValue }.first.flatMap { issues[$0] }
    }

    /// Caption IDs the user explicitly asked to translate from the Main HUD
    /// context menu, keyed by the source language they chose (or the source
    /// detected on the caption itself). Manual requests bypass every auto-
    /// pipeline filter — they always run, even for mic-side captions, even
    /// when auto-translation is OFF, even when the source language isn't in
    /// the user's active language selection. Entries are removed once the
    /// translation lands (or permanently fails).
    @ObservationIgnored private var pendingManual: [UUID: Language] = [:]
    @ObservationIgnored private var configurationTarget: Language?

    init(stream: CaptionStream, settings: SettingsStore) {
        self.stream = stream
        self.settings = settings
        recomputeConfigurations()
        observeSettings()
        observeCaptions()
    }

    // MARK: - Configuration

    /// Rebuilds `configurations` from current settings, selection, and any
    /// pending manual requests. Source languages = (auto pipeline's selection
    /// minus target) ∪ (manual queue's source languages minus target). The
    /// auto half contributes only when `translationEnabled` is on; manual
    /// entries always contribute. Each surviving entry becomes one
    /// `.translationTask` session in `TranslationHostView`.
    ///
    private func recomputeConfigurations() {
        guard let settings, let stream else {
            configurations = [:]
            return
        }

        let target = settings.translationTargetLanguage
        let targetLocale = Locale.Language(identifier: target.bcp47)

        if activeSessionID != stream.activeSession.id {
            activeSessionID = stream.activeSession.id
            resetRequests()
            pendingManual.removeAll()
        }

        var sourceLangs: Set<Language> = []

        if settings.translationEnabled {
            let selected = stream.languages.selectedLanguages
            if selected.isEmpty {
                sourceLangs.formUnion(
                    stream.captions.lazy
                        .filter { $0.source == .system }
                        .compactMap(\.language)
                )
            } else {
                sourceLangs.formUnion(selected)
            }
        }

        // Manual entries always contribute their source language, regardless
        // of auto pipeline state.
        sourceLangs.formUnion(pendingManual.values)
        sourceLangs.remove(target) // target→target is never a session.

        // Caption text changes many times per second. Rebuild the SwiftUI
        // translation tasks only when the actual language-pair set changes.
        if Set(configurations.keys) == sourceLangs,
           configurationTarget == target {
            return
        }

        var newConfigs: [Language: TranslationSession.Configuration] = [:]
        for lang in sourceLangs {
            if configurationTarget == target, let existing = configurations[lang] {
                newConfigs[lang] = existing
            } else {
                var configuration = TranslationSession.Configuration(
                    source: Locale.Language(identifier: lang.bcp47), target: targetLocale
                )
                #if compiler(>=6.3)
                if #available(macOS 26.4, *) { configuration.preferredStrategy = .lowLatency }
                #endif
                newConfigs[lang] = configuration
            }
        }
        configurations = newConfigs
        configurationTarget = target

        let sources = sourceLangs.map(\.rawValue).sorted().joined(separator: "+")
        let manualCount = pendingManual.count
        log.info("translation reconfigured: [\(sources, privacy: .public)] → \(target.rawValue, privacy: .public) (manual=\(manualCount))")
    }

    /// Re-arms after each fire; observes translation settings AND the active
    /// language selection (selection change → different source languages needed).
    private func observeSettings() {
        withObservationTracking { [weak self] in
            guard let self, let settings = self.settings else { return }
            _ = settings.translationEnabled
            _ = settings.translationTargetLanguage
            _ = self.stream?.languages.selectedLanguages
        } onChange: { [weak self] in
            Task { @MainActor [weak self] in
                self?.resetRequests()
                self?.recomputeConfigurations()
                self?.observeSettings()
            }
        }
    }

    /// In Auto mode, ASR output determines which explicit Apple Translation
    /// sessions are needed. Re-arm after every observable caption mutation.
    private func observeCaptions() {
        withObservationTracking { [weak self] in
            _ = self?.stream?.captions
            _ = self?.stream?.activeSession.id
        } onChange: { [weak self] in
            Task { @MainActor [weak self] in
                self?.recomputeConfigurations()
                self?.observeCaptions()
            }
        }
    }

    // MARK: - Manual requests (Main HUD context menu)

    /// Enqueues a one-shot translation for `captionID` using `sourceLanguage`
    /// as the explicit source. Used by the Main HUD right-click "Translate"
    /// action. The request bypasses every auto-pipeline filter: it runs even
    /// for mic-side captions, when Translation is OFF, or when the source
    /// language isn't in the active selection.
    ///
    /// If a session for `sourceLanguage` isn't already mounted, a fresh
    /// configuration is added and `TranslationHostView` will mount the
    /// corresponding `.translationTask`. Re-translating an already-translated
    /// caption is a valid use case (target language changed since the last
    /// translation) — the old text stays visible until the new one lands.
    func requestManualTranslation(captionID: UUID, sourceLanguage: Language) {
        pendingManual[captionID] = sourceLanguage
        failures.removeValue(forKey: captionID)
        sourceRetryAt.removeValue(forKey: sourceLanguage)
        recomputeConfigurations()
        configurations[sourceLanguage]?.invalidate()
    }

    /// Explicit retry also reopens the Apple sessions; a cancelled session
    /// must not be reused indefinitely.
    func retryTranslations() {
        resetRequests()
        for source in sourcesNeedingTranslation {
            configurations[source]?.invalidate()
        }
    }

    private func resetRequests() {
        generation += 1
        succeeded.removeAll()
        failures.removeAll()
        sourceRetryAt.removeAll()
        issues.removeAll()
    }

    // MARK: - Queue

    /// Source languages that currently have an active session, in a stable
    /// order so `ForEach` in the host view doesn't thrash on dict key sets.
    var sourcesNeedingTranslation: [Language] {
        configurations.keys.sorted { $0.rawValue < $1.rawValue }
    }

    static func languageAvailability() -> LanguageAvailability {
        #if compiler(>=6.3)
        if #available(macOS 26.4, *) { return LanguageAvailability(preferredStrategy: .lowLatency) }
        #endif
        return LanguageAvailability()
    }

    /// Captions that need translation by the given source-language session.
    /// Two paths feed the queue:
    ///
    ///   * **Manual** — user picked "Translate" in the bubble context menu.
    ///     Routes by the explicit source the user (or `caption.language`)
    ///     provided; bypasses all auto-pipeline filters (mic side, isFinal,
    ///     translation-enabled, language-selection membership).
    ///
    ///   * **Auto** — the CC HUD pipeline. Routes by `caption.language ==
    ///     source`, system side only, only while `translationEnabled` is on,
    ///     skip captions already translated to the current target.
    private func pending(for source: Language, at now: Date) -> [Caption] {
        guard let stream, let settings else { return [] }
        let target = settings.translationTargetLanguage

        return stream.captions.filter { cap in
            let trimmed = cap.text.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !trimmed.isEmpty else { return false }
            if inFlight.contains(cap.id) { return false }
            let input = Input(text: cap.text, source: source, target: target)
            if let failure = failures[cap.id], failure.input == input {
                if failure.unsupported { return false }
                if failure.isFinal == cap.isFinal,
                   failure.attempts >= 3 || now < failure.retryAt { return false }
            }

            // Manual path wins outright when the user explicitly enqueued
            // this caption. The chosen source must match this session's
            // language; otherwise some OTHER source session owns the work.
            if let manualSource = pendingManual[cap.id] {
                return manualSource == source
            }

            // Auto pipeline.
            guard settings.translationEnabled else { return false }
            guard cap.source == .system else { return false }
            if !cap.isFinal && trimmed.count < Self.minInterimChars { return false }
            if cap.translation != nil, cap.translationLanguage == target,
               succeeded[cap.id] == input { return false }
            if cap.isFinal, cap.translation != nil, cap.translationLanguage == target {
                return false
            }
            guard let lang = cap.language else { return false }
            return lang == source
        }
    }

    /// Minimum interim text length before we bother translating. Short
    /// interim chunks produce unstable single-char results that flicker.
    private static let minInterimChars = 4

    // MARK: - Run loop

    /// One scheduling tick, shared by the Apple session and deterministic
    /// regression tests. The global deadline limits all language sessions
    /// together to two requests per second, including changed partials.
    @discardableResult
    func translateNext(
        source: Language, target: Language, at now: Date = Date(),
        translate: (String) async throws -> String
    ) async -> Bool {
        guard let stream, let settings,
              !Task.isCancelled, settings.translationTargetLanguage == target,
              configurations[source] != nil,
              now >= nextRequestAt,
              now >= (sourceRetryAt[source] ?? .distantPast),
              let cap = pending(for: source, at: now).last else { return false }

        let input = Input(text: cap.text, source: source, target: target)
        let requestGeneration = generation
        let sessionID = stream.activeSession.id
        nextRequestAt = now.addingTimeInterval(0.5)
        inFlight.insert(cap.id)
        defer { inFlight.remove(cap.id) }
        let wasManual = pendingManual[cap.id] != nil
        log.info("translation request: source=\(source.rawValue, privacy: .public) target=\(target.rawValue, privacy: .public) chars=\(cap.text.count) final=\(cap.isFinal)")

        do {
            let result = try await translate(cap.text).trimmingCharacters(in: .whitespacesAndNewlines)
            try Task.checkCancellation()
            guard generation == requestGeneration, stream.activeSession.id == sessionID,
                  settings.translationTargetLanguage == target else { return true }
            guard !result.isEmpty else { throw TranslationError.nothingToTranslate }
            guard let current = stream.captions.first(where: { $0.id == cap.id }),
                  current.text == cap.text, wasManual || current.language == source else { return true }
            stream.setTranslation(result, sourceText: cap.text, language: target, forCaptionID: cap.id)
            succeeded[cap.id] = input
            failures.removeValue(forKey: cap.id)
            sourceRetryAt.removeValue(forKey: source)
            issues.removeValue(forKey: source)
            if wasManual {
                pendingManual.removeValue(forKey: cap.id)
                recomputeConfigurations()
            }
        } catch {
            // Changing language or closing a view cancels its task. That is
            // lifecycle control, not a failed caption or a reason to blacklist it.
            guard !Task.isCancelled, generation == requestGeneration,
                  stream.activeSession.id == sessionID else { return true }
            let previous = failures[cap.id]
            let attempts = (previous?.input == input && previous?.isFinal == cap.isFinal)
                ? (previous?.attempts ?? 0) + 1 : 1
            let unsupported: Bool
            switch error {
            case TranslationError.unsupportedSourceLanguage,
                 TranslationError.unsupportedTargetLanguage,
                 TranslationError.unsupportedLanguagePairing:
                unsupported = true
            default:
                unsupported = false
            }
            let retryAt = now.addingTimeInterval([2.0, 5.0, 15.0][min(attempts - 1, 2)])
            failures[cap.id] = Failure(input: input, isFinal: cap.isFinal, attempts: attempts,
                                      retryAt: retryAt, unsupported: unsupported)
            sourceRetryAt[source] = retryAt
            issues[source] = unsupported
                ? "\(source.displayName) → \(target.displayName) is not supported by Apple Translation."
                : (attempts < 3 ? "Translation interrupted — retrying…" : "Translation unavailable. Try again.")
            let nsError = error as NSError
            log.warning("translation failed: source=\(source.rawValue, privacy: .public) attempt=\(attempts) domain=\(nsError.domain, privacy: .public) code=\(nsError.code) error=\(error.localizedDescription, privacy: .public)")
            if !unsupported {
                configurations[source]?.invalidate()
            }
        }
        return true
    }

    func run(session: TranslationSession, source: Language) async {
        guard let settings else { return }
        let target = settings.translationTargetLanguage
        log.info("session opened: \(source.rawValue, privacy: .public) → \(target.rawValue, privacy: .public)")
        defer { log.info("session closed: \(source.rawValue, privacy: .public) → \(target.rawValue, privacy: .public)") }
        while !Task.isCancelled, settings.translationTargetLanguage == target {
            await translateNext(source: source, target: target) { text in
                try await session.translate(text).targetText
            }
            do { try await Task.sleep(for: .milliseconds(100)) }
            catch { return }
        }
    }
}

// MARK: - Environment plumbing

/// Optional carrier so bubble-level views can call `requestManualTranslation`
/// without the full singleton being plumbed through every parent. The value
/// is set at the WindowGroup root from `LingoFloatApp`; views read it via
/// `@Environment(\.captionTranslator)`.
private struct CaptionTranslatorKey: EnvironmentKey {
    static let defaultValue: CaptionTranslator? = nil
}

extension EnvironmentValues {
    var captionTranslator: CaptionTranslator? {
        get { self[CaptionTranslatorKey.self] }
        set { self[CaptionTranslatorKey.self] = newValue }
    }
}
