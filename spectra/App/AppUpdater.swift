import AppKit
import Sparkle

/// Sparkle's signed updater. The feed URL and Ed25519 public key live in
/// Info.plist; the private signing key must stay in CI or the maintainer's
/// keychain and must never be committed.
///
/// Canary builds never start the updater (`AppInfo.updatesEnabled == false`):
/// they have no feed, and the stable feed would replace them with the last
/// release on the next scheduled check.
@MainActor
final class AppUpdater: NSObject {
    let controller: SPUStandardUpdaterController
    let isEnabled = AppInfo.updatesEnabled

    override init() {
        controller = SPUStandardUpdaterController(startingUpdater: AppInfo.updatesEnabled,
                                                   updaterDelegate: nil,
                                                   userDriverDelegate: nil)
        super.init()
    }

    func checkForUpdates() {
        guard isEnabled else { return }
        controller.checkForUpdates(nil)
    }
}
