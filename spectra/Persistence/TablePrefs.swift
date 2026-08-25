//
//  TablePrefs.swift
//  Spectra
//
//  Per-(cluster, table) view preferences — hidden columns and sort — persisted
//  in UserDefaults (~/Library/Preferences), so they survive app updates and
//  restarts. Keyed by cluster id + GVR id; written through on every change from
//  ResourceListView.
//

import Foundation

nonisolated struct TablePrefs: Codable, Equatable {
    var hiddenColumns: [String] = []
    var sortColumnID: String = "name"
    var ascending: Bool = true
}

nonisolated enum TablePrefsStore {
    private static func key(cluster: String, table: String) -> String {
        "tableprefs.\(cluster).\(table)"
    }

    static func load(cluster: String, table: String) -> TablePrefs? {
        guard let data = UserDefaults.standard.data(forKey: key(cluster: cluster, table: table))
        else { return nil }
        return try? JSONDecoder().decode(TablePrefs.self, from: data)
    }

    static func save(_ prefs: TablePrefs, cluster: String, table: String) {
        guard let data = try? JSONEncoder().encode(prefs) else { return }
        UserDefaults.standard.set(data, forKey: key(cluster: cluster, table: table))
    }
}
