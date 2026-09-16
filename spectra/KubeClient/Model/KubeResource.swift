//
//  KubeResource.swift
//  Spectra
//
//  The universal, JSON-backed resource model. Every list/detail view can render
//  it without bespoke types; typed facets (Pod, Deployment, …) are computed
//  wrappers layered on top. Mirrors Freelens's generic KubeObject.
//

import Foundation

nonisolated struct KubeResource: Codable, Sendable, Identifiable, Hashable {
    /// The full resource body.
    var json: JSONValue

    init(json: JSONValue) {
        self.json = json
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.singleValueContainer()
        json = try container.decode(JSONValue.self)
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.singleValueContainer()
        try container.encode(json)
    }

    // MARK: - Top-level accessors

    var apiVersion: String? { json["apiVersion"]?.stringValue }
    var apiGroup: String? {
        guard let apiVersion else { return nil }
        return apiVersion.firstIndex(of: "/").map { String(apiVersion[..<$0]) } ?? ""
    }
    var kind: String? { json["kind"]?.stringValue }
    var metadata: JSONValue? { json["metadata"] }
    var spec: JSONValue? { json["spec"] }
    var status: JSONValue? { json["status"] }

    // MARK: - Metadata accessors

    var name: String { metadata?["name"]?.stringValue ?? "" }
    var namespace: String? { metadata?["namespace"]?.stringValue }
    var uid: String? { metadata?["uid"]?.stringValue }
    var resourceVersion: String? { metadata?["resourceVersion"]?.stringValue }
    var generation: Int? { metadata?["generation"]?.intValue }
    var creationTimestamp: String? { metadata?["creationTimestamp"]?.stringValue }
    var deletionTimestamp: String? { metadata?["deletionTimestamp"]?.stringValue }

    var labels: [String: String] {
        stringMap(metadata?["labels"])
    }

    var annotations: [String: String] {
        stringMap(metadata?["annotations"])
    }

    var finalizers: [String] {
        metadata?["finalizers"]?.arrayValue?.compactMap { $0.stringValue } ?? []
    }

    var ownerReferences: [OwnerReference] {
        metadata?["ownerReferences"]?.arrayValue?.compactMap(OwnerReference.init) ?? []
    }

    // MARK: - Identity & convenience

    /// Stable identity: uid if present, else namespaced name.
    var id: String { uid ?? scopedName }

    /// "namespace/name" or just "name" for cluster-scoped objects.
    var scopedName: String {
        if let namespace { return "\(namespace)/\(name)" }
        return name
    }

    var creationDate: Date? {
        creationTimestamp.flatMap(CredentialProvider.parseTimestamp)
    }

    func getLabel(_ key: String) -> String? { labels[key] }

    func value(at path: [String]) -> JSONValue? { json.value(at: path) }

    /// Free-text searchable representation for list filtering.
    var searchableText: String {
        var parts = [name, namespace ?? "", kind ?? ""]
        parts.append(contentsOf: labels.map { "\($0.key)=\($0.value)" })
        return parts.joined(separator: " ").lowercased()
    }

    private func stringMap(_ value: JSONValue?) -> [String: String] {
        guard let object = value?.objectValue else { return [:] }
        var result: [String: String] = [:]
        for (key, value) in object {
            if let s = value.stringValue { result[key] = s }
        }
        return result
    }
}

nonisolated struct OwnerReference: Sendable, Hashable {
    var apiVersion: String
    var kind: String
    var name: String
    var uid: String
    var controller: Bool

    init?(_ json: JSONValue) {
        guard let kind = json["kind"]?.stringValue,
              let name = json["name"]?.stringValue else { return nil }
        self.apiVersion = json["apiVersion"]?.stringValue ?? ""
        self.kind = kind
        self.name = name
        self.uid = json["uid"]?.stringValue ?? ""
        self.controller = json["controller"]?.boolValue ?? false
    }
}

extension Date {
    /// Compact Kubernetes-style age string (e.g. "5d", "3h", "12m", "8s").
    var k8sAge: String {
        let interval = max(0, Date().timeIntervalSince(self))
        let seconds = Int(interval)
        if seconds < 60 { return "\(seconds)s" }
        let minutes = seconds / 60
        if minutes < 60 { return "\(minutes)m" }
        let hours = minutes / 60
        if hours < 24 { return "\(hours)h" }
        let days = hours / 24
        if days < 365 { return "\(days)d" }
        return "\(days / 365)y"
    }
}
