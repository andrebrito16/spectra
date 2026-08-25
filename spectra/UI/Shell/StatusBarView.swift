//
//  StatusBarView.swift
//  Spectra
//
//  Thin bottom status bar: active cluster + connection + server version (left),
//  background activity + notifications + dock toggle (right).
//

import SwiftUI

struct StatusBarView: View {
    @Environment(\.appEnv) private var env

    private var activeState: ClusterConnectionState? {
        guard let id = env.clusters.activeClusterId else { return nil }
        return env.clusters.states[id]
    }

    private var activeName: String? {
        guard let id = env.clusters.activeClusterId else { return nil }
        return env.clusters.record(id: id)?.effectiveName
    }

    var body: some View {
        HStack(spacing: Tokens.Spacing.md) {
            if let activeName, let state = activeState {
                HStack(spacing: Tokens.Spacing.xs) {
                    StatusDot(status: state.status.status)
                    Text(activeName).font(.caption)
                    if let version = state.serverVersion {
                        Text(version).font(.caption).foregroundStyle(.secondary)
                    } else {
                        Text(state.status.label).font(.caption).foregroundStyle(.secondary)
                    }
                }
            } else {
                HStack(spacing: Tokens.Spacing.xs) {
                    StatusDot(status: .neutral)
                    Text("No cluster connected").font(.caption).foregroundStyle(.secondary)
                }
            }

            Spacer()

            if !env.notifications.items.isEmpty {
                Label("\(env.notifications.items.count)", systemImage: "bell.fill")
                    .font(.caption).foregroundStyle(.secondary)
            }

            Button {
                withAnimation(.snappy) { env.navigation.dockOpen.toggle() }
            } label: {
                Image(systemName: "square.bottomhalf.filled")
            }
            .buttonStyle(.plain)
            .help("Toggle dock (⌘`)")
            .accessibilityLabel("Toggle dock")
        }
        .padding(.horizontal, Tokens.Spacing.md)
        .frame(height: 24)
        .background(.bar)
        .overlay(alignment: .top) { Divider() }
    }
}
