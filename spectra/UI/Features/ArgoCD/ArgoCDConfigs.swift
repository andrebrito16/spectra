import SwiftUI

@MainActor
enum ArgoCDConfigs {
    static func register(into catalog: ResourceCatalog) {
        catalog.register("Application", group: "argoproj.io", ResourceConfig(
            columns: [
                Columns.name, Columns.namespace(),
                ColumnDefinition(id: "project", title: "Project", width: 130) {
                    $0.spec?["project"]?.stringValue ?? "default"
                },
                ColumnDefinition(id: "sync", title: "Sync", width: 110,
                                 status: { statusColor($0.argoSyncStatus) }) { $0.argoSyncStatus },
                ColumnDefinition(id: "health", title: "Health", width: 110,
                                 status: { statusColor($0.argoHealthStatus) }) { $0.argoHealthStatus },
                ColumnDefinition(id: "destination", title: "Destination", width: 180) { $0.argoDestination },
                Columns.age,
            ],
            detailSections: [DetailSectionDef(id: "application", title: "Application") { resource, _ in
                AnyView(ArgoApplicationSection(resource: resource))
            }]))

        catalog.register("ApplicationSet", group: "argoproj.io", ResourceConfig(columns: [
            Columns.name, Columns.namespace(),
            ColumnDefinition(id: "generators", title: "Generators", width: 200) {
                let names = ($0.spec?["generators"]?.arrayValue ?? []).flatMap {
                    ($0.objectValue ?? [:]).keys.filter { $0 != "template" }.sorted()
                }
                return names.isEmpty ? "—" : names.joined(separator: ", ")
            },
            ColumnDefinition(id: "project", title: "Project", width: 160) {
                $0.spec?["template"]?["spec"]?["project"]?.stringValue ?? "—"
            },
            Columns.age,
        ]))

        catalog.register("AppProject", group: "argoproj.io", ResourceConfig(columns: [
            Columns.name, Columns.namespace(),
            ColumnDefinition(id: "description", title: "Description", width: 240) {
                $0.spec?["description"]?.stringValue ?? "—"
            },
            ColumnDefinition(id: "repositories", title: "Source Repositories", width: 220) {
                ($0.spec?["sourceRepos"]?.arrayValue ?? []).compactMap(\.stringValue).joined(separator: ", ")
            },
            ColumnDefinition(id: "destinations", title: "Destinations", width: 100) {
                "\($0.spec?["destinations"]?.arrayValue?.count ?? 0)"
            },
            Columns.age,
        ]))

        catalog.register("Rollout", group: "argoproj.io", ResourceConfig(
            columns: [
                Columns.name, Columns.namespace(),
                ColumnDefinition(id: "strategy", title: "Strategy", width: 110) { $0.argoRolloutStrategy },
                ColumnDefinition(id: "phase", title: "Status", width: 120,
                                 status: { statusColor($0.argoRolloutPhase) }) { $0.argoRolloutPhase },
                ColumnDefinition(id: "ready", title: "Ready", width: 70) { $0.argoRolloutReplicas },
                ColumnDefinition(id: "updated", title: "Updated", width: 70) {
                    "\($0.status?["updatedReplicas"]?.intValue ?? 0)"
                },
                Columns.age,
            ],
            detailSections: [DetailSectionDef(id: "rollout", title: "Rollout") { resource, _ in
                AnyView(ArgoRolloutSection(resource: resource))
            }]))

        for kind in ["AnalysisRun", "Experiment"] {
            catalog.register(kind, group: "argoproj.io", ResourceConfig(columns: [
                Columns.name, Columns.namespace(),
                ColumnDefinition(id: "phase", title: "Phase", width: 120, status: {
                    statusColor($0.status?["phase"]?.stringValue ?? "Unknown")
                }) { $0.status?["phase"]?.stringValue ?? "Unknown" },
                ColumnDefinition(id: "message", title: "Message", width: 260) {
                    $0.status?["message"]?.stringValue ?? "—"
                },
                Columns.age,
            ]))
        }
        for kind in ["AnalysisTemplate", "ClusterAnalysisTemplate"] {
            var columns = [Columns.name]
            if kind == "AnalysisTemplate" { columns.append(Columns.namespace()) }
            columns.append(ColumnDefinition(id: "metrics", title: "Metrics", width: 260) {
                ($0.spec?["metrics"]?.arrayValue ?? []).compactMap { $0["name"]?.stringValue }
                    .joined(separator: ", ")
            })
            columns.append(Columns.age)
            catalog.register(kind, group: "argoproj.io", ResourceConfig(columns: columns))
        }
    }

    private static func statusColor(_ status: String) -> SpectraStatus {
        switch status {
        case "Healthy", "Synced", "Successful", "Succeeded": return .success
        case "Progressing", "Running", "Pending": return .info
        case "OutOfSync", "Paused", "Suspended", "Inconclusive", "Missing": return .warning
        case "Degraded", "Failed", "Error": return .error
        default: return .neutral
        }
    }
}

private struct ArgoApplicationSection: View {
    let resource: KubeResource

    var body: some View {
        DetailCard(title: "Application") {
            DetailRow(label: "Project", value: resource.spec?["project"]?.stringValue ?? "default")
            DetailRow(label: "Sync", value: resource.argoSyncStatus)
            DetailRow(label: "Health", value: resource.argoHealthStatus)
            DetailRow(label: "Repositories", value: resource.argoRepositories)
            DetailRow(label: "Target revisions", value: resource.argoTargetRevisions)
            DetailRow(label: "Destination", value: resource.argoDestination)
            DetailRow(label: "Namespace", value: resource.spec?["destination"]?["namespace"]?.stringValue ?? "—")
            if let message = resource.status?["health"]?["message"]?.stringValue {
                DetailRow(label: "Health message", value: message)
            }
            if let operation = resource.status?["operationState"] {
                DetailRow(label: "Last operation", value: operation["phase"]?.stringValue ?? "—")
                DetailRow(label: "Message", value: operation["message"]?.stringValue ?? "—")
            }
        }
    }
}

private struct ArgoRolloutSection: View {
    let resource: KubeResource

    var body: some View {
        DetailCard(title: "Rollout") {
            DetailRow(label: "Strategy", value: resource.argoRolloutStrategy)
            DetailRow(label: "Status", value: resource.argoRolloutPhase)
            DetailRow(label: "Ready", value: resource.argoRolloutReplicas)
            DetailRow(label: "Images", value: resource.argoRolloutImages)
            if let index = resource.status?["currentStepIndex"]?.intValue {
                let total = resource.spec?["strategy"]?["canary"]?["steps"]?.arrayValue?.count ?? 0
                DetailRow(label: "Canary step", value: index < total ? "\(index + 1) / \(total)" : "Completed")
            }
            if let weight = resource.status?["canary"]?["weights"]?["canary"]?["weight"]?.intValue {
                DetailRow(label: "Canary weight", value: "\(weight)%")
            }
            if let message = resource.status?["message"]?.stringValue {
                DetailRow(label: "Message", value: message)
            }
        }
    }
}
