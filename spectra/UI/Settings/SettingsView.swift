//
//  SettingsView.swift
//  Spectra
//
//  Preferences: Appearance, General (PATH for exec auth plugins, update channel),
//  Diagnostics (log level, reveal/collect logs), and per-cluster settings
//  (display, preferred namespace, node-shell image, kubectl version, Prometheus).
//

import SwiftUI
import SwiftData

struct SettingsView: View {
    var body: some View {
        TabView {
            AppearanceSettings()
                .tabItem { Label("Appearance", systemImage: "paintbrush") }
            GeneralSettings()
                .tabItem { Label("General", systemImage: "gearshape") }
            DiagnosticsSettings()
                .tabItem { Label("Diagnostics", systemImage: "stethoscope") }
            ClusterSettings()
                .tabItem { Label("Clusters", systemImage: "circle.hexagongrid") }
        }
        .frame(width: 560, height: 420)
    }
}

private struct AppearanceSettings: View {
    @Environment(\.appEnv) private var env

    var body: some View {
        @Bindable var theme = env.theme
        Form {
            Picker("Appearance", selection: $theme.mode) {
                ForEach(ThemeMode.allCases) { Text($0.label).tag($0) }
            }
            .pickerStyle(.segmented)
            LabeledContent("Accent") {
                ColorPicker("", selection: $theme.accent, supportsOpacity: false).labelsHidden()
            }
        }
        .formStyle(.grouped)
        .padding()
    }
}

private struct GeneralSettings: View {
    @Environment(\.appEnv) private var env
    @Environment(\.modelContext) private var modelContext
    @Query private var settingsList: [AppSettings]

    var body: some View {
        Form {
            if let settings = settingsList.first {
                @Bindable var settings = settings
                Section("PATH for credential plugins") {
                    TextField("Extra PATH (colon-separated)", text: $settings.extraPATH, axis: .vertical)
                        .lineLimit(2...4)
                        .font(.system(.caption, design: .monospaced))
                        .onChange(of: settings.extraPATH) { _, new in
                            env.clusters.extraPATH = new
                            try? modelContext.save()
                        }
                    Text("Where Spectra looks for aws / gke-gcloud-auth-plugin / kubelogin / kubectl / helm.")
                        .font(.caption).foregroundStyle(.secondary)
                }
                Section("Updates") {
                    Picker("Channel", selection: $settings.updateChannel) {
                        Text("Stable").tag("stable")
                        Text("Beta").tag("beta")
                    }
                    .onChange(of: settings.updateChannel) { _, _ in try? modelContext.save() }
                    Button("Check for Updates…") { env.updater.checkForUpdates() }
                    Text("Updates are downloaded only from signed Sparkle releases.")
                        .font(.caption).foregroundStyle(.secondary)
                }
            } else {
                Text("Settings not loaded.").foregroundStyle(.secondary)
            }
        }
        .formStyle(.grouped)
        .padding()
    }
}

private struct DiagnosticsSettings: View {
    @Environment(\.appEnv) private var env
    @Environment(\.modelContext) private var modelContext
    @Query private var settingsList: [AppSettings]

    var body: some View {
        Form {
            if let settings = settingsList.first {
                @Bindable var settings = settings
                Picker("Log level", selection: $settings.logLevel) {
                    Text("Debug").tag(LogLevel.debug.rawValue)
                    Text("Info").tag(LogLevel.info.rawValue)
                    Text("Warning").tag(LogLevel.warning.rawValue)
                    Text("Error").tag(LogLevel.error.rawValue)
                }
                .onChange(of: settings.logLevel) { _, new in
                    Log.minimumLevel = LogLevel(rawValue: new) ?? .info
                    try? modelContext.save()
                }
            }
            Section {
                Button("Reveal Diagnostics Logs in Finder") { Diagnostics.revealLogs() }
                Button("Collect Diagnostics…") {
                    Diagnostics.collect(appVersion: Bundle.main.appVersionString,
                                        clusterSummaries: clusterSummaries())
                }
            } footer: {
                Text("Logs never contain secrets or tokens. The bundle is for bug reports.")
                    .font(.caption).foregroundStyle(.secondary)
            }
        }
        .formStyle(.grouped)
        .padding()
    }

    private func clusterSummaries() -> [String] {
        env.clusters.records.map { record in
            let status = env.clusters.states[record.id]?.status.label ?? "unknown"
            return "\(record.effectiveName) [\(record.contextName)] — \(status)"
        }
    }
}

private struct ClusterSettings: View {
    @Environment(\.appEnv) private var env
    @Environment(\.modelContext) private var modelContext
    @State private var selectedID: String?

    private var selected: ClusterRecord? {
        env.clusters.records.first { $0.id == selectedID } ?? env.clusters.records.first
    }

    var body: some View {
        HSplitView {
            List(env.clusters.records, selection: $selectedID) { record in
                Text(record.effectiveName).tag(record.id)
            }
            .frame(minWidth: 160)

            if let record = selected {
                clusterForm(record)
            } else {
                Text("No clusters.").foregroundStyle(.secondary).frame(maxWidth: .infinity)
            }
        }
    }

    private func clusterForm(_ record: ClusterRecord) -> some View {
        @Bindable var record = record
        return Form {
            Section("Display") {
                TextField("Display name", text: Binding(
                    get: { record.displayName ?? "" },
                    set: { record.displayName = $0.isEmpty ? nil : $0 }))
                TextField("Preferred namespace", text: Binding(
                    get: { record.preferredNamespace ?? "" },
                    set: { record.preferredNamespace = $0.isEmpty ? nil : $0 }))
            }
            Section("Shell & binaries") {
                TextField("Node-shell image", text: Binding(
                    get: { record.nodeShellImage ?? "" },
                    set: { record.nodeShellImage = $0.isEmpty ? nil : $0 }))
                TextField("kubectl version override", text: Binding(
                    get: { record.kubectlVersionOverride ?? "" },
                    set: { record.kubectlVersionOverride = $0.isEmpty ? nil : $0 }))
            }
            Section("Metrics (Prometheus / Mimir / Thanos)") {
                Toggle("Enable metrics", isOn: $record.metricsEnabled)
                TextField("Direct URL (optional; auto-discovered if blank)", text: Binding(
                    get: { record.prometheusDirectURL ?? "" },
                    set: { record.prometheusDirectURL = $0.isEmpty ? nil : $0 }))
                TextField("Bearer token", text: Binding(
                    get: { record.prometheusToken ?? "" },
                    set: { record.prometheusToken = $0.isEmpty ? nil : $0 }))
                TextField("Tenant (X-Scope-OrgID, for Mimir)", text: Binding(
                    get: { record.metricsTenant ?? "" },
                    set: { record.metricsTenant = $0.isEmpty ? nil : $0 }))
            }
        }
        .formStyle(.grouped)
        // Persist EVERY editable field. The three commented-out ones below used to
        // be missing, so a kubectl override / Prometheus token / tenant typed here
        // was never saved (it only survived if SwiftData's autosave happened to
        // fire before the window closed) — the "settings don't stick" symptom.
        .onChange(of: record.displayName) { _, _ in save() }
        .onChange(of: record.preferredNamespace) { _, _ in save() }
        .onChange(of: record.nodeShellImage) { _, _ in save() }
        .onChange(of: record.kubectlVersionOverride) { _, _ in save() }
        .onChange(of: record.metricsEnabled) { _, _ in save() }
        .onChange(of: record.prometheusDirectURL) { _, _ in save() }
        .onChange(of: record.prometheusToken) { _, _ in save() }
        .onChange(of: record.metricsTenant) { _, _ in save() }
    }

    private func save() {
        // Just persist — do NOT `reload()` here. `reload()` reassigns
        // `clusters.records`, which rebuilds this Form's TextField mid-keystroke
        // (dropped characters / lost cursor). The records are `@Observable`
        // `@Model`s, so the sidebar/list update live without a reload.
        try? modelContext.save()
    }
}

extension Bundle {
    var appVersionString: String {
        let short = infoDictionary?["CFBundleShortVersionString"] as? String ?? "—"
        let build = infoDictionary?["CFBundleVersion"] as? String ?? "—"
        return "\(short) (\(build))"
    }
}
