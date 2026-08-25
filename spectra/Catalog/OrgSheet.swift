//
//  OrgSheet.swift
//  Spectra
//
//  Create or rename a cluster Org (organization). Orgs are local groupings of
//  clusters in the catalog — they don't touch any kubeconfig.
//

import SwiftUI

/// What an org sheet should do — drives a single `.sheet(item:)` so create and
/// rename can't collide the way two `.sheet(isPresented:)` modifiers do.
enum OrgSheetTarget: Identifiable {
    case create
    case rename(ClusterOrg)

    var id: String {
        switch self {
        case .create: return "create"
        case .rename(let org): return "rename-\(org.id)"
        }
    }

    var org: ClusterOrg? {
        if case .rename(let org) = self { return org }
        return nil
    }
}

struct OrgSheet: View {
    /// nil = create a new org; non-nil = rename the given org.
    let org: ClusterOrg?

    @Environment(\.appEnv) private var env
    @Environment(\.dismiss) private var dismiss
    @State private var name: String

    init(org: ClusterOrg?) {
        self.org = org
        _name = State(initialValue: org?.name ?? "")
    }

    private var trimmed: String { name.trimmingCharacters(in: .whitespaces) }

    var body: some View {
        VStack(alignment: .leading, spacing: Tokens.Spacing.md) {
            Text(org == nil ? "New Org" : "Rename Org").font(.headline)
            TextField("Org name", text: $name)
                .textFieldStyle(.roundedBorder)
                .onSubmit(save)
            HStack {
                Spacer()
                Button("Cancel") { dismiss() }
                Button("Save") { save() }
                    .keyboardShortcut(.defaultAction)
                    .disabled(trimmed.isEmpty)
            }
        }
        .padding(Tokens.Spacing.xl)
        .frame(width: 360)
    }

    private func save() {
        guard !trimmed.isEmpty else { return }
        if let org {
            env.clusters.renameOrg(org, to: trimmed)
        } else {
            env.clusters.createOrg(name: trimmed)
        }
        dismiss()
    }
}
