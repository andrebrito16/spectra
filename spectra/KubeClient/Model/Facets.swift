//
//  Facets.swift
//  Spectra
//
//  Lightweight typed accessors over KubeResource for common kinds — computed
//  wrappers giving list columns and detail views structured access without
//  bespoke model types. Mirrors Freelens's specifics/*.
//

import Foundation

nonisolated extension KubeResource {
    // MARK: - Pod

    var podPhase: String? { status?["phase"]?.stringValue }

    var containerStatuses: [JSONValue] { status?["containerStatuses"]?.arrayValue ?? [] }
    var initContainerStatuses: [JSONValue] { status?["initContainerStatuses"]?.arrayValue ?? [] }
    var containers: [JSONValue] { spec?["containers"]?.arrayValue ?? [] }
    var initContainers: [JSONValue] { spec?["initContainers"]?.arrayValue ?? [] }
    var volumes: [JSONValue] { spec?["volumes"]?.arrayValue ?? [] }

    var podReady: (ready: Int, total: Int) {
        let statuses = containerStatuses
        let ready = statuses.filter { $0["ready"]?.boolValue == true }.count
        return (ready, statuses.count)
    }

    var podRestarts: Int {
        containerStatuses.reduce(0) { $0 + ($1["restartCount"]?.intValue ?? 0) }
    }

    var nodeName: String? { spec?["nodeName"]?.stringValue }
    var podIP: String? { status?["podIP"]?.stringValue }
    var hostIP: String? { status?["hostIP"]?.stringValue }
    var qosClass: String? { status?["qosClass"]?.stringValue }
    var serviceAccountName: String? { spec?["serviceAccountName"]?.stringValue }

    var controlledBy: String? {
        ownerReferences.first.map { "\($0.kind)/\($0.name)" }
    }

    /// kubectl-style display status (printPod in kubectl's printers.go):
    /// deletionTimestamp → Terminating, init/container waiting/terminated
    /// reasons (CrashLoopBackOff, ImagePullBackOff, Init:1/2, …), else phase.
    var podDisplayStatus: String {
        var reason = status?["reason"]?.stringValue ?? podPhase ?? "Unknown"

        var initializing = false
        for (index, container) in initContainerStatuses.enumerated() {
            let state = container["state"]
            if let terminated = state?["terminated"] {
                if terminated["exitCode"]?.intValue == 0 { continue }
                if let r = terminated["reason"]?.stringValue, !r.isEmpty {
                    reason = "Init:\(r)"
                } else if let signal = terminated["signal"]?.intValue, signal != 0 {
                    reason = "Init:Signal:\(signal)"
                } else {
                    reason = "Init:ExitCode:\(terminated["exitCode"]?.intValue ?? 0)"
                }
            } else if let waiting = state?["waiting"]?["reason"]?.stringValue,
                      !waiting.isEmpty, waiting != "PodInitializing" {
                reason = "Init:\(waiting)"
            } else {
                reason = "Init:\(index)/\(initContainers.count)"
            }
            initializing = true
            break
        }

        if !initializing {
            var hasRunning = false
            for container in containerStatuses.reversed() {
                let state = container["state"]
                if let waiting = state?["waiting"]?["reason"]?.stringValue, !waiting.isEmpty {
                    reason = waiting
                } else if let terminated = state?["terminated"] {
                    if let r = terminated["reason"]?.stringValue, !r.isEmpty {
                        reason = r
                    } else if let signal = terminated["signal"]?.intValue, signal != 0 {
                        reason = "Signal:\(signal)"
                    } else {
                        reason = "ExitCode:\(terminated["exitCode"]?.intValue ?? 0)"
                    }
                } else if container["ready"]?.boolValue == true, state?["running"] != nil {
                    hasRunning = true
                }
            }
            if reason == "Completed" && hasRunning { reason = "Running" }
        }

        if deletionTimestamp != nil {
            reason = status?["reason"]?.stringValue == "NodeLost" ? "Unknown" : "Terminating"
        }
        return reason
    }

    /// Status color for the kubectl-style display status.
    var podStatusColor: SpectraStatus {
        let display = podDisplayStatus
        let bare = display.hasPrefix("Init:") ? String(display.dropFirst(5)) : display
        switch bare {
        case "Running": return .success
        case "Succeeded", "Completed": return .neutral
        case "Terminating", "Unknown": return .warning
        case "Pending", "ContainerCreating", "PodInitializing": return .info
        case "Failed", "Error", "CrashLoopBackOff", "ImagePullBackOff", "ErrImagePull",
             "InvalidImageName", "CreateContainerConfigError", "CreateContainerError",
             "OOMKilled", "Evicted", "NodeLost":
            return .error
        default:
            if bare.hasPrefix("ExitCode:") || bare.hasPrefix("Signal:") { return .error }
            if bare.contains("/") { return .info }  // Init:0/2 progress
            return .warning
        }
    }

    // MARK: - Deployment / StatefulSet / ReplicaSet

    var specReplicas: Int? { spec?["replicas"]?.intValue }
    var statusReplicas: Int { status?["replicas"]?.intValue ?? 0 }
    var statusReadyReplicas: Int { status?["readyReplicas"]?.intValue ?? 0 }
    var statusAvailableReplicas: Int { status?["availableReplicas"]?.intValue ?? 0 }
    var statusCurrentReplicas: Int { status?["currentReplicas"]?.intValue ?? 0 }

    // MARK: - DaemonSet

    var dsDesired: Int { status?["desiredNumberScheduled"]?.intValue ?? 0 }
    var dsCurrent: Int { status?["currentNumberScheduled"]?.intValue ?? 0 }
    var dsReady: Int { status?["numberReady"]?.intValue ?? 0 }
    var dsUpToDate: Int { status?["updatedNumberScheduled"]?.intValue ?? 0 }
    var dsAvailable: Int { status?["numberAvailable"]?.intValue ?? 0 }

    // MARK: - Job / CronJob

    var jobCompletions: String {
        let succeeded = status?["succeeded"]?.intValue ?? 0
        let completions = spec?["completions"]?.intValue ?? 1
        return "\(succeeded)/\(completions)"
    }
    var isSuspended: Bool { spec?["suspend"]?.boolValue ?? false }
    var cronSchedule: String? { spec?["schedule"]?.stringValue }
    var cronLastSchedule: String? { status?["lastScheduleTime"]?.stringValue }
    var cronActiveCount: Int { status?["active"]?.arrayValue?.count ?? 0 }

    // MARK: - Service

    var serviceType: String? { spec?["type"]?.stringValue }
    var clusterIP: String? { spec?["clusterIP"]?.stringValue }
    var servicePortsSummary: String {
        (spec?["ports"]?.arrayValue ?? []).compactMap { port in
            guard let p = port["port"]?.intValue else { return nil }
            let proto = port["protocol"]?.stringValue ?? "TCP"
            return "\(p)/\(proto)"
        }.joined(separator: ", ")
    }

    // MARK: - Ingress

    /// LoadBalancer addresses from status.loadBalancer.ingress[] (hostname or ip).
    /// Covers ALB (hostname), MetalLB/Traefik (ip), etc.
    var ingressLoadBalancers: [String] {
        (status?["loadBalancer"]?["ingress"]?.arrayValue ?? []).compactMap {
            $0["hostname"]?.stringValue ?? $0["ip"]?.stringValue
        }
    }

    // MARK: - Node

    var nodeReady: Bool {
        (status?["conditions"]?.arrayValue ?? []).contains {
            $0["type"]?.stringValue == "Ready" && $0["status"]?.stringValue == "True"
        }
    }
    var nodeRoles: String {
        let roleLabels = labels.keys.filter { $0.hasPrefix("node-role.kubernetes.io/") }
        let roles = roleLabels.map { $0.replacingOccurrences(of: "node-role.kubernetes.io/", with: "") }
        return roles.isEmpty ? "<none>" : roles.sorted().joined(separator: ",")
    }
    var kubeletVersion: String? { status?["nodeInfo"]?["kubeletVersion"]?.stringValue }
    var nodeUnschedulable: Bool { spec?["unschedulable"]?.boolValue ?? false }

    /// Taints as "key=value:Effect" (or "key:Effect" without a value).
    var nodeTaints: [String] {
        (spec?["taints"]?.arrayValue ?? []).compactMap { taint in
            guard let key = taint["key"]?.stringValue else { return nil }
            let effect = taint["effect"]?.stringValue ?? ""
            if let value = taint["value"]?.stringValue, !value.isEmpty {
                return "\(key)=\(value):\(effect)"
            }
            return "\(key):\(effect)"
        }
    }

    // MARK: - PVC / PV

    var pvcPhase: String? { status?["phase"]?.stringValue }
    var pvcCapacity: String? {
        status?["capacity"]?["storage"]?.stringValue
            ?? spec?["resources"]?["requests"]?["storage"]?.stringValue
    }
    var storageClassName: String? { spec?["storageClassName"]?.stringValue }
    var accessModes: String {
        (spec?["accessModes"]?.arrayValue ?? []).compactMap { $0.stringValue }.joined(separator: ",")
    }
}
