//
//  NavGrouping.swift
//  Spectra
//
//  Static grouping map (kind → section + order + icon) plus a builder that turns
//  the discovered GVR table into an ordered sidebar tree. CRD-backed kinds fall
//  into the Custom Resources section automatically, so new CRDs appear with no
//  code changes.
//

import Foundation

nonisolated enum NavSection: String, CaseIterable, Identifiable, Sendable {
    case cluster = "Cluster"
    case workloads = "Workloads"
    case argoCD = "Argo CD"
    case config = "Config"
    case network = "Network"
    case storage = "Storage"
    case helm = "Helm"
    case accessControl = "Access Control"
    case customResources = "Custom Resources"

    var id: String { rawValue }
    var icon: String { ResourceKindIcon.symbol(forSection: rawValue) }
}

/// A leaf entry in the sidebar tree.
nonisolated struct SidebarEntry: Identifiable, Sendable, Hashable {
    let id: String          // GVR id
    let title: String       // plural kind label
    let kind: String
    let icon: String
}

/// CRD kinds bucketed by their API group ("karpenter.sh" → NodeClaims, …),
/// shown as a collapsible subtree under Custom Resources, Lens-style.
nonisolated struct SidebarSubgroup: Identifiable, Sendable {
    let name: String        // API group
    let entries: [SidebarEntry]
    var id: String { name }
}

nonisolated struct SidebarSection: Identifiable, Sendable {
    let section: NavSection
    let entries: [SidebarEntry]
    let subgroups: [SidebarSubgroup]
    var id: String { section.id }
}

nonisolated enum NavGrouping {
    /// Match custom kinds by API group as well: unrelated controllers can both
    /// define a Gateway or Application without sharing its schema.
    static let customKindSection: [String: (section: NavSection, order: Int, title: String)] = [
        "argoproj.io/Application": (.argoCD, 0, "Applications"),
        "argoproj.io/ApplicationSet": (.argoCD, 1, "Application Sets"),
        "argoproj.io/AppProject": (.argoCD, 2, "Projects"),
        "argoproj.io/Rollout": (.argoCD, 3, "Rollouts"),
        "argoproj.io/AnalysisRun": (.argoCD, 4, "Analysis Runs"),
        "argoproj.io/AnalysisTemplate": (.argoCD, 5, "Analysis Templates"),
        "argoproj.io/ClusterAnalysisTemplate": (.argoCD, 6, "Cluster Analysis Templates"),
        "argoproj.io/Experiment": (.argoCD, 7, "Experiments"),
        "gateway.networking.k8s.io/Gateway": (.network, 6, "Gateways"),
        "gateway.networking.k8s.io/GatewayClass": (.network, 7, "Gateway Classes"),
        "gateway.networking.k8s.io/HTTPRoute": (.network, 8, "HTTP Routes"),
        "gateway.networking.k8s.io/GRPCRoute": (.network, 9, "GRPC Routes"),
        "gateway.networking.k8s.io/TLSRoute": (.network, 10, "TLS Routes"),
        "gateway.networking.k8s.io/TCPRoute": (.network, 11, "TCP Routes"),
        "gateway.networking.k8s.io/UDPRoute": (.network, 12, "UDP Routes"),
        "gateway.networking.k8s.io/ReferenceGrant": (.network, 13, "Reference Grants"),
    ]

    /// kind → (section, order within section).
    static let kindSection: [String: (NavSection, Int)] = [
        // Cluster
        "Node": (.cluster, 1), "Namespace": (.cluster, 2), "Event": (.cluster, 3),
        // Workloads
        "Pod": (.workloads, 0), "Deployment": (.workloads, 1), "DaemonSet": (.workloads, 2),
        "StatefulSet": (.workloads, 3), "ReplicaSet": (.workloads, 4),
        "ReplicationController": (.workloads, 5), "Job": (.workloads, 6), "CronJob": (.workloads, 7),
        // Config
        "ConfigMap": (.config, 0), "Secret": (.config, 1), "ResourceQuota": (.config, 2),
        "LimitRange": (.config, 3), "HorizontalPodAutoscaler": (.config, 4),
        "VerticalPodAutoscaler": (.config, 5), "PodDisruptionBudget": (.config, 6),
        "PriorityClass": (.config, 7), "RuntimeClass": (.config, 8), "Lease": (.config, 9),
        "MutatingWebhookConfiguration": (.config, 10),
        "ValidatingWebhookConfiguration": (.config, 11),
        // Network
        "Service": (.network, 0), "Endpoints": (.network, 1), "EndpointSlice": (.network, 2),
        "Ingress": (.network, 3), "IngressClass": (.network, 4), "NetworkPolicy": (.network, 5),
        // Storage
        "PersistentVolumeClaim": (.storage, 0), "PersistentVolume": (.storage, 1),
        "StorageClass": (.storage, 2),
        // Access Control
        "ServiceAccount": (.accessControl, 0), "Role": (.accessControl, 1),
        "ClusterRole": (.accessControl, 2), "RoleBinding": (.accessControl, 3),
        "ClusterRoleBinding": (.accessControl, 4),
        // Custom Resources (the CRD list lives here too)
        "CustomResourceDefinition": (.customResources, 0),
    ]

    /// Well-known built-in API groups; anything outside these (and not mapped
    /// above) is treated as a CRD kind and shown under Custom Resources.
    static let builtInGroups: Set<String> = [
        "", "apps", "batch", "autoscaling", "policy", "networking.k8s.io",
        "storage.k8s.io", "rbac.authorization.k8s.io", "scheduling.k8s.io",
        "coordination.k8s.io", "admissionregistration.k8s.io", "apiextensions.k8s.io",
        "authorization.k8s.io", "authentication.k8s.io", "certificates.k8s.io",
        "discovery.k8s.io", "events.k8s.io", "node.k8s.io",
        "flowcontrol.apiserver.k8s.io", "apiregistration.k8s.io",
        "autoscaling.k8s.io",
    ]

    /// Build the ordered sidebar tree from the discovered GVR table. CRD kinds
    /// are bucketed per API group under Custom Resources.
    static func build(from gvrs: [GroupVersionResource]) -> [SidebarSection] {
        var bySection: [NavSection: [(order: Int, entry: SidebarEntry)]] = [:]
        var crdByGroup: [String: [SidebarEntry]] = [:]
        var seenKinds: Set<String> = []
        var seenCRDs: Set<String> = []

        for gvr in gvrs where gvr.supports(verb: "list") {
            let key = "\(gvr.group)/\(gvr.kind)"
            if let mapping = customKindSection[key] {
                guard seenCRDs.insert(key).inserted else { continue }
                let entry = SidebarEntry(id: gvr.id, title: mapping.title, kind: gvr.kind,
                                         icon: ResourceKindIcon.symbol(forKind: gvr.kind))
                bySection[mapping.section, default: []].append((mapping.order, entry))
                continue
            }
            // Skip duplicate kinds (same kind served by multiple groups).
            let entry = SidebarEntry(id: gvr.id, title: titleCase(gvr.resource),
                                     kind: gvr.kind,
                                     icon: ResourceKindIcon.symbol(forKind: gvr.kind))
            if let (section, order) = kindSection[gvr.kind] {
                guard !seenKinds.contains(gvr.kind) else { continue }
                seenKinds.insert(gvr.kind)
                bySection[section, default: []].append((order, entry))
            } else if !builtInGroups.contains(gvr.group), !gvr.group.isEmpty {
                // Dedup per (group, kind): the same kind name may legitimately
                // exist in two unrelated CRD groups.
                guard !seenCRDs.contains(key) else { continue }
                seenCRDs.insert(key)
                crdByGroup[gvr.group, default: []].append(entry)
            }
        }

        return NavSection.allCases.compactMap { section in
            let direct = (bySection[section] ?? []).sorted {
                $0.order != $1.order ? $0.order < $1.order : $0.entry.title < $1.entry.title
            }.map(\.entry)
            let subgroups: [SidebarSubgroup] = section == .customResources
                ? crdByGroup.keys.sorted().map {
                    SidebarSubgroup(name: $0,
                                    entries: crdByGroup[$0]!.sorted { $0.title < $1.title })
                }
                : []
            guard !direct.isEmpty || !subgroups.isEmpty else { return nil }
            return SidebarSection(section: section, entries: direct, subgroups: subgroups)
        }
    }

    private static func titleCase(_ resource: String) -> String {
        // "pods" → "Pods", "networkpolicies" → "Networkpolicies" (good enough;
        // the kind drives the icon and detail rendering).
        guard let first = resource.first else { return resource }
        return String(first).uppercased() + resource.dropFirst()
    }
}
