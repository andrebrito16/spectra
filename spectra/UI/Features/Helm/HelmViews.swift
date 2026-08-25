//
//  HelmViews.swift
//  Spectra
//
//  Helm UI: releases (list/detail/history/upgrade/rollback/uninstall) and charts
//  (repos + search + install). All operations go through HelmService (shell-out).
//

import SwiftUI

// MARK: - Releases

struct HelmReleasesView: View {
    let session: ClusterSession
    @Environment(\.appEnv) private var env

    @State private var releases: [HelmRelease] = []
    @State private var loading = false
    @State private var detailTarget: HelmRelease?
    @State private var upgradeTarget: HelmRelease?

    var body: some View {
        VStack(spacing: 0) {
            HStack {
                Text("Helm Releases").font(.title2.weight(.semibold))
                if loading { ProgressView().controlSize(.small) }
                Spacer()
                Button { Task { await load() } } label: { Image(systemName: "arrow.clockwise") }
            }
            .padding(Tokens.Spacing.md)
            Divider()
            if releases.isEmpty && !loading {
                EmptyStateView(title: "No releases", systemImage: "shippingbox")
            } else {
                List(releases) { release in
                    HStack {
                        VStack(alignment: .leading, spacing: 0) {
                            Text(release.name).font(.callout)
                            Text("\(release.namespace) · \(release.chart)")
                                .font(.caption).foregroundStyle(.secondary)
                        }
                        Spacer()
                        Badge(text: release.status,
                              status: release.status == "deployed" ? .success : .warning)
                        Text("rev \(release.revision)").font(.caption2).foregroundStyle(.tertiary)
                    }
                    .contentShape(Rectangle())
                    .onTapGesture { detailTarget = release }
                    .contextMenu {
                        Button("Upgrade…") { upgradeTarget = release }
                        Button("Uninstall", role: .destructive) { uninstall(release) }
                    }
                }
            }
        }
        .background(.background)
        .navigationTitle("Helm Releases")
        .task { await load() }
        .sheet(item: $detailTarget) { release in
            HelmReleaseDetailSheet(session: session, release: release) { Task { await load() } }
        }
        .sheet(item: $upgradeTarget) { release in
            HelmInstallSheet(session: session, mode: .upgrade(release)) { Task { await load() } }
        }
    }

    private func load() async {
        guard let helm = env.helmService(for: session) else { return }
        loading = true
        defer { loading = false }
        do { releases = try await helm.listReleases() }
        catch { env.notifications.notify(.error, "Helm list failed", message: error.localizedDescription) }
    }

    private func uninstall(_ release: HelmRelease) {
        guard let helm = env.helmService(for: session) else { return }
        Task {
            do {
                try await helm.uninstall(name: release.name, namespace: release.namespace)
                env.notifications.notify(.success, "Uninstalled \(release.name)")
                await load()
            } catch {
                env.notifications.notify(.error, "Uninstall failed", message: error.localizedDescription)
            }
        }
    }
}

struct HelmReleaseDetailSheet: View {
    let session: ClusterSession
    let release: HelmRelease
    var onChange: () -> Void

    @Environment(\.appEnv) private var env
    @Environment(\.dismiss) private var dismiss
    @State private var values = ""
    @State private var manifest = ""
    @State private var history: [HelmHistoryEntry] = []
    @State private var editing = false

    var body: some View {
        VStack(spacing: 0) {
            HStack {
                Text("\(release.name) (\(release.namespace))").font(.headline)
                Spacer()
                Button("Edit Values…") { editing = true }
                Button("Done") { dismiss() }.keyboardShortcut(.defaultAction)
            }
            .padding(Tokens.Spacing.md)
            Divider()
            TabView {
                ScrollView { Text(values).font(.system(.caption, design: .monospaced))
                    .textSelection(.enabled).frame(maxWidth: .infinity, alignment: .leading)
                    .padding(Tokens.Spacing.sm) }
                    .tabItem { Text("Values") }
                ScrollView { Text(manifest).font(.system(.caption, design: .monospaced))
                    .textSelection(.enabled).frame(maxWidth: .infinity, alignment: .leading)
                    .padding(Tokens.Spacing.sm) }
                    .tabItem { Text("Manifest") }
                historyList.tabItem { Text("History") }
            }
        }
        .frame(width: 680, height: 540)
        .task { await load() }
        .sheet(isPresented: $editing) {
            HelmInstallSheet(session: session, mode: .upgrade(release)) {
                onChange()
                Task { await load() }
            }
        }
    }

    private var historyList: some View {
        List(history) { entry in
            HStack {
                Text("rev \(entry.revision)").font(.callout)
                Text(entry.status).font(.caption).foregroundStyle(.secondary)
                Spacer()
                Button("Rollback") { rollback(to: entry.revision) }
            }
        }
    }

    private func load() async {
        guard let helm = env.helmService(for: session) else { return }
        values = (try? await helm.getValues(name: release.name, namespace: release.namespace)) ?? ""
        manifest = (try? await helm.getManifest(name: release.name, namespace: release.namespace)) ?? ""
        history = (try? await helm.history(name: release.name, namespace: release.namespace)) ?? []
    }

    private func rollback(to revision: Int) {
        guard let helm = env.helmService(for: session) else { return }
        Task {
            do {
                try await helm.rollback(name: release.name, namespace: release.namespace,
                                        revision: revision)
                env.notifications.notify(.success, "Rolled back to rev \(revision)")
                onChange()
                dismiss()
            } catch {
                env.notifications.notify(.error, "Rollback failed", message: error.localizedDescription)
            }
        }
    }
}

// MARK: - Charts

struct HelmChartsView: View {
    let session: ClusterSession
    @Environment(\.appEnv) private var env

    @State private var repos: [HelmRepo] = []
    @State private var hits: [HelmChartHit] = []
    @State private var search = ""
    @State private var loading = false
    @State private var installTarget: HelmChartHit?
    @State private var showAddRepo = false
    @State private var newRepoName = ""
    @State private var newRepoURL = ""

    var body: some View {
        VStack(spacing: 0) {
            HStack {
                Text("Helm Charts").font(.title2.weight(.semibold))
                if loading { ProgressView().controlSize(.small) }
                Spacer()
                SearchField(placeholder: "Search charts…", text: $search)
                    .frame(width: 220)
                    .onSubmit { Task { await runSearch() } }
                Button { showAddRepo = true } label: { Image(systemName: "plus") }.help("Add repo")
                Button { Task { await updateRepos() } } label: { Image(systemName: "arrow.clockwise") }
                    .help("Update repos")
            }
            .padding(Tokens.Spacing.md)
            Divider()
            if hits.isEmpty && !loading {
                EmptyStateView(title: "No charts",
                               systemImage: "sailboat",
                               message: repos.isEmpty ? "Add a Helm repository to get started."
                                                      : "Search charts across your repos.")
            } else {
                List(hits) { hit in
                    HStack {
                        VStack(alignment: .leading, spacing: 0) {
                            Text(hit.name).font(.callout)
                            if let description = hit.description {
                                Text(description).font(.caption).foregroundStyle(.secondary).lineLimit(1)
                            }
                        }
                        Spacer()
                        Text(hit.version).font(.caption2).foregroundStyle(.tertiary)
                        Button("Install") { installTarget = hit }
                    }
                }
            }
        }
        .background(.background)
        .navigationTitle("Helm Charts")
        .task { await initialLoad() }
        .sheet(item: $installTarget) { hit in
            HelmInstallSheet(session: session, mode: .install(hit)) { }
        }
        .sheet(isPresented: $showAddRepo) { addRepoSheet }
    }

    private var addRepoSheet: some View {
        VStack(alignment: .leading, spacing: Tokens.Spacing.md) {
            Text("Add Helm Repository").font(.headline)
            TextField("Name", text: $newRepoName)
            TextField("URL", text: $newRepoURL)
            HStack {
                Spacer()
                Button("Cancel") { showAddRepo = false }
                Button("Add") { Task { await addRepo() } }.keyboardShortcut(.defaultAction)
            }
        }
        .padding(Tokens.Spacing.xl)
        .frame(width: 420)
    }

    private func initialLoad() async {
        guard let helm = env.helmService(for: session) else { return }
        repos = (try? await helm.listRepos()) ?? []
        await runSearch()
    }

    private func runSearch() async {
        guard let helm = env.helmService(for: session) else { return }
        loading = true
        defer { loading = false }
        hits = (try? await helm.searchCharts(search)) ?? []
    }

    private func updateRepos() async {
        guard let helm = env.helmService(for: session) else { return }
        do {
            try await helm.updateRepos()
            env.notifications.notify(.success, "Repositories updated")
            await runSearch()
        } catch {
            env.notifications.notify(.error, "Update failed", message: error.localizedDescription)
        }
    }

    private func addRepo() async {
        guard let helm = env.helmService(for: session) else { return }
        do {
            try await helm.addRepo(name: newRepoName, url: newRepoURL)
            showAddRepo = false
            newRepoName = ""; newRepoURL = ""
            await initialLoad()
        } catch {
            env.notifications.notify(.error, "Add repo failed", message: error.localizedDescription)
        }
    }
}

// MARK: - Install / Upgrade sheet

struct HelmInstallSheet: View {
    enum Mode {
        case install(HelmChartHit)
        case upgrade(HelmRelease)
    }

    let session: ClusterSession
    let mode: Mode
    var onComplete: () -> Void

    @Environment(\.appEnv) private var env
    @Environment(\.dismiss) private var dismiss
    @State private var releaseName = ""
    @State private var namespace = "default"
    @State private var values = ""
    @State private var working = false
    @State private var loadedDefaults = false

    private var chartRef: String {
        switch mode {
        case .install(let hit): return hit.name
        case .upgrade(let release): return release.chart
        }
    }

    private var title: String {
        switch mode {
        case .install: return "Install Chart"
        case .upgrade: return "Upgrade Release"
        }
    }

    var body: some View {
        VStack(spacing: 0) {
            HStack {
                Text(title).font(.headline)
                Spacer()
                if working { ProgressView().controlSize(.small) }
            }
            .padding(Tokens.Spacing.md)
            Divider()
            Form {
                TextField("Release name", text: $releaseName)
                TextField("Namespace", text: $namespace)
                Text("Chart: \(chartRef)").foregroundStyle(.secondary)
            }
            .padding(Tokens.Spacing.md)
            Text("Values").font(.caption).foregroundStyle(.secondary)
                .frame(maxWidth: .infinity, alignment: .leading).padding(.horizontal, Tokens.Spacing.md)
            YAMLEditor(text: $values).frame(minHeight: 240)
            Divider()
            HStack {
                Spacer()
                Button("Cancel") { dismiss() }
                Button(title) { run() }.keyboardShortcut(.defaultAction).disabled(working)
            }
            .padding(Tokens.Spacing.md)
        }
        .frame(width: 640, height: 600)
        .task { await prepare() }
    }

    private func prepare() async {
        guard !loadedDefaults else { return }
        loadedDefaults = true
        guard let helm = env.helmService(for: session) else { return }
        switch mode {
        case .install(let hit):
            releaseName = hit.name
            values = (try? await helm.showValues(chart: hit.name, version: hit.version)) ?? ""
        case .upgrade(let release):
            releaseName = release.name
            namespace = release.namespace
            values = (try? await helm.getValues(name: release.name, namespace: release.namespace)) ?? ""
        }
    }

    private func run() {
        guard let helm = env.helmService(for: session) else { return }
        working = true
        Task {
            defer { working = false }
            do {
                switch mode {
                case .install(let hit):
                    try await helm.install(name: releaseName, chart: hit.name, namespace: namespace,
                                           version: hit.version, values: values)
                case .upgrade(let release):
                    // `release.chart` is helm's "<name>-<version>" metadata, not a
                    // locatable chart — resolve it to a repo reference (and pin the
                    // installed version so editing values never bumps the chart).
                    guard let resolved =
                        try await helm.resolveChartReference(forReleaseChart: release.chart) else {
                        throw HelmError.command(
                            "Couldn't find chart “\(release.chart)” in your added Helm repos. " +
                            "Add its repository (Charts → +) and try again.")
                    }
                    try await helm.upgrade(name: releaseName, chart: resolved.reference,
                                           namespace: namespace, version: resolved.version,
                                           values: values)
                }
                env.notifications.notify(.success, "\(title) succeeded", message: releaseName)
                onComplete()
                dismiss()
            } catch {
                env.notifications.notify(.error, "\(title) failed", message: error.localizedDescription)
            }
        }
    }
}
