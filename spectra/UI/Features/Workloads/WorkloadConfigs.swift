//
//  WorkloadConfigs.swift
//  Spectra
//
//  Registers the Workloads section configs (columns, detail sections, actions)
//  into the ResourceCatalog. Mostly configuration of the Phase 5 engine.
//

import SwiftUI

@MainActor
enum WorkloadConfigs {
    static func register(into catalog: ResourceCatalog) {
        registerPods(catalog)
        registerDeployments(catalog)
        registerStatefulSets(catalog)
        registerDaemonSets(catalog)
        registerReplicaSets(catalog)
        registerJobs(catalog)
        registerCronJobs(catalog)
    }

    private static func registerPods(_ catalog: ResourceCatalog) {
        catalog.register("Pod", ResourceConfig(
            columns: [
                Columns.name,
                Columns.namespace(),
                ColumnDefinition(id: "ready", title: "Ready", width: 64, alignment: .trailing) {
                    let r = $0.podReady; return "\(r.ready)/\(r.total)"
                },
                ColumnDefinition(id: "restarts", title: "Restarts", width: 72, alignment: .trailing) {
                    "\($0.podRestarts)"
                },
                ColumnDefinition(id: "controlledby", title: "Controlled By", width: 160) {
                    $0.controlledBy ?? "—"
                },
                ColumnDefinition(id: "node", title: "Node", width: 160) { $0.nodeName ?? "—" },
                ColumnDefinition(id: "status", title: "Status", width: 110,
                                 status: { $0.podStatusColor }) { $0.podDisplayStatus },
                Columns.age,
            ],
            detailSections: [
                DetailSectionDef(id: "pod-summary", title: "Status") { r, _ in
                    AnyView(PodSummarySection(resource: r))
                },
                DetailSectionDef(id: "pod-containers", title: "Containers") { r, _ in
                    AnyView(PodContainersSection(resource: r))
                },
                DetailSectionDef(id: "pod-env", title: "Environment") { r, s in
                    AnyView(PodEnvSection(resource: r, session: s))
                },
                DetailSectionDef(id: "pod-volumes", title: "Volumes") { r, _ in
                    AnyView(PodVolumesSection(resource: r))
                },
                DetailSectionDef(id: "pod-metrics", title: "Metrics") { r, s in
                    AnyView(MetricsSection(resource: r, session: s))
                },
            ],
            actions: [DockActions.logs, DockActions.shell, DockActions.portForward,
                      WorkloadActions.evict]))
    }

    private static func registerDeployments(_ catalog: ResourceCatalog) {
        catalog.register("Deployment", ResourceConfig(
            columns: [
                Columns.name, Columns.namespace(),
                ColumnDefinition(id: "pods", title: "Pods", width: 80, alignment: .trailing) {
                    "\($0.statusReadyReplicas)/\($0.specReplicas ?? 0)"
                },
                ColumnDefinition(id: "replicas", title: "Replicas", width: 80, alignment: .trailing) {
                    "\($0.specReplicas ?? 0)"
                },
                Columns.age,
            ],
            actions: [WorkloadActions.scale, WorkloadActions.restart]))
    }

    private static func registerStatefulSets(_ catalog: ResourceCatalog) {
        catalog.register("StatefulSet", ResourceConfig(
            columns: [
                Columns.name, Columns.namespace(),
                ColumnDefinition(id: "pods", title: "Pods", width: 80, alignment: .trailing) {
                    "\($0.statusReadyReplicas)/\($0.specReplicas ?? 0)"
                },
                ColumnDefinition(id: "replicas", title: "Replicas", width: 80, alignment: .trailing) {
                    "\($0.specReplicas ?? 0)"
                },
                Columns.age,
            ],
            actions: [WorkloadActions.scale, WorkloadActions.restart]))
    }

    private static func registerDaemonSets(_ catalog: ResourceCatalog) {
        catalog.register("DaemonSet", ResourceConfig(
            columns: [
                Columns.name, Columns.namespace(),
                ColumnDefinition(id: "desired", title: "Desired", width: 70, alignment: .trailing) { "\($0.dsDesired)" },
                ColumnDefinition(id: "current", title: "Current", width: 70, alignment: .trailing) { "\($0.dsCurrent)" },
                ColumnDefinition(id: "ready", title: "Ready", width: 60, alignment: .trailing) { "\($0.dsReady)" },
                ColumnDefinition(id: "uptodate", title: "Up-to-date", width: 90, alignment: .trailing) { "\($0.dsUpToDate)" },
                ColumnDefinition(id: "available", title: "Available", width: 80, alignment: .trailing) { "\($0.dsAvailable)" },
                Columns.age,
            ],
            actions: [WorkloadActions.restart]))
    }

    private static func registerReplicaSets(_ catalog: ResourceCatalog) {
        let config = ResourceConfig(
            columns: [
                Columns.name, Columns.namespace(),
                ColumnDefinition(id: "desired", title: "Desired", width: 70, alignment: .trailing) { "\($0.specReplicas ?? 0)" },
                ColumnDefinition(id: "current", title: "Current", width: 70, alignment: .trailing) { "\($0.statusReplicas)" },
                ColumnDefinition(id: "ready", title: "Ready", width: 60, alignment: .trailing) { "\($0.statusReadyReplicas)" },
                Columns.age,
            ],
            actions: [WorkloadActions.scale])
        catalog.register("ReplicaSet", config)
        catalog.register("ReplicationController", config)
    }

    private static func registerJobs(_ catalog: ResourceCatalog) {
        catalog.register("Job", ResourceConfig(
            columns: [
                Columns.name, Columns.namespace(),
                ColumnDefinition(id: "completions", title: "Completions", width: 100, alignment: .trailing) {
                    $0.jobCompletions
                },
                Columns.age,
            ],
            actions: [WorkloadActions.suspend, WorkloadActions.resume]))
    }

    private static func registerCronJobs(_ catalog: ResourceCatalog) {
        catalog.register("CronJob", ResourceConfig(
            columns: [
                Columns.name, Columns.namespace(),
                ColumnDefinition(id: "schedule", title: "Schedule", width: 120) { $0.cronSchedule ?? "—" },
                ColumnDefinition(id: "suspend", title: "Suspend", width: 70) { $0.isSuspended ? "True" : "False" },
                ColumnDefinition(id: "active", title: "Active", width: 60, alignment: .trailing) { "\($0.cronActiveCount)" },
                ColumnDefinition(id: "lastschedule", title: "Last Schedule", width: 140) {
                    $0.cronLastSchedule.flatMap(CredentialProvider.parseTimestamp)?.k8sAge ?? "—"
                },
                Columns.age,
            ],
            actions: [WorkloadActions.trigger, WorkloadActions.suspend, WorkloadActions.resume]))
    }
}
