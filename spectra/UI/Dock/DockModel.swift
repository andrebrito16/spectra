//
//  DockModel.swift
//  Spectra
//
//  Bottom-dock tab model. Tabs host a terminal (local shell / pod exec / node
//  shell) or a live log stream. Tabs survive navigation; closing a tab tears
//  down its session/stream. Dock chrome is glass; hosted content is solid.
//

import SwiftUI

@MainActor
struct TerminalSpec: Identifiable {
    let id = UUID()
    let executable: String
    let args: [String]
    let environment: [String: String]
}

@MainActor
struct LogSpec: Identifiable {
    let id = UUID()
    let session: ClusterSession
    let namespace: String
    let pod: String
    var containers: [String]
    var initialContainer: String?
}

@MainActor
struct YAMLEditSpec: Identifiable {
    enum Intent { case edit, create }

    let id = UUID()
    let session: ClusterSession
    let intent: Intent
    let yaml: String
    /// For edit, the GVR + name/namespace target; for create resolved from YAML.
    var gvr: GroupVersionResource?
    var namespace: String?
    var name: String?
}

@MainActor
enum DockContent {
    case terminal(TerminalSpec)
    case logs(LogSpec)
    case yamlEditor(YAMLEditSpec)
}

@MainActor
struct DockTab: Identifiable {
    let id = UUID()
    let title: String
    let systemImage: String
    let content: DockContent
}

@MainActor
@Observable
final class DockModel {
    private(set) var tabs: [DockTab] = []
    var selectedTab: DockTab.ID?

    func open(_ tab: DockTab) {
        tabs.append(tab)
        selectedTab = tab.id
    }

    func close(_ id: DockTab.ID) {
        tabs.removeAll { $0.id == id }
        if selectedTab == id {
            selectedTab = tabs.last?.id
        }
    }

    func closeAll() {
        tabs.removeAll()
        selectedTab = nil
    }
}
