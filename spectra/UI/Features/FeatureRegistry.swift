//
//  FeatureRegistry.swift
//  Spectra
//
//  One-time registration of all per-kind resource configs into the shared
//  ResourceCatalog. Feature phases (6–8) add their registrations here.
//

import Foundation

@MainActor
enum FeatureRegistry {
    private static var didRegister = false

    static func registerAll() {
        guard !didRegister else { return }
        didRegister = true
        let catalog = ResourceCatalog.shared
        WorkloadConfigs.register(into: catalog)
        ConfigNetworkStorageConfigs.register(into: catalog)
        ClusterScopeConfigs.register(into: catalog)
        ArgoCDConfigs.register(into: catalog)
        GatewayConfigs.register(into: catalog)
    }
}
