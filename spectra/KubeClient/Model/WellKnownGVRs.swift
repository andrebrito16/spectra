//
//  WellKnownGVRs.swift
//  Spectra
//
//  Stable, well-known GVRs for built-in Kubernetes kinds. Used to seed
//  ClusterSession.gvrs immediately on cluster open so the sidebar / nav tree
//  is usable while real API discovery runs in the background. The discovered
//  set replaces this seed when ready (CRDs come along with it).
//

import Foundation

nonisolated enum WellKnownGVRs {
    static let all: [GroupVersionResource] = [
        // Core (group "")
        gvr("", "v1", "pods", "Pod", namespaced: true),
        gvr("", "v1", "services", "Service", namespaced: true),
        gvr("", "v1", "endpoints", "Endpoints", namespaced: true),
        gvr("", "v1", "configmaps", "ConfigMap", namespaced: true),
        gvr("", "v1", "secrets", "Secret", namespaced: true),
        gvr("", "v1", "persistentvolumeclaims", "PersistentVolumeClaim", namespaced: true),
        gvr("", "v1", "serviceaccounts", "ServiceAccount", namespaced: true),
        gvr("", "v1", "resourcequotas", "ResourceQuota", namespaced: true),
        gvr("", "v1", "limitranges", "LimitRange", namespaced: true),
        gvr("", "v1", "replicationcontrollers", "ReplicationController", namespaced: true),
        gvr("", "v1", "events", "Event", namespaced: true),
        gvr("", "v1", "namespaces", "Namespace", namespaced: false),
        gvr("", "v1", "nodes", "Node", namespaced: false),
        gvr("", "v1", "persistentvolumes", "PersistentVolume", namespaced: false),

        // apps
        gvr("apps", "v1", "deployments", "Deployment", namespaced: true),
        gvr("apps", "v1", "replicasets", "ReplicaSet", namespaced: true),
        gvr("apps", "v1", "statefulsets", "StatefulSet", namespaced: true),
        gvr("apps", "v1", "daemonsets", "DaemonSet", namespaced: true),

        // batch
        gvr("batch", "v1", "jobs", "Job", namespaced: true),
        gvr("batch", "v1", "cronjobs", "CronJob", namespaced: true),

        // autoscaling
        gvr("autoscaling", "v2", "horizontalpodautoscalers", "HorizontalPodAutoscaler", namespaced: true),

        // policy
        gvr("policy", "v1", "poddisruptionbudgets", "PodDisruptionBudget", namespaced: true),

        // networking
        gvr("networking.k8s.io", "v1", "ingresses", "Ingress", namespaced: true),
        gvr("networking.k8s.io", "v1", "networkpolicies", "NetworkPolicy", namespaced: true),
        gvr("networking.k8s.io", "v1", "ingressclasses", "IngressClass", namespaced: false),

        // discovery (EndpointSlice)
        gvr("discovery.k8s.io", "v1", "endpointslices", "EndpointSlice", namespaced: true),

        // storage
        gvr("storage.k8s.io", "v1", "storageclasses", "StorageClass", namespaced: false),

        // rbac
        gvr("rbac.authorization.k8s.io", "v1", "roles", "Role", namespaced: true),
        gvr("rbac.authorization.k8s.io", "v1", "rolebindings", "RoleBinding", namespaced: true),
        gvr("rbac.authorization.k8s.io", "v1", "clusterroles", "ClusterRole", namespaced: false),
        gvr("rbac.authorization.k8s.io", "v1", "clusterrolebindings", "ClusterRoleBinding", namespaced: false),

        // coordination / scheduling / node
        gvr("coordination.k8s.io", "v1", "leases", "Lease", namespaced: true),
        gvr("scheduling.k8s.io", "v1", "priorityclasses", "PriorityClass", namespaced: false),
        gvr("node.k8s.io", "v1", "runtimeclasses", "RuntimeClass", namespaced: false),

        // admissionregistration
        gvr("admissionregistration.k8s.io", "v1", "mutatingwebhookconfigurations",
            "MutatingWebhookConfiguration", namespaced: false),
        gvr("admissionregistration.k8s.io", "v1", "validatingwebhookconfigurations",
            "ValidatingWebhookConfiguration", namespaced: false),

        // CRDs
        gvr("apiextensions.k8s.io", "v1", "customresourcedefinitions",
            "CustomResourceDefinition", namespaced: false),
    ]

    private static func gvr(_ group: String, _ version: String, _ resource: String,
                            _ kind: String, namespaced: Bool) -> GroupVersionResource {
        GroupVersionResource(group: group, version: version, resource: resource, kind: kind,
                             namespaced: namespaced)
    }
}
