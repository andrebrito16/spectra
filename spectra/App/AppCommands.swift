//
//  AppCommands.swift
//  Spectra
//
//  Menu-bar commands wired to NavigationModel + ClusterManager, kept in sync with
//  the command palette and in-view hotkeys (single shortcut definition each).
//

import SwiftUI

struct SpectraCommands: Commands {
    let env: AppEnvironment

    var body: some Commands {
        CommandGroup(replacing: .newItem) {
            Button("Add Cluster…") { env.navigation.showAddCluster = true }
                .keyboardShortcut("n", modifiers: [.command, .shift])
            Button("Open Kubeconfig…") { env.navigation.showAddCluster = true }
                .keyboardShortcut("o", modifiers: .command)
        }

        CommandMenu("Cluster") {
            if let id = env.clusters.activeClusterId {
                let connected = env.clusters.states[id]?.status.isConnected ?? false
                if connected {
                    Button("Disconnect") { Task { await env.clusters.disconnect(id: id) } }
                } else {
                    Button("Connect") { Task { await env.clusters.connect(id: id) } }
                }
            }
            Divider()
            Button("Next Cluster") { env.switchCluster(delta: 1) }
                .keyboardShortcut(.rightArrow, modifiers: [.command, .option])
                .disabled(env.clusters.records.count < 2)
            Button("Previous Cluster") { env.switchCluster(delta: -1) }
                .keyboardShortcut(.leftArrow, modifiers: [.command, .option])
                .disabled(env.clusters.records.count < 2)
            Divider()
            Button("Show Catalog") { env.showCatalog() }
        }

        CommandMenu("Navigate") {
            Button("Back") { env.navigation.goBack() }
                .keyboardShortcut("[", modifiers: .command)
                .disabled(!env.navigation.canGoBack)
            Button("Forward") { env.navigation.goForward() }
                .keyboardShortcut("]", modifiers: .command)
                .disabled(!env.navigation.canGoForward)
            Divider()
            Button("Command Palette…") { env.navigation.showCommandPalette = true }
                .keyboardShortcut("k", modifiers: .command)
                .disabled(env.clusters.activeSession == nil && env.clusters.records.isEmpty)
        }

        CommandGroup(after: .toolbar) {
            Button("Toggle Dock") { env.navigation.dockOpen.toggle() }
                .keyboardShortcut("`", modifiers: .command)
            Button("New Terminal") { env.openLocalTerminal() }
                .keyboardShortcut("t", modifiers: .command)
                .disabled(env.clusters.activeSession == nil)
        }

        CommandGroup(replacing: .help) {
            Button("Open Source Licenses") {
                if let url = Bundle.main.url(forResource: "OpenSourceNotices", withExtension: "txt")
                    ?? Bundle.main.url(forResource: "OpenSourceNotices", withExtension: "txt", subdirectory: "Resources") {
                    NSWorkspace.shared.open(url)
                }
            }
            Button("Check for Updates…") { env.updater.checkForUpdates() }
            Divider()
            Button("Keyboard Shortcuts") { env.navigation.showShortcuts = true }
                .keyboardShortcut("/", modifiers: .command)
            Button("Reveal Diagnostics Logs") { Diagnostics.revealLogs() }
        }
    }
}
