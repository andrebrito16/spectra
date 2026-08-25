//
//  NavigationModel.swift
//  Spectra
//
//  Routing + tabs. The content area is tabbed: navigating opens (or selects) a
//  tab. The selected tab's route drives the content. Back/forward operate over
//  navigation history. Also holds shared UI flags (palette, dock, etc.).
//

import SwiftUI

@MainActor
@Observable
final class NavigationModel {
    enum Route: Hashable {
        case catalog
        case overview
        case kind(String)      // GVR id
        case special(String)   // non-GVR destinations (e.g. "helm/charts")

        var gvrID: String? {
            if case .kind(let id) = self { return id }
            return nil
        }

        var tag: String {
            switch self {
            case .catalog: return "catalog"
            case .overview: return "overview"
            case .kind(let id): return id
            case .special(let id): return "special:\(id)"
            }
        }

        init(tag: String) {
            switch tag {
            case "catalog": self = .catalog
            case "overview": self = .overview
            default:
                if tag.hasPrefix("special:") {
                    self = .special(String(tag.dropFirst("special:".count)))
                } else {
                    self = .kind(tag)
                }
            }
        }
    }

    struct Tab: Identifiable, Hashable {
        let id = UUID()
        var route: Route
        var title: String
        var systemImage: String
    }

    private(set) var tabs: [Tab] = []
    var selectedTabID: Tab.ID?

    /// The selected tab's route (or catalog when no tabs are open).
    var route: Route {
        tabs.first { $0.id == selectedTabID }?.route ?? .catalog
    }

    /// The selected object (uid/scopedName) in the current list view.
    var detailSelection: String?

    // Shared UI state (menu bar + views toggle these).
    var showCommandPalette = false
    var showAddCluster = false
    var showShortcuts = false
    var dockOpen = false

    private var backStack: [Route] = []
    private var forwardStack: [Route] = []

    var canGoBack: Bool { !backStack.isEmpty }
    var canGoForward: Bool { !forwardStack.isEmpty }

    // MARK: - Navigation

    func navigate(to route: Route, title: String? = nil, systemImage: String? = nil) {
        let current = self.route
        if route != current {
            backStack.append(current)
            forwardStack.removeAll()
        }
        select(route, title: title, systemImage: systemImage)
    }

    /// Open/select a tab for the route without touching history.
    private func select(_ route: Route, title: String?, systemImage: String?) {
        detailSelection = nil
        if let existing = tabs.first(where: { $0.route == route }) {
            selectedTabID = existing.id
            return
        }
        let tab = Tab(route: route,
                      title: title ?? Self.defaultTitle(route),
                      systemImage: systemImage ?? Self.defaultIcon(route))
        tabs.append(tab)
        selectedTabID = tab.id
    }

    func selectTab(_ id: Tab.ID) {
        selectedTabID = id
        detailSelection = nil
    }

    func closeTab(_ id: Tab.ID) {
        guard let index = tabs.firstIndex(where: { $0.id == id }) else { return }
        let wasSelected = tabs[index].id == selectedTabID
        tabs.remove(at: index)
        if wasSelected {
            selectedTabID = tabs.indices.contains(index) ? tabs[index].id
                : tabs.last?.id
        }
    }

    func goBack() {
        guard let previous = backStack.popLast() else { return }
        forwardStack.append(route)
        select(previous, title: nil, systemImage: nil)
    }

    func goForward() {
        guard let next = forwardStack.popLast() else { return }
        backStack.append(route)
        select(next, title: nil, systemImage: nil)
    }

    func reset() {
        tabs.removeAll()
        selectedTabID = nil
        detailSelection = nil
        backStack.removeAll()
        forwardStack.removeAll()
    }

    // MARK: - Workspace snapshots (per-cluster tab state)

    /// Everything needed to bring a cluster's workspace back exactly as it was:
    /// open tabs, selection, and history. Kept by AppEnvironment per cluster so
    /// switching away and back doesn't dump you on the Overview.
    struct Snapshot {
        var tabs: [Tab]
        var selectedTabID: Tab.ID?
        var backStack: [Route]
        var forwardStack: [Route]
    }

    func snapshot() -> Snapshot {
        Snapshot(tabs: tabs, selectedTabID: selectedTabID,
                 backStack: backStack, forwardStack: forwardStack)
    }

    func restore(_ snapshot: Snapshot) {
        tabs = snapshot.tabs
        selectedTabID = snapshot.selectedTabID ?? tabs.last?.id
        detailSelection = nil
        backStack = snapshot.backStack
        forwardStack = snapshot.forwardStack
    }

    // MARK: - Titles / icons

    static func defaultTitle(_ route: Route) -> String {
        switch route {
        case .catalog: return "Catalog"
        case .overview: return "Overview"
        case .kind(let id): return id.split(separator: "/").last.map { $0.capitalized } ?? "Resource"
        case .special(let id):
            switch id {
            case "helm/charts": return "Charts"
            case "helm/releases": return "Releases"
            case "network/portforwards": return "Port Forwards"
            default: return id.capitalized
            }
        }
    }

    static func defaultIcon(_ route: Route) -> String {
        switch route {
        case .catalog: return "square.grid.2x2"
        case .overview: return "gauge.with.dots.needle.50percent"
        case .kind: return "cube"
        case .special(let id):
            if id.hasPrefix("helm") { return "sailboat" }
            if id.contains("portforward") { return "arrow.left.arrow.right" }
            return "square"
        }
    }
}
