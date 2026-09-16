//
//  CatalogView.swift
//  Spectra
//
//  Cluster catalog / landing screen. Shows a welcome (first-run) when no clusters
//  are known, otherwise the clusters — grouped into user-created Orgs when any
//  exist, a flat grid otherwise. Clusters are drag-and-drop reorderable; dropping
//  a cluster on another reorders it, dropping on an org header/zone files it into
//  that org. Mirrors Freelens's catalog + welcome.
//

import SwiftUI

struct CatalogView: View {
    @Environment(\.appEnv) private var env
    @State private var orgSheet: OrgSheetTarget?

    var body: some View {
        Group {
            if env.clusters.storeUnavailable {
                StoreRecoveryView()
            } else if env.clusters.records.isEmpty {
                WelcomeView()
            } else {
                clusterContent
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(.background)
        .navigationTitle("Clusters")
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                Button { env.clusters.syncFromKubeconfig() } label: {
                    Label("Refresh", systemImage: "arrow.clockwise")
                }
                .help("Re-detect contexts from ~/.kube/config")
            }
            ToolbarItem(placement: .primaryAction) {
                Button { orgSheet = .create } label: {
                    Label("New Org", systemImage: "folder.badge.plus")
                }
                .help("Create an organization to group clusters")
            }
            ToolbarItem(placement: .primaryAction) {
                Button { env.navigation.showAddCluster = true } label: {
                    Label("Add Cluster", systemImage: "plus")
                }
            }
        }
        .sheet(item: $orgSheet) { OrgSheet(org: $0.org) }
    }

    private var clusterContent: some View {
        ScrollView {
            LazyVStack(alignment: .leading, spacing: Tokens.Spacing.lg) {
                if env.clusters.orgs.isEmpty {
                    ClusterGrid(records: env.clusters.orderedRecords)
                } else {
                    ForEach(env.clusters.groupedClusters.filter {
                        $0.org != nil || !$0.records.isEmpty
                    }) { group in
                        OrgSection(group: group, onRename: { orgSheet = .rename($0) })
                    }
                }
            }
            .padding(Tokens.Spacing.xl)
            .animation(.snappy, value: env.clusters.records.map(\.sortOrder))
        }
    }
}

/// One org (or the ungrouped bucket) with its clusters, acting as a drop target.
private struct OrgSection: View {
    @Environment(\.appEnv) private var env
    let group: ClusterManager.ClusterGroup
    let onRename: (ClusterOrg) -> Void
    @State private var targeted = false

    var body: some View {
        VStack(alignment: .leading, spacing: Tokens.Spacing.md) {
            header
            if group.records.isEmpty {
                emptyDropZone
            } else {
                ClusterGrid(records: group.records)
            }
        }
        .padding(Tokens.Spacing.md)
        .background(targeted ? AnyShapeStyle(env.theme.accent.opacity(0.08))
                             : AnyShapeStyle(.clear),
                    in: RoundedRectangle(cornerRadius: Tokens.Radius.lg))
    }

    private var header: some View {
        HStack(spacing: Tokens.Spacing.sm) {
            Image(systemName: group.org == nil ? "tray" : "folder.fill")
                .foregroundStyle(group.org == nil ? AnyShapeStyle(.secondary)
                                                  : AnyShapeStyle(env.theme.accent))
            Text(group.name)
                .font(.headline)
            Text("\(group.records.count)")
                .font(.caption.monospacedDigit())
                .foregroundStyle(.secondary)
                .padding(.horizontal, 6)
                .padding(.vertical, 1)
                .background(.quaternary, in: Capsule())
            Spacer()
            if let org = group.org {
                Menu {
                    Button("Rename…") { onRename(org) }
                    Button("Delete Org", role: .destructive) { env.clusters.deleteOrg(org) }
                } label: {
                    Image(systemName: "ellipsis.circle").foregroundStyle(.secondary)
                }
                .menuStyle(.borderlessButton)
                .fixedSize()
            }
        }
        .padding(.horizontal, Tokens.Spacing.xs)
        .contentShape(Rectangle())
        .dropDestination(for: String.self) { items, _ in
            guard let dragged = items.first else { return false }
            env.clusters.setOrg(group.org?.id, for: dragged)
            return true
        } isTargeted: { targeted = $0 }
    }

    private var emptyDropZone: some View {
        RoundedRectangle(cornerRadius: Tokens.Radius.lg)
            .strokeBorder(style: StrokeStyle(lineWidth: 1, dash: [6]))
            .foregroundStyle(.quaternary)
            .frame(height: 60)
            .overlay {
                Text("Drag clusters here")
                    .font(.caption)
                    .foregroundStyle(.tertiary)
            }
            .dropDestination(for: String.self) { items, _ in
                guard let dragged = items.first else { return false }
                env.clusters.setOrg(group.org?.id, for: dragged)
                return true
            } isTargeted: { targeted = $0 }
    }
}

private struct ClusterGrid: View {
    let records: [ClusterRecord]

    var body: some View {
        LazyVGrid(columns: [GridItem(.adaptive(minimum: 240), spacing: Tokens.Spacing.lg)],
                  spacing: Tokens.Spacing.lg) {
            ForEach(records) { record in
                ClusterCard(record: record)
            }
        }
    }
}

private struct ClusterCard: View {
    @Environment(\.appEnv) private var env
    let record: ClusterRecord
    @State private var showRename = false

    private var status: ConnectionStatus {
        env.clusters.states[record.id]?.status ?? .disconnected
    }

    private var version: String? {
        env.clusters.states[record.id]?.serverVersion
    }

    var body: some View {
        Button {
            env.openCluster(record.id)
        } label: {
            VStack(alignment: .leading, spacing: Tokens.Spacing.sm) {
                HStack {
                    Image(systemName: record.effectiveIcon)
                        .font(.title)
                        .foregroundStyle(record.identityStyle(fallback: env.theme.accent))
                    Spacer()
                    StatusDot(status: status.status, diameter: 10)
                }
                Text(record.effectiveName)
                    .font(.headline)
                    .lineLimit(1)
                Text(record.contextName)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                if let version {
                    Text(version).font(.caption2).foregroundStyle(.tertiary)
                } else {
                    Text(status.label).font(.caption2).foregroundStyle(.tertiary)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(Tokens.Spacing.lg)
            .background {
                if let start = record.customColor {
                    ClusterThemeBackground(start: start, end: record.gradientEndColor ?? start,
                                           angle: record.gradientAngle ?? 135)
                }
            }
            .background(.regularMaterial,
                        in: RoundedRectangle(cornerRadius: Tokens.Radius.lg))
            .clipShape(RoundedRectangle(cornerRadius: Tokens.Radius.lg))
        }
        .buttonStyle(.plain)
        .draggable(record.id)
        .dropDestination(for: String.self) { items, _ in
            guard let dragged = items.first else { return false }
            env.clusters.moveCluster(dragged, before: record.id)
            return true
        }
        .contextMenu {
            Button("Open") { env.openCluster(record.id) }
            Button("Customize…") { showRename = true }
            if status.isConnected {
                Button("Disconnect") { Task { await env.clusters.disconnect(id: record.id) } }
            } else {
                Button("Connect") { Task { await env.clusters.connect(id: record.id) } }
            }
            Divider()
            Menu("Move to") {
                Button("Ungrouped") { env.clusters.setOrg(nil, for: record.id) }
                if !env.clusters.orgs.isEmpty { Divider() }
                ForEach(env.clusters.orgs) { org in
                    Button(org.name) { env.clusters.setOrg(org.id, for: record.id) }
                }
            }
            Divider()
            Button("Remove", role: .destructive) {
                Task { await env.clusters.remove(id: record.id) }
            }
        }
        .sheet(isPresented: $showRename) {
            CustomizeClusterSheet(record: record)
        }
    }
}

/// Shown when the cluster store couldn't be read (or read back empty on an
/// install that had clusters). We deliberately do NOT re-detect from kubeconfig
/// in this state — doing so would overwrite the user's saved names/orgs — so the
/// user gets an honest recovery prompt instead of a silent (destructive) re-seed.
private struct StoreRecoveryView: View {
    @Environment(\.appEnv) private var env

    /// The store read *cleanly* but came back empty on an install that had clusters
    /// before. The most likely cause is that the records are genuinely gone (a fresh
    /// store after a failed migration / reinstall / wipe), NOT a store we couldn't
    /// read — so "Try Again" would re-read 0 rows forever. Re-detecting is the action
    /// that actually resolves this state, so it leads.
    private var canReseed: Bool { env.clusters.canReseedFromKubeconfig }

    var body: some View {
        VStack(spacing: Tokens.Spacing.lg) {
            Image(systemName: "exclamationmark.triangle.fill")
                .font(.system(size: 56))
                .foregroundStyle(.orange)
            VStack(spacing: Tokens.Spacing.xs) {
                Text(canReseed ? "Your saved cluster list is empty"
                               : "Couldn't read your saved clusters")
                    .font(.title2.weight(.semibold))
                Text(canReseed
                     ? "Spectra read your cluster store but found no clusters, even though "
                       + "this install had clusters before. Re-detect them from your kubeconfig "
                       + "to get going again."
                     : "Spectra didn't re-detect clusters from your kubeconfig because that "
                       + "would overwrite your saved names, orgs and preferences. Your data is "
                       + "left untouched on disk. Try again, or relaunch the app.")
                    .font(.callout)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
                    .frame(maxWidth: 440)
            }
            HStack(spacing: Tokens.Spacing.md) {
                // When the store read cleanly but empty, re-detecting is the only action
                // that escapes this screen — make it prominent and demote "Try Again"
                // (which would just re-read 0 records). On a hard read failure we have no
                // escape hatch (re-detecting could clobber records we merely couldn't
                // load), so "Try Again" leads instead.
                if canReseed {
                    SpectraButton(title: "Re-detect from kubeconfig",
                                  systemImage: "arrow.triangle.2.circlepath", prominent: true) {
                        env.clusters.forceReseedFromKubeconfig()
                    }
                }
                SpectraButton(title: "Try Again", systemImage: "arrow.clockwise",
                              prominent: !canReseed) {
                    env.clusters.retryLoad()
                }
            }
            if canReseed {
                Text("Re-detecting reads contexts from ~/.kube/config. Any saved names, "
                     + "orgs or preferences that couldn't be read will be lost.")
                    .font(.caption)
                    .foregroundStyle(.tertiary)
                    .multilineTextAlignment(.center)
                    .frame(maxWidth: 440)
            }
        }
        .padding(Tokens.Spacing.xxl)
    }
}

private struct WelcomeView: View {
    @Environment(\.appEnv) private var env

    var body: some View {
        VStack(spacing: Tokens.Spacing.xl) {
            Image(systemName: "circle.hexagongrid")
                .font(.system(size: 64))
                .foregroundStyle(env.theme.accent)
            VStack(spacing: Tokens.Spacing.xs) {
                Text("Welcome to Spectra")
                    .font(.largeTitle.weight(.bold))
                Text("A native macOS Kubernetes IDE")
                    .foregroundStyle(.secondary)
            }
            VStack(spacing: Tokens.Spacing.sm) {
                SpectraButton(title: "Add from ~/.kube/config", systemImage: "plus.circle",
                              prominent: true) { env.navigation.showAddCluster = true }
                Text("Or open a kubeconfig file or paste YAML from the Add Cluster dialog.")
                    .font(.caption)
                    .foregroundStyle(.tertiary)
            }
        }
        .padding(Tokens.Spacing.xxl)
    }
}
