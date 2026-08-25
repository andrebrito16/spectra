//
//  ScaleDialog.swift
//  Spectra
//
//  Replica scaling dialog presented by the list/drawer for scalable workloads.
//  Uses the scale subresource via the API client.
//

import SwiftUI

struct ScaleDialog: View {
    let resource: KubeResource
    let session: ClusterSession

    @Environment(\.dismiss) private var dismiss
    @Environment(\.appEnv) private var env
    @State private var replicas: Int
    @State private var applying = false

    init(resource: KubeResource, session: ClusterSession) {
        self.resource = resource
        self.session = session
        _replicas = State(initialValue: resource.spec?["replicas"]?.intValue ?? 1)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: Tokens.Spacing.lg) {
            Text("Scale \(resource.kind ?? "")").font(.headline)
            Text(resource.scopedName).font(.caption).foregroundStyle(.secondary)
            Stepper(value: $replicas, in: 0...1000) {
                HStack {
                    Text("Replicas")
                    Spacer()
                    TextField("", value: $replicas, format: .number)
                        .frame(width: 60)
                        .multilineTextAlignment(.trailing)
                }
            }
            HStack {
                Spacer()
                Button("Cancel") { dismiss() }
                Button("Scale") { apply() }
                    .keyboardShortcut(.defaultAction)
                    .disabled(applying)
            }
        }
        .padding(Tokens.Spacing.xl)
        .frame(width: 320)
    }

    private func apply() {
        guard let kind = resource.kind, let gvr = session.gvr(forKind: kind) else { return }
        applying = true
        Task {
            defer { applying = false }
            do {
                _ = try await session.client.updateScale(gvr, namespace: resource.namespace,
                                                         name: resource.name, replicas: replicas)
                env.notifications.notify(.success, "Scaled \(resource.name) to \(replicas)")
                dismiss()
            } catch {
                env.notifications.notify(.error, "Scale failed", message: error.localizedDescription)
            }
        }
    }
}
