//
//  NodeMetricsProvider.swift
//  Spectra
//
//  Polls metrics-server (metrics.k8s.io) for live per-node CPU/memory usage —
//  the simple, node-name-keyed source Lens/Freelens-style usage bars use. Served
//  through the API server (aggregated API), so it works where pod-proxy doesn't.
//

import SwiftUI

@MainActor
@Observable
final class NodeMetricsProvider {
    struct Usage: Sendable {
        var cpuCores: Double
        var memoryBytes: Double
    }

    private(set) var byNode: [String: Usage] = [:]
    private(set) var available = false
    private var task: Task<Void, Never>?

    func start(session: ClusterSession) {
        stop()
        task = Task { [weak self] in
            while !Task.isCancelled {
                await self?.fetch(session: session)
                try? await Task.sleep(for: .seconds(30))
            }
        }
    }

    func stop() {
        task?.cancel()
        task = nil
        byNode = [:]
        available = false
    }

    func usage(forNode name: String) -> Usage? {
        byNode[name]
    }

    private func fetch(session: ClusterSession) async {
        do {
            let request = try await session.connection.makeRequest(
                path: "/apis/metrics.k8s.io/v1beta1/nodes")
            let (data, http) = try await session.connection.perform(request)
            guard (200..<300).contains(http.statusCode) else {
                available = false
                return
            }
            let value = try JSONDecoder().decode(JSONValue.self, from: data)
            var result: [String: Usage] = [:]
            for item in value["items"]?.arrayValue ?? [] {
                guard let name = item.value(at: ["metadata", "name"])?.stringValue else { continue }
                let cpu = KubeQuantity.cpuCores(item.value(at: ["usage", "cpu"])?.stringValue) ?? 0
                let mem = KubeQuantity.memoryBytes(item.value(at: ["usage", "memory"])?.stringValue) ?? 0
                result[name] = Usage(cpuCores: cpu, memoryBytes: mem)
            }
            byNode = result
            available = !result.isEmpty
        } catch {
            available = false
        }
    }
}
