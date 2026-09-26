//
//  Theme.swift
//  Spectra
//
//  Liquid Glass-first design system (macOS 26). We lean on system materials and
//  semantic colors for chrome and keep only the minimal token set Kubernetes
//  genuinely needs: status colors, an accent/tint, a typography ramp, and a
//  spacing scale. Data-dense surfaces stay solid; chrome uses glass.
//

import SwiftUI

nonisolated enum ThemeMode: String, CaseIterable, Identifiable, Sendable {
    case light, dark, auto
    var id: String { rawValue }

    var label: String {
        switch self {
        case .light: return "Light"
        case .dark: return "Dark"
        case .auto: return "Automatic"
        }
    }

    var colorScheme: ColorScheme? {
        switch self {
        case .light: return .light
        case .dark: return .dark
        case .auto: return nil
        }
    }
}

/// Semantic status used for coloring badges, table cells, and dots across the app.
nonisolated enum SpectraStatus: Sendable {
    case success   // running / ready / bound / active
    case info      // pending / progressing / neutral-positive
    case warning   // degraded / not-ready / terminating
    case error     // failed / crashloop / unreachable
    case neutral   // unknown / completed / suspended

    var color: Color {
        switch self {
        case .success: return .green
        case .info: return .blue
        case .warning: return .orange
        case .error: return .red
        case .neutral: return .secondary
        }
    }
}

/// Minimal, app-wide design tokens. Prefer system semantic colors; only define
/// what we genuinely need on top.
enum Tokens {
    enum Spacing {
        static let xxs: CGFloat = 2
        static let xs: CGFloat = 4
        static let sm: CGFloat = 8
        static let md: CGFloat = 12
        static let lg: CGFloat = 16
        static let xl: CGFloat = 24
        static let xxl: CGFloat = 32
    }

    /// Base corner radius; nested shapes derive concentric radii from their
    /// container via SwiftUI's container-relative shapes where possible.
    enum Radius {
        static let sm: CGFloat = 6
        static let md: CGFloat = 10
        static let lg: CGFloat = 16
    }

    enum Sidebar {
        static let minWidth: CGFloat = 180
        static let idealWidth: CGFloat = 280
        static let maxWidth: CGFloat = 420
    }

    enum Dock {
        static let minHeight: CGFloat = 120
        static let defaultHeight: CGFloat = 260
        static let collapsedHeight: CGFloat = 0
    }
}

/// Observable theme injected via SwiftUI environment. Holds the user's mode and
/// the accent tint, both persisted in UserDefaults so the choice made during
/// onboarding (or in Preferences) survives a relaunch. Status colors are static
/// (see `SpectraStatus`).
@Observable
final class Theme {
    private enum Keys {
        static let mode = "spectra.themeMode"
        static let accentHex = "spectra.accentHex"
    }

    var mode: ThemeMode {
        didSet { UserDefaults.standard.set(mode.rawValue, forKey: Keys.mode) }
    }
    var accent: Color {
        didSet { UserDefaults.standard.set(accent.rgbHex, forKey: Keys.accentHex) }
    }

    init(mode: ThemeMode? = nil, accent: Color? = nil) {
        let defaults = UserDefaults.standard
        self.mode = mode
            ?? defaults.string(forKey: Keys.mode).flatMap(ThemeMode.init(rawValue:))
            ?? .auto
        self.accent = accent ?? Color(hex: defaults.string(forKey: Keys.accentHex)) ?? .accentColor
    }

    /// True when the accent is the app's default (asset catalog) color.
    var usesDefaultAccent: Bool {
        UserDefaults.standard.string(forKey: Keys.accentHex) == nil
    }

    /// Back to the asset-catalog accent (and forget the persisted override).
    func resetAccent() {
        accent = .accentColor
        UserDefaults.standard.removeObject(forKey: Keys.accentHex)
    }

    var colorScheme: ColorScheme? { mode.colorScheme }
}
