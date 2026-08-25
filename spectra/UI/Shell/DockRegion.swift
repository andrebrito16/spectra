//
//  DockRegion.swift
//  Spectra
//
//  Bottom dock host: a resizable panel with a glass tab strip hosting terminals
//  and log streams. The hosted content (SwiftTerm / log view) sits on solid,
//  legible backgrounds; only the chrome is glass.
//

import SwiftUI

struct DockRegion: View {
    @Binding var height: Double
    var onClose: () -> Void

    @Environment(\.appEnv) private var env

    var body: some View {
        VStack(spacing: 0) {
            resizeHandle
            tabStrip
            Divider()
            content
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(.regularMaterial)
        .overlay(alignment: .top) { Divider() }
    }

    private var resizeHandle: some View {
        Rectangle()
            .fill(Color.clear)
            .frame(height: 8)
            .overlay { Capsule().fill(.tertiary).frame(width: 36, height: 4) }
            .contentShape(Rectangle())
            .gesture(
                DragGesture().onChanged { value in
                    height = min(max(height - value.translation.height, Tokens.Dock.minHeight), 800)
                })
            .onHover { hovering in
                if hovering { NSCursor.resizeUpDown.push() } else { NSCursor.pop() }
            }
            .accessibilityLabel("Resize dock")
    }

    private var tabStrip: some View {
        HStack(spacing: Tokens.Spacing.xs) {
            ForEach(env.dock.tabs) { tab in
                tabChip(tab)
            }
            Spacer()
            Button { onClose() } label: { Image(systemName: "xmark") }
                .buttonStyle(.plain)
                .accessibilityLabel("Close dock")
        }
        .padding(.horizontal, Tokens.Spacing.md)
        .padding(.vertical, Tokens.Spacing.xs)
    }

    private func tabChip(_ tab: DockTab) -> some View {
        let selected = env.dock.selectedTab == tab.id
        return HStack(spacing: Tokens.Spacing.xs) {
            Image(systemName: tab.systemImage).font(.caption2)
            Text(tab.title).font(.caption).lineLimit(1)
            Button { env.dock.close(tab.id) } label: {
                Image(systemName: "xmark").font(.caption2)
            }
            .buttonStyle(.plain)
        }
        .padding(.horizontal, Tokens.Spacing.sm)
        .padding(.vertical, Tokens.Spacing.xs)
        .background(selected ? AnyShapeStyle(.tint.opacity(0.2)) : AnyShapeStyle(.quaternary),
                    in: RoundedRectangle(cornerRadius: Tokens.Radius.sm))
        .contentShape(Rectangle())
        .onTapGesture { env.dock.selectedTab = tab.id }
        .onMiddleClick { env.dock.close(tab.id) }
    }

    @ViewBuilder
    private var content: some View {
        if let id = env.dock.selectedTab, let tab = env.dock.tabs.first(where: { $0.id == id }) {
            switch tab.content {
            case .terminal(let spec):
                TerminalView(spec: spec).id(tab.id)
            case .logs(let spec):
                LogView(spec: spec).id(tab.id)
            case .yamlEditor(let spec):
                YAMLEditorPanel(spec: spec, tabID: tab.id).id(tab.id)
            }
        } else {
            ZStack {
                Color(nsColor: .textBackgroundColor)
                Text("No dock tabs open. Open a terminal, pod shell, or logs from a resource.")
                    .font(.callout).foregroundStyle(.secondary)
            }
        }
    }
}
