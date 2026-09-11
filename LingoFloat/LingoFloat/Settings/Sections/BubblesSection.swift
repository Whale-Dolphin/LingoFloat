import SwiftUI

/// Bubble formatting — three knobs that normalise the wildly different
/// per-engine output cadences (Whisper short, ElevenLabs huge, Nova-3
/// middle) into a single user-controlled shape.
///
/// All controls feed `BubbleSplitter` inside `CaptionStream`. No
/// engine-specific logic here; the splitter is applied uniformly across
/// every transcription engine.
struct BubblesSection: View {

    @Environment(SettingsStore.self) private var store
    private let descriptor = SettingsCategoryID.bubbles.descriptor

    var body: some View {
        @Bindable var store = store

        SectionShell(descriptor: descriptor) {

            SettingsCard(
                title: "Run-on safety limit",
                footer: "Normal captions move to the context row at sentence-ending punctuation. This limit is used only when a very long passage has no punctuation at all."
            ) {
                HStack(spacing: 12) {
                    SettingsRowLabel(
                        title: "Maximum run-on characters",
                        subtitle: "Emergency limit for text with no complete sentence boundary."
                    )
                    Spacer(minLength: 12)
                    Slider(
                        value: Binding(
                            get: { Double(store.bubbleMaxChars) },
                            set: { store.bubbleMaxChars = Int($0) }
                        ),
                        in: Double(SettingsStore.bubbleMaxCharsRange.lowerBound)
                            ... Double(SettingsStore.bubbleMaxCharsRange.upperBound),
                        step: 10
                    )
                    .frame(maxWidth: 240)
                    Text("\(store.bubbleMaxChars)")
                        .font(.system(.caption, design: .monospaced))
                        .foregroundStyle(.secondary)
                        .frame(width: 50, alignment: .trailing)
                        .contentTransition(.numericText())
                }
            }

            SettingsCard(
                title: "Silence break",
                footer: "With sentence boundaries enabled, this timeout closes only text that already ends in punctuation; a pause in the middle of a sentence keeps accumulating. If sentence boundaries are off, any idle row may close."
            ) {
                HStack(spacing: 12) {
                    SettingsRowLabel(
                        title: "Idle timeout",
                        subtitle: "Seconds to wait after a completed sentence becomes idle."
                    )
                    Spacer(minLength: 12)
                    Slider(
                        value: $store.bubbleSilenceBreakSec,
                        in: SettingsStore.bubbleSilenceBreakRange,
                        step: 0.1
                    )
                    .frame(maxWidth: 240)
                    Text(String(format: "%.1f s", store.bubbleSilenceBreakSec))
                        .font(.system(.caption, design: .monospaced))
                        .foregroundStyle(.secondary)
                        .frame(width: 50, alignment: .trailing)
                        .contentTransition(.numericText())
                }
            }

            SettingsCard(
                title: "Cutting strategy",
                footer: "On: a complete sentence becomes the smaller context row when the next sentence starts. Supports English, Chinese, Japanese, Arabic and Indic sentence punctuation. Off: text only breaks at the run-on safety limit."
            ) {
                Toggle(isOn: $store.bubbleSentenceAware) {
                    SettingsRowLabel(
                        title: "Prefer sentence boundaries",
                        subtitle: store.bubbleSentenceAware
                            ? "Keep sentences intact and continue with the next sentence below."
                            : "Only apply the emergency length limit."
                    )
                }
                .toggleStyle(.switch)
            }

            SettingsCard(
                title: "Text size",
                footer: "Font size for caption text in the Main HUD chat. The CC HUD keeps its current subtitle at a fixed movie-caption size and renders only the previous context smaller."
            ) {
                HStack(spacing: 12) {
                    SettingsRowLabel(
                        title: "Bubble font size",
                        subtitle: "Caption text in points. Default 13 matches SwiftUI's body size."
                    )
                    Spacer(minLength: 12)
                    Slider(
                        value: $store.bubbleFontSize,
                        in: SettingsStore.bubbleFontSizeRange,
                        step: 1
                    )
                    .frame(maxWidth: 240)
                    Text("\(Int(store.bubbleFontSize)) pt")
                        .font(.system(.caption, design: .monospaced))
                        .foregroundStyle(.secondary)
                        .frame(width: 50, alignment: .trailing)
                        .contentTransition(.numericText())
                }
            }
        }
    }
}
