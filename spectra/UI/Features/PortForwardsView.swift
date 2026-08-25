//
//  PortForwardsView.swift
//  Spectra
//
//  Management view for active port-forwards (backed by PortForwardManager).
//  Start from Service/Pod actions; stop / open-in-browser here.
//

import SwiftUI
import AppKit

struct PortForwardsView: View {
    let session: ClusterSession
    @Environment(\.appEnv) private var env

    private var forwards: [PortForwardManager.Forward] {
        env.portForwards.forwards(forCluster: session.id)
    }

    var body: some View {
        VStack(spacing: 0) {
            HStack {
                Text("Port Forwards").font(.title2.weight(.semibold))
                Spacer()
                Text("\(forwards.count) active").font(.caption).foregroundStyle(.secondary)
            }
            .padding(Tokens.Spacing.md)
            Divider()
            if forwards.isEmpty {
                EmptyStateView(title: "No port-forwards",
                               systemImage: "arrow.left.arrow.right",
                               message: "Start one from a Service or Pod’s actions.")
            } else {
                List(forwards) { forward in
                    HStack(spacing: Tokens.Spacing.sm) {
                        StatusDot(status: forward.status)
                        VStack(alignment: .leading, spacing: 0) {
                            Text("\(forward.kind)/\(forward.name)").font(.callout)
                            Text(forward.namespace).font(.caption).foregroundStyle(.secondary)
                        }
                        Spacer()
                        Text("\(forward.localPort.map(String.init) ?? "—") → \(forward.remotePort)")
                            .font(.system(.caption, design: .monospaced))
                        Text(forward.statusText).font(.caption2).foregroundStyle(.secondary)
                        if let local = forward.localPort {
                            Button {
                                if let url = URL(string: "http://127.0.0.1:\(local)") {
                                    NSWorkspace.shared.open(url)
                                }
                            } label: { Image(systemName: "safari") }
                            .buttonStyle(.plain)
                            .help("Open in browser")
                        }
                        Button { env.portForwards.stop(id: forward.id) } label: {
                            Image(systemName: "stop.circle")
                        }
                        .buttonStyle(.plain)
                        .help("Stop")
                    }
                }
            }
        }
        .background(.background)
        .navigationTitle("Port Forwards")
    }
}
