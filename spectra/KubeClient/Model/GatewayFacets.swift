import Foundation

extension KubeResource {
    var gatewayAddresses: [String] {
        (status?["addresses"]?.arrayValue ?? []).compactMap { $0["value"]?.stringValue }
    }

    var gatewayListeners: [JSONValue] { spec?["listeners"]?.arrayValue ?? [] }

    var gatewayListenersSummary: String {
        let listeners = gatewayListeners.map {
            "\($0["protocol"]?.stringValue ?? "?"):\($0["port"]?.stringValue ?? "?")"
        }
        return listeners.isEmpty ? "—" : listeners.joined(separator: ", ")
    }

    /// A controller's condition only describes the current spec when it has
    /// observed this generation. Never show an old True condition as ready.
    func gatewayCondition(_ type: String, in conditions: [JSONValue]? = nil) -> String {
        let conditions = conditions ?? status?["conditions"]?.arrayValue ?? []
        guard let condition = conditions.first(where: { $0["type"]?.stringValue == type }) else {
            return "Unknown"
        }
        if let generation {
            guard let observed = condition["observedGeneration"]?.intValue else { return "Unknown" }
            if observed < generation { return "Pending" }
        }
        return condition["status"]?.stringValue ?? "Unknown"
    }

    var gatewayRouteParents: [JSONValue] { status?["parents"]?.arrayValue ?? [] }

    /// Route conditions live per parent, not at status.conditions. A partial
    /// attachment must not be reported as accepted for every parent.
    func gatewayRouteCondition(_ type: String) -> String {
        guard !gatewayRouteParents.isEmpty else { return "Unknown" }
        var values = gatewayRouteParents.map {
            gatewayCondition(type, in: $0["conditions"]?.arrayValue ?? [])
        }
        let references = spec?["parentRefs"]?.arrayValue ?? []
        if references.contains(where: { reference in
            !gatewayRouteParents.contains { parent in
                guard let reported = parent["parentRef"] else { return false }
                return gatewayParentKey(reference) == gatewayParentKey(reported)
            }
        }) { values.append("Unknown") }
        if values.contains("False") { return "False" }
        if values.contains("Pending") { return "Pending" }
        return values.allSatisfy { $0 == "True" } ? "True" : "Unknown"
    }

    private func gatewayParentKey(_ reference: JSONValue) -> [String] {
        [reference["group"]?.stringValue ?? "gateway.networking.k8s.io",
         reference["kind"]?.stringValue ?? "Gateway",
         reference["namespace"]?.stringValue ?? namespace ?? "",
         reference["name"]?.stringValue ?? "",
         reference["sectionName"]?.stringValue ?? "",
         reference["port"]?.stringValue ?? ""]
    }

    func gatewayReference(_ reference: JSONValue, defaultKind: String) -> String {
        let kind = reference["kind"]?.stringValue ?? defaultKind
        let ns = reference["namespace"]?.stringValue ?? namespace
        let name = reference["name"]?.stringValue ?? "?"
        var label = "\(kind) \(ns.map { "\($0)/" } ?? "")\(name)"
        if let section = reference["sectionName"]?.stringValue { label += "#\(section)" }
        if let port = reference["port"]?.stringValue { label += ":\(port)" }
        return label
    }

    var gatewayParentRefsSummary: String {
        let parents = (spec?["parentRefs"]?.arrayValue ?? []).map {
            gatewayReference($0, defaultKind: "Gateway")
        }
        return parents.isEmpty ? "—" : parents.joined(separator: ", ")
    }

    var gatewayBackendsSummary: String {
        let backends = (spec?["rules"]?.arrayValue ?? []).flatMap {
            $0["backendRefs"]?.arrayValue ?? []
        }.map { gatewayReference($0, defaultKind: "Service") }
        return backends.isEmpty ? "—" : backends.joined(separator: ", ")
    }
}
