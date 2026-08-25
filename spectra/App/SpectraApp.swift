//
//  SpectraApp.swift
//  Spectra
//
//  App entry point. Builds the SwiftData container with the real Spectra schema,
//  injects the root AppEnvironment, and defines the main window + Settings scene.
//

import SwiftUI
import SwiftData

@main
struct SpectraApp: App {
    private let appEnvironment = AppEnvironment.shared
    let modelContainer: ModelContainer

    init() {
        let schema = Schema([
            ClusterRecord.self,
            ClusterOrg.self,
            Favorite.self,
            SavedPortForward.self,
            AppSettings.self,
        ])
        // App-owned store location + hardened open (migrates the legacy
        // `default.store`, retries transient open failures, quarantines an
        // unopenable store instead of crashing). See PersistenceStore.
        modelContainer = PersistenceStore.makeContainer(schema: schema)
    }

    var body: some Scene {
        WindowGroup {
            RootView(modelContext: modelContainer.mainContext)
                .environment(\.appEnv, appEnvironment)
        }
        .modelContainer(modelContainer)
        .defaultSize(width: 1440, height: 960)
        .windowResizability(.contentMinSize)
        .commands { SpectraCommands(env: appEnvironment) }

        Settings {
            SettingsView()
                .environment(\.appEnv, appEnvironment)
                .modelContainer(modelContainer)
        }
    }
}

/// Root view that applies the theme color scheme and bootstraps services once.
private struct RootView: View {
    @Environment(\.appEnv) private var env
    let modelContext: ModelContext
    @State private var didBootstrap = false

    var body: some View {
        MainWindow()
            .preferredColorScheme(env.theme.colorScheme)
            .frame(minWidth: 1000, minHeight: 720)
            .task {
                guard !didBootstrap else { return }
                didBootstrap = true
                env.bootstrap(modelContext: modelContext)
            }
    }
}
