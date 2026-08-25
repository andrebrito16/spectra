//
//  ResourceStore.swift
//  Spectra
//
//  @MainActor observable store for one kind in one cluster. Fed by reference-
//  counted informers; coalesces watch bursts with a ~250ms debounce before
//  publishing to SwiftUI. Replaces Freelens's MobX KubeObjectStore.
//

import SwiftUI

@MainActor
@Observable
final class ResourceStore {
    let gvr: GroupVersionResource
    private(set) var items: [KubeResource] = []
    var isLoading = false
    var error: KubeError?
    private(set) var loadedNamespaces: [String] = []

    private let connection: ClusterConnection
    private let client: KubeAPIClient
    private var informers: [Informer] = []
    private var byUID: [String: KubeResource] = [:]
    private var flushScheduled = false
    /// Bumped on every restart; events from informers of an older generation
    /// (cancelled but still draining) are dropped instead of polluting the
    /// fresh state with spurious errors.
    private var generation = 0

    init(gvr: GroupVersionResource, connection: ClusterConnection, client: KubeAPIClient) {
        self.gvr = gvr
        self.connection = connection
        self.client = client
    }

    // MARK: - Subscription (Lens-style: keep stores warm for the session)
    //
    // Once a kind is touched, its informer keeps running for the whole session
    // so revisiting a tab is instant (data already cached). `unsubscribe()` is
    // intentionally a no-op. URLSession caps concurrent connections per host,
    // so this is bounded in practice.

    func subscribe(namespaces: [String]) {
        if informers.isEmpty || loadedNamespaces != namespaces {
            restart(namespaces: namespaces)
        }
    }

    func unsubscribe() { /* kept warm */ }

    /// Stop all informers for good — the owning session is being torn down or
    /// replaced (disconnect/reconnect), so "warm" no longer applies.
    func shutdown() {
        generation += 1  // drop any in-flight events from the dying informers
        stopAll()
    }

    /// Re-run with a new namespace set (selector changed).
    func setNamespaces(_ namespaces: [String]) {
        guard loadedNamespaces != namespaces else { return }
        restart(namespaces: namespaces)
    }

    /// Force a full relist even when the namespace set is unchanged
    /// (Refresh button, error recovery).
    func refresh() {
        restart(namespaces: loadedNamespaces)
    }

    private func restart(namespaces: [String]) {
        stopAll()
        generation += 1
        let gen = generation
        loadedNamespaces = namespaces
        byUID = [:]
        items = []
        error = nil

        let scopes: [String?] = gvr.namespaced && !namespaces.isEmpty ? namespaces : [nil]
        for scope in scopes {
            let informer = Informer(connection: connection, client: client,
                                    gvr: gvr, namespace: scope) { [weak self] event in
                await self?.handle(event, scope: scope, generation: gen)
            }
            informers.append(informer)
            Task { await informer.start() }
        }
    }

    private func stopAll() {
        let toStop = informers
        informers = []
        for informer in toStop {
            Task { await informer.stop() }
        }
    }

    // MARK: - Event application

    private func handle(_ event: InformerEvent, scope: String?, generation: Int) {
        guard generation == self.generation else { return }
        switch event {
        case .loading(let loading):
            isLoading = loading
        case .error(let error):
            self.error = error
        case .listed(let list, _):
            error = nil  // informer recovered — clear any stale failure
            if scope == nil {
                byUID.removeAll()
            } else {
                byUID = byUID.filter { $0.value.namespace != scope }
            }
            for resource in list { byUID[resource.id] = resource }
            scheduleFlush()
        case .event(let watchEvent):
            let resource = watchEvent.object
            switch watchEvent.type {
            case .added, .modified: byUID[resource.id] = resource
            case .deleted: byUID[resource.id] = nil
            default: break
            }
            scheduleFlush()
        }
    }

    private func scheduleFlush() {
        guard !flushScheduled else { return }
        flushScheduled = true
        Task { @MainActor in
            try? await Task.sleep(for: .milliseconds(250))
            self.flushScheduled = false
            self.items = self.byUID.values.sorted { lhs, rhs in
                if lhs.namespace != rhs.namespace {
                    return (lhs.namespace ?? "") < (rhs.namespace ?? "")
                }
                return lhs.name < rhs.name
            }
        }
    }

    // MARK: - Queries

    func byName(_ name: String, namespace: String?) -> KubeResource? {
        items.first { $0.name == name && $0.namespace == namespace }
    }

    func byNamespace(_ namespace: String) -> [KubeResource] {
        items.filter { $0.namespace == namespace }
    }

    func byOwnerUID(_ uid: String) -> [KubeResource] {
        items.filter { $0.ownerReferences.contains { $0.uid == uid } }
    }

    func byLabelSelector(_ selector: [String: String]) -> [KubeResource] {
        guard !selector.isEmpty else { return items }
        return items.filter { resource in
            selector.allSatisfy { resource.labels[$0.key] == $0.value }
        }
    }
}
