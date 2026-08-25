//
//  KeyboardShortcutsView.swift
//  Spectra
//
//  Discoverable list of keyboard shortcuts (Phase 4.8 / 12), kept in sync with
//  the menu bar and command palette.
//

import SwiftUI

struct KeyboardShortcutsView: View {
    @Environment(\.dismiss) private var dismiss

    private let shortcuts: [(String, String)] = [
        ("⌘K", "Command palette"),
        ("⌘T", "New terminal"),
        ("⌘`", "Toggle dock"),
        ("⌘[ / ⌘]", "Back / forward"),
        ("⇧⌘N", "Add cluster"),
        ("⌘O", "Open kubeconfig"),
        ("⌘/", "Keyboard shortcuts"),
        ("⌘,", "Preferences"),
    ]

    var body: some View {
        VStack(spacing: 0) {
            HStack {
                Text("Keyboard Shortcuts").font(.headline)
                Spacer()
                Button("Done") { dismiss() }.keyboardShortcut(.defaultAction)
            }
            .padding(Tokens.Spacing.md)
            Divider()
            List(shortcuts, id: \.0) { shortcut in
                HStack {
                    Text(shortcut.0)
                        .font(.system(.body, design: .monospaced))
                        .frame(width: 110, alignment: .leading)
                    Text(shortcut.1)
                    Spacer()
                }
            }
            .listStyle(.plain)
        }
        .frame(width: 420, height: 380)
    }
}
