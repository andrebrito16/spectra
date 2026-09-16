//
//  DetailDrawer.swift
//  Spectra
//
//  Right-side resizable detail drawer: title, action toolbar, then composable
//  sections (Metadata, Conditions, kind-specific spec, Events) and a read-only
//  YAML view. The drawer background is glass chrome; YAML stays solid/legible.
//

import SwiftUI

struct DetailDrawer: View {
    let resource: KubeResource
    let session: ClusterSession
    var onEdit: (KubeResource) -> Void
    var onClose: () -> Void

    @Environment(\.appEnv) private var env
    @State private var width: CGFloat = 420
    @State private var showYAML = false
    @State private var pendingAction: ObjectAction?
    @State private var scaleTarget: KubeResource?
    @State private var portForwardTarget: KubeResource?

    private var actions: [ObjectAction] {
        let universal = UniversalActions.make(
            onEdit: onEdit,
            onViewYAML: { _ in showYAML = true })
        let kindSpecific = ResourceCatalog.shared.actions(forKind: resource.kind ?? "", group: resource.apiGroup)
        return kindSpecific + universal
    }

    private var kindSections: [DetailSectionDef] {
        ResourceCatalog.shared.detailSections(forKind: resource.kind ?? "", group: resource.apiGroup)
    }

    var body: some View {
        HStack(spacing: 0) {
            resizeHandle
            VStack(spacing: 0) {
                header
                Divider()
                ScrollView {
                    VStack(spacing: Tokens.Spacing.md) {
                        MetadataSection(resource: resource)
                        ForEach(kindSections) { section in
                            section.makeView(resource, session)
                        }
                        ConditionsSection(resource: resource)
                        EventsSection(resource: resource, session: session)
                    }
                    .padding(Tokens.Spacing.md)
                }
            }
            .frame(width: width)
            .glassEffect(in: .rect(cornerRadius: 0))
        }
        .frame(maxHeight: .infinity)
        .sheet(isPresented: $showYAML) {
            YAMLViewerSheet(resource: resource)
        }
        .sheet(item: $scaleTarget) { target in
            ScaleDialog(resource: target, session: session)
        }
        .sheet(item: $portForwardTarget) { target in
            PortForwardDialog(resource: target, session: session)
        }
        .confirmationDialog(pendingAction?.confirm ?? "",
                            isPresented: Binding(get: { pendingAction?.confirm != nil },
                                                 set: { if !$0 { pendingAction = nil } }),
                            titleVisibility: .visible) {
            if let action = pendingAction {
                Button(action.title, role: action.role) { run(action) }
            }
            Button("Cancel", role: .cancel) { pendingAction = nil }
        }
    }

    private var header: some View {
        HStack(spacing: Tokens.Spacing.sm) {
            Image(systemName: ResourceKindIcon.symbol(forKind: resource.kind ?? ""))
                .foregroundStyle(env.theme.accent)
            VStack(alignment: .leading, spacing: 0) {
                Text(resource.name).font(.headline).lineLimit(1)
                Text(resource.kind ?? "").font(.caption).foregroundStyle(.secondary)
            }
            Spacer()
            Menu {
                ForEach(actions.filter { $0.isAvailable(resource) }) { action in
                    Button(role: action.role) {
                        trigger(action)
                    } label: {
                        Label(action.title, systemImage: action.systemImage)
                    }
                }
            } label: {
                Image(systemName: "ellipsis.circle")
            }
            .menuStyle(.borderlessButton)
            .fixedSize()

            Button { onClose() } label: { Image(systemName: "xmark") }
                .buttonStyle(.plain)
                .keyboardShortcut(.cancelAction)
                .accessibilityLabel("Close detail")
        }
        .padding(Tokens.Spacing.md)
    }

    private var resizeHandle: some View {
        Rectangle()
            .fill(Color.clear)
            .frame(width: 6)
            .overlay { Divider() }
            .contentShape(Rectangle())
            .gesture(
                DragGesture()
                    .onChanged { value in
                        width = min(max(width - value.translation.width, 320), 720)
                    }
            )
            .onHover { hovering in
                if hovering { NSCursor.resizeLeftRight.push() } else { NSCursor.pop() }
            }
    }

    private func trigger(_ action: ObjectAction) {
        switch action.interaction {
        case .scale: scaleTarget = resource
        case .logs: env.openLogs(resource, session: session)
        case .shell: env.openShell(resource, session: session)
        case .nodeShell: env.openNodeShell(resource, session: session)
        case .portForward: portForwardTarget = resource
        case nil:
            if action.confirm != nil { pendingAction = action } else { run(action) }
        }
    }

    private func run(_ action: ObjectAction) {
        pendingAction = nil
        Task {
            do {
                try await action.perform(resource, session)
            } catch {
                env.notifications.notify(.error, action.title, message: error.localizedDescription)
            }
        }
    }
}

/// Read-only YAML viewer sheet.
struct YAMLViewerSheet: View {
    let resource: KubeResource
    @Environment(\.dismiss) private var dismiss
    @State private var yaml = ""

    var body: some View {
        VStack(spacing: 0) {
            HStack {
                Text("\(resource.kind ?? "Resource"): \(resource.name)").font(.headline)
                Spacer()
                Button("Done") { dismiss() }.keyboardShortcut(.defaultAction)
            }
            .padding(Tokens.Spacing.md)
            Divider()
            YAMLEditor(text: $yaml, isEditable: false)
                .frame(minWidth: 560, minHeight: 480)
        }
        .frame(width: 640, height: 560)
        .onAppear { yaml = (try? resource.yamlString()) ?? "" }
    }
}
