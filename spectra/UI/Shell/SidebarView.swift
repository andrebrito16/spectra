//
//  SidebarView.swift
//  Spectra
//
//  Left navigation sidebar. Data-driven from the active session's discovered GVR
//  table via NavGrouping. Sections are collapsible (whole header toggles) and
//  closed by default except Workloads. A bottom space-indicator + horizontal
//  swipe switch clusters Arc-style. Selecting an item opens/switches a tab.
//

import SwiftUI

struct SidebarView: View {
    @Environment(\.appEnv) private var env
    @State private var expanded: Set<String> = ["Workloads"]
    @State private var orgSheet: OrgSheetTarget?

    private var activeRecord: ClusterRecord? {
        env.clusters.activeClusterId.flatMap { env.clusters.record(id: $0) }
    }

    var body: some View {
        VStack(spacing: 0) {
            ClusterSwitcher()
            Divider()
            Color.clear.frame(height: Tokens.Spacing.md)
            if let session = env.clusters.activeSession {
                navList(for: session)
            } else {
                knownClustersList
            }
            if env.clusters.records.count > 1 {
                Divider()
                SpaceIndicator()
            }
        }
        .background {
            if let record = activeRecord, let start = record.customColor {
                ClusterThemeBackground(start: start, end: record.gradientEndColor ?? start,
                                       angle: record.gradientAngle ?? 135)
            }
        }
        .simultaneousGesture(clusterSwipe)
        .clusterSideScroll { delta in
            withAnimation(.snappy) { env.switchCluster(delta: delta) }
        }
    }

    /// Horizontal swipe switches clusters (Arc Spaces-style). Vertical scrolling
    /// still works because this is a simultaneous gesture with a high threshold.
    private var clusterSwipe: some Gesture {
        DragGesture(minimumDistance: 30)
            .onEnded { value in
                let dx = value.translation.width, dy = value.translation.height
                guard abs(dx) > 80, abs(dx) > abs(dy) * 2 else { return }
                withAnimation(.snappy) { env.switchCluster(delta: dx < 0 ? 1 : -1) }
            }
    }

    private func navList(for session: ClusterSession) -> some View {
        List(selection: routeSelection) {
            Label("Overview", systemImage: "gauge.with.dots.needle.50percent")
                .tag(NavigationModel.Route.overview.tag)

            ForEach(NavGrouping.build(from: session.gvrs)) { group in
                section(group.section.rawValue, icon: group.section.icon) {
                    ForEach(group.entries) { entry in
                        entryRow(entry, indent: Tokens.Spacing.lg)
                    }
                    ForEach(group.subgroups) { sub in
                        subgroup(sub)
                    }
                }
            }

            section("Helm", icon: "sailboat") {
                Label("Charts", systemImage: "sailboat")
                    .padding(.leading, Tokens.Spacing.lg)
                    .tag(NavigationModel.Route.special("helm/charts").tag)
                Label("Releases", systemImage: "shippingbox")
                    .padding(.leading, Tokens.Spacing.lg)
                    .tag(NavigationModel.Route.special("helm/releases").tag)
            }

            section("Tools", icon: "wrench.and.screwdriver") {
                Label("Port Forwards", systemImage: "arrow.left.arrow.right")
                    .padding(.leading, Tokens.Spacing.lg)
                    .tag(NavigationModel.Route.special("network/portforwards").tag)
            }
        }
        .listStyle(.sidebar)
        .scrollContentBackground(.hidden)
        .labelStyle(SidebarResourceLabelStyle())
        .overlay {
            if session.gvrs.isEmpty && session.bootstrapError == nil {
                Spinner(label: "Loading resources…")
            }
        }
    }

    /// Collapsible section whose ENTIRE header toggles on a single click. State is
    /// per-section (a Set), so expanding one section never collapses another. We
    /// drive it with an explicit Button rather than a DisclosureGroup, whose label
    /// (in a sidebar List) only toggles via the small chevron — the cause of the
    /// "needs a second, precise click" behavior.
    @ViewBuilder
    private func section<Content: View>(_ title: String, icon: String,
                                        @ViewBuilder content: @escaping () -> Content) -> some View {
        let isOpen = expanded.contains(title)
        Button {
            withAnimation(.snappy) {
                if expanded.contains(title) { expanded.remove(title) } else { expanded.insert(title) }
            }
        } label: {
            HStack(spacing: Tokens.Spacing.sm) {
                Image(systemName: icon)
                    .frame(width: 18)
                Text(title)
                    .font(.callout.weight(.semibold))
                    .foregroundStyle(.primary)
                Spacer(minLength: 0)
                Image(systemName: "chevron.right")
                    .font(.caption2.weight(.semibold))
                    .foregroundStyle(.tertiary)
                    .rotationEffect(.degrees(isOpen ? 90 : 0))
            }
            .contentShape(Rectangle())
            .padding(.vertical, 2)
        }
        .buttonStyle(.plain)

        if isOpen {
            content()
        }
    }

    private func entryRow(_ entry: SidebarEntry, indent: CGFloat) -> some View {
        Label(entry.title, systemImage: entry.icon)
            .padding(.leading, indent)
            .tag(NavigationModel.Route.kind(entry.id).tag)
    }

    /// Collapsible API-group bucket under Custom Resources (Lens-style):
    /// "karpenter.sh" → NodeClaims, NodePools, …
    @ViewBuilder
    private func subgroup(_ sub: SidebarSubgroup) -> some View {
        let key = "crd:\(sub.name)"
        let isOpen = expanded.contains(key)
        Button {
            withAnimation(.snappy) {
                if isOpen { expanded.remove(key) } else { expanded.insert(key) }
            }
        } label: {
            HStack(spacing: Tokens.Spacing.sm) {
                Text(sub.name)
                    .font(.callout)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                Spacer(minLength: 0)
                Text("\(sub.entries.count)")
                    .font(.caption2.monospacedDigit())
                    .foregroundStyle(.tertiary)
                Image(systemName: "chevron.right")
                    .font(.caption2.weight(.semibold))
                    .foregroundStyle(.tertiary)
                    .rotationEffect(.degrees(isOpen ? 90 : 0))
            }
            .padding(.leading, Tokens.Spacing.lg)
            .contentShape(Rectangle())
            .padding(.vertical, 1)
        }
        .buttonStyle(.plain)

        if isOpen {
            ForEach(sub.entries) { entry in
                entryRow(entry, indent: Tokens.Spacing.lg * 2)
            }
        }
    }

    private var knownClustersList: some View {
        VStack(spacing: 0) {
            HStack {
                Text("CLUSTERS")
                    .font(.caption2.weight(.semibold))
                    .foregroundStyle(.secondary)
                Spacer()
                Button { orgSheet = .create } label: {
                    Image(systemName: "folder.badge.plus")
                }
                .buttonStyle(.plain)
                .foregroundStyle(.secondary)
                .help("New Org — group clusters together")
            }
            .padding(.horizontal, Tokens.Spacing.md)
            .padding(.vertical, Tokens.Spacing.xs)

            // A ScrollView (not a List): `.draggable` reliably starts a drag here,
            // whereas inside a `.sidebar` List the row drag never initiates.
            ScrollView {
                LazyVStack(alignment: .leading, spacing: 2) {
                    if env.clusters.orgs.isEmpty {
                        ForEach(env.clusters.orderedRecords) { record in
                            ClusterSidebarRow(record: record, onCreateOrg: { orgSheet = .create })
                        }
                    } else {
                        ForEach(env.clusters.groupedClusters.filter {
                            $0.org != nil || !$0.records.isEmpty
                        }) { group in
                            OrgSidebarHeader(group: group, onRename: { orgSheet = .rename($0) })
                            ForEach(group.records) { record in
                                ClusterSidebarRow(record: record, onCreateOrg: { orgSheet = .create })
                            }
                            if group.records.isEmpty {
                                OrgEmptyDropZone(org: group.org)
                            }
                        }
                    }
                }
                .padding(.horizontal, Tokens.Spacing.sm)
                .padding(.bottom, Tokens.Spacing.sm)
                .animation(.snappy, value: env.clusters.records.map(\.sortOrder))
            }
        }
        .sheet(item: $orgSheet) { OrgSheet(org: $0.org) }
    }

    private var routeSelection: Binding<String?> {
        Binding {
            env.navigation.route.tag
        } set: { newValue in
            guard let tag = newValue else { return }
            let route = NavigationModel.Route(tag: tag)
            var title: String?
            var icon: String?
            if case .kind(let id) = route {
                // Section headers and CRD-group rows are ForEach elements, so
                // List gives them IMPLICIT selection tags from their ids
                // ("Custom Resources", "karpenter.sh", …). Those parse as
                // .kind routes with no matching GVR — opening a junk tab that
                // falls back to the catalog. Only navigate to real kinds.
                guard let gvr = env.clusters.activeSession?.gvr(byID: id) else { return }
                title = gvr.kind
                icon = ResourceKindIcon.symbol(forKind: gvr.kind)
            }
            env.navigation.navigate(to: route, title: title, systemImage: icon)
        }
    }
}

/// Use the same icon column for navigation rows and section headers.
private struct SidebarResourceLabelStyle: LabelStyle {
    func makeBody(configuration: Configuration) -> some View {
        HStack(spacing: Tokens.Spacing.sm) {
            configuration.icon.frame(width: 18)
            configuration.title
        }
    }
}

/// Arc Spaces-style indicator: each cluster's icon, the active one tinted with
/// its custom color (theme accent if none), the rest grey. Click to switch.
struct SpaceIndicator: View {
    @Environment(\.appEnv) private var env

    var body: some View {
        HStack(spacing: Tokens.Spacing.md) {
            ForEach(env.clusters.orderedRecords) { record in
                let active = record.id == env.clusters.activeClusterId
                Image(systemName: record.effectiveIcon)
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(active ? record.identityStyle(fallback: env.theme.accent)
                                            : AnyShapeStyle(.tertiary))
                    .scaleEffect(active ? 1.15 : 1)
                    .frame(width: 20, height: 20)
                    .contentShape(Rectangle())
                    .onTapGesture { withAnimation(.snappy) { env.openCluster(record.id) } }
                    .help(record.effectiveName)
            }
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, Tokens.Spacing.sm)
    }
}

/// Cluster header at the top of the sidebar: active cluster + a popover to switch
/// among connected clusters, rename, or return to the catalog.
struct ClusterSwitcher: View {
    @Environment(\.appEnv) private var env
    @State private var showPopover = false
    @State private var renameTarget: ClusterRecord?

    private var activeRecord: ClusterRecord? {
        guard let id = env.clusters.activeClusterId else { return nil }
        return env.clusters.record(id: id)
    }

    var body: some View {
        Button {
            showPopover.toggle()
        } label: {
            HStack(spacing: Tokens.Spacing.sm) {
                Image(systemName: activeRecord?.effectiveIcon ?? ClusterStyle.defaultSymbol)
                    .foregroundStyle(activeRecord?.identityStyle(fallback: env.theme.accent) ?? AnyShapeStyle(env.theme.accent))
                    .font(.title3)
                VStack(alignment: .leading, spacing: 0) {
                    Text(activeRecord?.effectiveName ?? "Catalog")
                        .font(.headline)
                        .lineLimit(1)
                    if let id = activeRecord?.id {
                        Text((env.clusters.states[id]?.status ?? .disconnected).label)
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                            .lineLimit(1)
                    }
                }
                Spacer()
                Image(systemName: "chevron.up.chevron.down")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            .padding(.horizontal, Tokens.Spacing.md)
            .padding(.vertical, Tokens.Spacing.sm)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .contextMenu {
            if let activeRecord {
                Button("Customize…") { renameTarget = activeRecord }
            }
        }
        .popover(isPresented: $showPopover, arrowEdge: .bottom) {
            switcherPopover
        }
        .sheet(isPresented: Binding(get: { renameTarget != nil },
                                    set: { if !$0 { renameTarget = nil } })) {
            if let renameTarget { CustomizeClusterSheet(record: renameTarget) }
        }
    }

    private var switcherPopover: some View {
        VStack(alignment: .leading, spacing: 0) {
            Button {
                env.showCatalog()
                showPopover = false
            } label: {
                Label("Show Catalog", systemImage: "square.grid.2x2")
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
            .buttonStyle(.plain)
            .padding(Tokens.Spacing.sm)

            Divider()

            if let activeRecord {
                Button {
                    showPopover = false
                    renameTarget = activeRecord
                } label: {
                    Label("Customize Cluster…", systemImage: "paintpalette")
                }
                .buttonStyle(.plain)
                .padding(Tokens.Spacing.sm)
                Divider()
            }

            ForEach(env.clusters.groupedClusters.filter {
                $0.org != nil || !$0.records.isEmpty
            }) { group in
                if !env.clusters.orgs.isEmpty {
                    HStack(spacing: Tokens.Spacing.xs) {
                        Image(systemName: group.org == nil ? "tray" : "folder.fill")
                            .font(.caption2)
                            .foregroundStyle(group.org == nil ? AnyShapeStyle(.secondary)
                                                              : AnyShapeStyle(env.theme.accent))
                        Text(group.name)
                            .font(.caption2.weight(.semibold))
                            .foregroundStyle(.secondary)
                        Spacer()
                    }
                    .padding(.horizontal, Tokens.Spacing.sm)
                    .padding(.top, Tokens.Spacing.xs)
                }
                ForEach(group.records) { record in
                    switcherRow(record)
                }
            }
        }
        .frame(width: 260)
        .padding(.vertical, Tokens.Spacing.xs)
    }

    @ViewBuilder
    private func switcherRow(_ record: ClusterRecord) -> some View {
        Button {
            env.openCluster(record.id)
            showPopover = false
        } label: {
            HStack {
                Image(systemName: record.effectiveIcon)
                    .foregroundStyle(record.identityStyle(fallback: env.theme.accent))
                    .frame(width: 18)
                StatusDot(status: env.clusters.states[record.id]?.status.status ?? .neutral)
                Text(record.effectiveName)
                Spacer()
                if record.id == env.clusters.activeClusterId {
                    Image(systemName: "checkmark").font(.caption)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .padding(.horizontal, Tokens.Spacing.sm)
        .padding(.vertical, Tokens.Spacing.xs)
        .contextMenu {
            Button("Customize…") {
                showPopover = false
                renameTarget = record
            }
        }
    }
}

/// A draggable, drop-targetable cluster row in the sidebar's catalog list.
/// Dropping another cluster on it reorders (and adopts this row's org); works
/// with or without any orgs. Built on a plain Button in a ScrollView so the drag
/// reliably starts (a `.sidebar` List swallows row drags).
private struct ClusterSidebarRow: View {
    @Environment(\.appEnv) private var env
    let record: ClusterRecord
    let onCreateOrg: () -> Void
    @State private var hovering = false
    @State private var targeted = false
    @State private var renaming = false

    var body: some View {
        Button {
            env.openCluster(record.id)
        } label: {
            HStack(spacing: Tokens.Spacing.sm) {
                Image(systemName: record.effectiveIcon)
                    .foregroundStyle(record.identityStyle(fallback: env.theme.accent))
                    .frame(width: 18)
                StatusDot(status: env.clusters.states[record.id]?.status.status ?? .neutral)
                Text(record.effectiveName)
                    .lineLimit(1)
                Spacer(minLength: 0)
            }
            .padding(.horizontal, Tokens.Spacing.sm)
            .padding(.vertical, 5)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(rowBackground, in: RoundedRectangle(cornerRadius: Tokens.Radius.sm))
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .onHover { hovering = $0 }
        .draggable(record.id)
        .dropDestination(for: String.self) { items, _ in
            guard let dragged = items.first else { return false }
            env.clusters.moveCluster(dragged, before: record.id)
            return true
        } isTargeted: { targeted = $0 }
        .contextMenu {
            Button("Open") { env.openCluster(record.id) }
            Button("Customize…") { renaming = true }
            Menu("Move to") {
                Button("Ungrouped") { env.clusters.setOrg(nil, for: record.id) }
                if !env.clusters.orgs.isEmpty { Divider() }
                ForEach(env.clusters.orgs) { org in
                    Button(org.name) { env.clusters.setOrg(org.id, for: record.id) }
                }
                Divider()
                Button("New Org…") { onCreateOrg() }
            }
            Divider()
            Button("Remove", role: .destructive) {
                Task { await env.clusters.remove(id: record.id) }
            }
        }
        .sheet(isPresented: $renaming) {
            CustomizeClusterSheet(record: record)
        }
    }

    private var rowBackground: AnyShapeStyle {
        if targeted { return AnyShapeStyle(env.theme.accent.opacity(0.25)) }
        if hovering { return AnyShapeStyle(Color.secondary.opacity(0.12)) }
        return AnyShapeStyle(.clear)
    }
}

/// A clear, drop-targetable org (or "Ungrouped") header in the sidebar list.
private struct OrgSidebarHeader: View {
    @Environment(\.appEnv) private var env
    let group: ClusterManager.ClusterGroup
    let onRename: (ClusterOrg) -> Void
    @State private var targeted = false

    var body: some View {
        HStack(spacing: Tokens.Spacing.xs) {
            Image(systemName: group.org == nil ? "tray" : "folder.fill")
                .font(.caption2)
                .foregroundStyle(group.org == nil ? AnyShapeStyle(.secondary)
                                                  : AnyShapeStyle(env.theme.accent))
            Text(group.name.uppercased())
                .font(.caption2.weight(.semibold))
                .foregroundStyle(.secondary)
            Spacer()
            Text("\(group.records.count)")
                .font(.caption2.monospacedDigit())
                .foregroundStyle(.tertiary)
        }
        .padding(.horizontal, Tokens.Spacing.sm)
        .padding(.vertical, 4)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(targeted ? AnyShapeStyle(env.theme.accent.opacity(0.18))
                             : AnyShapeStyle(.clear),
                    in: RoundedRectangle(cornerRadius: Tokens.Radius.sm))
        .contentShape(Rectangle())
        .padding(.top, Tokens.Spacing.xs)
        .dropDestination(for: String.self) { items, _ in
            guard let dragged = items.first else { return false }
            env.clusters.setOrg(group.org?.id, for: dragged)
            return true
        } isTargeted: { targeted = $0 }
        .contextMenu {
            if let org = group.org {
                Button("Rename…") { onRename(org) }
                Button("Delete Org", role: .destructive) { env.clusters.deleteOrg(org) }
            }
        }
    }
}

/// Dashed drop zone shown under an empty org so clusters can be dragged into it.
private struct OrgEmptyDropZone: View {
    @Environment(\.appEnv) private var env
    let org: ClusterOrg?
    @State private var targeted = false

    var body: some View {
        Text("Drag clusters here")
            .font(.caption2)
            .foregroundStyle(.tertiary)
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.horizontal, Tokens.Spacing.sm)
            .padding(.vertical, 6)
            .background {
                RoundedRectangle(cornerRadius: Tokens.Radius.sm)
                    .strokeBorder(style: StrokeStyle(lineWidth: 1, dash: [4]))
                    .foregroundStyle(targeted ? AnyShapeStyle(env.theme.accent)
                                              : AnyShapeStyle(.quaternary))
            }
            .dropDestination(for: String.self) { items, _ in
                guard let dragged = items.first else { return false }
                env.clusters.setOrg(org?.id, for: dragged)
                return true
            } isTargeted: { targeted = $0 }
    }
}
