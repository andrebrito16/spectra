//
//  MetricsModels.swift
//  Spectra
//
//  Models for Prometheus query_range responses and the thin MetricSeries used
//  between the query layer and Swift Charts.
//

import Foundation

nonisolated struct MetricPoint: Sendable, Identifiable {
    let id = UUID()
    let date: Date
    let value: Double
}

nonisolated struct MetricSeries: Sendable, Identifiable {
    let id = UUID()
    let name: String
    let points: [MetricPoint]
}

nonisolated enum MetricKind: String, CaseIterable, Sendable, Identifiable {
    case cpu = "CPU"
    case memory = "Memory"
    var id: String { rawValue }
}

nonisolated enum MetricScope: Sendable {
    case pod(namespace: String, name: String)
    case node(name: String)
    case cluster
}

/// Decoded Prometheus `query_range` response.
nonisolated struct PrometheusResponse: Decodable, Sendable {
    let status: String
    let data: PrometheusData

    struct PrometheusData: Decodable, Sendable {
        let resultType: String
        let result: [PrometheusResult]
    }

    struct PrometheusResult: Decodable, Sendable {
        let metric: [String: String]
        let values: [[PrometheusValue]]
    }

    /// A [timestamp, "value"] pair where timestamp is a number and value a string.
    enum PrometheusValue: Decodable, Sendable {
        case number(Double)
        case string(String)

        init(from decoder: Decoder) throws {
            let container = try decoder.singleValueContainer()
            if let d = try? container.decode(Double.self) { self = .number(d) }
            else { self = .string((try? container.decode(String.self)) ?? "0") }
        }

        var asDouble: Double {
            switch self {
            case .number(let d): return d
            case .string(let s): return Double(s) ?? 0
            }
        }
    }
}
