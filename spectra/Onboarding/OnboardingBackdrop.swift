//
//  OnboardingBackdrop.swift
//  Spectra
//
//  The living background behind the onboarding pages: a slowly drifting mesh
//  gradient built from the accent color and a few companion hues, softened
//  toward the window background so text stays legible in both appearances.
//  Purely visual, no audio. Honors Reduce Motion by freezing the mesh.
//

import SwiftUI

struct OnboardingBackdrop: View {
    let accent: Color
    /// 1 = calm drift; the final page nudges this up for a little celebration.
    var energy: Double = 1

    @Environment(\.colorScheme) private var colorScheme
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        Group {
            if reduceMotion {
                mesh(at: 0)
            } else {
                TimelineView(.animation(minimumInterval: 1 / 30)) { context in
                    mesh(at: context.date.timeIntervalSinceReferenceDate)
                }
            }
        }
        .overlay {
            // Soft vignette so the center (where the content lives) is calmer.
            RadialGradient(colors: [base.opacity(0.35), .clear],
                           center: .center, startRadius: 40, endRadius: 520)
        }
        .ignoresSafeArea()
        .allowsHitTesting(false)
        .accessibilityHidden(true)
    }

    private var base: Color { colorScheme == .dark ? .black : .white }

    private var palette: [Color] {
        let soften = colorScheme == .dark ? 0.62 : 0.55
        let companions: [Color] = [
            Color(hex: "#5E5CE6") ?? .indigo,   // indigo
            Color(hex: "#40C8E0") ?? .teal,     // teal
            Color(hex: "#BF5AF2") ?? .purple,   // purple
            Color(hex: "#FF9F0A") ?? .orange,   // warm counterpoint
        ]
        let raw: [Color] = [
            accent, companions[0], companions[1],
            companions[2], accent, companions[0],
            companions[1], companions[3], accent,
        ]
        return raw.map { $0.mix(with: base, by: soften) }
    }

    private func mesh(at time: TimeInterval) -> some View {
        let t = Float(time * 0.28 * energy)
        func wobble(_ base: Float, _ phase: Float, _ amp: Float) -> Float {
            base + sin(t + phase) * amp
        }
        let points: [SIMD2<Float>] = [
            [0, 0], [wobble(0.5, 0.0, 0.18), 0], [1, 0],
            [0, wobble(0.5, 1.3, 0.16)],
            [wobble(0.5, 2.1, 0.22), wobble(0.5, 0.7, 0.22)],
            [1, wobble(0.5, 3.4, 0.16)],
            [0, 1], [wobble(0.5, 4.2, 0.18), 1], [1, 1],
        ]
        return MeshGradient(width: 3, height: 3, points: points, colors: palette)
    }
}
