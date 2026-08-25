//
//  DetailSections.swift
//  Spectra
//
//  Built-in detail-drawer sections shown for every kind (so CRDs get a usable
//  detail view for free): Metadata, Conditions, and live Events. Kind-specific
//  spec sections are contributed by feature phases via DetailSectionDef.
//

import SwiftUI

/// A labeled key/value row used throughout detail views.
struct DetailRow: View {
    let label: String
    let value: String

    var body: some View {
        HStack(alignment: .top) {
            Text(label)
                .font(.callout)
                .foregroundStyle(.secondary)
                .frame(width: 140, alignment: .leading)
            Text(value)
                .font(.callout)
                .textSelection(.enabled)
            Spacer(minLength: 0)
        }
    }
}

/// A titled card grouping detail content.
struct DetailCard<Content: View>: View {
    let title: String
    @ViewBuilder var content: Content

    var body: some View {
        VStack(alignment: .leading, spacing: Tokens.Spacing.sm) {
            Text(title)
                .font(.headline)
            content
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(Tokens.Spacing.md)
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: Tokens.Radius.md))
    }
}

/// Chip cloud for labels/annotations.
struct KeyValueChips: View {
    let pairs: [String: String]

    var body: some View {
        if pairs.isEmpty {
            Text("None").font(.caption).foregroundStyle(.tertiary)
        } else {
            FlowLayout(spacing: Tokens.Spacing.xs) {
                ForEach(pairs.sorted(by: { $0.key < $1.key }), id: \.key) { key, value in
                    Text("\(key): \(value)")
                        .font(.caption)
                        .lineLimit(1)
                        .padding(.horizontal, Tokens.Spacing.sm)
                        .padding(.vertical, 2)
                        .background(.quaternary, in: Capsule())
                        .textSelection(.enabled)
                }
            }
        }
    }
}

struct MetadataSection: View {
    let resource: KubeResource

    var body: some View {
        DetailCard(title: "Metadata") {
            VStack(alignment: .leading, spacing: Tokens.Spacing.xs) {
                DetailRow(label: "Name", value: resource.name)
                if let namespace = resource.namespace {
                    DetailRow(label: "Namespace", value: namespace)
                }
                if let uid = resource.uid { DetailRow(label: "UID", value: uid) }
                if let created = resource.creationTimestamp {
                    DetailRow(label: "Created",
                              value: "\(created) (\(resource.creationDate?.k8sAge ?? "?"))")
                }
                DetailRow(label: "Labels", value: "")
                    .hidden().frame(height: 0)
                VStack(alignment: .leading, spacing: 2) {
                    Text("Labels").font(.callout).foregroundStyle(.secondary)
                    KeyValueChips(pairs: resource.labels)
                }
                VStack(alignment: .leading, spacing: 2) {
                    Text("Annotations").font(.callout).foregroundStyle(.secondary)
                    KeyValueChips(pairs: resource.annotations)
                }
                if !resource.ownerReferences.isEmpty {
                    DetailRow(label: "Controlled By",
                              value: resource.ownerReferences
                                .map { "\($0.kind)/\($0.name)" }.joined(separator: ", "))
                }
                if !resource.finalizers.isEmpty {
                    DetailRow(label: "Finalizers",
                              value: resource.finalizers.joined(separator: ", "))
                }
            }
        }
    }
}

struct ConditionsSection: View {
    let resource: KubeResource

    private var conditions: [JSONValue] {
        resource.status?["conditions"]?.arrayValue ?? []
    }

    var body: some View {
        if !conditions.isEmpty {
            DetailCard(title: "Conditions") {
                VStack(alignment: .leading, spacing: Tokens.Spacing.xs) {
                    ForEach(Array(conditions.enumerated()), id: \.offset) { _, condition in
                        HStack(alignment: .top) {
                            let type = condition["type"]?.stringValue ?? "?"
                            let statusValue = condition["status"]?.stringValue ?? "?"
                            Badge(text: type, status: statusValue == "True" ? .success : .neutral)
                            VStack(alignment: .leading, spacing: 0) {
                                if let reason = condition["reason"]?.stringValue {
                                    Text(reason).font(.caption)
                                }
                                if let message = condition["message"]?.stringValue {
                                    Text(message).font(.caption2).foregroundStyle(.secondary)
                                }
                            }
                            Spacer()
                        }
                    }
                }
            }
        }
    }
}

/// Live Events filtered to this object via involvedObject.uid.
struct EventsSection: View {
    let resource: KubeResource
    let session: ClusterSession

    @State private var store: ResourceStore?

    private var events: [KubeResource] {
        guard let store, let uid = resource.uid else { return [] }
        return store.items
            .filter { $0.value(at: ["involvedObject", "uid"])?.stringValue == uid }
            .sorted { ($0.value(at: ["lastTimestamp"])?.stringValue ?? "")
                      > ($1.value(at: ["lastTimestamp"])?.stringValue ?? "") }
    }

    var body: some View {
        DetailCard(title: "Events") {
            if events.isEmpty {
                Text("No events").font(.caption).foregroundStyle(.tertiary)
            } else {
                VStack(alignment: .leading, spacing: Tokens.Spacing.xs) {
                    ForEach(events.prefix(20)) { event in
                        HStack(alignment: .top, spacing: Tokens.Spacing.sm) {
                            let type = event.value(at: ["type"])?.stringValue ?? "Normal"
                            StatusDot(status: type == "Warning" ? .warning : .info)
                            VStack(alignment: .leading, spacing: 0) {
                                Text(event.value(at: ["message"])?.stringValue ?? "")
                                    .font(.caption)
                                Text(event.value(at: ["reason"])?.stringValue ?? "")
                                    .font(.caption2).foregroundStyle(.secondary)
                            }
                        }
                    }
                }
            }
        }
        .onAppear { subscribe() }
        .onDisappear { store?.unsubscribe() }
    }

    private func subscribe() {
        guard let gvr = session.gvr(forKind: "Event") else { return }
        let store = session.store(for: gvr)
        self.store = store
        store.subscribe(namespaces: session.namespaceScope)
    }
}

/// A simple flow layout for chips.
struct FlowLayout: Layout {
    var spacing: CGFloat = 4

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        let maxWidth = proposal.width ?? .infinity
        var x: CGFloat = 0, y: CGFloat = 0, rowHeight: CGFloat = 0
        for subview in subviews {
            let size = subview.sizeThatFits(.unspecified)
            if x + size.width > maxWidth {
                x = 0; y += rowHeight + spacing; rowHeight = 0
            }
            x += size.width + spacing
            rowHeight = max(rowHeight, size.height)
        }
        return CGSize(width: maxWidth == .infinity ? x : maxWidth, height: y + rowHeight)
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize,
                       subviews: Subviews, cache: inout ()) {
        var x = bounds.minX, y = bounds.minY, rowHeight: CGFloat = 0
        for subview in subviews {
            let size = subview.sizeThatFits(.unspecified)
            if x + size.width > bounds.maxX {
                x = bounds.minX; y += rowHeight + spacing; rowHeight = 0
            }
            subview.place(at: CGPoint(x: x, y: y), proposal: ProposedViewSize(size))
            x += size.width + spacing
            rowHeight = max(rowHeight, size.height)
        }
    }
}
