//
//  NodeDetail.swift
//  Spectra
//
//  Node detail sections: addresses + node info, capacity/allocatable, taints,
//  and the live list of pods scheduled on the node.
//

import SwiftUI

struct NodeInfoSection: View {
    let resource: KubeResource

    private var addresses: [JSONValue] { resource.status?["addresses"]?.arrayValue ?? [] }
    private var nodeInfo: JSONValue? { resource.status?["nodeInfo"] }
    private var taints: [JSONValue] { resource.spec?["taints"]?.arrayValue ?? [] }

    var body: some View {
        DetailCard(title: "Node") {
            VStack(alignment: .leading, spacing: Tokens.Spacing.xs) {
                HStack {
                    Badge(text: resource.nodeReady ? "Ready" : "NotReady",
                          status: resource.nodeReady ? .success : .error)
                    if resource.nodeUnschedulable {
                        Badge(text: "SchedulingDisabled", status: .warning)
                    }
                    Spacer()
                }
                DetailRow(label: "Roles", value: resource.nodeRoles)
                ForEach(Array(addresses.enumerated()), id: \.offset) { _, address in
                    DetailRow(label: address["type"]?.stringValue ?? "Address",
                              value: address["address"]?.stringValue ?? "—")
                }
                if let info = nodeInfo {
                    DetailRow(label: "OS Image", value: info["osImage"]?.stringValue ?? "—")
                    DetailRow(label: "Kernel", value: info["kernelVersion"]?.stringValue ?? "—")
                    DetailRow(label: "Container Runtime",
                              value: info["containerRuntimeVersion"]?.stringValue ?? "—")
                    DetailRow(label: "Kubelet", value: info["kubeletVersion"]?.stringValue ?? "—")
                    DetailRow(label: "Architecture", value: info["architecture"]?.stringValue ?? "—")
                }
                if !taints.isEmpty {
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Taints").font(.callout).foregroundStyle(.secondary)
                        ForEach(Array(taints.enumerated()), id: \.offset) { _, taint in
                            let key = taint["key"]?.stringValue ?? ""
                            let value = taint["value"]?.stringValue ?? ""
                            let effect = taint["effect"]?.stringValue ?? ""
                            Text("\(key)=\(value):\(effect)").font(.caption).textSelection(.enabled)
                        }
                    }
                }
            }
        }
    }
}

struct PodsOnNodeSection: View {
    let resource: KubeResource
    let session: ClusterSession
    @State private var store: ResourceStore?

    private var pods: [KubeResource] {
        (store?.items ?? []).filter { $0.nodeName == resource.name }
    }

    var body: some View {
        DetailCard(title: "Pods (\(pods.count))") {
            if pods.isEmpty {
                Text("No pods").font(.caption).foregroundStyle(.tertiary)
            } else {
                VStack(alignment: .leading, spacing: 2) {
                    ForEach(pods.prefix(50)) { pod in
                        HStack {
                            StatusDot(status: pod.podStatusColor)
                            Text(pod.scopedName).font(.caption)
                            Spacer()
                            Text(pod.podDisplayStatus).font(.caption2).foregroundStyle(.secondary)
                        }
                    }
                }
            }
        }
        .onAppear { subscribe() }
        .onDisappear { store?.unsubscribe() }
    }

    private func subscribe() {
        guard let gvr = session.gvr(forKind: "Pod") else { return }
        let store = session.store(for: gvr)
        self.store = store
        store.subscribe(namespaces: [])
    }
}
