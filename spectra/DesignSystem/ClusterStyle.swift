//
//  ClusterStyle.swift
//  Spectra
//
//  Arc-style per-cluster identity: a curated SF Symbol + accent color stored on
//  ClusterRecord (iconSymbol / iconColorHex). Drives the sidebar space
//  indicator, the cluster switcher header, and the customize sheet.
//

import SwiftUI
import AppKit

nonisolated enum ClusterStyle {
    static let defaultSymbol = "circle.hexagongrid.fill"

    /// Curated icon choices shown in the customize sheet.
    static let symbols: [String] = [
        "circle.hexagongrid.fill", "apple.terminal.fill", "lightbulb.fill", "heart.fill",
        "cloud.fill", "server.rack", "shippingbox.fill", "flame.fill",
        "bolt.fill", "leaf.fill", "star.fill", "globe.americas.fill",
        "gearshape.fill", "hammer.fill", "testtube.2", "house.fill",
        "briefcase.fill", "gamecontroller.fill", "lock.shield.fill", "wrench.adjustable.fill",
        "cpu.fill", "network", "folder.fill", "paperplane.fill",
    ]

    /// Named color palette; the hex string is what ClusterRecord persists.
    static let palette: [(name: String, hex: String)] = [
        ("Blue", "#0A84FF"), ("Purple", "#BF5AF2"), ("Pink", "#FF375F"),
        ("Red", "#FF453A"), ("Orange", "#FF9F0A"), ("Yellow", "#FFD60A"),
        ("Green", "#30D158"), ("Teal", "#40C8E0"), ("Indigo", "#5E5CE6"),
        ("Brown", "#AC8E68"),
    ]

    static let gradients: [ClusterGradientPreset] = [
        .init(name: "Aurora", start: "#5B4FE9", end: "#28C6B7", angle: 35),
        .init(name: "Dusk", start: "#7854D8", end: "#EF8AAF", angle: 135),
        .init(name: "Ocean", start: "#1479C9", end: "#38C9B5", angle: 55),
        .init(name: "Ember", start: "#DF5268", end: "#F4AD62", angle: 145),
        .init(name: "Forest", start: "#218779", end: "#9DC46D", angle: 35),
        .init(name: "Midnight", start: "#364595", end: "#A166DB", angle: 125),
    ]
}

nonisolated struct ClusterGradientPreset: Identifiable {
    let name: String
    let start: String
    let end: String
    let angle: Double
    var id: String { name }
}

/// One gradient implementation shared by the editor, sidebar, and cards.
nonisolated struct ClusterGradient: ShapeStyle {
    let start: Color
    let end: Color
    var angle: Double = 135

    func resolve(in environment: EnvironmentValues) -> some ShapeStyle {
        let radians = angle * .pi / 180
        let dx = cos(radians) / 2
        let dy = sin(radians) / 2
        return LinearGradient(colors: [start, end],
                              startPoint: UnitPoint(x: 0.5 - dx, y: 0.5 - dy),
                              endPoint: UnitPoint(x: 0.5 + dx, y: 0.5 + dy))
    }
}

struct ClusterThemeBackground: View {
    let start: Color
    let end: Color
    var angle: Double = 135
    @Environment(\.colorScheme) private var colorScheme

    var body: some View {
        Rectangle()
            .fill(ClusterGradient(start: start, end: end, angle: angle))
            .opacity(colorScheme == .dark ? 0.28 : 0.17)
            .allowsHitTesting(false)
            .accessibilityHidden(true)
    }
}

nonisolated extension Color {
    /// Parses "#RRGGBB" (or "RRGGBB"); nil for anything else.
    init?(hex: String?) {
        guard var value = hex?.trimmingCharacters(in: .whitespaces), !value.isEmpty else {
            return nil
        }
        if value.hasPrefix("#") { value.removeFirst() }
        guard value.count == 6, let rgb = UInt32(value, radix: 16) else { return nil }
        self.init(red: Double((rgb >> 16) & 0xFF) / 255,
                  green: Double((rgb >> 8) & 0xFF) / 255,
                  blue: Double(rgb & 0xFF) / 255)
    }
    var rgbHex: String? {
        guard let rgb = NSColor(self).usingColorSpace(.sRGB) else { return nil }
        return String(format: "#%02X%02X%02X",
                      Int((rgb.redComponent * 255).rounded()),
                      Int((rgb.greenComponent * 255).rounded()),
                      Int((rgb.blueComponent * 255).rounded()))
    }
}

nonisolated extension ClusterRecord {
    var effectiveIcon: String { iconSymbol ?? ClusterStyle.defaultSymbol }
    /// The cluster's custom accent, if one is set (falls back to theme accent at
    /// the call sites so "no color" follows the app theme).
    var customColor: Color? { Color(hex: iconColorHex) }
    var gradientEndColor: Color? { Color(hex: gradientEndColorHex) }

    func identityStyle(fallback: Color) -> AnyShapeStyle {
        let start = customColor ?? fallback
        if let end = gradientEndColor {
            return AnyShapeStyle(ClusterGradient(start: start, end: end, angle: gradientAngle ?? 135))
        }
        return AnyShapeStyle(start)
    }
}
