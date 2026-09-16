//
//  ObjectActions.swift
//  Spectra
//
//  Shared object-action model used by row context menus, the bulk toolbar, and
//  the drawer toolbar. Universal actions (edit/delete/force-delete/finalizers/
//  copy-yaml) plus kind-specific actions contributed by feature phases.
//

import SwiftUI
import AppKit

/// Some actions are handled by the host (they need UI or app-level services like
/// the dock and port-forward manager) rather than a plain cluster mutation.
enum ActionInteraction: Equatable {
    case scale
    case logs
    case shell
    case nodeShell
    case portForward
}

@MainActor
struct ObjectAction: Identifiable {
    let id: String
    let title: String
    let systemImage: String
    var role: ButtonRole?
    /// Confirmation message; nil means perform immediately.
    var confirm: String?
    /// Interactive input required (e.g. scale); the host presents the dialog.
    var interaction: ActionInteraction?
    var isAvailable: (KubeResource) -> Bool
    let perform: (KubeResource, ClusterSession) async throws -> Void

    init(id: String, title: String, systemImage: String, role: ButtonRole? = nil,
         confirm: String? = nil, interaction: ActionInteraction? = nil,
         isAvailable: @escaping (KubeResource) -> Bool = { _ in true },
         perform: @escaping (KubeResource, ClusterSession) async throws -> Void) {
        self.id = id
        self.title = title
        self.systemImage = systemImage
        self.role = role
        self.confirm = confirm
        self.interaction = interaction
        self.isAvailable = isAvailable
        self.perform = perform
    }
}

@MainActor
enum UniversalActions {
    /// Edit + View YAML need UI callbacks to open the editor; the rest act on the cluster.
    static func make(onEdit: @escaping (KubeResource) -> Void,
                     onViewYAML: @escaping (KubeResource) -> Void) -> [ObjectAction] {
        [
            ObjectAction(id: "edit", title: "Edit", systemImage: "pencil") { resource, _ in
                await MainActor.run { onEdit(resource) }
            },
            ObjectAction(id: "view-yaml", title: "View YAML", systemImage: "doc.text") { resource, _ in
                await MainActor.run { onViewYAML(resource) }
            },
            ObjectAction(id: "copy-yaml", title: "Copy YAML", systemImage: "doc.on.doc") { resource, _ in
                let yaml = (try? resource.yamlString()) ?? ""
                NSPasteboard.general.clearContents()
                NSPasteboard.general.setString(yaml, forType: .string)
            },
            ObjectAction(id: "delete", title: "Delete", systemImage: "trash", role: .destructive,
                         confirm: "Delete this resource?") { resource, session in
                try await deleteResource(resource, session: session, force: false)
            },
            ObjectAction(id: "force-delete", title: "Force Delete", systemImage: "trash.slash",
                         role: .destructive, confirm: "Force-delete (grace period 0)?") { resource, session in
                try await deleteResource(resource, session: session, force: true)
            },
            ObjectAction(id: "remove-finalizers", title: "Remove Finalizers",
                         systemImage: "xmark.bin", role: .destructive,
                         confirm: "Force-remove finalizers? This can orphan resources.",
                         isAvailable: { !$0.finalizers.isEmpty }) { resource, session in
                try await removeFinalizers(resource, session: session)
            },
        ]
    }

    static func deleteResource(_ resource: KubeResource, session: ClusterSession, force: Bool) async throws {
        guard let kind = resource.kind, let gvr = session.gvr(forKind: kind, group: resource.apiGroup) else {
            throw KubeError.notFound("no GVR for kind \(resource.kind ?? "?")")
        }
        try await session.client.delete(gvr, namespace: resource.namespace, name: resource.name,
                                        gracePeriodSeconds: force ? 0 : nil)
    }

    static func removeFinalizers(_ resource: KubeResource, session: ClusterSession) async throws {
        guard let kind = resource.kind, let gvr = session.gvr(forKind: kind, group: resource.apiGroup) else {
            throw KubeError.notFound("no GVR for kind \(resource.kind ?? "?")")
        }
        let patch: [String: JSONValue] = ["metadata": .object(["finalizers": .null])]
        let data = try JSONEncoder().encode(JSONValue.object(patch))
        _ = try await session.client.patch(gvr, namespace: resource.namespace,
                                           name: resource.name, data: data, type: .merge)
    }
}
