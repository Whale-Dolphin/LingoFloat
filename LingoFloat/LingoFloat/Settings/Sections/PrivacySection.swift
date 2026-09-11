import SwiftUI

/// Audio inputs and independent capture preferences for the subtitle
/// overlay and ordinary app windows. Appearance lives in `Windows`.
struct PrivacySection: View {

    @Environment(SettingsStore.self) private var store
    private let descriptor = SettingsCategoryID.privacy.descriptor

    var body: some View {
        @Bindable var store = store

        SectionShell(descriptor: descriptor) {
            SettingsCard(
                title: "Audio inputs",
                footer: "Off = transcribe only system audio (the other side of the call). Frees the Apple Neural Engine from running two pipelines at once — noticeably faster on the `medium` Whisper model. Applies on next Start."
            ) {
                Toggle(isOn: $store.captureMicrophone) {
                    SettingsRowLabel(
                        title: "Capture microphone",
                        subtitle: "When off, the app only transcribes what macOS is playing."
                    )
                }
                .toggleStyle(.switch)
            }

            SettingsCard(
                title: "Screen capture",
                footer: "By default, screenshots include the main app but exclude the subtitle overlay. Some macOS screen-recording tools may ignore window capture exclusion."
            ) {
                Toggle(isOn: $store.ccHUDHiddenFromCapture) {
                    SettingsRowLabel(
                        title: "Hide CC HUD from screen capture",
                        subtitle: "Keep floating subtitles out of your screenshots. Does not affect the main app."
                    )
                }
                .toggleStyle(.switch)
                .accessibilityIdentifier("hide-cc-hud-from-capture")

                Toggle(isOn: $store.windowsHiddenFromCapture) {
                    SettingsRowLabel(
                        title: "Hide main app from screen capture",
                        subtitle: "Main window and Settings only. Leave off to capture the app normally."
                    )
                }
                .toggleStyle(.switch)
                .accessibilityIdentifier("hide-main-app-from-capture")
            }
        }
    }
}

#Preview {
    PrivacySection()
        .environment(SettingsStore())
        .frame(width: 720, height: 700)
}
