import Foundation
import Testing
import Translation
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

    @Test("Unchanged interim text makes one request across 1,000 scheduler ticks")
    func unchangedInterimIsDeduplicated() async throws {
        try await withFixture { stream, _, translator in
            let now = Date()
            var requests = 0
            for tick in 0..<1_000 {
                await translator.translateNext(source: .ja, target: .zh, at: now.addingTimeInterval(Double(tick) / 50)) { _ in
                    requests += 1
                    return "今天的天气很好。"
                }
            }
            #expect(requests == 1)
            #expect(stream.captions.first?.translation == "今天的天气很好。")
            stream.flushNow()
        }
    }

    @Test("Changed partials and different language sessions share a two-per-second limit")
    func rateLimitCoversChangedTextAndLanguages() async throws {
        try await withFixture { stream, _, translator in
            let now = Date()
            var requests = 0
            let translate: (String) async throws -> String = { _ in requests += 1; return "译文" }
            await translator.translateNext(source: .ja, target: .zh, at: now, translate: translate)
            var caption = stream.captions[0]
            caption.text += " 明日も晴れです。"
            stream.applyCaption(caption)
            await translator.translateNext(source: .ja, target: .zh, at: now.addingTimeInterval(0.1), translate: translate)
            #expect(requests == 1)
            await translator.translateNext(source: .ja, target: .zh, at: now.addingTimeInterval(0.5), translate: translate)
            #expect(requests == 2)

            let english = Caption(source: .system, text: "Good morning.", language: .en, isFinal: true)
            stream.applyCaption(english)
            translator.requestManualTranslation(captionID: english.id, sourceLanguage: .en)
            await translator.translateNext(source: .en, target: .zh, at: now.addingTimeInterval(0.6), translate: translate)
            #expect(requests == 2)
            await translator.translateNext(source: .en, target: .zh, at: now.addingTimeInterval(1), translate: translate)
            #expect(requests == 3)
        }
    }

    @Test("Temporary failure backs off, succeeds on retry, and persists the translation")
    func transientFailureRecovers() async throws {
        try await withFixture { stream, history, translator in
            let now = Date()
            var requests = 0
            let translate: (String) async throws -> String = { _ in
                requests += 1
                if requests == 1 { throw TranslationError.internalError }
                return "今天的天气很好。"
            }
            await translator.translateNext(source: .ja, target: .zh, at: now, translate: translate)
            #expect(translator.translationIssue != nil)
            await translator.translateNext(source: .ja, target: .zh, at: now.addingTimeInterval(1), translate: translate)
            #expect(requests == 1)
            await translator.translateNext(source: .ja, target: .zh, at: now.addingTimeInterval(2), translate: translate)
            #expect(requests == 2)
            #expect(translator.translationIssue == nil)
            stream.flushNow()
            #expect(history.load(id: stream.activeSession.id)?.captions.first?.translation == "今天的天气很好。")
        }
    }

    @Test("Repeated errors have a finite retry budget; explicit retry recovers")
    func retryBudgetIsBounded() async throws {
        try await withFixture { stream, _, translator in
            let now = Date()
            var requests = 0
            for seconds in [0.0, 1, 2, 6, 7, 22, 60] {
                await translator.translateNext(source: .ja, target: .zh, at: now.addingTimeInterval(seconds)) { _ in
                    requests += 1
                    throw TranslationError.internalError
                }
            }
            #expect(requests == 3)
            #expect(stream.captions.first?.translation == nil)
            translator.retryTranslations()
            await translator.translateNext(source: .ja, target: .zh, at: now.addingTimeInterval(61)) { _ in "恢复了" }
            #expect(stream.captions.first?.translation == "恢复了")
        }
    }

    @Test("Cancelled view task does not poison the caption")
    func cancelledTaskCanResumeInNewSession() async throws {
        try await withFixture { stream, _, translator in
            let now = Date()
            let task = Task { @MainActor in
                await translator.translateNext(source: .ja, target: .zh, at: now) { _ in
                    withUnsafeCurrentTask { $0?.cancel() }
                    throw CancellationError()
                }
            }
            _ = await task.value
            #expect(translator.translationIssue == nil)
            await translator.translateNext(source: .ja, target: .zh, at: now.addingTimeInterval(1)) { _ in "恢复了" }
            #expect(stream.captions.first?.translation == "恢复了")
        }
    }

    @Test("Apple cancellation without task cancellation is retried after backoff")
    func cancelledAppleSessionRecovers() async throws {
        try await withFixture { stream, _, translator in
            let now = Date()
            await translator.translateNext(source: .ja, target: .zh, at: now) { _ in throw CancellationError() }
            await translator.translateNext(source: .ja, target: .zh, at: now.addingTimeInterval(2)) { _ in "恢复了" }
            #expect(stream.captions.first?.translation == "恢复了")
        }
    }

    @Test("Late result is discarded and the latest source text is translated next")
    func staleResultIsNotCached() async throws {
        try await withFixture { stream, _, translator in
            let now = Date()
            await translator.translateNext(source: .ja, target: .zh, at: now) { _ in
                var changed = stream.captions[0]
                changed.text = "明日は雨です。"
                stream.applyCaption(changed)
                return "旧译文"
            }
            #expect(stream.captions.first?.translation == nil)
            await translator.translateNext(source: .ja, target: .zh, at: now.addingTimeInterval(0.5)) { text in
                #expect(text == "明日は雨です。")
                return "明天会下雨。"
            }
            #expect(stream.captions.first?.translation == "明天会下雨。")
        }
    }

    @Test("Clear rejects an in-flight translation from the previous chat")
    func clearRejectsInFlightResult() async throws {
        try await withFixture { stream, _, translator in
            await translator.translateNext(source: .ja, target: .zh) { _ in
                stream.clearContext()
                return "旧会话的译文"
            }
            #expect(stream.captions.isEmpty)
        }
    }

    @Test("A failed partial gets a fresh retry when finalized or changed")
    func newRevisionCanRecoverAfterBudgetExhausted() async throws {
        try await withFixture { stream, _, translator in
            let now = Date()
            for seconds in [0.0, 2, 7] {
                await translator.translateNext(source: .ja, target: .zh, at: now.addingTimeInterval(seconds)) { _ in
                    throw TranslationError.internalError
                }
            }
            var final = stream.captions[0]
            final.isFinal = true
            stream.applyCaption(final)
            await translator.translateNext(source: .ja, target: .zh, at: now.addingTimeInterval(22)) { _ in "完整译文" }
            #expect(stream.captions.first?.translation == "完整译文")
        }
    }

    @Test("Unsupported language pairs do not enter an automatic retry loop")
    func unsupportedPairDoesNotLoop() async throws {
        try await withFixture { _, _, translator in
            let now = Date()
            var requests = 0
            for seconds in [0.0, 2, 10, 100] {
                await translator.translateNext(source: .ja, target: .zh, at: now.addingTimeInterval(seconds)) { _ in
                    requests += 1
                    throw TranslationError.unsupportedLanguagePairing
                }
            }
            #expect(requests == 1)
            #expect(translator.translationIssue?.contains("not supported") == true)
        }
    }

    private func withFixture(
        _ body: (CaptionStream, ChatHistoryStore, CaptionTranslator) async throws -> Void
    ) async throws {
        let defaults = UserDefaults.standard
        let keys = ["LingoFloat.settings.translationEnabled", "LingoFloat.settings.translationTargetLanguage",
                    "LingoFloat.settings.transcriptionEngine", "LingoFloat.settings.activeChatID",
                    "LingoFloat.LanguageSettings.selected"]
        let saved = keys.map { defaults.object(forKey: $0) }
        defer { for (key, value) in zip(keys, saved) { defaults.set(value, forKey: key) } }
        let temp = try TempHistory.make(suffix: "translation-scheduler")
        defer { temp.cleanup() }
        let session = ChatSession(id: "scheduler-fixture", captions: [
            Caption(source: .system, text: "今日はいい天気です。", language: .ja, isFinal: false)
        ])
        temp.store.save(session)
        let settings = SettingsStore()
        settings.translationEnabled = true
        settings.translationTargetLanguage = .zh
        settings.transcriptionEngine = .deepgram
        settings.activeChatID = session.id
        let stream = CaptionStream()
        stream.languages.selectedLanguages = [.ja]
        stream.attach(settings: settings, history: temp.store)
        let translator = CaptionTranslator(stream: stream, settings: settings)
        try await body(stream, temp.store, translator)
    }

    @Test("Installed Apple models translate successive Japanese captions to Chinese",
          .enabled(if: ProcessInfo.processInfo.environment["LINGOFLOAT_REAL_TRANSLATION"] == "1"))
    func realAppleTranslation() async throws {
        #if compiler(>=6.3)
        guard #available(macOS 26.4, *) else {
            Issue.record("This opt-in integration test requires macOS 26.4 or later")
            return
        }
        let source = Locale.Language(identifier: "ja")
        let target = Locale.Language(identifier: "zh")
        let availability = LanguageAvailability(preferredStrategy: .lowLatency)
        let status = await availability.status(from: source, to: target)
        try #require(status == .installed, "Install Japanese and Chinese using the app before running this test")
        let session = TranslationSession(installedSource: source, target: target, preferredStrategy: .lowLatency)
        try await withFixture { stream, _, translator in
            for sentence in ["今日はいい天気です。", "明日は雨が降ります。", "駅まで歩いて行きます。", "電車は九時に出発します。"] {
                var caption = stream.captions[0]
                caption.text = sentence
                caption.translation = nil
                caption.translationLanguage = nil
                stream.applyCaption(caption)
                let attempted = await translator.translateNext(source: .ja, target: .zh) { text in
                    try await session.translate(text).targetText
                }
                #expect(attempted)
                let result = try #require(stream.captions.first?.translation)
                #expect(!result.isEmpty && result != sentence)
                #expect(stream.captions.first?.translationLanguage == .zh)
                try await Task.sleep(for: .milliseconds(550))
            }
            stream.flushNow()
        }
        #else
        Issue.record("This opt-in integration test requires Xcode 26.4 or later")
        #endif
    }
}
