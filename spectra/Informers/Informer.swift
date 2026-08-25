//
//  Informer.swift
//  Spectra
//
//  Per-(GVR, scope) informer: list → watch, with relist on 410/expiry and
//  reconnect with backoff. Streams watch events via URLSession.bytes. Feeds a
//  ResourceStore through a sink. Mirrors Freelens's kube-watch pipeline.
//

import Foundation

actor Informer {
    private let connection: ClusterConnection
    private let client: KubeAPIClient
    private let gvr: GroupVersionResource
    private let namespace: String?
    private let sink: @Sendable (InformerEvent) async -> Void
    private var task: Task<Void, Never>?

    init(connection: ClusterConnection, client: KubeAPIClient,
         gvr: GroupVersionResource, namespace: String?,
         sink: @escaping @Sendable (InformerEvent) async -> Void) {
        self.connection = connection
        self.client = client
        self.gvr = gvr
        self.namespace = namespace
        self.sink = sink
    }

    func start() {
        guard task == nil else { return }
        task = Task { await run() }
    }

    func stop() {
        task?.cancel()
        task = nil
    }

    private func run() async {
        var backoff = 1.0
        while !Task.isCancelled {
            do {
                await sink(.loading(true))
                let list = try await client.list(gvr, namespace: namespace)
                await sink(.listed(list.items, resourceVersion: list.resourceVersion))
                await sink(.loading(false))
                backoff = 1.0
                try await watch(resourceVersion: list.resourceVersion)
            } catch is CancellationError {
                break
            } catch {
                // stop() cancels the task; the in-flight list/watch then throws
                // URLError.cancelled (not CancellationError) — don't surface it.
                if Task.isCancelled || (error as? URLError)?.code == .cancelled { break }
                await sink(.error(error as? KubeError ?? .transport(error.localizedDescription)))
                await sink(.loading(false))
            }
            if Task.isCancelled { break }
            try? await Task.sleep(for: .seconds(backoff))
            backoff = min(backoff * 2, 30)
        }
    }

    private func watch(resourceVersion: String?) async throws {
        var query = [
            URLQueryItem(name: "watch", value: "1"),
            URLQueryItem(name: "allowWatchBookmarks", value: "true"),
        ]
        if let resourceVersion {
            query.append(.init(name: "resourceVersion", value: resourceVersion))
        }
        var request = try await connection.makeRequest(
            path: gvr.collectionPath(namespace: namespace), queryItems: query)
        request.timeoutInterval = 3600  // long-lived stream

        let (bytes, response) = try await connection.bytes(for: request)
        if let http = response as? HTTPURLResponse {
            if http.statusCode == 410 { return }  // expired → relist
            guard (200..<300).contains(http.statusCode) else {
                throw KubeError.http(status: http.statusCode, reason: nil, message: "watch failed")
            }
        }

        for try await line in bytes.lines {
            if Task.isCancelled { break }
            guard !line.isEmpty, let data = line.data(using: .utf8),
                  let event = parse(data) else { continue }
            switch event.type {
            case .error:
                throw KubeError.http(status: 410, reason: "Expired", message: "watch expired")
            case .bookmark:
                continue
            default:
                await sink(.event(event))
            }
        }
    }

    private func parse(_ data: Data) -> WatchEvent? {
        guard let value = try? JSONDecoder().decode(JSONValue.self, from: data),
              let typeString = value["type"]?.stringValue,
              let type = WatchEvent.EventType(rawValue: typeString),
              let objectJSON = value["object"] else { return nil }
        return WatchEvent(type: type, object: KubeResource(json: objectJSON))
    }
}
