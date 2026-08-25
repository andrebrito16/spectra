//
//  WorkloadActions.swift
//  Spectra
//
//  Kind-specific workload actions: scale, restart, suspend/resume, trigger,
//  evict. Registered onto the relevant kinds in WorkloadConfigs.
//

import Foundation

@MainActor
enum WorkloadActions {
    static let scale = ObjectAction(
        id: "scale", title: "Scale", systemImage: "arrow.up.arrow.down",
        interaction: .scale, isAvailable: { $0.specReplicas != nil },
        perform: { _, _ in })

    static let restart = ObjectAction(
        id: "restart", title: "Restart", systemImage: "arrow.clockwise.circle",
        confirm: "Restart this workload? Pods will roll.") { resource, session in
        let now = ISO8601DateFormatter().string(from: Date())
        let patch: JSONValue = .object([
            "spec": .object(["template": .object(["metadata": .object([
                "annotations": .object(["kubectl.kubernetes.io/restartedAt": .string(now)]),
            ])])]),
        ])
        try await patchSpec(resource, session: session, json: patch, type: .strategicMerge)
    }

    static let suspend = ObjectAction(
        id: "suspend", title: "Suspend", systemImage: "pause.circle",
        isAvailable: { !$0.isSuspended }) { resource, session in
        try await patchSpec(resource, session: session,
                            json: .object(["spec": .object(["suspend": .bool(true)])]),
                            type: .merge)
    }

    static let resume = ObjectAction(
        id: "resume", title: "Resume", systemImage: "play.circle",
        isAvailable: { $0.isSuspended }) { resource, session in
        try await patchSpec(resource, session: session,
                            json: .object(["spec": .object(["suspend": .bool(false)])]),
                            type: .merge)
    }

    static let trigger = ObjectAction(
        id: "trigger", title: "Trigger", systemImage: "play.fill",
        confirm: "Manually trigger a Job from this CronJob?") { resource, session in
        try await triggerCronJob(resource, session: session)
    }

    static let evict = ObjectAction(
        id: "evict", title: "Evict", systemImage: "eject",
        confirm: "Evict this pod (respecting disruption budgets)?") { resource, session in
        guard let namespace = resource.namespace else {
            throw KubeError.notFound("pod has no namespace")
        }
        try await session.client.evict(namespace: namespace, podName: resource.name)
    }

    // MARK: - Helpers

    static func patchSpec(_ resource: KubeResource, session: ClusterSession,
                          json: JSONValue, type: PatchType) async throws {
        guard let kind = resource.kind, let gvr = session.gvr(forKind: kind) else {
            throw KubeError.notFound("no GVR for kind \(resource.kind ?? "?")")
        }
        let data = try JSONEncoder().encode(json)
        _ = try await session.client.patch(gvr, namespace: resource.namespace,
                                           name: resource.name, data: data, type: type)
    }

    static func triggerCronJob(_ cronjob: KubeResource, session: ClusterSession) async throws {
        guard let jobGVR = session.gvr(forKind: "Job") else {
            throw KubeError.notFound("Job kind not available")
        }
        guard let jobSpec = cronjob.spec?["jobTemplate"]?["spec"] else {
            throw KubeError.decoding("CronJob has no jobTemplate.spec")
        }
        let suffix = Int(Date().timeIntervalSince1970) % 1_000_000
        let jobName = "\(cronjob.name)-manual-\(suffix)"
        var metadata: [String: JSONValue] = ["name": .string(jobName)]
        if let namespace = cronjob.namespace { metadata["namespace"] = .string(namespace) }
        if let uid = cronjob.uid {
            metadata["ownerReferences"] = .array([.object([
                "apiVersion": .string(cronjob.apiVersion ?? "batch/v1"),
                "kind": .string("CronJob"),
                "name": .string(cronjob.name),
                "uid": .string(uid),
                "controller": .bool(true),
                "blockOwnerDeletion": .bool(true),
            ])])
        }
        let job = KubeResource(json: .object([
            "apiVersion": .string("batch/v1"),
            "kind": .string("Job"),
            "metadata": .object(metadata),
            "spec": jobSpec,
        ]))
        _ = try await session.client.create(jobGVR, namespace: cronjob.namespace, resource: job)
    }
}
