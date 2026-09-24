//
//  AppInfo.swift
//  Spectra
//
//  Build-flavour facts. The `Canary` build configuration compiles with the
//  `CANARY` condition, a separate bundle id (`…spectra.canary`), a different
//  product name and a yellow icon, so a main-branch build can be installed next
//  to the stable release. Everything that must not collide between the two
//  installs (SwiftData store, logs, Sparkle) keys off this type.
//

import Foundation

nonisolated enum AppInfo {
    /// True when built with `-configuration Canary` (see `scripts/canary.sh`).
    static let isCanary: Bool = {
        #if CANARY
        return true
        #else
        return false
        #endif
    }()

    /// Name shown in diagnostics bundles and other user-facing text.
    static var displayName: String { isCanary ? "Spectra Canary" : "Spectra" }

    /// Folder under `~/Library/Application Support` that owns the store + logs.
    /// Stable and canary never share it, so a schema change in a canary build
    /// cannot corrupt the store the stable app is using.
    static var supportDirectoryName: String { isCanary ? "Spectra Canary" : "Spectra" }

    /// Sparkle only makes sense for the stable channel: the canary is a local
    /// build with no feed of its own, and the stable feed would "update" it back
    /// to the last release.
    static var updatesEnabled: Bool { !isCanary }
}
