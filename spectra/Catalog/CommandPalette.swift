//
//  CommandPalette.swift
//  Spectra
//
//  ⌘K overlay with fuzzy search over context-aware commands: navigate to any
//  resource kind, switch cluster, return to catalog, toggle dock. Commands are
//  generated from the active session. Mirrors Freelens's command palette.
//

import SwiftUI

struct PaletteCommand: Identifiable {
    let id: String
    let title: String
    let subtitle: String?
    let systemImage: String
    let run: () -> Void
}

struct CommandPalette: View {
    @Environment(\.appEnv) private var env
    @Environment(\.dismiss) private var dismiss
    @State private var query = ""
    @FocusState private var focused: Bool

    private var commands: [PaletteCommand] {
        var result: [PaletteCommand] = []

        if let session = env.clusters.activeSession {
            result.append(PaletteCommand(id: "overview", title: "Overview",
                                         subtitle: "Cluster", systemImage: "gauge") {
                env.navigation.navigate(to: .overview)
            })
            for group in NavGrouping.build(from: session.gvrs) {
                for entry in group.entries {
                    result.append(PaletteCommand(
                        id: "kind:\(entry.id)", title: entry.title,
                        subtitle: group.section.rawValue, systemImage: entry.icon) {
                        env.navigation.navigate(to: .kind(entry.id))
                    })
                }
                for sub in group.subgroups {
                    for entry in sub.entries {
                        result.append(PaletteCommand(
                            id: "kind:\(entry.id)", title: entry.title,
                            subtitle: sub.name, systemImage: entry.icon) {
                            env.navigation.navigate(to: .kind(entry.id))
                        })
                    }
                }
            }
            result.append(PaletteCommand(id: "toggle-dock", title: "Toggle Dock",
                                         subtitle: "View", systemImage: "square.bottomhalf.filled") {
                env.navigation.dockOpen.toggle()
            })
        }

        result.append(PaletteCommand(id: "catalog", title: "Show Catalog",
                                     subtitle: "Navigate", systemImage: "square.grid.2x2") {
            env.showCatalog()
        })
        for record in env.clusters.orderedRecords where record.id != env.clusters.activeClusterId {
            result.append(PaletteCommand(
                id: "switch:\(record.id)", title: "Switch to \(record.effectiveName)",
                subtitle: "Cluster", systemImage: "arrow.left.arrow.right") {
                env.openCluster(record.id)
            })
        }
        return result
    }

    private var filtered: [PaletteCommand] {
        guard !query.isEmpty else { return commands }
        let needle = query.lowercased()
        return commands.filter {
            $0.title.lowercased().contains(needle)
            || ($0.subtitle?.lowercased().contains(needle) ?? false)
        }
    }

    var body: some View {
        VStack(spacing: 0) {
            HStack(spacing: Tokens.Spacing.sm) {
                Image(systemName: "magnifyingglass").foregroundStyle(.secondary)
                TextField("Type a command…", text: $query)
                    .textFieldStyle(.plain)
                    .font(.title3)
                    .focused($focused)
                    .onSubmit { runFirst() }
            }
            .padding(Tokens.Spacing.md)

            Divider()

            List(filtered) { command in
                Button {
                    command.run()
                    dismiss()
                } label: {
                    HStack(spacing: Tokens.Spacing.sm) {
                        Image(systemName: command.systemImage)
                            .foregroundStyle(.secondary)
                            .frame(width: 20)
                        Text(command.title)
                        Spacer()
                        if let subtitle = command.subtitle {
                            Text(subtitle).font(.caption).foregroundStyle(.tertiary)
                        }
                    }
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
            }
            .listStyle(.plain)
        }
        .frame(width: 560, height: 420)
        .onAppear { focused = true }
    }

    private func runFirst() {
        if let first = filtered.first {
            first.run()
            dismiss()
        }
    }
}
