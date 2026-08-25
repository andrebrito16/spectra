//
//  ClusterStyle.swift
//  Spectra
//
//  Arc-style per-cluster identity: a curated SF Symbol + accent color stored on
//  ClusterRecord (iconSymbol / iconColorHex). Drives the sidebar space
//  indicator, the cluster switcher header, and the customize sheet.
//

import SwiftUI

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
}

nonisolated extension ClusterRecord {
    var effectiveIcon: String { iconSymbol ?? ClusterStyle.defaultSymbol }
    /// The cluster's custom accent, if one is set (falls back to theme accent at
    /// the call sites so "no color" follows the app theme).
    var customColor: Color? { Color(hex: iconColorHex) }
}
