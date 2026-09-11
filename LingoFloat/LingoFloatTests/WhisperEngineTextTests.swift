import Testing
@testable import LingoFloat

struct WhisperEngineTextTests {
    @Test("blank-audio control tokens are removed from visible captions")
    func removesBlankAudioToken() {
        let text = WhisperEngine.sanitizeTranscript(
            "Welcome to LingoFloat.   [BLANK_AUDIO]\n"
        )

        #expect(text == "Welcome to LingoFloat.")
    }

    @Test("ordinary transcript text is preserved while whitespace is normalized")
    func preservesSpokenText() {
        let text = WhisperEngine.sanitizeTranscript("  one\n two   three  ")

        #expect(text == "one two three")
    }
}
