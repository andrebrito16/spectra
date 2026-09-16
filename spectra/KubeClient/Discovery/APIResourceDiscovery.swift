import Foundation

nonisolated struct APIResourceList: Decodable {
    let groupVersion: String
    let resources: [APIResourceEntry]

    /// Lists arrive in preference order. A version can add resources missing
    /// from an earlier list without replacing an already discovered resource.
    static func preferredResources(from lists: [APIResourceList]) -> [GroupVersionResource] {
        var seen: Set<String> = []
        return lists.flatMap { list -> [GroupVersionResource] in
            let parts = list.groupVersion.split(separator: "/", maxSplits: 1).map(String.init)
            guard let version = parts.last else { return [] }
            let group = parts.count > 1 ? parts[0] : ""
            return list.resources.compactMap { entry in
                guard !entry.name.contains("/"), seen.insert("\(group)/\(entry.name)").inserted else { return nil }
                return GroupVersionResource(
                    group: group, version: version, resource: entry.name, kind: entry.kind,
                    namespaced: entry.namespaced,
                    singularName: entry.singularName ?? entry.kind.lowercased(),
                    shortNames: entry.shortNames ?? [], verbs: entry.verbs ?? [],
                    categories: entry.categories ?? [])
            }
        }
    }
}

nonisolated struct APIResourceEntry: Decodable {
    let name: String
    let singularName: String?
    let namespaced: Bool
    let kind: String
    let verbs: [String]?
    let shortNames: [String]?
    let categories: [String]?
}

nonisolated struct APIGroupList: Decodable {
    let groups: [APIGroupEntry]
}

nonisolated struct APIGroupEntry: Decodable {
    let name: String
    let versions: [GroupVersionEntry]
    let preferredVersion: GroupVersionEntry?

    var orderedVersions: [GroupVersionEntry] {
        let preferred = preferredVersion ?? versions.first
        return (preferred.map { [$0] } ?? []) + versions.filter { $0.version != preferred?.version }
    }
}

nonisolated struct GroupVersionEntry: Decodable {
    let groupVersion: String
    let version: String
}
