//
//  HelmModels.swift
//  Spectra
//
//  Decodable models for `helm ... --output json`.
//

import Foundation

nonisolated struct HelmRelease: Codable, Identifiable, Sendable {
    var name: String
    var namespace: String
    var revision: String
    var updated: String?
    var status: String
    var chart: String
    var appVersion: String?

    var id: String { "\(namespace)/\(name)" }

    enum CodingKeys: String, CodingKey {
        case name, namespace, revision, updated, status, chart
        case appVersion = "app_version"
    }
}

nonisolated struct HelmHistoryEntry: Codable, Identifiable, Sendable {
    var revision: Int
    var updated: String?
    var status: String
    var chart: String
    var appVersion: String?
    var description: String?

    var id: Int { revision }

    enum CodingKeys: String, CodingKey {
        case revision, updated, status, chart, description
        case appVersion = "app_version"
    }
}

nonisolated struct HelmRepo: Codable, Identifiable, Sendable {
    var name: String
    var url: String
    var id: String { name }
}

nonisolated struct HelmChartHit: Codable, Identifiable, Sendable {
    var name: String
    var version: String
    var appVersion: String?
    var description: String?

    var id: String { name }

    enum CodingKeys: String, CodingKey {
        case name, version, description
        case appVersion = "app_version"
    }
}

nonisolated enum HelmError: LocalizedError {
    case notInstalled
    case command(String)

    var errorDescription: String? {
        switch self {
        case .notInstalled: return "helm binary not found (set PATH in Preferences)"
        case .command(let message): return message
        }
    }
}
