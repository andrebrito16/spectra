//
//  PortForwardDialog.swift
//  Spectra
//
//  Presented before starting a `kubectl port-forward` so the user can choose the
//  local port on their Mac (text input) instead of always getting a system-picked
//  one. When the resource exposes several ports, the cluster-side port is pickable.
//

import SwiftUI

struct PortForwardDialog: View {
    let resource: KubeResource
    let session: ClusterSession

    @Environment(\.dismiss) private var dismiss
    @Environment(\.appEnv) private var env

    private let options: [PortOption]
    @State private var remotePort: Int
    @State private var localPortText: String
    @State private var openInBrowser = true
    /// The last auto-suggested local port — lets us refresh the default when the
    /// cluster port changes, without clobbering a value the user typed in.
    @State private var lastSuggested: Int

    init(resource: KubeResource, session: ClusterSession) {
        self.resource = resource
        self.session = session
        let opts = Self.portOptions(for: resource)
        self.options = opts
        let preferred = opts.first?.port ?? 80
        // Suggest the cluster port when it's free on this Mac, else a free port —
        // privileged (<1024) or busy cluster ports can't be bound locally.
        let suggested = LocalPort.suggest(preferred: preferred)
        _remotePort = State(initialValue: preferred)
        _localPortText = State(initialValue: String(suggested))
        _lastSuggested = State(initialValue: suggested)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: Tokens.Spacing.lg) {
            Text("Forward Port").font(.headline)
            Text(resource.scopedName).font(.caption).foregroundStyle(.secondary)

            HStack {
                Text("Cluster port")
                Spacer()
                if options.count > 1 {
                    Picker("", selection: $remotePort) {
                        ForEach(options) { Text($0.label).tag($0.port) }
                    }
                    .labelsHidden()
                    .frame(width: 160)
                } else {
                    Text(verbatim: "\(remotePort)").foregroundStyle(.secondary)
                }
            }

            HStack {
                Text("Local port")
                Spacer()
                TextField("auto", text: $localPortText)
                    .frame(width: 100)
                    .multilineTextAlignment(.trailing)
                    .onChange(of: localPortText) { _, new in
                        let digits = String(new.filter(\.isNumber).prefix(5))
                        if digits != new { localPortText = digits }
                    }
            }
            Text("Leave blank to let the system pick a free local port.")
                .font(.caption2).foregroundStyle(.secondary)

            Toggle("Open in browser when ready", isOn: $openInBrowser)
                .toggleStyle(.checkbox)

            HStack {
                Spacer()
                Button("Cancel") { dismiss() }
                Button("Forward") { start() }
                    .keyboardShortcut(.defaultAction)
                    .disabled(!isValid)
            }
        }
        .padding(Tokens.Spacing.xl)
        .frame(width: 360)
        .onChange(of: remotePort) { _, new in
            // Follow the cluster port with a fresh free-port suggestion, unless
            // the user typed their own local port.
            guard localPortText.isEmpty || localPortText == String(lastSuggested) else { return }
            let suggested = LocalPort.suggest(preferred: new)
            localPortText = String(suggested)
            lastSuggested = suggested
        }
    }

    /// Blank = auto (valid); otherwise must be a port in 1...65535.
    private var isValid: Bool {
        if localPortText.isEmpty { return true }
        guard let port = Int(localPortText) else { return false }
        return (1...65535).contains(port)
    }

    private func start() {
        let localPort = localPortText.isEmpty ? nil : Int(localPortText)
        env.startPortForward(resource, session: session,
                             remotePort: remotePort, localPort: localPort,
                             openInBrowser: openInBrowser)
        dismiss()
    }

    // MARK: - Ports

    struct PortOption: Identifiable, Hashable {
        let port: Int
        let label: String
        var id: Int { port }
    }

    /// Cluster-side ports exposed by the resource: `spec.ports[].port` for a
    /// Service, container ports otherwise. Falls back to 80 when none are declared.
    static func portOptions(for resource: KubeResource) -> [PortOption] {
        var raw: [(port: Int, name: String?)] = []
        if resource.kind == "Service" {
            for entry in resource.spec?["ports"]?.arrayValue ?? [] {
                if let port = entry["port"]?.intValue {
                    raw.append((port, entry["name"]?.stringValue))
                }
            }
        } else {
            for container in resource.containers {
                for entry in container["ports"]?.arrayValue ?? [] {
                    if let port = entry["containerPort"]?.intValue {
                        raw.append((port, entry["name"]?.stringValue))
                    }
                }
            }
        }
        if raw.isEmpty { raw = [(80, nil)] }
        return raw.map { port, name in
            PortOption(port: port, label: name.map { "\($0) (\(port))" } ?? "\(port)")
        }
    }
}
