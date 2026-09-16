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
            result.append(contentsOf: APIResourceList.preferredResources(from: [core]))
        }

        // Named groups (/apis)
        let groupsRequest = try await client.connection.makeRequest(path: "/apis")
        let groupList = try await client.performDecodable(groupsRequest, as: APIGroupList.self)
        for group in groupList.groups {
            // A group's preferred version need not serve every resource. For
            // example, Gateway can be v1 while ReferenceGrant is v1beta1 and
            // TCPRoute is v1alpha2. Keep the first served version per resource,
            // preferring the server's preferred version when it is available.
            var lists: [APIResourceList] = []
            for version in group.orderedVersions {
                guard let list = try? await resourceList(path: "/apis/\(version.groupVersion)") else { continue }
                lists.append(list)
            }
            result.append(contentsOf: APIResourceList.preferredResources(from: lists))
        }
        return result
    }

    private func resourceList(path: String) async throws -> APIResourceList {
        let request = try await client.connection.makeRequest(path: path)
        return try await client.performDecodable(request, as: APIResourceList.self)
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
