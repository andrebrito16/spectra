//
//  NodeUsageCell.swift
//  Spectra
//
//  Compact CPU/RAM usage bar for the Nodes list, fed by metrics-server
//  (NodeMetricsProvider) over the node's allocatable/capacity. Like Freelens's
//  node usage indicators.
//

import SwiftUI

struct NodeUsageCell: View {
    enum Metric { case cpu, memory }

    let node: KubeResource
    let metric: Metric
    @Environment(\.appEnv) private var env

    private var fraction: Double? {
        guard let usage = env.nodeMetrics.byNode[node.name] else { return nil }
        switch metric {
        case .cpu:
            guard let capacity = capacityCPU, capacity > 0 else { return nil }
            return min(usage.cpuCores / capacity, 1)
        case .memory:
            guard let capacity = capacityMemory, capacity > 0 else { return nil }
            return min(usage.memoryBytes / capacity, 1)
        }
    }

    private var capacityCPU: Double? {
        KubeQuantity.cpuCores(node.status?["allocatable"]?["cpu"]?.stringValue
            ?? node.status?["capacity"]?["cpu"]?.stringValue)
    }

    private var capacityMemory: Double? {
        KubeQuantity.memoryBytes(node.status?["allocatable"]?["memory"]?.stringValue
            ?? node.status?["capacity"]?["memory"]?.stringValue)
    }

    private var detail: String {
        guard let usage = env.nodeMetrics.byNode[node.name] else { return "—" }
        switch metric {
        case .cpu:
            let total = capacityCPU ?? 0
            return String(format: "%.2f / %.0f cores", usage.cpuCores, total)
        case .memory:
            return "\(KubeQuantity.formatBytes(usage.memoryBytes)) / \(KubeQuantity.formatBytes(capacityMemory ?? 0))"
        }
    }

    var body: some View {
        if let fraction {
            VStack(alignment: .leading, spacing: 2) {
                Text("\(Int((fraction * 100).rounded()))%")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                GeometryReader { geo in
                    ZStack(alignment: .leading) {
                        Capsule().fill(.quaternary)
                        Capsule().fill(color(fraction))
                            .frame(width: max(2, geo.size.width * fraction))
                    }
                }
                .frame(height: 5)
            }
            .help(detail)
        } else {
            Text("—").foregroundStyle(.tertiary)
        }
    }

    private func color(_ fraction: Double) -> Color {
        switch fraction {
        case ..<0.7: return .green
        case ..<0.9: return .orange
        default: return .red
        }
    }
}
