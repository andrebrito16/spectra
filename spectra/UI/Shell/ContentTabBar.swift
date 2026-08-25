//
//  ContentTabBar.swift
//  Spectra
//
//  Tab strip above the content area. Each open view is a tab; click to switch,
//  ⌘W or the × to close. Sidebar navigation opens/selects tabs.
//

import SwiftUI

struct ContentTabBar: View {
    @Environment(\.appEnv) private var env

    var body: some View {
        let nav = env.navigation
        if !nav.tabs.isEmpty {
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 1) {
                    ForEach(nav.tabs) { tab in
                        TabChip(tab: tab,
                                isSelected: tab.id == nav.selectedTabID,
                                onSelect: { nav.selectTab(tab.id) },
                                onClose: { nav.closeTab(tab.id) })
                    }
                }
                .padding(.horizontal, Tokens.Spacing.xs)
            }
            .frame(height: 34)
            .background(.bar)
            .overlay(alignment: .bottom) { Divider() }
        }
    }
}

private struct TabChip: View {
    let tab: NavigationModel.Tab
    let isSelected: Bool
    let onSelect: () -> Void
    let onClose: () -> Void

    @State private var hovering = false

    var body: some View {
        HStack(spacing: Tokens.Spacing.xs) {
            Image(systemName: tab.systemImage)
                .font(.caption2)
                .foregroundStyle(isSelected ? .primary : .secondary)
            Text(tab.title)
                .font(.callout)
                .lineLimit(1)
                .foregroundStyle(isSelected ? .primary : .secondary)
            Button(action: onClose) {
                Image(systemName: "xmark")
                    .font(.system(size: 8, weight: .bold))
            }
            .buttonStyle(.plain)
            .opacity(hovering || isSelected ? 1 : 0)
            .accessibilityLabel("Close tab")
        }
        .padding(.horizontal, Tokens.Spacing.sm)
        .frame(height: 34)
        .background(isSelected ? AnyShapeStyle(.background) : AnyShapeStyle(.clear))
        .overlay(alignment: .bottom) {
            if isSelected {
                Rectangle().fill(.tint).frame(height: 2)
            }
        }
        .contentShape(Rectangle())
        .onTapGesture(perform: onSelect)
        .onMiddleClick(perform: onClose)
        .onHover { hovering = $0 }
        .frame(maxWidth: 200)
    }
}
