//
//  Models.swift
//  Spectra
//
//  SwiftData persistence. Replaces the starter `Item` model with real app state:
//  known clusters + per-cluster prefs, favorites/hotbar, saved port-forwards,
//  and global app settings. Later phases fill in additional fields.
//

import Foundation
import SwiftData

/// A known cluster = a (kubeconfig path, context name) pair, plus display and
/// per-cluster preferences. Mirrors Freelens's persisted cluster model.
@Model
final class ClusterRecord {
    /// Stable id = hash(kubeConfigPath:contextName) — see Kubeconfig/ClusterIdentity.
    @Attribute(.unique) var id: String
    var kubeconfigPath: String
    var contextName: String

    // Display preferences
    var displayName: String?
    var iconColorHex: String?
    /// Optional second color and direction for the cluster's local theme.
    /// Existing records retain their solid color through lightweight migration.
    var gradientEndColorHex: String?
    var gradientAngle: Double?
    /// SF Symbol shown in the space indicator / switcher (nil = default).
    var iconSymbol: String?
    var pinned: Bool

    // Grouping & ordering (drag-to-reorder; orgs)
    /// Organization this cluster belongs to (nil = ungrouped). See `ClusterOrg`.
    var orgId: String?
    /// Position within its group, kept dense (0..n-1) for drag-to-reorder.
    var sortOrder: Int = 0

    // Per-cluster preferences (Phase 2/11/12)
    var preferredNamespace: String?
    var nodeShellImage: String?
    var kubectlVersionOverride: String?
    var httpProxy: String?

    // Prometheus / metrics preferences (Phase 11)
    var prometheusProvider: String?
    var prometheusServicePath: String?
    var prometheusDirectURL: String?
    var prometheusToken: String?
    /// X-Scope-OrgID tenant for multi-tenant backends (e.g. Grafana Mimir).
    var metricsTenant: String?
    var metricsEnabled: Bool

    var lastConnectedAt: Date?
    var createdAt: Date

    init(id: String, kubeconfigPath: String, contextName: String) {
        self.id = id
        self.kubeconfigPath = kubeconfigPath
        self.contextName = contextName
        self.pinned = false
        self.metricsEnabled = true
        self.createdAt = Date()
    }
}

/// An organization: a user-created group that clusters can be sorted into
/// (e.g. "Production", "Staging"). Ordering is drag-driven via `sortOrder`.
@Model
final class ClusterOrg {
    @Attribute(.unique) var id: String
    var name: String
    /// Position of the org among other orgs (dense, 0..n-1).
    var sortOrder: Int
    var colorHex: String?
    var createdAt: Date

    init(id: String = UUID().uuidString, name: String, sortOrder: Int, colorHex: String? = nil) {
        self.id = id
        self.name = name
        self.sortOrder = sortOrder
        self.colorHex = colorHex
        self.createdAt = Date()
    }
}

/// A pinned item in the hotbar/favorites bar. v1 pins clusters; later phases may
/// pin specific resource views.
@Model
final class Favorite {
    @Attribute(.unique) var id: String
    var clusterId: String
    var kind: String?
    var name: String?
    var namespace: String?
    var order: Int

    init(id: String, clusterId: String, order: Int) {
        self.id = id
        self.clusterId = clusterId
        self.order = order
    }
}

/// A persisted port-forward, resumed on launch (Phase 9).
@Model
final class SavedPortForward {
    @Attribute(.unique) var id: String
    var clusterId: String
    var kind: String
    var name: String
    var namespace: String
    var localPort: Int
    var remotePort: Int
    var protocolName: String
    var active: Bool

    init(id: String, clusterId: String, kind: String, name: String,
         namespace: String, localPort: Int, remotePort: Int, protocolName: String = "TCP") {
        self.id = id
        self.clusterId = clusterId
        self.kind = kind
        self.name = name
        self.namespace = namespace
        self.localPort = localPort
        self.remotePort = remotePort
        self.protocolName = protocolName
        self.active = false
    }
}

/// Global, app-wide settings (single row). Phase 4 wires the theme toggle; Phase
/// 12 wires log level + update channel.
@Model
final class AppSettings {
    var themeMode: String        // ThemeMode.rawValue
    var extraPATH: String        // colon-separated PATH additions for exec auth plugins
    var logLevel: Int            // LogLevel.rawValue
    var updateChannel: String
    var terminalFont: String?
    var terminalShell: String?
    var telemetryEnabled: Bool

    init() {
        self.themeMode = ThemeMode.auto.rawValue
        self.extraPATH = AppSettings.defaultExtraPATH
        self.logLevel = LogLevel.info.rawValue
        self.updateChannel = "stable"
        self.telemetryEnabled = false
    }

    /// Common locations where cloud auth plugins (aws, gke-gcloud-auth-plugin,
    /// kubelogin) and helm/kubectl live, so `exec` credential plugins resolve.
    static var defaultExtraPATH: String {
        let home = NSHomeDirectory()
        return [
            "/usr/local/bin",
            "/opt/homebrew/bin",
            "/opt/homebrew/sbin",
            "\(home)/.local/bin",
            "\(home)/.local/share/mise/shims",
            "\(home)/.asdf/shims",
            "/usr/local/share/google-cloud-sdk/bin",
        ].joined(separator: ":")
    }
}

extension ClusterRecord {
    var effectiveName: String {
        if let displayName, !displayName.isEmpty { return displayName }
        return contextName
    }
}
