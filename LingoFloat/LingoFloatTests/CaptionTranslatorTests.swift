import Foundation
import Testing
@testable import LingoFloat

@MainActor
@Suite("CaptionTranslator auto source", .serialized)
struct CaptionTranslatorTests {
    @Test("Auto mounts an explicit translation session after ASR detects a source language")
    func autoCreatesDetectedSourceConfiguration() async throws {
        let temp = try TempHistory.make(suffix: "translator-auto")
        defer { temp.cleanup() }
        let settings = SettingsStore()
        let oldEnabled = settings.translationEnabled
        let oldTarget = settings.translationTargetLanguage
        defer {
            settings.translationEnabled = oldEnabled
            settings.translationTargetLanguage = oldTarget
        }
        settings.translationEnabled = true
        settings.translationTargetLanguage = .zh

        let stream = CaptionStream()
        stream.attach(settings: settings, history: temp.store)
        let oldSelected = stream.languages.selectedLanguages
        defer { stream.languages.selectedLanguages = oldSelected }
        stream.languages.selectedLanguages = []
        let translator = CaptionTranslator(stream: stream, settings: settings)
        #expect(translator.sourcesNeedingTranslation.isEmpty)

        let session = ChatSession(
            id: "auto-ja-source",
            createdAt: Date(),
            captions: [Caption(source: .system, text: "こんにちは。", language: .ja, isFinal: true)]
        )
        temp.store.save(session)
        stream.activate(sessionID: session.id)

        await waitUntil { translator.sourcesNeedingTranslation == [.ja] }
        #expect(translator.sourcesNeedingTranslation == [.ja])
    }

    @Test("Auto ignores mic language and target-to-target captions")
    func autoExcludesUntranslatableSources() async throws {
        let temp = try TempHistory.make(suffix: "translator-filter")
        defer { temp.cleanup() }
        let settings = SettingsStore()
        let oldEnabled = settings.translationEnabled
        let oldTarget = settings.translationTargetLanguage
        defer {
            settings.translationEnabled = oldEnabled
            settings.translationTargetLanguage = oldTarget
        }
        settings.translationEnabled = true
        settings.translationTargetLanguage = .zh

        let stream = CaptionStream()
        stream.attach(settings: settings, history: temp.store)
        let oldSelected = stream.languages.selectedLanguages
        defer { stream.languages.selectedLanguages = oldSelected }
        stream.languages.selectedLanguages = []
        let session = ChatSession(
            id: "auto-filter-source",
            createdAt: Date(),
            captions: [
                Caption(source: .microphone, text: "English", language: .en, isFinal: true),
                Caption(source: .system, text: "中文", language: .zh, isFinal: true)
            ]
        )
        temp.store.save(session)
        stream.activate(sessionID: session.id)
        let translator = CaptionTranslator(stream: stream, settings: settings)

        await Task.yield()
        #expect(translator.sourcesNeedingTranslation.isEmpty)
    }

    private func waitUntil(_ condition: () -> Bool) async {
        for _ in 0..<50 {
            if condition() { return }
            try? await Task.sleep(for: .milliseconds(10))
        }
    }
}
