//
//  MetricsService.swift
//  Spectra
//
//  Discovers a Prometheus-compatible metrics backend (Grafana Mimir, Thanos, or
//  vanilla Prometheus) and queries it. On EKS the API-server service proxy to
//  metrics pods is often blocked, so when an Ingress exists for the backend we
//  query it directly (as Grafana does). Mimir uses the /prometheus path prefix
//  and may need an X-Scope-OrgID tenant header.
//

import Foundation

actor MetricsService {
    private let client: KubeAPIClient
    private let userDirectURL: String?
    private let token: String?
    private let orgID: String?

    private enum Backend {
        case direct(String)                  // absolute base URL (ingress or user URL)
        case proxy(base: String, prefix: String)
    }
    private var backend: Backend?
    private var resolved = false

    init(client: KubeAPIClient, directURL: String?, token: String?, orgID: String?) {
        self.client = client
        self.userDirectURL = (directURL?.isEmpty ?? true) ? nil : directURL
        self.token = (token?.isEmpty ?? true) ? nil : token
        self.orgID = (orgID?.isEmpty ?? true) ? nil : orgID
    }

    func isAvailable() async -> Bool {
        await resolve()
        return backend != nil
    }

    // MARK: - Discovery

    private static let serviceGVR = GroupVersionResource(
        group: "", version: "v1", resource: "services", kind: "Service", namespaced: true)
    private static let ingressGVR = GroupVersionResource(
        group: "networking.k8s.io", version: "v1", resource: "ingresses",
        kind: "Ingress", namespaced: true)

    private func resolve() async {
        guard !resolved else { return }
        resolved = true

        if let userDirectURL {
            backend = .direct(userDirectURL)
            return
        }

        // (serviceSelectors, prometheus-API path prefix)
        let providers: [(selectors: [String], prefix: String)] = [
            (["app.kubernetes.io/name=grafana-mimir,app.kubernetes.io/component=query-frontend",
              "app.kubernetes.io/name=mimir,app.kubernetes.io/component=query-frontend",
              "app.kubernetes.io/name=grafana-mimir,app.kubernetes.io/component=gateway",
              "app.kubernetes.io/name=mimir,app.kubernetes.io/component=nginx"], "/prometheus"),
            (["app.kubernetes.io/name=thanos-query", "app.kubernetes.io/name=thanos-querier",
              "app=thanos-query"], ""),
            (["app.kubernetes.io/name=prometheus,app.kubernetes.io/component=server",
              "app=prometheus,component=server", "app.kubernetes.io/name=prometheus"], ""),
        ]

        for provider in providers {
            for selector in provider.selectors {
                guard let svc = await firstService(selector: selector),
                      let namespace = svc.namespace else { continue }
                // Prefer an Ingress (works when API-proxy is blocked); else proxy.
                if let url = await ingressURL(forService: svc.name, namespace: namespace) {
                    backend = .direct(url)
                } else {
                    backend = .proxy(base: proxyBase(svc), prefix: provider.prefix)
                }
                return
            }
        }
    }

    private func firstService(selector: String) async -> KubeResource? {
        try? await client.list(Self.serviceGVR, labelSelector: selector).items.first
    }

    /// Find an Ingress whose backend points at the service; return its base URL
    /// (host + path), e.g. https://mimir.example/prometheus.
    private func ingressURL(forService serviceName: String, namespace: String) async -> String? {
        guard let list = try? await client.list(Self.ingressGVR, namespace: namespace) else {
            return nil
        }
        for ingress in list.items {
            for rule in ingress.spec?["rules"]?.arrayValue ?? [] {
                guard let host = rule["host"]?.stringValue else { continue }
                for path in rule["http"]?["paths"]?.arrayValue ?? [] {
                    let backendName = path["backend"]?["service"]?["name"]?.stringValue
                    guard backendName == serviceName else { continue }
                    let p = path["path"]?.stringValue ?? ""
                    let pathPart = (p == "/" || p.isEmpty) ? "" : p
                    return "https://\(host)\(pathPart)"
                }
            }
        }
        return nil
    }

    private func proxyBase(_ service: KubeResource) -> String {
        let namespace = service.namespace ?? "default"
        let ports = service.spec?["ports"]?.arrayValue ?? []
        let port = ports.first { ($0["name"]?.stringValue ?? "").contains("http") }?["port"]?.intValue
            ?? ports.first { ($0["port"]?.intValue ?? 0) != 9095 }?["port"]?.intValue
            ?? ports.first?["port"]?.intValue
            ?? 9090
        return "/api/v1/namespaces/\(namespace)/services/\(service.name):\(port)/proxy"
    }

    // MARK: - Query

    func queryRange(_ query: String, start: Date, end: Date, step: Int) async throws -> [MetricSeries] {
        await resolve()
        guard let backend else { return [] }
        let queryItems = [
            URLQueryItem(name: "query", value: query),
            URLQueryItem(name: "start", value: String(Int(start.timeIntervalSince1970))),
            URLQueryItem(name: "end", value: String(Int(end.timeIntervalSince1970))),
            URLQueryItem(name: "step", value: "\(step)s"),
        ]

        let response: PrometheusResponse
        switch backend {
        case .direct(let base):
            response = try await queryDirect(base: base, queryItems: queryItems)
        case .proxy(let base, let prefix):
            var request = try await client.connection.makeRequest(
                path: "\(base)\(prefix)/api/v1/query_range", queryItems: queryItems)
            if let orgID { request.setValue(orgID, forHTTPHeaderField: "X-Scope-OrgID") }
            response = try await client.performDecodable(request, as: PrometheusResponse.self)
        }
        return seriesFrom(response)
    }

    private func queryDirect(base: String, queryItems: [URLQueryItem]) async throws -> PrometheusResponse {
        let trimmed = base.hasSuffix("/") ? String(base.dropLast()) : base
        guard var components = URLComponents(string: "\(trimmed)/api/v1/query_range") else {
            throw KubeError.invalidURL(base)
        }
        components.queryItems = queryItems
        guard let url = components.url else { throw KubeError.invalidURL(base) }
        var request = URLRequest(url: url)
        if let token { request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization") }
        if let orgID { request.setValue(orgID, forHTTPHeaderField: "X-Scope-OrgID") }
        let (data, _) = try await URLSession.shared.data(for: request)
        return try JSONDecoder().decode(PrometheusResponse.self, from: data)
    }

    private func seriesFrom(_ response: PrometheusResponse) -> [MetricSeries] {
        response.data.result.map { result in
            let name = result.metric["pod"] ?? result.metric["instance"]
                ?? result.metric["node"] ?? result.metric["__name__"] ?? "series"
            let points = result.values.compactMap { pair -> MetricPoint? in
                guard pair.count == 2 else { return nil }
                return MetricPoint(date: Date(timeIntervalSince1970: pair[0].asDouble),
                                   value: pair[1].asDouble)
            }
            return MetricSeries(name: name, points: points)
        }
    }
}
