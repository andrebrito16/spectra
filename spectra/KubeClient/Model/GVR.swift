//
//  GVR.swift
//  Spectra
//
//  GroupVersionResource / GroupVersionKind descriptors. Built dynamically by the
//  discovery layer so API paths are never hardcoded — this is what powers CRDs
//  and the generic resource browser.
//

import Foundation

nonisolated struct GroupVersionResource: Sendable, Hashable, Identifiable, Codable {
    /// API group; empty string for the core group.
    var group: String
    var version: String
    /// Plural resource name (e.g. "pods").
    var resource: String
    var kind: String
    var namespaced: Bool
    var singularName: String
    var shortNames: [String]
    var verbs: [String]
    var categories: [String]

    init(group: String, version: String, resource: String, kind: String,
         namespaced: Bool, singularName: String = "", shortNames: [String] = [],
         verbs: [String] = [], categories: [String] = []) {
        self.group = group
        self.version = version
        self.resource = resource
        self.kind = kind
        self.namespaced = namespaced
        self.singularName = singularName
        self.shortNames = shortNames
        self.verbs = verbs
        self.categories = categories
    }

    /// Stable identity across a cluster (group/version/resource).
    var id: String { "\(group)/\(version)/\(resource)" }

    var groupVersion: String { group.isEmpty ? version : "\(group)/\(version)" }

    /// API base path prefix.
    var apiPrefix: String {
        group.isEmpty ? "/api/\(version)" : "/apis/\(group)/\(version)"
    }

    /// List/collection path for the given namespace (nil = all namespaces).
    func collectionPath(namespace: String?) -> String {
        if namespaced, let namespace, !namespace.isEmpty {
            return "\(apiPrefix)/namespaces/\(namespace)/\(resource)"
        }
        return "\(apiPrefix)/\(resource)"
    }

    /// Path to a single object.
    func objectPath(namespace: String?, name: String) -> String {
        if namespaced, let namespace, !namespace.isEmpty {
            return "\(apiPrefix)/namespaces/\(namespace)/\(resource)/\(name)"
        }
        return "\(apiPrefix)/\(resource)/\(name)"
    }

    func subresourcePath(namespace: String?, name: String, subresource: String) -> String {
        "\(objectPath(namespace: namespace, name: name))/\(subresource)"
    }

    func supports(verb: String) -> Bool {
        verbs.isEmpty || verbs.contains(verb)
    }
}

nonisolated struct GroupVersionKind: Sendable, Hashable {
    var group: String
    var version: String
    var kind: String

    var groupVersion: String { group.isEmpty ? version : "\(group)/\(version)" }
}
