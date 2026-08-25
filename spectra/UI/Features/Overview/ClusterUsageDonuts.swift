//
//  ClusterUsageDonuts.swift
//  Spectra
//
//  Lens-style cluster capacity donuts on the Overview: one for CPU, one for
//  memory. Concentric rings show usage (metrics-server), requests, and limits
//  (summed from non-finished pod specs), each as a fraction of the cluster's
//  allocatable capacity (summed from nodes). Center shows usage %.
//

import SwiftUI

struct ClusterUsageDonuts: View {
    let session: ClusterSession
    @Environment(\.appEnv) private var env

    private var nodeStore: ResourceStore? {
        session.gvr(forKind: "Node").map { session.store(for: $0) }
    }
    private var podStore: ResourceStore? {
        session.gvr(forKind: "Pod").map { session.store(for: $0) }
    }

    var body: some View {
        HStack(alignment: .top, spacing: Tokens.Spacing.lg) {
            DonutCard(title: "CPU", totals: cpuTotals, format: Self.cores)
            DonutCard(title: "Memory", totals: memoryTotals, format: Self.gib)
        }
        .onAppear {
            nodeStore?.subscribe(namespaces: [])
            podStore?.subscribe(namespaces: session.namespaceScope)
        }
    }

    // MARK: - Aggregation

    struct Totals {
        var capacity = 0.0
        var usage: Double?   // nil when metrics-server is unavailable
        var requests = 0.0
        var limits = 0.0
    }

    /// Pods that still hold their requests/limits on a node.
    private var activePods: [KubeResource] {
        (podStore?.items ?? []).filter { $0.podPhase != "Succeeded" && $0.podPhase != "Failed" }
    }

    private var cpuTotals: Totals {
        var totals = Totals()
        for node in nodeStore?.items ?? [] {
            totals.capacity += KubeQuantity.cpuCores(
                node.status?["allocatable"]?["cpu"]?.stringValue) ?? 0
        }
        if env.nodeMetrics.available {
            totals.usage = env.nodeMetrics.byNode.values.reduce(0) { $0 + $1.cpuCores }
        }
        for pod in activePods {
            for container in pod.containers {
                let resources = container["resources"]
                totals.requests += KubeQuantity.cpuCores(
                    resources?["requests"]?["cpu"]?.stringValue) ?? 0
                totals.limits += KubeQuantity.cpuCores(
                    resources?["limits"]?["cpu"]?.stringValue) ?? 0
            }
        }
        return totals
    }

    private var memoryTotals: Totals {
        var totals = Totals()
        for node in nodeStore?.items ?? [] {
            totals.capacity += KubeQuantity.memoryBytes(
                node.status?["allocatable"]?["memory"]?.stringValue) ?? 0
        }
        if env.nodeMetrics.available {
            totals.usage = env.nodeMetrics.byNode.values.reduce(0) { $0 + $1.memoryBytes }
        }
        for pod in activePods {
            for container in pod.containers {
                let resources = container["resources"]
                totals.requests += KubeQuantity.memoryBytes(
                    resources?["requests"]?["memory"]?.stringValue) ?? 0
                totals.limits += KubeQuantity.memoryBytes(
                    resources?["limits"]?["memory"]?.stringValue) ?? 0
            }
        }
        return totals
    }

    // MARK: - Formatting

    static func cores(_ value: Double) -> String {
        value >= 10 ? String(format: "%.0f cores", value) : String(format: "%.2f cores", value)
    }

    static func gib(_ value: Double) -> String {
        String(format: "%.1f GiB", value / 1_073_741_824)
    }
}

/// One donut: usage / requests / limits as concentric rings over capacity.
private struct DonutCard: View {
    let title: String
    let totals: ClusterUsageDonuts.Totals
    let format: (Double) -> String

    private var usageColor: Color { .blue }
    private var requestsColor: Color { .orange }
    private var limitsColor: Color { .purple }

    private func fraction(_ value: Double?) -> Double {
        guard let value, totals.capacity > 0 else { return 0 }
        return value / totals.capacity
    }

    var body: some View {
        DetailCard(title: title) {
            HStack(spacing: Tokens.Spacing.xl) {
                donut
                legend
                Spacer(minLength: 0)
            }
            .padding(.vertical, Tokens.Spacing.sm)
        }
    }

    private var donut: some View {
        ZStack {
            Ring(fraction: fraction(totals.usage), color: usageColor, diameter: 120)
            Ring(fraction: fraction(totals.requests), color: requestsColor, diameter: 94)
            Ring(fraction: fraction(totals.limits), color: limitsColor, diameter: 68)
            VStack(spacing: 0) {
                if let usage = totals.usage, totals.capacity > 0 {
                    Text("\(Int((usage / totals.capacity * 100).rounded()))%")
                        .font(.headline.monospacedDigit())
                } else {
                    Text("—").font(.headline)
                }
            }
        }
        .frame(width: 132, height: 132)
    }

    private var legend: some View {
        VStack(alignment: .leading, spacing: Tokens.Spacing.xs) {
            legendRow(usageColor, "Usage",
                      totals.usage.map(format) ?? "metrics unavailable",
                      fraction: totals.usage.map(fraction))
            legendRow(requestsColor, "Requests", format(totals.requests),
                      fraction: fraction(totals.requests))
            legendRow(limitsColor, "Limits", format(totals.limits),
                      fraction: fraction(totals.limits))
            legendRow(.secondary, "Capacity", format(totals.capacity), fraction: nil)
        }
    }

    private func legendRow(_ color: Color, _ label: String, _ value: String,
                           fraction: Double?) -> some View {
        HStack(spacing: Tokens.Spacing.sm) {
            Circle().fill(color).frame(width: 8, height: 8)
            Text(label).font(.caption).foregroundStyle(.secondary)
                .frame(width: 60, alignment: .leading)
            Text(value).font(.caption.monospacedDigit())
            if let fraction {
                Text("(\(Int((fraction * 100).rounded()))%)")
                    .font(.caption2.monospacedDigit())
                    .foregroundStyle(.tertiary)
            }
        }
    }
}

/// A circular progress ring; fractions above 1 (e.g. overcommitted limits) are
/// drawn full.
private struct Ring: View {
    let fraction: Double
    let color: Color
    let diameter: CGFloat
    private let lineWidth: CGFloat = 10

    var body: some View {
        ZStack {
            Circle()
                .stroke(.quaternary, lineWidth: lineWidth)
            Circle()
                .trim(from: 0, to: min(max(fraction, 0), 1))
                .stroke(color, style: StrokeStyle(lineWidth: lineWidth, lineCap: .round))
                .rotationEffect(.degrees(-90))
        }
        .frame(width: diameter, height: diameter)
    }
}
