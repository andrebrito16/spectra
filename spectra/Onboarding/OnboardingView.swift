//
//  OnboardingView.swift
//  Spectra
//
//  First-run onboarding, presented as a sheet over the main window. Arc /
//  Raycast-style: a living gradient backdrop, big friendly type, one idea per
//  page, Liquid Glass widgets, Return to continue. No audio, ever.
//
//  Pages live in OnboardingPages.swift; this file is the frame: progress,
//  Skip, Back/Continue, keyboard handling and completion bookkeeping.
//

import SwiftUI

struct OnboardingView: View {
    @Environment(\.appEnv) private var env
    @Environment(\.dismiss) private var dismiss
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    @State private var page: OnboardingPage = .welcome
    @State private var goingForward = true

    var body: some View {
        ZStack {
            OnboardingBackdrop(accent: env.theme.accent, energy: page == .ready ? 1.6 : 1)

            VStack(spacing: 0) {
                header
                    .padding(.horizontal, Tokens.Spacing.xxl)
                    .padding(.top, Tokens.Spacing.xl)

                ZStack {
                    pageContent
                        .id(page)
                        .transition(pageTransition)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .padding(.horizontal, Tokens.Spacing.xxl)
                .clipped()

                footer
                    .padding(.horizontal, Tokens.Spacing.xxl)
                    .padding(.bottom, Tokens.Spacing.xl)
            }
        }
        .frame(width: 920, height: 640)
        .interactiveDismissDisabled()
        .onKeyPress(.rightArrow) { advance(); return .handled }
        .onKeyPress(.leftArrow) { back(); return .handled }
        .focusable()
        .focusEffectDisabled()
        .onDisappear {
            // However the sheet went away, a person has seen it — never nag twice.
            Onboarding.markCompleted()
        }
    }

    // MARK: - Chrome

    private var header: some View {
        HStack {
            OnboardingProgress(current: page, accent: env.theme.accent)
            Spacer()
            if !page.isLast {
                Button("Skip") { finish() }
                    .buttonStyle(.plain)
                    .foregroundStyle(.secondary)
                    .keyboardShortcut(.cancelAction)
                    .accessibilityHint("Skip the introduction")
            }
        }
        .frame(height: 24)
    }

    private var footer: some View {
        HStack(spacing: Tokens.Spacing.md) {
            Button("Back") { back() }
                .buttonStyle(.glass)
                .controlSize(.large)
                .opacity(page.previous == nil ? 0 : 1)
                .disabled(page.previous == nil)
            Spacer()
            VStack(spacing: Tokens.Spacing.xs) {
                Button(page.continueTitle) { advance() }
                    .buttonStyle(.glassProminent)
                    .controlSize(.extraLarge)
                    .keyboardShortcut(.defaultAction)
                Text("Press ↩ to continue")
                    .font(.caption2)
                    .foregroundStyle(.tertiary)
            }
            Spacer()
            // Balances the Back button so Continue stays centered.
            Button("Back") {}
                .buttonStyle(.glass)
                .controlSize(.large)
                .hidden()
        }
    }

    @ViewBuilder
    private var pageContent: some View {
        switch page {
        case .welcome: WelcomePage()
        case .look: LookPage()
        case .clusters: ClustersPage()
        case .tools: ToolsPage()
        case .shortcuts: ShortcutsPage()
        case .ready: ReadyPage()
        }
    }

    // MARK: - Navigation

    private var pageTransition: AnyTransition {
        if reduceMotion { return .opacity }
        let inset: CGFloat = goingForward ? 64 : -64
        return .asymmetric(
            insertion: .modifier(active: PageShift(x: inset, opacity: 0, scale: 1),
                                 identity: PageShift(x: 0, opacity: 1, scale: 1)),
            removal: .modifier(active: PageShift(x: 0, opacity: 0, scale: 0.97),
                               identity: PageShift(x: 0, opacity: 1, scale: 1)))
    }

    private func advance() {
        guard let next = page.next else {
            finish()
            return
        }
        goingForward = true
        Log.debug("Onboarding: \(page) → \(next)", .ui)
        withAnimation(.spring(duration: 0.55, bounce: 0.12)) { page = next }
    }

    private func back() {
        guard let previous = page.previous else { return }
        goingForward = false
        Log.debug("Onboarding: \(page) → \(previous)", .ui)
        withAnimation(.spring(duration: 0.55, bounce: 0.12)) { page = previous }
    }

    private func finish() {
        Log.info("Onboarding finished on \(page)", .ui)
        Onboarding.markCompleted()
        dismiss()
    }
}

/// Offset + fade (+ tiny scale) used for page changes.
private struct PageShift: ViewModifier {
    var x: CGFloat
    var opacity: Double
    var scale: CGFloat

    func body(content: Content) -> some View {
        content
            .offset(x: x)
            .opacity(opacity)
            .scaleEffect(scale)
    }
}

/// Arc-style segmented progress: one pill per page, filled up to the current one.
private struct OnboardingProgress: View {
    let current: OnboardingPage
    let accent: Color

    var body: some View {
        HStack(spacing: 6) {
            ForEach(OnboardingPage.allCases) { page in
                Capsule()
                    .fill(page.rawValue <= current.rawValue
                          ? AnyShapeStyle(accent) : AnyShapeStyle(.quaternary))
                    .frame(width: page == current ? 28 : 14, height: 5)
            }
        }
        .animation(.snappy, value: current)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Step \(current.rawValue + 1) of \(OnboardingPage.allCases.count)")
    }
}

// MARK: - Shared building blocks (used by the pages)

/// Staggered entrance: fade + rise + un-blur after `delay` seconds. Every page
/// is rebuilt when shown (`.id(page)`), so `onAppear` fires per visit.
struct Reveal: ViewModifier {
    let delay: Double
    @State private var shown = false
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    func body(content: Content) -> some View {
        content
            .opacity(shown ? 1 : 0)
            .offset(y: shown ? 0 : 18)
            .blur(radius: shown ? 0 : 6)
            .onAppear {
                if reduceMotion {
                    shown = true
                } else {
                    withAnimation(.spring(duration: 0.7, bounce: 0.16).delay(delay)) {
                        shown = true
                    }
                }
            }
    }
}

extension View {
    func reveal(delay: Double = 0) -> some View { modifier(Reveal(delay: delay)) }
}

/// Page headline block shared by all pages after the welcome.
struct OnboardingTitle: View {
    let eyebrow: String
    let title: String
    let subtitle: String

    var body: some View {
        VStack(spacing: Tokens.Spacing.sm) {
            Text(eyebrow.uppercased())
                .font(.caption.weight(.semibold))
                .tracking(1.2)
                .foregroundStyle(.secondary)
                .reveal(delay: 0)
            Text(title)
                .font(.system(size: 34, weight: .bold, design: .rounded))
                .reveal(delay: 0.05)
            Text(subtitle)
                .font(.title3)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .frame(maxWidth: 560)
                .reveal(delay: 0.1)
        }
        .multilineTextAlignment(.center)
    }
}

/// A rounded Liquid Glass panel used for the interactive widgets.
struct GlassPanel<Content: View>: View {
    var cornerRadius: CGFloat = Tokens.Radius.lg
    @ViewBuilder let content: Content

    var body: some View {
        content
            .glassEffect(in: .rect(cornerRadius: cornerRadius))
    }
}
