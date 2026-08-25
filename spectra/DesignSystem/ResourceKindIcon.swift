//
//  ResourceKindIcon.swift
//  Spectra
//
//  Maps Kubernetes resource kinds (and sidebar sections) to SF Symbols. Falls
//  back to a generic glyph for unknown/CRD kinds.
//

import SwiftUI

nonisolated enum ResourceKindIcon {
    /// SF Symbol name for a given Kubernetes `kind`.
    static func symbol(forKind kind: String) -> String {
        switch kind {
        case "Pod": return "shippingbox"
        case "Deployment": return "square.stack.3d.up"
        case "ReplicaSet": return "square.stack.3d.up.badge.a"
        case "ReplicationController": return "square.stack.3d.up.badge.a"
        case "StatefulSet": return "cylinder.split.1x2"
        case "DaemonSet": return "square.grid.3x3"
        case "Job": return "checklist"
        case "CronJob": return "clock.arrow.circlepath"
        case "ConfigMap": return "doc.text"
        case "Secret": return "lock.doc"
        case "Service": return "network"
        case "Endpoints", "EndpointSlice": return "point.3.connected.trianglepath.dotted"
        case "Ingress": return "arrow.down.left.and.arrow.up.right"
        case "IngressClass": return "arrow.triangle.branch"
        case "NetworkPolicy": return "shield.lefthalf.filled"
        case "PersistentVolume": return "externaldrive"
        case "PersistentVolumeClaim": return "externaldrive.badge.checkmark"
        case "StorageClass": return "internaldrive"
        case "Node": return "server.rack"
        case "Namespace": return "square.dashed"
        case "Event": return "bell"
        case "HorizontalPodAutoscaler", "VerticalPodAutoscaler": return "arrow.up.arrow.down"
        case "PodDisruptionBudget": return "cross.case"
        case "ResourceQuota": return "gauge.with.dots.needle.50percent"
        case "LimitRange": return "ruler"
        case "PriorityClass": return "list.number"
        case "RuntimeClass": return "cpu"
        case "Lease": return "calendar.badge.clock"
        case "MutatingWebhookConfiguration", "ValidatingWebhookConfiguration": return "arrow.triangle.2.circlepath"
        case "ServiceAccount": return "person.badge.key"
        case "Role", "ClusterRole": return "person.text.rectangle"
        case "RoleBinding", "ClusterRoleBinding": return "link"
        case "CustomResourceDefinition": return "puzzlepiece.extension"
        default: return "cube"
        }
    }

    /// SF Symbol for a sidebar section header.
    static func symbol(forSection section: String) -> String {
        switch section {
        case "Cluster": return "circle.grid.cross"
        case "Workloads": return "square.stack.3d.up"
        case "Config": return "slider.horizontal.3"
        case "Network": return "network"
        case "Storage": return "externaldrive"
        case "Helm": return "sailboat"
        case "Access Control": return "lock.shield"
        case "Custom Resources": return "puzzlepiece.extension"
        default: return "folder"
        }
    }
}
