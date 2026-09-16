//
//  ResourceListConfig.swift
//  Spectra
//
//  The config that drives the generic list/detail engine, per kind: columns,
//  detail sections, and kind-specific actions. Feature phases (6–8, 10) register
//  configs here instead of building bespoke screens. A kind is "supported" the
//  moment it has columns; everything else falls back to sensible defaults so
//  CRDs work for free.
//

import SwiftUI

/// A single table column: a value extractor and optional status coloring.
@MainActor
struct ColumnDefinition: Identifiable {
    let id: String
    let title: String
    /// Minimum/ideal width hint for the Table column.
    var width: CGFloat?
    var alignment: Alignment = .leading
    /// Text value (also used for sorting + accessibility).
    let value: (KubeResource) -> String
    /// Optional sort key when the display text doesn't sort correctly or is
    /// expensive to compute (e.g. Age sorts by the raw RFC3339 timestamp).
    var sortKey: ((KubeResource) -> String)?
    /// Optional status coloring for a leading dot.
    var status: ((KubeResource) -> SpectraStatus?)?
    /// Optional custom cell (e.g. a usage bar). Overrides the text rendering.
    var cell: ((KubeResource) -> AnyView)?

    init(id: String, title: String, width: CGFloat? = nil, alignment: Alignment = .leading,
         sortKey: ((KubeResource) -> String)? = nil,
         status: ((KubeResource) -> SpectraStatus?)? = nil,
         cell: ((KubeResource) -> AnyView)? = nil,
         value: @escaping (KubeResource) -> String) {
        self.id = id
        self.title = title
        self.width = width
        self.alignment = alignment
        self.sortKey = sortKey
        self.value = value
        self.status = status
        self.cell = cell
    }
}

/// A composable detail-drawer section registered per kind (Phase 6–8 fill these).
@MainActor
struct DetailSectionDef: Identifiable {
    let id: String
    let title: String
    let makeView: (KubeResource, ClusterSession) -> AnyView
}

/// Per-kind configuration assembled by feature phases.
@MainActor
struct ResourceConfig {
    var columns: [ColumnDefinition]
    var detailSections: [DetailSectionDef]
    var actions: [ObjectAction]

    init(columns: [ColumnDefinition],
         detailSections: [DetailSectionDef] = [],
         actions: [ObjectAction] = []) {
        self.columns = columns
        self.detailSections = detailSections
        self.actions = actions
    }
}

/// Registry of per-kind configs, optionally scoped to an API group. Feature phases register into the shared catalog;
/// unregistered kinds (including CRDs) get default columns.
@MainActor
final class ResourceCatalog {
    static let shared = ResourceCatalog()

    private var configs: [String: ResourceConfig] = [:]
    private var groupConfigs: [String: ResourceConfig] = [:]

    func register(_ kind: String, group: String? = nil, _ config: ResourceConfig) {
        if let group {
            groupConfigs["\(group)/\(kind)"] = config
        } else {
            configs[kind] = config
        }
    }

    func config(forKind kind: String, group: String? = nil) -> ResourceConfig? {
        if let group, let config = groupConfigs["\(group)/\(kind)"] { return config }
        return configs[kind]
    }

    /// Columns for a kind: registered columns, else defaults.
    func columns(forKind kind: String, namespaced: Bool, group: String? = nil) -> [ColumnDefinition] {
        config(forKind: kind, group: group)?.columns ?? Self.defaultColumns(namespaced: namespaced)
    }

    func actions(forKind kind: String, group: String? = nil) -> [ObjectAction] {
        config(forKind: kind, group: group)?.actions ?? []
    }

    func detailSections(forKind kind: String, group: String? = nil) -> [DetailSectionDef] {
        config(forKind: kind, group: group)?.detailSections ?? []
    }

    /// Default columns for any kind (CRDs included): Name [+ Namespace] + Age.
    static func defaultColumns(namespaced: Bool) -> [ColumnDefinition] {
        var columns: [ColumnDefinition] = [
            ColumnDefinition(id: "name", title: "Name") { $0.name },
        ]
        if namespaced {
            columns.append(ColumnDefinition(id: "namespace", title: "Namespace", width: 180) {
                $0.namespace ?? "—"
            })
        }
        columns.append(Columns.age)
        return columns
    }
}

/// Reusable column definitions shared across kinds.
@MainActor
enum Columns {
    /// Sort key is the raw RFC3339 timestamp (k8s always serializes UTC with a
    /// fixed layout), so lexicographic order IS chronological order — correct
    /// sorting ("10d" vs "2d" would sort wrong as text) with zero date parsing.
    static let age = ColumnDefinition(id: "age", title: "Age", width: 64, alignment: .trailing,
                                      sortKey: { $0.creationTimestamp ?? "" }) {
        $0.creationDate?.k8sAge ?? "—"
    }

    static func namespace() -> ColumnDefinition {
        ColumnDefinition(id: "namespace", title: "Namespace", width: 180) { $0.namespace ?? "—" }
    }

    static let name = ColumnDefinition(id: "name", title: "Name") { $0.name }
}
