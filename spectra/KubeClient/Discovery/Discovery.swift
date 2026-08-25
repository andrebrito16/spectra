//
//  Discovery.swift
//  Spectra
//
//  API discovery: server version, the full GVR table (built-ins + CRDs),
//  namespaces, and RBAC self-checks. The GVR table drives dynamic navigation and
//  CRD support. Mirrors Freelens's request-api-resources + cluster detectors.
//

import Foundation

nonisolated struct ServerVersionInfo: Decodable, Sendable {
    var gitVersion: String?
    var major: String?
    var minor: String?
}

private nonisolated struct APIResourceList: Decodable {
    let groupVersion: String
    let resources: [APIResourceEntry]
}

private nonisolated struct APIResourceEntry: Decodable {
    let name: String
    let singularName: String?
    let namespaced: Bool
    let kind: String
    let verbs: [String]?
    let shortNames: [String]?
    let categories: [String]?
}

private nonisolated struct APIGroupList: Decodable {
    let groups: [APIGroupEntry]
}

private nonisolated struct APIGroupEntry: Decodable {
    let name: String
    let versions: [GroupVersionEntry]
    let preferredVersion: GroupVersionEntry?
}

private nonisolated struct GroupVersionEntry: Decodable {
    let groupVersion: String
    let version: String
}

private nonisolated struct SelfSubjectAccessReviewStatus: Decodable {
    let allowed: Bool
}

private nonisolated struct SelfSubjectAccessReviewResponse: Decodable {
    let status: SelfSubjectAccessReviewStatus?
}

actor Discovery {
    private let client: KubeAPIClient

    init(client: KubeAPIClient) {
        self.client = client
    }

    func serverVersion() async throws -> ServerVersionInfo {
        let request = try await client.connection.makeRequest(path: "version")
        return try await client.performDecodable(request, as: ServerVersionInfo.self)
    }

    /// Discover the full GVR table across the core group and all API groups.
    func discoverResources() async throws -> [GroupVersionResource] {
        var result: [GroupVersionResource] = []

        // Core group (/api/v1)
        if let core = try? await resourceList(path: "/api/v1") {
            result.append(contentsOf: gvrs(from: core, group: "", version: "v1"))
        }

        // Named groups (/apis)
        let groupsRequest = try await client.connection.makeRequest(path: "/apis")
        let groupList = try await client.performDecodable(groupsRequest, as: APIGroupList.self)
        for group in groupList.groups {
            guard let preferred = group.preferredVersion ?? group.versions.first else { continue }
            let path = "/apis/\(preferred.groupVersion)"
            guard let list = try? await resourceList(path: path) else { continue }
            result.append(contentsOf: gvrs(from: list, group: group.name, version: preferred.version))
        }
        return result
    }

    private func resourceList(path: String) async throws -> APIResourceList {
        let request = try await client.connection.makeRequest(path: path)
        return try await client.performDecodable(request, as: APIResourceList.self)
    }

    private func gvrs(from list: APIResourceList, group: String, version: String) -> [GroupVersionResource] {
        list.resources
            .filter { !$0.name.contains("/") }  // skip subresources
            .map { entry in
                GroupVersionResource(
                    group: group, version: version, resource: entry.name, kind: entry.kind,
                    namespaced: entry.namespaced,
                    singularName: entry.singularName ?? entry.kind.lowercased(),
                    shortNames: entry.shortNames ?? [],
                    verbs: entry.verbs ?? [],
                    categories: entry.categories ?? [])
            }
    }

    /// List namespaces; returns [] if forbidden (caller falls back to context ns).
    func listNamespaces() async throws -> [String] {
        let gvr = GroupVersionResource(group: "", version: "v1", resource: "namespaces",
                                       kind: "Namespace", namespaced: false)
        do {
            let list = try await client.list(gvr)
            return list.items.map(\.name).sorted()
        } catch KubeError.forbidden {
            return []
        }
    }

    /// SelfSubjectAccessReview — fail open (return true) if the review itself errors,
    /// so we don't hide the entire UI when RBAC introspection is unavailable.
    func canI(verb: String, group: String, resource: String, namespace: String? = nil) async -> Bool {
        var attributes: [String: JSONValue] = [
            "verb": .string(verb),
            "group": .string(group),
            "resource": .string(resource),
        ]
        if let namespace { attributes["namespace"] = .string(namespace) }
        let body: JSONValue = .object([
            "apiVersion": .string("authorization.k8s.io/v1"),
            "kind": .string("SelfSubjectAccessReview"),
            "spec": .object(["resourceAttributes": .object(attributes)]),
        ])
        do {
            let data = try JSONEncoder().encode(body)
            let request = try await client.connection.makeRequest(
                path: "/apis/authorization.k8s.io/v1/selfsubjectaccessreviews",
                method: "POST", body: data, contentType: "application/json")
            let response = try await client.performDecodable(
                request, as: SelfSubjectAccessReviewResponse.self)
            return response.status?.allowed ?? true
        } catch {
            return true
        }
    }
}
