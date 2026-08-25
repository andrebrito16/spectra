//
//  PodDetail.swift
//  Spectra
//
//  Pod-specific detail sections: status summary, containers (init + regular),
//  and volumes. Registered as DetailSectionDefs for the "Pod" kind.
//

import SwiftUI

struct PodSummarySection: View {
    let resource: KubeResource

    var body: some View {
        DetailCard(title: "Status") {
            VStack(alignment: .leading, spacing: Tokens.Spacing.xs) {
                HStack {
                    Badge(text: resource.podDisplayStatus, status: resource.podStatusColor)
                    Spacer()
                }
                if let node = resource.nodeName { DetailRow(label: "Node", value: node) }
                if let podIP = resource.podIP { DetailRow(label: "Pod IP", value: podIP) }
                if let hostIP = resource.hostIP { DetailRow(label: "Host IP", value: hostIP) }
                if let qos = resource.qosClass { DetailRow(label: "QoS Class", value: qos) }
                if let sa = resource.serviceAccountName {
                    DetailRow(label: "Service Account", value: sa)
                }
                let ready = resource.podReady
                DetailRow(label: "Containers Ready", value: "\(ready.ready)/\(ready.total)")
                DetailRow(label: "Restarts", value: "\(resource.podRestarts)")
            }
        }
    }
}

struct PodContainersSection: View {
    let resource: KubeResource

    var body: some View {
        DetailCard(title: "Containers") {
            VStack(alignment: .leading, spacing: Tokens.Spacing.sm) {
                ForEach(Array(resource.initContainers.enumerated()), id: \.offset) { _, container in
                    ContainerCard(container: container, statuses: resource.initContainerStatuses,
                                  isInit: true)
                }
                ForEach(Array(resource.containers.enumerated()), id: \.offset) { _, container in
                    ContainerCard(container: container, statuses: resource.containerStatuses,
                                  isInit: false)
                }
            }
        }
    }
}

private struct ContainerCard: View {
    let container: JSONValue
    let statuses: [JSONValue]
    let isInit: Bool

    private var name: String { container["name"]?.stringValue ?? "?" }
    private var image: String { container["image"]?.stringValue ?? "?" }

    private var status: JSONValue? {
        statuses.first { $0["name"]?.stringValue == name }
    }

    private var ready: Bool { status?["ready"]?.boolValue ?? false }
    private var restarts: Int { status?["restartCount"]?.intValue ?? 0 }

    private var stateText: String {
        guard let state = status?["state"]?.objectValue, let key = state.keys.first else {
            return "—"
        }
        if key == "waiting", let reason = state["waiting"]?["reason"]?.stringValue { return reason }
        if key == "terminated", let reason = state["terminated"]?["reason"]?.stringValue { return reason }
        return key.capitalized
    }

    /// "request 100m · limit 500m" from spec.resources, nil when neither is set.
    private func resourceLine(_ key: String) -> String? {
        let resources = container["resources"]
        let request = resources?["requests"]?[key]?.stringValue
        let limit = resources?["limits"]?[key]?.stringValue
        guard request != nil || limit != nil else { return nil }
        return "request \(request ?? "—") · limit \(limit ?? "—")"
    }

    /// The single-key state object ("running"/"waiting"/"terminated" → details).
    private func stateEntry(_ field: String) -> (kind: String, detail: JSONValue)? {
        guard let state = status?[field]?.objectValue, let key = state.keys.first,
              let detail = state[key] else { return nil }
        return (key, detail)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            HStack {
                StatusDot(status: ready ? .success : .warning)
                Text(name).font(.callout.weight(.medium))
                if isInit {
                    Text("init").font(.caption2).foregroundStyle(.secondary)
                }
                Spacer()
                Text(stateText).font(.caption).foregroundStyle(.secondary)
            }
            DetailRow(label: "Image", value: image)
            DetailRow(label: "Restarts", value: "\(restarts)")
            if let cpu = resourceLine("cpu") { DetailRow(label: "CPU", value: cpu) }
            if let memory = resourceLine("memory") { DetailRow(label: "Memory", value: memory) }
            if let current = stateEntry("state") {
                ContainerStateRows(kind: current.kind, detail: current.detail)
            }
            if let last = stateEntry("lastState") {
                Divider().padding(.vertical, 2)
                HStack(spacing: Tokens.Spacing.sm) {
                    Text("Last Status").font(.caption.weight(.semibold)).foregroundStyle(.secondary)
                    Badge(text: last.kind, status: Self.lastStatusColor(last))
                }
                ContainerStateRows(kind: last.kind, detail: last.detail)
            }
        }
        .padding(Tokens.Spacing.sm)
        .background(.quaternary.opacity(0.4), in: RoundedRectangle(cornerRadius: Tokens.Radius.sm))
    }

    private static func lastStatusColor(_ entry: (kind: String, detail: JSONValue)) -> SpectraStatus {
        guard entry.kind == "terminated" else { return .neutral }
        return entry.detail["exitCode"]?.intValue == 0 ? .neutral : .error
    }
}

/// Detail rows for one container state object — reason + exit code, signal,
/// and started/finished times (Lens-style).
private struct ContainerStateRows: View {
    let kind: String       // "running" / "waiting" / "terminated"
    let detail: JSONValue

    var body: some View {
        switch kind {
        case "terminated":
            let reason = detail["reason"]?.stringValue ?? "Terminated"
            DetailRow(label: "Reason",
                      value: detail["exitCode"]?.intValue.map { "\(reason) — exit code: \($0)" } ?? reason)
            if let signal = detail["signal"]?.intValue {
                DetailRow(label: "Signal", value: "\(signal)")
            }
            if let message = detail["message"]?.stringValue {
                DetailRow(label: "Message", value: message)
            }
            if let started = detail["startedAt"]?.stringValue {
                DetailRow(label: "Started at", value: Self.format(started))
            }
            if let finished = detail["finishedAt"]?.stringValue {
                DetailRow(label: "Finished at", value: Self.format(finished))
            }
        case "waiting":
            if let reason = detail["reason"]?.stringValue {
                DetailRow(label: "Reason", value: reason)
            }
            if let message = detail["message"]?.stringValue {
                DetailRow(label: "Message", value: message)
            }
        default:  // running
            if let started = detail["startedAt"]?.stringValue {
                DetailRow(label: "Started at", value: Self.format(started))
            }
        }
    }

    /// "Jun 10, 2026, 7:49:42 AM GMT-4" — local timezone, like Lens.
    private static func format(_ timestamp: String) -> String {
        guard let date = CredentialProvider.parseTimestamp(timestamp) else { return timestamp }
        return date.formatted(date: .abbreviated, time: .complete)
    }
}

struct PodVolumesSection: View {
    let resource: KubeResource

    var body: some View {
        if !resource.volumes.isEmpty {
            DetailCard(title: "Volumes") {
                VStack(alignment: .leading, spacing: Tokens.Spacing.xs) {
                    ForEach(Array(resource.volumes.enumerated()), id: \.offset) { _, volume in
                        let name = volume["name"]?.stringValue ?? "?"
                        let type = volume.objectValue?.keys.first { $0 != "name" } ?? "unknown"
                        DetailRow(label: name, value: type)
                    }
                }
            }
        }
    }
}
