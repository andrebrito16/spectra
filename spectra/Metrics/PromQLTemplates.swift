//
//  PromQLTemplates.swift
//  Spectra
//
//  PromQL query templates per metric kind and scope. Ported in spirit from
//  Freelens's prometheus providers. Parameterized by namespace/pod/node.
//

import Foundation

nonisolated enum PromQLTemplates {
    static func query(_ kind: MetricKind, _ scope: MetricScope) -> String {
        switch (kind, scope) {
        case let (.cpu, .pod(namespace, name)):
            return "sum(rate(container_cpu_usage_seconds_total{namespace=\"\(namespace)\",pod=\"\(name)\",container!=\"\"}[2m]))"
        case let (.memory, .pod(namespace, name)):
            return "sum(container_memory_working_set_bytes{namespace=\"\(namespace)\",pod=\"\(name)\",container!=\"\"})"
        case let (.cpu, .node(name)):
            return "sum(rate(node_cpu_seconds_total{mode!=\"idle\"}[2m]) * on(instance) group_left(node) (kube_node_info{node=\"\(name)\"} or node_uname_info))"
        case let (.memory, .node(name)):
            return "sum((node_memory_MemTotal_bytes - node_memory_MemAvailable_bytes) * on(instance) group_left(node) (kube_node_info{node=\"\(name)\"} or node_uname_info))"
        case (.cpu, .cluster):
            return "sum(rate(container_cpu_usage_seconds_total{container!=\"\"}[2m]))"
        case (.memory, .cluster):
            return "sum(container_memory_working_set_bytes{container!=\"\"})"
        }
    }
}
