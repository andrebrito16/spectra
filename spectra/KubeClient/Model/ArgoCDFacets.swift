import Foundation

extension KubeResource {
    var argoSources: [JSONValue] {
        if let sources = spec?["sources"]?.arrayValue, !sources.isEmpty { return sources }
        return spec?["source"].map { [$0] } ?? []
    }

    var argoRepositories: String {
        let repositories = argoSources.compactMap { $0["repoURL"]?.stringValue }
        return repositories.isEmpty ? "—" : repositories.joined(separator: ", ")
    }

    var argoTargetRevisions: String {
        let revisions = argoSources.compactMap { $0["targetRevision"]?.stringValue }
        return revisions.isEmpty ? "—" : revisions.joined(separator: ", ")
    }

    var argoDestination: String {
        let destination = spec?["destination"]
        return destination?["name"]?.stringValue ?? destination?["server"]?.stringValue ?? "—"
    }

    var argoSyncStatus: String { status?["sync"]?["status"]?.stringValue ?? "Unknown" }
    var argoHealthStatus: String { status?["health"]?["status"]?.stringValue ?? "Unknown" }

    var argoRolloutStrategy: String {
        if spec?["strategy"]?["canary"]?.objectValue != nil { return "Canary" }
        if spec?["strategy"]?["blueGreen"]?.objectValue != nil { return "Blue/Green" }
        return "—"
    }

    var argoRolloutPhase: String {
        if let phase = status?["phase"]?.stringValue, !phase.isEmpty { return phase }
        if spec?["paused"]?.boolValue == true || !(status?["pauseConditions"]?.arrayValue ?? []).isEmpty {
            return "Paused"
        }
        return "Unknown"
    }

    var argoRolloutReplicas: String {
        "\(status?["readyReplicas"]?.intValue ?? 0)/\(spec?["replicas"]?.intValue ?? 1)"
    }

    var argoRolloutImages: String {
        let images = (spec?["template"]?["spec"]?["containers"]?.arrayValue ?? [])
            .compactMap { $0["image"]?.stringValue }
        return images.isEmpty ? "—" : images.joined(separator: ", ")
    }
}
