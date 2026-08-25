//
//  SpectraControls.swift
//  Spectra
//
//  Reusable SwiftUI controls built on native Liquid Glass styling. Grown over
//  time; Phase 1 ships the ones the shell needs (badge, status dot, search
//  field, spinner, empty state, glass button).
//

import SwiftUI

/// A small status pill, e.g. pod phase or connection state.
struct Badge: View {
    let text: String
    var status: SpectraStatus = .neutral

    var body: some View {
        Text(text)
            .font(.caption2.weight(.medium))
            .padding(.horizontal, Tokens.Spacing.sm)
            .padding(.vertical, Tokens.Spacing.xxs)
            .background(status.color.opacity(0.18), in: Capsule())
            .foregroundStyle(status.color)
            .accessibilityLabel("\(text) status")
    }
}

/// A colored status dot (connection/health indicators).
struct StatusDot: View {
    var status: SpectraStatus
    var diameter: CGFloat = 8

    var body: some View {
        Circle()
            .fill(status.color)
            .frame(width: diameter, height: diameter)
            .accessibilityHidden(true)
    }
}

/// A search field with a leading magnifier and clear button.
struct SearchField: View {
    let placeholder: String
    @Binding var text: String

    var body: some View {
        HStack(spacing: Tokens.Spacing.xs) {
            Image(systemName: "magnifyingglass")
                .foregroundStyle(.secondary)
            TextField(placeholder, text: $text)
                .textFieldStyle(.plain)
            if !text.isEmpty {
                Button {
                    text = ""
                } label: {
                    Image(systemName: "xmark.circle.fill")
                        .foregroundStyle(.secondary)
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Clear search")
            }
        }
        .padding(.horizontal, Tokens.Spacing.sm)
        .padding(.vertical, Tokens.Spacing.xs)
        .background(.quaternary, in: RoundedRectangle(cornerRadius: Tokens.Radius.sm))
    }
}

/// Indeterminate spinner with optional label.
struct Spinner: View {
    var label: String?

    var body: some View {
        HStack(spacing: Tokens.Spacing.sm) {
            ProgressView()
                .controlSize(.small)
            if let label {
                Text(label).foregroundStyle(.secondary)
            }
        }
    }
}

/// "No items" / empty-state placeholder.
struct EmptyStateView: View {
    let title: String
    var systemImage: String = "tray"
    var message: String?
    var action: (() -> Void)?
    var actionLabel: String?

    var body: some View {
        ContentUnavailableView {
            Label(title, systemImage: systemImage)
        } description: {
            if let message { Text(message) }
        } actions: {
            if let action, let actionLabel {
                Button(actionLabel, action: action)
                    .buttonStyle(.glassProminent)
            }
        }
    }
}

/// A primary action button wrapping the native glass style.
struct SpectraButton: View {
    let title: String
    var systemImage: String?
    var prominent: Bool = false
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            if let systemImage {
                Label(title, systemImage: systemImage)
            } else {
                Text(title)
            }
        }
        .buttonStyle(prominent ? AnyPrimitiveButtonStyle(.glassProminent)
                               : AnyPrimitiveButtonStyle(.glass))
    }
}

/// Type-erased button style so `SpectraButton` can switch between glass variants.
struct AnyPrimitiveButtonStyle: PrimitiveButtonStyle {
    private let makeBodyClosure: (Configuration) -> AnyView

    init<S: PrimitiveButtonStyle>(_ style: S) {
        makeBodyClosure = { configuration in
            AnyView(style.makeBody(configuration: configuration))
        }
    }

    func makeBody(configuration: Configuration) -> some View {
        makeBodyClosure(configuration)
    }
}
