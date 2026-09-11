import Foundation
import Testing
@testable import LingoFloat

@Suite("LanguageSettings auto detection")
struct LanguageSettingsTests {
    private let key = "LingoFloat.LanguageSettings.selected"

    @Test("missing preference defaults to English, explicit empty preference restores Auto")
    func autoPersistsAcrossRelaunch() throws {
        let name = "LingoFloatTests.LanguageSettings.\(UUID().uuidString)"
        let defaults = try #require(UserDefaults(suiteName: name))
        defer { defaults.removePersistentDomain(forName: name) }

        #expect(LanguageSettings(defaults: defaults).selectedLanguages == [.en])
        let first = LanguageSettings(defaults: defaults)
        first.selectedLanguages = []
        #expect(defaults.array(forKey: key) as? [String] == [])
        #expect(LanguageSettings(defaults: defaults).selectedLanguages.isEmpty)
    }

    @Test("Auto mode accepts every detected language and does not force Whisper")
    func autoAcceptsDetectedLanguages() throws {
        let name = "LingoFloatTests.LanguageSettings.\(UUID().uuidString)"
        let defaults = try #require(UserDefaults(suiteName: name))
        defer { defaults.removePersistentDomain(forName: name) }
        let settings = LanguageSettings(defaults: defaults)
        settings.selectedLanguages = []

        #expect(settings.forcedWhisperLanguage == nil)
        #expect(settings.accepts(.ja))
        #expect(settings.accepts(.en))
        #expect(settings.accepts(.zh))
        #expect(settings.accepts(nil))
    }

    @Test("a fixed source still filters other detected languages")
    func fixedSourceStillFilters() throws {
        let name = "LingoFloatTests.LanguageSettings.\(UUID().uuidString)"
        let defaults = try #require(UserDefaults(suiteName: name))
        defer { defaults.removePersistentDomain(forName: name) }
        let settings = LanguageSettings(defaults: defaults)
        settings.selectedLanguages = [.ja]

        #expect(settings.forcedWhisperLanguage == "ja")
        #expect(settings.accepts(.ja))
        #expect(!settings.accepts(.en))
    }
}
