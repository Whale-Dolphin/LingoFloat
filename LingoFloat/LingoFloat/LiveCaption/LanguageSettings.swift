import Foundation
import Observation

/// User-toggleable set of expected languages. Persisted to UserDefaults.
///
/// How this maps to engines:
///   - 0 selected: fall back to engine default / auto-detect
///   - 1 selected: pass that one as the locked decoding language
///   - 2+ selected: enable auto-detect, then filter results by detected
///     language to reject anything outside the pool
///
/// No fixed presets — the supported set comes from the currently-active
/// `TranscriptionEngine.supportedLanguages`. The UI can warn when a user's
/// selection doesn't fit an engine (e.g. `uk` on Deepgram Nova-3 multilingual).
@Observable
final class LanguageSettings {

    private let defaultsKey = "LingoFloat.LanguageSettings.selected"
    private let defaults: UserDefaults

    /// Subset of languages user wants captioned. Order is irrelevant.
    var selectedLanguages: Set<Language> {
        didSet {
            persist()
        }
    }

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        if let stored = defaults.array(forKey: defaultsKey) as? [String] {
            // An explicitly persisted empty array means Auto. Distinguish it
            // from a missing key so Auto survives an app relaunch.
            self.selectedLanguages = Set(stored.compactMap(Language.init(rawValue:)))
        } else {
            // No persisted choice yet — default to English-only. Users can
            // expand from Settings; defaulting to one locked language is
            // cheaper and more accurate than auto-detect on first launch.
            self.selectedLanguages = [.en]
        }
    }

    /// Language to pass to Whisper's `DecodingOptions.language`.
    /// Returns nil when the user has selected ≠ 1 language (auto-detect mode).
    var forcedWhisperLanguage: String? {
        guard selectedLanguages.count == 1, let only = selectedLanguages.first else { return nil }
        return only.whisperCode
    }

    /// Whether `lang` (as detected by the engine) is allowed to surface in the UI.
    func accepts(_ lang: Language?) -> Bool {
        guard !selectedLanguages.isEmpty else { return true }
        guard let lang else { return true }     // unknown → don't filter
        return selectedLanguages.contains(lang)
    }

    /// Languages selected by the user but not supported by `engineLanguages`.
    /// Used by the UI to display a warning chip.
    func unsupported(by engineLanguages: [Language]) -> Set<Language> {
        let allowed = Set(engineLanguages)
        return selectedLanguages.subtracting(allowed)
    }

    private func persist() {
        let raw = selectedLanguages.map(\.rawValue).sorted()
        defaults.set(raw, forKey: defaultsKey)
    }
}
