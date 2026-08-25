//
//  ClusterManager.swift
//  Spectra
//
//  Registry of all known clusters and their live `ClusterConnection`s. Loads
//  known clusters from SwiftData, surfaces available kubeconfig contexts, and
//  owns the connect/disconnect lifecycle. Mirrors Freelens's cluster manager.
//

import SwiftUI
import SwiftData

@Observable
@MainActor
final class ClusterManager {
    /// Known clusters, persisted to SwiftData.
    private(set) var records: [ClusterRecord] = []
    /// User-created organizations clusters can be grouped into, ordered.
    private(set) var orgs: [ClusterOrg] = []
    /// Per-cluster displayed connection state (observed by the UI).
    private(set) var states: [String: ClusterConnectionState] = [:]
    /// Per-cluster runtime session (connection + client + discovery + stores).
    private(set) var sessions: [String: ClusterSession] = [:]

    /// The currently-focused cluster (drives the cluster frame). Phase 4 sets it.
    var activeClusterId: String?

    private var connections: [String: ClusterConnection] = [:]
    private var modelContext: ModelContext?
    private let loader = KubeconfigLoader()

    /// PATH additions for exec credential plugins, loaded from AppSettings.
    var extraPATH: String = AppSettings.defaultExtraPATH

    // MARK: - Store-health guards (see the data-loss note on `syncFromKubeconfig`)

    /// The most recent `reload()` threw (store couldn't be read).
    private(set) var lastLoadFailed = false
    /// `syncFromKubeconfig` declined to re-seed because the store read back empty
    /// on an install that has had clusters before — a likely transient glitch,
    /// not a real first run.
    private(set) var refusedSeedOnEmptyStore = false
    /// The catalog shows a recovery banner (instead of the misleading first-run
    /// Welcome) whenever the store looks unreadable / suspiciously empty.
    var storeUnavailable: Bool { lastLoadFailed || refusedSeedOnEmptyStore }

    /// True when the recovery screen can safely offer a "re-detect from kubeconfig"
    /// escape hatch: the store read *cleanly* but came back empty (the GUARD 2
    /// tripwire), as opposed to a hard read failure where re-detecting could clobber
    /// records we merely couldn't load. This is what stops the recovery screen from
    /// being a dead-end when the sticky marker outlives the store it described (a
    /// reinstall / fresh store: marker says "had clusters", store genuinely empty,
    /// so "Try Again" re-reads 0 records forever and never escapes).
    var canReseedFromKubeconfig: Bool { refusedSeedOnEmptyStore && !lastLoadFailed }

    /// Sticky marker that this install has had at least one cluster persisted.
    /// Lives in UserDefaults — NOT SwiftData — on purpose: it has to stay
    /// readable even when the SwiftData store is the thing that failed, so we can
    /// tell a genuine first run (seeding defaults is safe) apart from a store that
    /// came back empty after a glitch (seeding would cement permanent data loss).
    private let hasPersistedClustersKey = "spectra.hasPersistedClusters"
    private var hasPersistedClustersBefore: Bool {
        UserDefaults.standard.bool(forKey: hasPersistedClustersKey)
    }
    private func setHasPersistedClusters(_ value: Bool) {
        UserDefaults.standard.set(value, forKey: hasPersistedClustersKey)
    }

    func attach(modelContext: ModelContext) {
        self.modelContext = modelContext
        loadSettings()
        reloadOrgs()
        reload()
        normalizeOrdering()
        syncFromKubeconfig()
    }

    /// Auto-detect contexts from ~/.kube/config and $KUBECONFIG, adding any that
    /// aren't already known. Existing records (with edits/pins) are preserved.
    func syncFromKubeconfig() {
        guard let modelContext else { return }

        // GUARD 1 — if `reload()` just failed, we have no trustworthy picture of
        // what's persisted. Seeding kubeconfig defaults now would write over
        // records we merely couldn't read. This is the long-idle data-loss we hit:
        // a transient "default.store couldn't be opened" made `reload()` throw,
        // then this sync re-seeded 3 default records over the user's real ones.
        if lastLoadFailed {
            Log.error("syncFromKubeconfig skipped — cluster store could not be read this launch",
                      .persistence)
            return
        }

        // Read the authoritative set of known IDs straight from the store rather
        // than the in-memory `records` cache. Because `id` is `.unique`, inserting
        // a context that already exists would UPSERT and wipe the user's display
        // names / icons / orgs; bailing on a read error makes that impossible.
        let existingIDs: Set<String>
        do {
            existingIDs = Set(try modelContext.fetch(FetchDescriptor<ClusterRecord>()).map(\.id))
        } catch {
            Log.error("syncFromKubeconfig skipped — couldn't read existing records: \(error)",
                      .persistence)
            return
        }

        // GUARD 2 (tripwire) — zero records, yet this install has persisted
        // clusters before. That is almost never a real first run; it means the
        // store opened but presented empty after a transient failure / recovery.
        // Seeding + saving here is exactly what turns a recoverable glitch into
        // PERMANENT loss of display names, orgs and per-cluster prefs. Refuse, and
        // leave the on-disk store untouched for a healthy reload next launch.
        if existingIDs.isEmpty && hasPersistedClustersBefore {
            refusedSeedOnEmptyStore = true
            Log.error("syncFromKubeconfig REFUSED — store returned 0 clusters but this install had clusters before; not re-seeding (avoids overwriting recoverable data)",
                      .persistence)
            return
        }

        let available = availableContexts()
        var added = 0
        var nextOrder = (records.map(\.sortOrder).max() ?? -1) + 1
        for ref in available where !existingIDs.contains(ref.id) {
            let record = ClusterRecord(id: ref.id, kubeconfigPath: ref.kubeconfigPath,
                                       contextName: ref.contextName)
            record.sortOrder = nextOrder
            nextOrder += 1
            modelContext.insert(record)
            added += 1
        }
        if added > 0 {
            try? modelContext.save()
            setHasPersistedClusters(true)
            reload()
            Log.info("Auto-detected \(added) cluster context(s) from kubeconfig", .app)
        }
    }

    /// Re-attempt loading the store after a read failure (drives the catalog's
    /// "Try Again"). Clears the degraded flags and re-syncs once a healthy read
    /// is back.
    func retryLoad() {
        refusedSeedOnEmptyStore = false
        reloadOrgs()
        reload()
        guard !storeUnavailable else { return }
        normalizeOrdering()
        syncFromKubeconfig()
    }

    /// Escape hatch from `refusedSeedOnEmptyStore`: the user explicitly chose, from
    /// the recovery screen, to re-detect contexts from their kubeconfig — accepting
    /// that the empty read is real (e.g. a fresh store after reinstall) rather than a
    /// transient glitch, and that any saved names/orgs that couldn't be read are gone.
    /// Clearing the sticky marker drops GUARD 2 so the normal seed path runs instead
    /// of refusing again. Only valid when `canReseedFromKubeconfig` — a hard read
    /// failure keeps "Try Again" (retry the read), where re-detecting would be unsafe.
    func forceReseedFromKubeconfig() {
        guard canReseedFromKubeconfig else { return }
        refusedSeedOnEmptyStore = false
        setHasPersistedClusters(false)
        syncFromKubeconfig()
    }

    func reload() {
        guard let modelContext else { return }
        let descriptor = FetchDescriptor<ClusterRecord>(sortBy: [SortDescriptor(\.createdAt)])
        // Retry a couple of times: a long-idle relaunch can hit a transient SQLite
        // "file couldn't be opened" that clears on a subsequent attempt.
        var lastError: Error?
        for attempt in 0..<3 {
            do {
                records = try modelContext.fetch(descriptor)
                lastLoadFailed = false
                if !records.isEmpty { setHasPersistedClusters(true) }
                return
            } catch {
                lastError = error
                // Give a transient SQLite lock / "file couldn't be opened" a
                // moment to clear before retrying (no pause = same instant fail).
                if attempt < 2 { Thread.sleep(forTimeInterval: 0.1) }
            }
        }
        // Do NOT clobber `records` to [] here. An empty `records` would (a) flash
        // the Welcome screen over real data and (b) let `syncFromKubeconfig`
        // re-seed defaults and save over the user's customized records/orgs.
        // Keep the last good in-memory snapshot and flag the failure instead.
        lastLoadFailed = true
        Log.error("Failed to load cluster records: \(lastError.map { "\($0)" } ?? "unknown")",
                  .persistence)
    }

    func reloadOrgs() {
        guard let modelContext else { return }
        let descriptor = FetchDescriptor<ClusterOrg>(
            sortBy: [SortDescriptor(\.sortOrder), SortDescriptor(\.createdAt)])
        orgs = (try? modelContext.fetch(descriptor)) ?? []
    }

    // MARK: - Orgs & ordering (drag-to-reorder, grouping)

    /// A display group: an org (nil = the ungrouped bucket) plus its clusters in
    /// drag order. Drives the catalog sections and the cluster-switch order.
    struct ClusterGroup: Identifiable {
        let org: ClusterOrg?
        let records: [ClusterRecord]
        var id: String { org?.id ?? "__ungrouped__" }
        var name: String { org?.name ?? "Ungrouped" }
    }

    /// The org a record effectively belongs to, treating a dangling id (org was
    /// deleted) as ungrouped.
    private func effectiveOrgId(_ record: ClusterRecord) -> String? {
        guard let id = record.orgId, orgs.contains(where: { $0.id == id }) else { return nil }
        return id
    }

    /// Clusters grouped by org (orgs in their own order, ungrouped last), each
    /// group sorted by `sortOrder`. Empty orgs are included (as drop targets).
    var groupedClusters: [ClusterGroup] {
        var result: [ClusterGroup] = []
        for org in orgs {
            let recs = records.filter { $0.orgId == org.id }
                .sorted { ($0.sortOrder, $0.createdAt) < ($1.sortOrder, $1.createdAt) }
            result.append(ClusterGroup(org: org, records: recs))
        }
        let ungrouped = records.filter { effectiveOrgId($0) == nil }
            .sorted { ($0.sortOrder, $0.createdAt) < ($1.sortOrder, $1.createdAt) }
        result.append(ClusterGroup(org: nil, records: ungrouped))
        return result
    }

    /// All clusters flattened in visual order — used for next/previous switching.
    var orderedRecords: [ClusterRecord] {
        groupedClusters.flatMap(\.records)
    }

    func createOrg(name: String) {
        guard let modelContext else { return }
        let org = ClusterOrg(name: name, sortOrder: (orgs.map(\.sortOrder).max() ?? -1) + 1)
        modelContext.insert(org)
        try? modelContext.save()
        reloadOrgs()
    }

    func renameOrg(_ org: ClusterOrg, to name: String) {
        org.name = name
        try? modelContext?.save()
        reloadOrgs()
    }

    /// Delete an org; its clusters fall back to ungrouped (kubeconfigs untouched).
    func deleteOrg(_ org: ClusterOrg) {
        for record in records where record.orgId == org.id { record.orgId = nil }
        modelContext?.delete(org)
        try? modelContext?.save()
        reloadOrgs()
        reload()
        normalizeOrdering()
    }

    /// Assign a cluster to an org (nil = ungrouped), placing it at the group's end.
    func setOrg(_ orgId: String?, for recordId: String) {
        guard let record = record(id: recordId) else { return }
        let previous = effectiveOrgId(record)
        record.orgId = orgId
        record.sortOrder = .max  // sort last in the destination group, then densify
        densify(orgId: orgId)
        if previous != orgId { densify(orgId: previous) }
        try? modelContext?.save()
        reload()
    }

    /// Move the dragged cluster to sit immediately before `targetId`, adopting the
    /// target's org. Drives drag-and-drop reordering across and within groups.
    func moveCluster(_ draggedId: String, before targetId: String) {
        guard draggedId != targetId,
              let dragged = record(id: draggedId),
              let target = record(id: targetId) else { return }
        let destOrg = effectiveOrgId(target)
        let previous = effectiveOrgId(dragged)
        dragged.orgId = destOrg
        var group = records
            .filter { effectiveOrgId($0) == destOrg && $0.id != draggedId }
            .sorted { ($0.sortOrder, $0.createdAt) < ($1.sortOrder, $1.createdAt) }
        let index = group.firstIndex { $0.id == targetId } ?? group.count
        group.insert(dragged, at: index)
        for (i, record) in group.enumerated() { record.sortOrder = i }
        if previous != destOrg { densify(orgId: previous) }
        try? modelContext?.save()
        reload()
    }

    /// Reassign dense 0..n-1 `sortOrder` values to one group in its current order.
    private func densify(orgId: String?) {
        let group = records.filter { effectiveOrgId($0) == orgId }
            .sorted { ($0.sortOrder, $0.createdAt) < ($1.sortOrder, $1.createdAt) }
        for (i, record) in group.enumerated() { record.sortOrder = i }
    }

    /// One-time/idempotent repair so every group has dense, distinct ordering
    /// (covers the migration from before `sortOrder` existed — all were 0).
    private func normalizeOrdering() {
        var changed = false
        for group in groupedClusters {
            for (i, record) in group.records.enumerated() where record.sortOrder != i {
                record.sortOrder = i
                changed = true
            }
        }
        if changed {
            try? modelContext?.save()
            reload()
        }
    }

    private func loadSettings() {
        guard let modelContext else { return }
        let descriptor = FetchDescriptor<AppSettings>()
        if let settings = try? modelContext.fetch(descriptor).first {
            extraPATH = settings.extraPATH
            Log.minimumLevel = LogLevel(rawValue: settings.logLevel) ?? .info
        } else {
            let settings = AppSettings()
            modelContext.insert(settings)
            try? modelContext.save()
            extraPATH = settings.extraPATH
        }
    }

    // MARK: - Records

    func record(id: String) -> ClusterRecord? {
        records.first { $0.id == id }
    }

    func state(for id: String) -> ClusterConnectionState {
        if let existing = states[id] { return existing }
        let state = ClusterConnectionState()
        states[id] = state
        return state
    }

    // MARK: - Kubeconfig discovery

    func availableContexts() -> [KubeContextRef] {
        loader.availableContexts()
    }

    func contexts(inFile path: String) -> [KubeContextRef] {
        guard let config = try? loader.load(path: path) else { return [] }
        return loader.contextRefs(path: path, config: config)
    }

    // MARK: - Add / remove

    @discardableResult
    func addCluster(_ ref: KubeContextRef) -> ClusterRecord {
        if let existing = record(id: ref.id) { return existing }
        let record = ClusterRecord(id: ref.id, kubeconfigPath: ref.kubeconfigPath,
                                   contextName: ref.contextName)
        record.sortOrder = (records.map(\.sortOrder).max() ?? -1) + 1
        modelContext?.insert(record)
        try? modelContext?.save()
        reload()
        return record
    }

    func remove(id: String) async {
        await disconnect(id: id)
        if let record = record(id: id) {
            modelContext?.delete(record)
            try? modelContext?.save()
        }
        states[id] = nil
        if activeClusterId == id { activeClusterId = nil }
        reload()
        // Deliberate emptiness — clear the sticky marker so a real "no clusters"
        // state isn't later mistaken for a glitched empty read by the tripwire.
        if records.isEmpty && !lastLoadFailed { setHasPersistedClusters(false) }
    }

    // MARK: - Connection lifecycle

    func connection(id: String) -> ClusterConnection? {
        connections[id]
    }

    func session(id: String) -> ClusterSession? {
        sessions[id]
    }

    var activeSession: ClusterSession? {
        guard let activeClusterId else { return nil }
        return sessions[activeClusterId]
    }

    func connect(id: String) async {
        guard let record = record(id: id) else { return }
        let state = state(for: id)
        do {
            let resolved = try loader.resolve(path: record.kubeconfigPath,
                                              contextName: record.contextName)
            let connection = try ClusterConnection(resolved: resolved,
                                                   extraPATH: extraPATH, state: state)
            connections[id] = connection
            sessions[id]?.shutdown()  // stop informers still on the old connection
            let session = ClusterSession(connection: connection)
            sessions[id] = session
            record.lastConnectedAt = Date()
            try? modelContext?.save()
            await connection.connect()
            if state.status.isConnected {
                await session.bootstrap()
            }
        } catch {
            state.set(.unreachable(error.localizedDescription))
            Log.error("Connect failed for \(id): \(error.localizedDescription)", .client)
        }
    }

    func disconnect(id: String) async {
        sessions[id]?.shutdown()
        if let connection = connections[id] {
            await connection.disconnect()
        }
        connections[id] = nil
        sessions[id] = nil
    }

    /// Tear down and re-establish a cluster's connection (used by the Retry
    /// action after a failed connect). Invalidates the previous connection
    /// without flipping the status to disconnected, then connects fresh.
    func reconnect(id: String) async {
        if let connection = connections[id] {
            await connection.invalidate()
        }
        await connect(id: id)
    }
}
