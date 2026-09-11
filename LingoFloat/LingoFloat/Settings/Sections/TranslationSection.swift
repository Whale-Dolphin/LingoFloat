import SwiftUI
import Translation

/// Settings page for the auto-translation feature: master toggle +
/// target language picker. Uses Apple's on-device Translation framework,
/// so there's no API key, no cost, and no network — just a one-time
/// per-pair language model download macOS prompts for on first use.
///
/// Scope: translation applies to the **CC HUD only**. The system-side
/// chat column in the Main HUD still shows captions in the original
/// language. Mic captions are never translated.
struct TranslationSection: View {

    @Environment(SettingsStore.self) private var store
    @Environment(CaptionStream.self) private var stream
    @State private var supportedTargets: [Language] = [.en, .zh, .ja]
    private let descriptor = SettingsCategoryID.translation.descriptor

    private var source: Language? {
        let selected = stream.languages.selectedLanguages
        return selected.count == 1 ? selected.first : nil
    }

    var body: some View {
        @Bindable var store = store

        SectionShell(descriptor: descriptor) {

            SettingsCard(
                title: "Auto-translate captions",
                footer: "Translation applies to the CC HUD only. The Main HUD's system column shows the original language. Uses Apple's on-device Translation framework — free, offline, ~50 ms. macOS may prompt to download a language pair the first time it's used."
            ) {
                Toggle(isOn: $store.translationEnabled) {
                    SettingsRowLabel(
                        title: "Enable translation",
                        subtitle: store.translationEnabled
                            ? "On — system captions translate to \(store.translationTargetLanguage.displayName)."
                            : "Off — captions display in their original language only."
                    )
                }
                .toggleStyle(.switch)
            }

            SettingsCard(
                title: "Language pair",
                footer: "From controls speech recognition; To controls Apple on-device translation. Auto detects each caption's language, then translates it to the target you choose."
            ) {
                HStack(spacing: 12) {
                    SettingsRowLabel(
                        title: "From",
                        subtitle: "Choose Auto to detect the spoken language."
                    )
                    Spacer()
                    Picker("Source language", selection: Binding(
                        get: { source },
                        set: {
                            if let language = $0 {
                                stream.languages.selectedLanguages = [language]
                                if store.translationTargetLanguage == language {
                                    store.translationTargetLanguage = (language == .zh) ? .en : .zh
                                }
                            } else {
                                stream.languages.selectedLanguages = []
                            }
                            store.translationEnabled = true
                        }
                    )) {
                        Text("Auto detect").tag(Language?.none)
                        Divider()
                        ForEach(Language.allCases.sorted(by: { $0.displayName < $1.displayName })) { lang in
                            Text(lang.displayName).tag(Language?.some(lang))
                        }
                    }
                    .labelsHidden()
                    .pickerStyle(.menu)
                    .fixedSize()
                }

                SettingsRowDivider()

                HStack(spacing: 12) {
                    SettingsRowLabel(
                        title: "To",
                        subtitle: "The subtitle language you want to read."
                    )
                    Spacer()
                    Picker("Translation language", selection: $store.translationTargetLanguage) {
                        ForEach(supportedTargets) { lang in
                            Text(lang.displayName).tag(lang)
                        }
                    }
                    .labelsHidden()
                    .pickerStyle(.menu)
                    .fixedSize()
                    .disabled(!store.translationEnabled)
                }
            }
        }
        .task { await loadSupportedTargets() }
    }

    private func loadSupportedTargets() async {
        let locales = await LanguageAvailability().supportedLanguages
        let codes = Set(locales.compactMap { $0.languageCode?.identifier })
        let available = Language.allCases
            .filter { codes.contains($0.bcp47) }
            .sorted { $0.displayName < $1.displayName }
        if !available.isEmpty {
            supportedTargets = available
        }
    }
}
