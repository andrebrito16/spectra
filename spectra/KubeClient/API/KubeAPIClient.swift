//
//  KubeAPIClient.swift
//  Spectra
//
//  Generic, GVR-parameterized Kubernetes client bound to a ClusterConnection.
//  Provides list/get/CRUD/patch/subresource operations for ANY resource kind —
//  built-in or CRD — with no per-kind code. Mirrors Freelens's KubeApi.
//

import Foundation
import Yams

nonisolated enum PatchType: Sendable {
    case strategicMerge
    case merge
    case json
    case apply

    var contentType: String {
        switch self {
        case .strategicMerge: return "application/strategic-merge-patch+json"
        case .merge: return "application/merge-patch+json"
        case .json: return "application/json-patch+json"
        case .apply: return "application/apply-patch+yaml"
        }
    }
}

nonisolated enum DeletePropagation: String, Sendable {
    case foreground = "Foreground"
    case background = "Background"
    case orphan = "Orphan"
}

/// A decoded Kubernetes list response.
nonisolated struct KubeList: Sendable {
    var items: [KubeResource]
    var resourceVersion: String?
    var continueToken: String?
}

nonisolated struct KubeAPIClient: Sendable {
    let connection: ClusterConnection

    private static let encoder = JSONEncoder()
    private static let decoder = JSONDecoder()

    // MARK: - Read

    func list(_ gvr: GroupVersionResource, namespace: String? = nil,
              labelSelector: String? = nil, fieldSelector: String? = nil,
              limit: Int? = nil, continueToken: String? = nil) async throws -> KubeList {
        var query: [URLQueryItem] = []
        if let labelSelector { query.append(.init(name: "labelSelector", value: labelSelector)) }
        if let fieldSelector { query.append(.init(name: "fieldSelector", value: fieldSelector)) }
        if let limit { query.append(.init(name: "limit", value: String(limit))) }
        if let continueToken { query.append(.init(name: "continue", value: continueToken)) }

        let request = try await connection.makeRequest(
            path: gvr.collectionPath(namespace: namespace), queryItems: query)
        let value = try await performJSON(request)
        // List responses strip apiVersion/kind from each item (only the list
        // carries them). Backfill from the GVR so detail views, icons, and the
        // ResourceCatalog lookup by kind work for items that haven't been
        // watch-updated yet.
        let items = (value["items"]?.arrayValue ?? []).map { itemJSON -> KubeResource in
            var object = itemJSON.objectValue ?? [:]
            if object["apiVersion"] == nil { object["apiVersion"] = .string(gvr.groupVersion) }
            if object["kind"] == nil { object["kind"] = .string(gvr.kind) }
            return KubeResource(json: .object(object))
        }
        return KubeList(items: items,
                        resourceVersion: value["metadata"]?["resourceVersion"]?.stringValue,
                        continueToken: value["metadata"]?["continue"]?.stringValue)
    }

    func get(_ gvr: GroupVersionResource, namespace: String?, name: String) async throws -> KubeResource {
        let request = try await connection.makeRequest(
            path: gvr.objectPath(namespace: namespace, name: name))
        return KubeResource(json: try await performJSON(request))
    }

    // MARK: - Write

    func create(_ gvr: GroupVersionResource, namespace: String?,
                resource: KubeResource) async throws -> KubeResource {
        let body = try Self.encoder.encode(resource)
        let request = try await connection.makeRequest(
            path: gvr.collectionPath(namespace: namespace), method: "POST",
            body: body, contentType: "application/json")
        return KubeResource(json: try await performJSON(request))
    }

    func update(_ gvr: GroupVersionResource, namespace: String?, name: String,
                resource: KubeResource) async throws -> KubeResource {
        let body = try Self.encoder.encode(resource)
        let request = try await connection.makeRequest(
            path: gvr.objectPath(namespace: namespace, name: name), method: "PUT",
            body: body, contentType: "application/json")
        return KubeResource(json: try await performJSON(request))
    }

    func patch(_ gvr: GroupVersionResource, namespace: String?, name: String,
               data: Data, type: PatchType) async throws -> KubeResource {
        var query: [URLQueryItem] = []
        if type == .apply {
            query = [.init(name: "fieldManager", value: "spectra"),
                     .init(name: "force", value: "true")]
        }
        let request = try await connection.makeRequest(
            path: gvr.objectPath(namespace: namespace, name: name), method: "PATCH",
            queryItems: query, body: data, contentType: type.contentType)
        return KubeResource(json: try await performJSON(request))
    }

    @discardableResult
    func delete(_ gvr: GroupVersionResource, namespace: String?, name: String,
                propagation: DeletePropagation = .background,
                gracePeriodSeconds: Int? = nil) async throws -> KubeResource {
        var options: [String: JSONValue] = [
            "apiVersion": .string("v1"),
            "kind": .string("DeleteOptions"),
            "propagationPolicy": .string(propagation.rawValue),
        ]
        if let gracePeriodSeconds { options["gracePeriodSeconds"] = .int(gracePeriodSeconds) }
        let body = try Self.encoder.encode(JSONValue.object(options))
        let request = try await connection.makeRequest(
            path: gvr.objectPath(namespace: namespace, name: name), method: "DELETE",
            body: body, contentType: "application/json")
        return KubeResource(json: try await performJSON(request))
    }

    func deleteCollection(_ gvr: GroupVersionResource, namespace: String?,
                          labelSelector: String? = nil) async throws {
        var query: [URLQueryItem] = []
        if let labelSelector { query.append(.init(name: "labelSelector", value: labelSelector)) }
        let request = try await connection.makeRequest(
            path: gvr.collectionPath(namespace: namespace), method: "DELETE", queryItems: query)
        _ = try await performJSON(request)
    }

    // MARK: - Subresources

    func getScale(_ gvr: GroupVersionResource, namespace: String?, name: String) async throws -> KubeResource {
        let request = try await connection.makeRequest(
            path: gvr.subresourcePath(namespace: namespace, name: name, subresource: "scale"))
        return KubeResource(json: try await performJSON(request))
    }

    func updateScale(_ gvr: GroupVersionResource, namespace: String?, name: String,
                     replicas: Int) async throws -> KubeResource {
        let patch: [String: JSONValue] = ["spec": .object(["replicas": .int(replicas)])]
        let body = try Self.encoder.encode(JSONValue.object(patch))
        let request = try await connection.makeRequest(
            path: gvr.subresourcePath(namespace: namespace, name: name, subresource: "scale"),
            method: "PATCH", body: body, contentType: PatchType.merge.contentType)
        return KubeResource(json: try await performJSON(request))
    }

    /// Evict a pod via the eviction subresource (used by node drain).
    func evict(namespace: String, podName: String, gracePeriodSeconds: Int? = nil) async throws {
        var spec: [String: JSONValue] = [
            "apiVersion": .string("policy/v1"),
            "kind": .string("Eviction"),
            "metadata": .object(["name": .string(podName), "namespace": .string(namespace)]),
        ]
        if let gracePeriodSeconds {
            spec["deleteOptions"] = .object(["gracePeriodSeconds": .int(gracePeriodSeconds)])
        }
        let body = try Self.encoder.encode(JSONValue.object(spec))
        let path = "/api/v1/namespaces/\(namespace)/pods/\(podName)/eviction"
        let request = try await connection.makeRequest(
            path: path, method: "POST", body: body, contentType: "application/json")
        _ = try await performJSON(request)
    }

    // MARK: - Apply (YAML editor / templates)

    /// Server-side apply from YAML text. Resolves the target object path from the
    /// supplied GVR + parsed name/namespace.
    func apply(yaml: String, gvr: GroupVersionResource,
               namespace: String?, name: String) async throws -> KubeResource {
        let object = try Yams.load(yaml: yaml)
        let data = try JSONSerialization.data(withJSONObject: object as Any)
        return try await patch(gvr, namespace: namespace, name: name, data: data, type: .apply)
    }

    // MARK: - Raw JSON helpers

    /// Perform a request and decode the JSON body, mapping errors to KubeError.
    private func performJSON(_ request: URLRequest) async throws -> JSONValue {
        let (data, http) = try await connection.perform(request)
        guard (200..<300).contains(http.statusCode) else {
            throw KubeError.from(httpStatus: http.statusCode, data: data)
        }
        if data.isEmpty { return .object([:]) }
        do {
            return try Self.decoder.decode(JSONValue.self, from: data)
        } catch {
            throw KubeError.decoding("\(error)")
        }
    }

    /// Perform a request returning the decoded value as a typed Decodable.
    func performDecodable<T: Decodable>(_ request: URLRequest, as type: T.Type) async throws -> T {
        let (data, http) = try await connection.perform(request)
        guard (200..<300).contains(http.statusCode) else {
            throw KubeError.from(httpStatus: http.statusCode, data: data)
        }
        do {
            return try Self.decoder.decode(T.self, from: data)
        } catch {
            throw KubeError.decoding("\(error)")
        }
    }
}
