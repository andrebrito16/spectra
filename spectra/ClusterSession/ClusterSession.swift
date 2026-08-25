//
//  ClusterSession.swift
//  Spectra
//
//  Per-cluster runtime: the authenticated connection, the generic client, the
//  discovery results (GVR table, namespaces, RBAC), the selected-namespace set,
//  and a lazily-created cache of ResourceStores (the dynamic registry / API
//  manager). One ClusterSession exists per connected cluster.
//

import SwiftUI

@MainActor
@Observable
final class ClusterSession {
    nonisolated let id: String
    nonisolated let connection: ClusterConnection
    nonisolated let client: KubeAPIClient
    nonisolated let discovery: Discovery

    private(set) var gvrs: [GroupVersionResource] = []
    /// Namespace names seeded by the one-shot discovery list — the immediate
    /// fallback shown before the live watch lists, and the value used when RBAC
    /// forbids watching namespaces.
    private(set) var seededNamespaces: [String] = []
    /// Live namespace store, kept warm so the namespace filter reflects
    /// namespaces created/deleted while the app is open (see startNamespaceWatch).
    private var namespaceStore: ResourceStore?

    /// Namespace names — live from the Namespace informer once it has listed,
    /// otherwise the discovery seed.
    var namespaces: [String] {
        if let store = namespaceStore, !store.items.isEmpty {
            return store.items.map(\.name).sorted()
        }
        return seededNamespaces
    }
    private(set) var serverVersion: String?
    private(set) var bootstrapError: String?
    private(set) var isBootstrapped = false
    /// Cached CRDs, used to derive printer columns for custom-resource lists.
    private(set) var crds: [KubeResource] = []

    /// Selected namespaces driving informer subscriptions; empty = all namespaces.
    var selectedNamespaces: Set<String> = []

    /// RBAC: kinds the user may "list", keyed by GVR id (populated on bootstrap).
    private(set) var allowedToList: Set<String> = []

    private var stores: [String: ResourceStore] = [:]

    init(connection: ClusterConnection) {
        self.id = connection.id
        self.connection = connection
        let client = KubeAPIClient(connection: connection)
        self.client = client
        self.discovery = Discovery(client: client)
    }

    /// Seed the sidebar immediately with well-known built-in GVRs so the user
    /// can click Pods/Services/etc. while real discovery runs in background.
    /// Discovery + version + namespaces + CRDs all run in parallel; the GVR
    /// table is replaced with the discovered set when it lands (adds CRDs).
    func bootstrap() async {
        // Step 1: seed instantly — sidebar appears, user can navigate.
        if gvrs.isEmpty { gvrs = WellKnownGVRs.all }

        // Step 2: kick everything off in parallel.
        let discovery = self.discovery
        let client = self.client
        async let versionResult = try? await discovery.serverVersion()
        async let resourcesResult = try? await discovery.discoverResources()
        async let namespacesResult = try? await discovery.listNamespaces()

        // Step 3: fold results in as they arrive (no serial wait).
        if let version = await versionResult { serverVersion = version.gitVersion }
        if let ns = await namespacesResult { seededNamespaces = ns }
        if let resources = await resourcesResult, !resources.isEmpty {
            gvrs = resources.sorted { $0.kind < $1.kind }
        }
        isBootstrapped = true

        // Keep a warm informer on cluster Namespaces so the namespace filter
        // stays in sync with namespaces created/deleted after bootstrap (the
        // discovery seed above is a one-shot list and goes stale).
        startNamespaceWatch()

        // Step 4: CRD list (for printer columns on custom resources). Background-y,
        // doesn't block isBootstrapped.
        if let crdGVR = gvrs.first(where: { $0.kind == "CustomResourceDefinition" }),
           let list = try? await client.list(crdGVR) {
            crds = list.items
        }
    }

    /// Subscribe to a cluster-wide Namespace informer via the shared store
    /// registry (so the Namespaces list view reuses the same warm informer).
    /// Cluster-scoped, so an empty namespace scope means "all". No-op if RBAC
    /// later forbids the watch — `namespaces` falls back to the discovery seed.
    private func startNamespaceWatch() {
        guard namespaceStore == nil, let gvr = gvr(forKind: "Namespace") else { return }
        let store = store(for: gvr)
        store.subscribe(namespaces: [])
        namespaceStore = store
    }

    // MARK: - GVR lookup

    func gvr(forKind kind: String, group: String? = nil) -> GroupVersionResource? {
        if let group {
            return gvrs.first { $0.kind == kind && $0.group == group }
        }
        return gvrs.first { $0.kind == kind }
    }

    func gvr(forResource resource: String) -> GroupVersionResource? {
        gvrs.first { $0.resource == resource }
    }

    func gvr(byID id: String) -> GroupVersionResource? {
        gvrs.first { $0.id == id }
    }

    // MARK: - Store registry (dynamic; CRDs get a store with no extra code)

    func store(for gvr: GroupVersionResource) -> ResourceStore {
        if let existing = stores[gvr.id] { return existing }
        let store = ResourceStore(gvr: gvr, connection: connection, client: client)
        stores[gvr.id] = store
        return store
    }

    /// Derive list columns for a custom resource from its CRD's printer columns.
    func printerColumns(forGVR gvr: GroupVersionResource) -> [ColumnDefinition]? {
        guard let crd = crds.first(where: {
            $0.spec?["group"]?.stringValue == gvr.group
            && $0.spec?["names"]?["plural"]?.stringValue == gvr.resource
        }) else { return nil }
        let versions = crd.spec?["versions"]?.arrayValue ?? []
        let version = versions.first { $0["name"]?.stringValue == gvr.version } ?? versions.first
        let printer = version?["additionalPrinterColumns"]?.arrayValue ?? []
        guard !printer.isEmpty else { return nil }

        var columns: [ColumnDefinition] = [Columns.name]
        if gvr.namespaced { columns.append(Columns.namespace()) }
        for column in printer.prefix(6) {
            guard let name = column["name"]?.stringValue,
                  let path = column["jsonPath"]?.stringValue else { continue }
            let components = path.split(separator: ".").map(String.init).filter { !$0.isEmpty }
            columns.append(ColumnDefinition(id: name, title: name, width: 130) { resource in
                resource.value(at: components)?.stringValue ?? "—"
            })
        }
        columns.append(Columns.age)
        return columns
    }

    /// Namespace scope for subscriptions ([] = all namespaces).
    var namespaceScope: [String] {
        selectedNamespaces.isEmpty ? [] : Array(selectedNamespaces).sorted()
    }

    /// Propagate a namespace-selection change to all active stores.
    func applyNamespaceSelection() {
        let scope = namespaceScope
        for store in stores.values {
            store.setNamespaces(scope)
        }
    }

    /// Stop all informers — called when this session is replaced or its
    /// connection torn down, so nothing keeps using the dead URLSession.
    func shutdown() {
        for store in stores.values {
            store.shutdown()
        }
    }
}
