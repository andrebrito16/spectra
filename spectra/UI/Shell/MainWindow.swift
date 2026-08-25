//
//  MainWindow.swift
//  Spectra
//
//  The main IDE window: NavigationSplitView (Liquid Glass sidebar + content
//  routed by NavigationModel) with a resizable bottom dock, a status bar, the
//  notifications overlay, and the ⌘K command palette. Dock height persists.
//

import SwiftUI

struct MainWindow: View {
    @Environment(\.appEnv) private var env
    @AppStorage("dockHeight") private var dockHeight = Tokens.Dock.defaultHeight
    @State private var columnVisibility: NavigationSplitViewVisibility = .all

    var body: some View {
        @Bindable var navigation = env.navigation

        NavigationSplitView(columnVisibility: $columnVisibility) {
            SidebarView()
                .navigationSplitViewColumnWidth(
                    min: Tokens.Sidebar.minWidth,
                    ideal: Tokens.Sidebar.idealWidth,
                    max: Tokens.Sidebar.maxWidth)
        } detail: {
            contentRegion
        }
        .overlay { NotificationsOverlay() }
        .sheet(isPresented: $navigation.showCommandPalette) {
            CommandPalette()
        }
        .sheet(isPresented: $navigation.showAddCluster) {
            AddClusterView()
        }
        .sheet(isPresented: $navigation.showShortcuts) {
            KeyboardShortcutsView()
        }
    }

    private var contentRegion: some View {
        @Bindable var navigation = env.navigation
        return VStack(spacing: 0) {
            ContentTabBar()
            ZStack(alignment: .bottom) {
                ContentRouter()
                    .id(navigation.route)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)

                if navigation.dockOpen {
                    DockRegion(height: $dockHeight) { navigation.dockOpen = false }
                        .frame(height: dockHeight)
                        .transition(.move(edge: .bottom))
                }
            }
            StatusBarView()
        }
    }
}
