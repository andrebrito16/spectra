//
//  MetricsChartView.swift
//  Spectra
//
//  Swift Charts time-series panel with metric tabs (CPU/Memory) and a time-range
//  selector. Degrades gracefully when Prometheus is unavailable. Embedded in
//  pod/node/cluster detail via MetricsSection.
//

import SwiftUI
import Charts

struct MetricsChartView: View {
    let session: ClusterSession
    let scope: MetricScope

    @Environment(\.appEnv) private var env
    @State private var kind: MetricKind = .cpu
    @State private var rangeSeconds = 3600
    @State private var series: [MetricSeries] = []
    @State private var available = true
    @State private var loading = false

    private let ranges: [(String, Int)] = [("1h", 3600), ("6h", 21600), ("24h", 86400)]

    var body: some View {
        VStack(alignment: .leading, spacing: Tokens.Spacing.sm) {
            HStack {
                Picker("", selection: $kind) {
                    ForEach(MetricKind.allCases) { Text($0.rawValue).tag($0) }
                }
                .pickerStyle(.segmented)
                .frame(width: 180)
                .labelsHidden()
                Spacer()
                Picker("", selection: $rangeSeconds) {
                    ForEach(ranges, id: \.1) { Text($0.0).tag($0.1) }
                }
                .pickerStyle(.segmented)
                .frame(width: 150)
                .labelsHidden()
            }

            if !available {
                Label("Metrics unavailable — configure Prometheus in cluster settings.",
                      systemImage: "chart.line.downtrend.xyaxis")
                    .font(.caption).foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, minHeight: 120)
            } else if loading && series.isEmpty {
                ProgressView().frame(maxWidth: .infinity, minHeight: 120)
            } else {
                chart
            }
        }
        .onChange(of: kind) { _, _ in Task { await reload() } }
        .onChange(of: rangeSeconds) { _, _ in Task { await reload() } }
        .task { await reload() }
    }

    private var chart: some View {
        Chart {
            ForEach(series) { s in
                ForEach(s.points) { point in
                    AreaMark(x: .value("Time", point.date),
                             y: .value(kind.rawValue, point.value))
                    .foregroundStyle(by: .value("Series", s.name))
                    .opacity(0.6)
                }
            }
        }
        .chartYAxis {
            AxisMarks { value in
                AxisGridLine()
                AxisValueLabel {
                    if let double = value.as(Double.self) {
                        Text(format(double))
                    }
                }
            }
        }
        .frame(minHeight: 160)
    }

    private func reload() async {
        guard let record = env.clusters.record(id: session.id) else { return }
        let service = MetricsService(client: session.client,
                                     directURL: record.prometheusDirectURL,
                                     token: record.prometheusToken,
                                     orgID: record.metricsTenant)
        loading = true
        defer { loading = false }
        guard await service.isAvailable() else {
            available = false
            return
        }
        available = true
        let end = Date()
        let start = end.addingTimeInterval(-Double(rangeSeconds))
        let step = max(rangeSeconds / 120, 15)
        let query = PromQLTemplates.query(kind, scope)
        do {
            series = try await service.queryRange(query, start: start, end: end, step: step)
        } catch {
            available = false
        }
    }

    private func format(_ value: Double) -> String {
        switch kind {
        case .cpu:
            return String(format: "%.2f", value)
        case .memory:
            let units = ["B", "KiB", "MiB", "GiB", "TiB"]
            var v = value, i = 0
            while v >= 1024 && i < units.count - 1 { v /= 1024; i += 1 }
            return String(format: "%.1f%@", v, units[i])
        }
    }
}

/// Detail-section wrapper choosing the scope from the resource kind.
struct MetricsSection: View {
    let resource: KubeResource
    let session: ClusterSession

    private var scope: MetricScope? {
        switch resource.kind {
        case "Pod":
            return .pod(namespace: resource.namespace ?? "default", name: resource.name)
        case "Node":
            return .node(name: resource.name)
        default:
            return nil
        }
    }

    var body: some View {
        if let scope {
            DetailCard(title: "Metrics") {
                MetricsChartView(session: session, scope: scope)
            }
        }
    }
}
