//
//  ResourceListView.swift
//  Spectra
//
//  The generic, config-driven list engine using a native SwiftUI Table so
//  columns size/resize properly (no collapsing). Live data from the kind's
//  ResourceStore, with namespace selector, column visibility, sort menu, row/
//  bulk actions, and a sliding detail drawer.
//

import SwiftUI

/// Carrier for Table's header-click sorting. The actual comparison happens in
/// `ResourceListView.sorted(_:)` (column values are MainActor view config, not
/// reachable from a nonisolated comparator) — this just identifies the column
/// and direction, giving us native clickable headers + sort arrows.
nonisolated struct ColumnSort: SortComparator, Hashable {
    var columnID: String
    var order: SortOrder = .forward

    func compare(_ lhs: KubeResource, _ rhs: KubeResource) -> ComparisonResult {
        .orderedSame  // unused: rows are pre-sorted by the view
    }
}

struct ResourceListView: View {
    let session: ClusterSession
    let gvr: GroupVersionResource

    @Environment(\.appEnv) private var env
    @State private var search = ""
    @State private var sortColumnID = "name"
    @State private var ascending = true
    @State private var tableSort: [ColumnSort] = [ColumnSort(columnID: "name")]
    @State private var selection: KubeResource.ID?
    @State private var hiddenColumns: Set<String> = []
    @State private var scaleTarget: KubeResource?
    @State private var portForwardTarget: KubeResource?
    @State private var showNamespacePopover = false

    /// Cached, session-scoped store. Read synchronously so revisited tabs
    /// render their cached items immediately — no loading flash. Informers
    /// stay warm for the session (see ResourceStore).
    private var store: ResourceStore {
        session.store(for: gvr)
    }

    private var allColumns: [ColumnDefinition] {
        if let registered = ResourceCatalog.shared.config(forKind: gvr.kind)?.columns {
            return registered
        }
        if let crdColumns = session.printerColumns(forGVR: gvr) {
            return crdColumns
        }
        return ResourceCatalog.defaultColumns(namespaced: gvr.namespaced)
    }

    private var columns: [ColumnDefinition] {
        allColumns.filter { !hiddenColumns.contains($0.id) }
    }

    private var filtered: [KubeResource] {
        var result = store.items
        if !search.isEmpty {
            let needle = search.lowercased()
            result = result.filter { $0.searchableText.contains(needle) }
        }
        return sorted(result)
    }

    private var selectedResource: KubeResource? {
        guard let selection else { return nil }
        return store.items.first { $0.id == selection }
    }

    var body: some View {
        // Evaluate the filter+sort pipeline ONCE per render — as a computed
        // property it would run for every reader (count label, empty check,
        // rows), multiplying the sort cost.
        let visible = filtered
        HStack(spacing: 0) {
            VStack(spacing: 0) {
                header(visibleCount: visible.count)
                Divider()
                tableOrEmpty(visible)
            }
            if let resource = selectedResource {
                DetailDrawer(resource: resource, session: session,
                             onEdit: { env.openYAMLEdit($0, gvr: gvr, session: session) },
                             onClose: { selection = nil })
                    .transition(.move(edge: .trailing))
            }
        }
        .background(.background)
        .navigationTitle(gvr.kind)
        .onAppear {
            store.subscribe(namespaces: session.namespaceScope)
            if let prefs = TablePrefsStore.load(cluster: session.id, table: gvr.id) {
                hiddenColumns = Set(prefs.hiddenColumns)
                sortColumnID = prefs.sortColumnID
                ascending = prefs.ascending
            }
            tableSort = [ColumnSort(columnID: sortColumnID,
                                    order: ascending ? .forward : .reverse)]
        }
        .onChange(of: session.selectedNamespaces) { _, _ in
            store.setNamespaces(session.namespaceScope)
        }
        .onChange(of: hiddenColumns) { _, _ in saveTablePrefs() }
        .onChange(of: sortColumnID) { _, _ in saveTablePrefs() }
        .onChange(of: ascending) { _, _ in saveTablePrefs() }
        .onChange(of: tableSort) { _, new in
            guard let first = new.first else { return }
            sortColumnID = first.columnID
            ascending = first.order == .forward
        }
        .sheet(item: $scaleTarget) { resource in
            ScaleDialog(resource: resource, session: session)
        }
        .sheet(item: $portForwardTarget) { resource in
            PortForwardDialog(resource: resource, session: session)
        }
    }

    // MARK: - Header

    private func header(visibleCount: Int) -> some View {
        HStack(spacing: Tokens.Spacing.md) {
            Text(gvr.kind).font(.title2.weight(.semibold))
            if store.isLoading { ProgressView().controlSize(.small) }
            Spacer()
            Text(countLabel(visibleCount: visibleCount)).font(.caption).foregroundStyle(.secondary)
            SearchField(placeholder: "Filter…", text: $search).frame(width: 220)
            if gvr.namespaced { namespaceMenu }
            sortMenu
            columnMenu
            Button { store.refresh() } label: {
                Image(systemName: "arrow.clockwise")
            }
            .help("Refresh")
            if gvr.supports(verb: "create") {
                Button {
                    env.openYAMLCreate(kind: gvr.kind,
                                       template: CreateTemplates.template(forKind: gvr.kind),
                                       gvr: gvr, session: session)
                } label: { Image(systemName: "plus") }
                    .help("Create \(gvr.kind)")
            }
        }
        .padding(Tokens.Spacing.md)
    }

    private func countLabel(visibleCount: Int) -> String {
        if search.isEmpty { return "\(store.items.count) items" }
        return "Filtered: \(visibleCount) / \(store.items.count)"
    }

    private var namespaceMenu: some View {
        Button {
            showNamespacePopover.toggle()
        } label: {
            Label(session.selectedNamespaces.isEmpty
                  ? "Namespaces" : "Namespaces (\(session.selectedNamespaces.count))",
                  systemImage: "square.dashed")
        }
        .buttonStyle(.borderless)
        .fixedSize()
        .popover(isPresented: $showNamespacePopover, arrowEdge: .bottom) {
            NamespaceFilterPopover(session: session)
        }
    }

    /// Menu row that shows a leading checkmark only when selected (avoids the
    /// invalid empty SF Symbol).
    @ViewBuilder
    private func checkmarkLabel(_ title: String, checked: Bool) -> some View {
        if checked {
            Label(title, systemImage: "checkmark")
        } else {
            Text(title)
        }
    }

    private var sortMenu: some View {
        Menu {
            ForEach(allColumns) { column in
                Button {
                    let toggled: SortOrder = ascending ? .reverse : .forward
                    tableSort = [ColumnSort(columnID: column.id,
                                            order: sortColumnID == column.id ? toggled : .forward)]
                } label: {
                    if sortColumnID == column.id {
                        Label(column.title, systemImage: ascending ? "chevron.up" : "chevron.down")
                    } else {
                        Text(column.title)
                    }
                }
            }
        } label: {
            Image(systemName: "arrow.up.arrow.down")
        }
        .menuStyle(.borderlessButton)
        .fixedSize()
        .help("Sort")
    }

    private var columnMenu: some View {
        Menu {
            ForEach(allColumns) { column in
                Button {
                    if hiddenColumns.contains(column.id) { hiddenColumns.remove(column.id) }
                    else { hiddenColumns.insert(column.id) }
                } label: {
                    checkmarkLabel(column.title, checked: !hiddenColumns.contains(column.id))
                }
                .disabled(column.id == "name")
            }
        } label: {
            Image(systemName: "tablecells")
        }
        .menuStyle(.borderlessButton)
        .fixedSize()
        .help("Columns")
    }

    // MARK: - Table

    @ViewBuilder
    private func tableOrEmpty(_ visible: [KubeResource]) -> some View {
        if visible.isEmpty {
            EmptyStateView(title: store.error == nil ? "No \(gvr.kind)" : "Couldn’t load",
                           systemImage: "tray",
                           message: store.error?.localizedDescription)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        } else {
            table(visible)
        }
    }

    private func table(_ visible: [KubeResource]) -> some View {
        Table(of: KubeResource.self, selection: $selection, sortOrder: $tableSort) {
            TableColumnForEach(columns) { column in
                TableColumn(column.title,
                            sortUsing: ColumnSort(columnID: column.id)) { (resource: KubeResource) in
                    cellContent(column, resource)
                }
                .width(min: column.width ?? 200)
            }
        } rows: {
            ForEach(visible) { resource in
                TableRow(resource)
            }
        }
        .contextMenu(forSelectionType: KubeResource.ID.self) { ids in
            if let id = ids.first, let resource = store.items.first(where: { $0.id == id }) {
                rowMenu(for: resource)
            }
        }
    }

    @ViewBuilder
    private func cellContent(_ column: ColumnDefinition, _ resource: KubeResource) -> some View {
        if let cell = column.cell {
            cell(resource)
        } else if let status = column.status?(resource) {
            HStack(spacing: 4) {
                StatusDot(status: status, diameter: 7)
                Text(column.value(resource)).lineLimit(1).monospacedDigit()
            }
        } else {
            // monospacedDigit: proportional digits make trailing-aligned
            // numeric columns (Restarts, Ready, counts) look ragged.
            Text(column.value(resource)).lineLimit(1).monospacedDigit()
        }
    }

    @ViewBuilder
    private func rowMenu(for resource: KubeResource) -> some View {
        let universal = UniversalActions.make(onEdit: { env.openYAMLEdit($0, gvr: gvr, session: session) },
                                              onViewYAML: { selection = $0.id })
        let kindSpecific = ResourceCatalog.shared.actions(forKind: gvr.kind)
        ForEach((kindSpecific + universal).filter { $0.isAvailable(resource) }) { action in
            Button(role: action.role) {
                runAction(action, on: resource)
            } label: {
                Label(action.title, systemImage: action.systemImage)
            }
        }
    }

    // MARK: - Behavior

    private func saveTablePrefs() {
        TablePrefsStore.save(TablePrefs(hiddenColumns: Array(hiddenColumns).sorted(),
                                        sortColumnID: sortColumnID, ascending: ascending),
                             cluster: session.id, table: gvr.id)
    }

    private func sorted(_ items: [KubeResource]) -> [KubeResource] {
        guard let column = allColumns.first(where: { $0.id == sortColumnID }) else { return items }
        // Compute each item's key once (n calls), not inside the comparator
        // (2·n·log n calls) — column closures can be expensive (JSON traversal).
        let key = column.sortKey ?? column.value
        let sorted = items
            .map { (key: key($0), item: $0) }
            .sorted { $0.key.localizedStandardCompare($1.key) == .orderedAscending }
            .map(\.item)
        return ascending ? sorted : sorted.reversed()
    }

    private func runAction(_ action: ObjectAction, on resource: KubeResource) {
        switch action.interaction {
        case .scale: scaleTarget = resource
        case .logs: env.openLogs(resource, session: session)
        case .shell: env.openShell(resource, session: session)
        case .nodeShell: env.openNodeShell(resource, session: session)
        case .portForward: portForwardTarget = resource
        case nil:
            Task {
                do {
                    try await action.perform(resource, session)
                } catch {
                    env.notifications.notify(.error, action.title, message: error.localizedDescription)
                }
            }
        }
    }
}

/// Namespace multi-select with substring search: typing "web" matches
/// "teachy-web-dev" and "teachy-web-stg". Stays open for multi-toggling.
/// Selected namespaces sort to the top; ↑/↓ move a highlight through the
/// results and ⏎ toggles it (or the first match) without leaving the field.
private struct NamespaceFilterPopover: View {
    let session: ClusterSession
    @State private var search = ""
    @State private var highlighted: Int?

    private var filtered: [String] {
        let needle = search.trimmingCharacters(in: .whitespaces)
        let matches = needle.isEmpty
            ? session.namespaces
            : session.namespaces.filter { $0.localizedCaseInsensitiveContains(needle) }
        return matches.sorted { lhs, rhs in
            let lhsSelected = session.selectedNamespaces.contains(lhs)
            let rhsSelected = session.selectedNamespaces.contains(rhs)
            if lhsSelected != rhsSelected { return lhsSelected }
            return lhs < rhs
        }
    }

    var body: some View {
        VStack(spacing: 0) {
            SearchField(placeholder: "Filter namespaces…", text: $search)
                .padding(Tokens.Spacing.sm)
                .onSubmit { toggleHighlighted() }
            Divider()
            ScrollViewReader { proxy in
                ScrollView {
                    LazyVStack(alignment: .leading, spacing: 0) {
                        row("All Namespaces", checked: session.selectedNamespaces.isEmpty,
                            highlighted: false) {
                            session.selectedNamespaces = []
                            session.applyNamespaceSelection()
                        }
                        Divider()
                        ForEach(Array(filtered.enumerated()), id: \.element) { index, ns in
                            row(ns, checked: session.selectedNamespaces.contains(ns),
                                highlighted: index == highlighted) {
                                toggle(ns)
                            }
                            .id(ns)
                        }
                        if filtered.isEmpty {
                            Text("No namespaces match “\(search)”")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                                .padding(Tokens.Spacing.sm)
                        }
                    }
                    .padding(.vertical, Tokens.Spacing.xs)
                }
                .frame(maxHeight: 320)
                .onChange(of: highlighted) { _, index in
                    if let index, filtered.indices.contains(index) {
                        proxy.scrollTo(filtered[index])
                    }
                }
            }
        }
        .frame(width: 280)
        .onChange(of: search) { _, _ in
            highlighted = filtered.isEmpty ? nil : 0
        }
        .onKeyPress(.downArrow) { move(1); return .handled }
        .onKeyPress(.upArrow) { move(-1); return .handled }
    }

    private func move(_ delta: Int) {
        guard !filtered.isEmpty else { return }
        highlighted = min(max((highlighted ?? -1) + delta, 0), filtered.count - 1)
    }

    /// ⏎ toggles the highlighted row (or the first match when none yet).
    private func toggleHighlighted() {
        guard !filtered.isEmpty else { return }
        let ns = filtered[min(highlighted ?? 0, filtered.count - 1)]
        toggle(ns)
        // Selection re-sorts the list — keep the highlight on the same row.
        highlighted = filtered.firstIndex(of: ns)
    }

    private func toggle(_ ns: String) {
        if session.selectedNamespaces.contains(ns) { session.selectedNamespaces.remove(ns) }
        else { session.selectedNamespaces.insert(ns) }
        session.applyNamespaceSelection()
    }

    private func row(_ title: String, checked: Bool, highlighted: Bool,
                     action: @escaping () -> Void) -> some View {
        Button(action: action) {
            HStack(spacing: Tokens.Spacing.sm) {
                Image(systemName: "checkmark")
                    .font(.caption.weight(.semibold))
                    .opacity(checked ? 1 : 0)
                Text(title).lineLimit(1)
                Spacer(minLength: 0)
            }
            .contentShape(Rectangle())
            .padding(.horizontal, Tokens.Spacing.sm)
            .padding(.vertical, 4)
            .background(highlighted ? AnyShapeStyle(.tint.opacity(0.18)) : AnyShapeStyle(.clear),
                        in: RoundedRectangle(cornerRadius: Tokens.Radius.sm))
        }
        .buttonStyle(.plain)
        .padding(.horizontal, Tokens.Spacing.xs)
    }
}
