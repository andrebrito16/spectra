//
//  AppEnvironment.swift
//  Spectra
//
//  Root, app-wide observable injected via the SwiftUI environment. Holds the
//  singletons later phases populate (cluster manager, theme, notifications).
//  Created here in Phase 1; grown by Phases 2–4.
//

import SwiftUI
import SwiftData

@Observable
@MainActor
final class AppEnvironment {
    /// The one app-wide instance. Views resolve it through `\.appEnv`, whose
    /// default falls back to this — never the trapping `@Environment(Type.self)`
    /// lookup (see `AppEnvironmentKey`).
    static let shared = AppEnvironment()

    let theme: Theme
    let notifications: NotificationCenterModel
    let clusters: ClusterManager
    let navigation: NavigationModel
    let dock: DockModel
    let portForwards: PortForwardManager
    let nodeMetrics: NodeMetricsProvider
    let updater: AppUpdater

    /// Saved workspace (tabs + history) per cluster, restored on switch-back.
    private var navSnapshots: [String: NavigationModel.Snapshot] = [:]

    init(theme: Theme = Theme(),
         notifications: NotificationCenterModel = NotificationCenterModel()) {
        self.theme = theme
        self.notifications = notifications
        self.clusters = ClusterManager()
        self.navigation = NavigationModel()
        self.dock = DockModel()
        self.portForwards = PortForwardManager()
        self.nodeMetrics = NodeMetricsProvider()
        self.updater = AppUpdater()
    }

    /// Switch the focused cluster (connecting if needed). The outgoing cluster's
    /// workspace is snapshotted and the incoming one's restored, so you land on
    /// exactly the tab you left — not the Overview.
    func openCluster(_ id: String) {
        if clusters.activeClusterId == id {
            connectAndPollMetrics(id)
            return
        }
        if let current = clusters.activeClusterId {
            navSnapshots[current] = navigation.snapshot()
        }
        clusters.activeClusterId = id
        if let snapshot = navSnapshots[id], !snapshot.tabs.isEmpty {
            navigation.restore(snapshot)
        } else {
            navigation.reset()
            navigation.navigate(to: .overview, title: "Overview")
        }
        connectAndPollMetrics(id)
    }

    private func connectAndPollMetrics(_ id: String) {
        nodeMetrics.stop()
        Task {
            if clusters.session(id: id) == nil {
                await clusters.connect(id: id)
            }
            if let session = clusters.session(id: id) {
                nodeMetrics.start(session: session)
            }
        }
    }

    /// Retry connecting to a cluster after a failure. Rebuilds the connection +
    /// session from scratch and resumes node-metrics polling once connected.
    func retryConnection(_ id: String) {
        nodeMetrics.stop()
        Task {
            await clusters.reconnect(id: id)
            if let session = clusters.session(id: id),
               clusters.states[id]?.status.isConnected == true {
                nodeMetrics.start(session: session)
            }
        }
    }

    /// Return to the catalog (does not disconnect). The cluster's workspace is
    /// snapshotted so reopening it restores the tabs.
    func showCatalog() {
        if let current = clusters.activeClusterId {
            navSnapshots[current] = navigation.snapshot()
        }
        nodeMetrics.stop()
        clusters.activeClusterId = nil
        navigation.reset()
    }

    /// Switch to the next/previous known cluster (Arc Spaces-style), wrapping.
    /// Follows the visual order (orgs, then ungrouped), not insertion order.
    func switchCluster(delta: Int) {
        let records = clusters.orderedRecords
        guard !records.isEmpty else { return }
        guard let current = clusters.activeClusterId,
              let index = records.firstIndex(where: { $0.id == current }) else {
            openCluster(records[0].id)
            return
        }
        let next = (index + delta + records.count) % records.count
        guard records[next].id != current else { return }
        openCluster(records[next].id)
    }

    /// Wires services that need the SwiftData context (clusters persistence).
    /// Called once from the app entry after the model container exists.
    func bootstrap(modelContext: ModelContext) {
        FeatureRegistry.registerAll()
        clusters.attach(modelContext: modelContext)
        portForwards.attach(modelContext: modelContext)
    }

    // MARK: - Dock interactions (logs, shells, port-forward)

    func openLocalTerminal() {
        let shell = ProcessInfo.processInfo.environment["SHELL"] ?? "/bin/zsh"
        var environment: [String: String] = [
            "PATH": "\(clusters.extraPATH):\(ProcessInfo.processInfo.environment["PATH"] ?? "")",
        ]
        if let session = clusters.activeSession, let record = clusters.record(id: session.id) {
            environment["KUBECONFIG"] = record.kubeconfigPath
        }
        let spec = TerminalSpec(executable: shell, args: ["-l"], environment: environment)
        dock.open(DockTab(title: "Terminal", systemImage: "terminal", content: .terminal(spec)))
        navigation.dockOpen = true
    }

    func openLogs(_ pod: KubeResource, session: ClusterSession) {
        let containers = pod.containers.compactMap { $0["name"]?.stringValue }
            + pod.initContainers.compactMap { $0["name"]?.stringValue }
        let spec = LogSpec(session: session, namespace: pod.namespace ?? "default",
                           pod: pod.name, containers: containers,
                           initialContainer: containers.first)
        dock.open(DockTab(title: "Logs: \(pod.name)", systemImage: "doc.plaintext",
                          content: .logs(spec)))
        navigation.dockOpen = true
    }

    func openShell(_ pod: KubeResource, session: ClusterSession) {
        guard let kubectl = resolveKubectl(), let record = clusters.record(id: session.id) else { return }
        var args = ["exec", "-it", "-n", pod.namespace ?? "default", pod.name]
        if let container = pod.containers.first?["name"]?.stringValue {
            args += ["-c", container]
        }
        args += ["--context", record.contextName, "--", "sh", "-c", "exec bash || exec sh"]
        let spec = TerminalSpec(executable: kubectl, args: args,
                                environment: ["KUBECONFIG": record.kubeconfigPath,
                                              "PATH": toolPATH])
        dock.open(DockTab(title: "Shell: \(pod.name)", systemImage: "terminal",
                          content: .terminal(spec)))
        navigation.dockOpen = true
    }

    func openNodeShell(_ node: KubeResource, session: ClusterSession) {
        guard let kubectl = resolveKubectl(), let record = clusters.record(id: session.id) else { return }
        let image = record.nodeShellImage ?? "alpine"
        let args = ["debug", "node/\(node.name)", "-it", "--image=\(image)",
                    "--context", record.contextName, "--", "chroot", "/host"]
        let spec = TerminalSpec(executable: kubectl, args: args,
                                environment: ["KUBECONFIG": record.kubeconfigPath,
                                              "PATH": toolPATH])
        dock.open(DockTab(title: "Node: \(node.name)", systemImage: "terminal",
                          content: .terminal(spec)))
        navigation.dockOpen = true
    }

    /// Open a YAML editor for an existing resource in the bottom dock.
    func openYAMLEdit(_ resource: KubeResource, gvr: GroupVersionResource,
                      session: ClusterSession) {
        let spec = YAMLEditSpec(session: session, intent: .edit,
                                yaml: (try? resource.yamlString()) ?? "",
                                gvr: gvr, namespace: resource.namespace, name: resource.name)
        dock.open(DockTab(title: "Edit: \(resource.name)", systemImage: "pencil",
                          content: .yamlEditor(spec)))
        navigation.dockOpen = true
    }

    /// Open a YAML editor pre-filled with a create template in the bottom dock.
    func openYAMLCreate(kind: String, template: String, gvr: GroupVersionResource,
                        session: ClusterSession) {
        let spec = YAMLEditSpec(session: session, intent: .create, yaml: template, gvr: gvr)
        dock.open(DockTab(title: "Create: \(kind)", systemImage: "plus.square",
                          content: .yamlEditor(spec)))
        navigation.dockOpen = true
    }

    /// Start a port-forward to `remotePort` on the cluster resource. `localPort == nil`
    /// lets the system pick a free local port; otherwise the chosen local port is bound.
    func startPortForward(_ resource: KubeResource, session: ClusterSession,
                          remotePort: Int, localPort: Int?, openInBrowser: Bool = false) {
        guard let kubectl = resolveKubectl(), let record = clusters.record(id: session.id) else { return }
        let kind = resource.kind ?? "Pod"
        portForwards.start(clusterId: session.id, kubeconfigPath: record.kubeconfigPath,
                           context: record.contextName, kubectl: kubectl,
                           extraPATH: clusters.extraPATH, kind: kind,
                           name: resource.name, namespace: resource.namespace ?? "default",
                           remotePort: remotePort, localPort: localPort,
                           openInBrowser: openInBrowser)
        let local = localPort.map(String.init) ?? "auto"
        notifications.notify(.info, "Port-forward starting",
                             message: "\(resource.name) \(local) → :\(remotePort)")
    }

    func helmService(for session: ClusterSession) -> HelmService? {
        guard let helm = BinaryResolver.path(for: "helm", extraPATH: clusters.extraPATH),
              let record = clusters.record(id: session.id) else {
            notifications.notify(.error, "helm not found",
                                 message: "Install helm or add its location in Preferences → PATH.")
            return nil
        }
        return HelmService(helmPath: helm, kubeconfigPath: record.kubeconfigPath,
                           context: record.contextName, extraPATH: clusters.extraPATH)
    }

    /// PATH for spawned CLI tools (kubectl exec/debug): the user's extra dirs +
    /// well-known tool locations + the inherited PATH, so a Launchd-spawned child
    /// can find exec credential plugins (aws / gke-gcloud-auth-plugin / …).
    private var toolPATH: String {
        BinaryResolver.searchDirs(extraPATH: clusters.extraPATH).joined(separator: ":")
    }

    private func resolveKubectl() -> String? {
        if let kubectl = BinaryResolver.path(for: "kubectl", extraPATH: clusters.extraPATH) {
            return kubectl
        }
        notifications.notify(.error, "kubectl not found",
                             message: "Install kubectl or add its location in Preferences → PATH.")
        return nil
    }
}

// MARK: - Environment plumbing

/// Custom key so views read AppEnvironment via `@Environment(\.appEnv)`.
/// The non-optional `@Environment(AppEnvironment.self)` form fatalErrors when a
/// detached AppKit-bridged hosting view (Table rows, split panes) is laid out
/// without the injected value — seen in the wild as an EXC_BREAKPOINT in
/// `EnvironmentValues.subscript.getter` during `NSHostingView.layout()`. This
/// key falls back to `AppEnvironment.shared` (the same instance the app
/// injects), so that lookup can never trap.
private struct AppEnvironmentKey: EnvironmentKey {
    nonisolated static var defaultValue: AppEnvironment {
        MainActor.assumeIsolated { AppEnvironment.shared }
    }
}

extension EnvironmentValues {
    var appEnv: AppEnvironment {
        get { self[AppEnvironmentKey.self] }
        set { self[AppEnvironmentKey.self] = newValue }
    }
}
