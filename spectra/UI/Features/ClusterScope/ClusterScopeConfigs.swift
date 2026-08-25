//
//  ClusterScopeConfigs.swift
//  Spectra
//
//  Registers cluster-scope kinds: Node (with cordon/uncordon/drain), Namespace,
//  Event (global list), and CustomResourceDefinition. Custom-resource instances
//  derive their columns from the CRD's printer columns (see ClusterSession).
//

import SwiftUI

@MainActor
enum NodeActions {
    static let cordon = ObjectAction(
        id: "cordon", title: "Cordon", systemImage: "nosign",
        isAvailable: { !$0.nodeUnschedulable },
        perform: { node, session in try await setUnschedulable(node, session: session, value: true) })

    static let uncordon = ObjectAction(
        id: "uncordon", title: "Uncordon", systemImage: "checkmark.circle",
        isAvailable: { $0.nodeUnschedulable },
        perform: { node, session in try await setUnschedulable(node, session: session, value: false) })

    static let drain = ObjectAction(
        id: "drain", title: "Drain", systemImage: "arrow.down.to.line",
        confirm: "Cordon and evict all non-DaemonSet pods from this node?",
        perform: { node, session in try await drainNode(node, session: session) })

    private static func setUnschedulable(_ node: KubeResource, session: ClusterSession,
                                         value: Bool) async throws {
        guard let gvr = session.gvr(forKind: "Node") else { throw KubeError.notFound("Node GVR") }
        let patch: JSONValue = .object(["spec": .object(["unschedulable": .bool(value)])])
        let data = try JSONEncoder().encode(patch)
        _ = try await session.client.patch(gvr, namespace: nil, name: node.name,
                                           data: data, type: .merge)
    }

    private static func drainNode(_ node: KubeResource, session: ClusterSession) async throws {
        try await setUnschedulable(node, session: session, value: true)
        guard let podGVR = session.gvr(forKind: "Pod") else { return }
        let pods = try await session.client.list(podGVR, namespace: nil,
                                                 fieldSelector: "spec.nodeName=\(node.name)")
        for pod in pods.items {
            let isDaemon = pod.ownerReferences.contains { $0.kind == "DaemonSet" }
            let isMirror = pod.annotations["kubernetes.io/config.mirror"] != nil
            if isDaemon || isMirror { continue }
            guard let namespace = pod.namespace else { continue }
            try? await session.client.evict(namespace: namespace, podName: pod.name)
        }
    }
}

@MainActor
enum ClusterScopeConfigs {
    static func register(into catalog: ResourceCatalog) {
        catalog.register("Node", ResourceConfig(
            columns: [
                Columns.name,
                ColumnDefinition(id: "status", title: "Status", width: 90,
                                 status: { $0.nodeReady ? .success : .error }) {
                    $0.nodeReady ? "Ready" : "NotReady"
                },
                ColumnDefinition(id: "roles", title: "Roles", width: 140) { $0.nodeRoles },
                ColumnDefinition(id: "taints", title: "Taints", width: 56, alignment: .trailing,
                                 cell: { AnyView(NodeTaintsCell(node: $0)) }) {
                    "\($0.nodeTaints.count)"
                },
                ColumnDefinition(id: "version", title: "Version", width: 120) {
                    $0.kubeletVersion ?? "—"
                },
                ColumnDefinition(id: "cpu", title: "CPU", width: 110,
                                 cell: { AnyView(NodeUsageCell(node: $0, metric: .cpu)) }) { _ in "" },
                ColumnDefinition(id: "memory", title: "Memory", width: 130,
                                 cell: { AnyView(NodeUsageCell(node: $0, metric: .memory)) }) { _ in "" },
                Columns.age,
            ],
            detailSections: [
                DetailSectionDef(id: "node-info", title: "Node") { r, _ in
                    AnyView(NodeInfoSection(resource: r))
                },
                DetailSectionDef(id: "node-pods", title: "Pods") { r, s in
                    AnyView(PodsOnNodeSection(resource: r, session: s))
                },
                DetailSectionDef(id: "node-metrics", title: "Metrics") { r, s in
                    AnyView(MetricsSection(resource: r, session: s))
                },
            ],
            actions: [NodeActions.cordon, NodeActions.uncordon, NodeActions.drain,
                      DockActions.nodeShell]))

        registerNamespaceAndEvents(catalog)
    }

    private static func registerNamespaceAndEvents(_ catalog: ResourceCatalog) {
        catalog.register("Namespace", ResourceConfig(columns: [
            Columns.name,
            ColumnDefinition(id: "status", title: "Status", width: 110,
                             status: { $0.status?["phase"]?.stringValue == "Active" ? .success : .warning }) {
                $0.status?["phase"]?.stringValue ?? "—"
            },
            Columns.age,
        ]))

        catalog.register("Event", ResourceConfig(columns: [
            ColumnDefinition(id: "type", title: "Type", width: 80,
                             status: { $0.json["type"]?.stringValue == "Warning" ? .warning : .info }) {
                $0.json["type"]?.stringValue ?? "Normal"
            },
            ColumnDefinition(id: "reason", title: "Reason", width: 140) {
                $0.json["reason"]?.stringValue ?? "—"
            },
            ColumnDefinition(id: "object", title: "Object", width: 200) {
                let kind = $0.value(at: ["involvedObject", "kind"])?.stringValue ?? "?"
                let name = $0.value(at: ["involvedObject", "name"])?.stringValue ?? "?"
                return "\(kind)/\(name)"
            },
            ColumnDefinition(id: "message", title: "Message") {
                $0.json["message"]?.stringValue ?? ""
            },
            ColumnDefinition(id: "count", title: "Count", width: 56, alignment: .trailing) {
                "\($0.json["count"]?.intValue ?? 1)"
            },
            ColumnDefinition(id: "age", title: "Last Seen", width: 80, alignment: .trailing) {
                $0.value(at: ["lastTimestamp"])?.stringValue
                    .flatMap(CredentialProvider.parseTimestamp)?.k8sAge ?? "—"
            },
        ]))

        catalog.register("CustomResourceDefinition", ResourceConfig(columns: [
            Columns.name,
            ColumnDefinition(id: "group", title: "Group", width: 200) {
                $0.spec?["group"]?.stringValue ?? "—"
            },
            ColumnDefinition(id: "scope", title: "Scope", width: 110) {
                $0.spec?["scope"]?.stringValue ?? "—"
            },
            Columns.age,
        ]))
    }
}

/// Taint count cell; resting the cursor on a non-zero count pops the full
/// taint list ("key=value:Effect"), Lens-style. The popover is debounced —
/// it only opens after the cursor RESTS on the cell, so sweeping the mouse
/// down the list doesn't flash a popover per row.
struct NodeTaintsCell: View {
    let node: KubeResource
    @State private var showPopover = false
    @State private var hoverTask: Task<Void, Never>?

    private static let restDelay: Duration = .milliseconds(300)

    var body: some View {
        let taints = node.nodeTaints
        Text("\(taints.count)")
            .monospacedDigit()  // proportional digits right-align raggedly (1 vs 0)
            .foregroundStyle(taints.isEmpty ? AnyShapeStyle(.tertiary) : AnyShapeStyle(.primary))
            .frame(maxWidth: .infinity, alignment: .trailing)
            .contentShape(Rectangle())
            .onHover { inside in
                hoverTask?.cancel()
                hoverTask = nil
                if inside, !taints.isEmpty {
                    hoverTask = Task {
                        try? await Task.sleep(for: Self.restDelay)
                        guard !Task.isCancelled else { return }
                        showPopover = true
                    }
                } else {
                    showPopover = false
                }
            }
            .popover(isPresented: $showPopover, arrowEdge: .bottom) {
                VStack(alignment: .leading, spacing: Tokens.Spacing.xs) {
                    ForEach(taints, id: \.self) { taint in
                        Text(taint).font(.caption.monospaced())
                    }
                }
                .padding(Tokens.Spacing.md)
            }
    }
}
