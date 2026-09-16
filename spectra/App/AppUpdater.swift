import AppKit
import Sparkle

/// Sparkle's signed updater. The feed URL and Ed25519 public key live in
/// Info.plist; the private signing key must stay in CI or the maintainer's
/// keychain and must never be committed.
@MainActor
final class AppUpdater: NSObject {
    let controller: SPUStandardUpdaterController

    override init() {
        controller = SPUStandardUpdaterController(startingUpdater: true,
                                                   updaterDelegate: nil,
                                                   userDriverDelegate: nil)
        super.init()
    }

    func checkForUpdates() {
        controller.checkForUpdates(nil)
    }
}
