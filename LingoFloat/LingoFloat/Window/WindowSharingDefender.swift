import AppKit
import Foundation
import Observation
import OSLog

/// Applies independent capture preferences to the subtitle overlay and
/// ordinary app windows. `sharingType` exclusion depends on the macOS
/// capture path; it is not a guarantee against every screen recorder.
///
/// Lifecycle:
///   - We listen for `NSWindow.didBecomeMainNotification` to catch new
///     windows the user might open (e.g. Settings sheet).
///   - We re-apply on every change to the settings flag using `@Observable`
///     tracking + re-arm.
@MainActor
final class WindowSharingDefender {

    private let log = Log.HUD
    private let store: SettingsStore
    private var notificationToken: NSObjectProtocol?

    init(store: SettingsStore) {
        self.store = store
        applyToAllWindows()
        observeSettings()
        observeNewWindows()
    }

    deinit {
        if let token = notificationToken {
            NotificationCenter.default.removeObserver(token)
        }
    }

    // MARK: - Public

    /// Apply the current setting to every NSWindow of the app.
    /// Idempotent — safe to call as often as you want.
    func applyToAllWindows() {
        for window in NSApp.windows {
            let hidden = HUDDescriptor.ccHUD.matches(window)
                ? store.ccHUDHiddenFromCapture : store.windowsHiddenFromCapture
            window.sharingType = hidden ? .none : .readOnly
        }
        log.info("applied capture preferences: mainHidden=\(self.store.windowsHiddenFromCapture), ccHUDHidden=\(self.store.ccHUDHiddenFromCapture)")
    }

    // MARK: - Internals

    private func observeSettings() {
        // `@Observable` tracking only fires once per onChange; we have to
        // re-arm after each fire to keep watching.
        withObservationTracking { [self] in
            _ = store.windowsHiddenFromCapture
            _ = store.ccHUDHiddenFromCapture
        } onChange: { [weak self] in
            Task { @MainActor [weak self] in
                guard let self else { return }
                self.applyToAllWindows()
                self.observeSettings()
            }
        }
    }

    private func observeNewWindows() {
        // `didBecomeMainNotification` fires when any NSWindow becomes the
        // app's main window — including the Settings panel the first time
        // it's opened. Cheap, fires rarely.
        notificationToken = NotificationCenter.default.addObserver(
            forName: NSWindow.didBecomeMainNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            Task { @MainActor [weak self] in
                self?.applyToAllWindows()
            }
        }
    }

}
