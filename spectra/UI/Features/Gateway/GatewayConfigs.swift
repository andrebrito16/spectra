import SwiftUI

/// Gateway API is shared by GKE and other conforming controllers. Use the
/// discovered GVR and the resource's GatewayClass, with no provider allowlist.
@MainActor
enum GatewayConfigs {
    static func register(into catalog: ResourceCatalog) {
        catalog.register("Gateway", group: "gateway.networking.k8s.io", ResourceConfig(
            columns: [
                Columns.name, Columns.namespace(),
                ColumnDefinition(id: "class", title: "Class", width: 180) {
                    $0.spec?["gatewayClassName"]?.stringValue ?? "—"
                },
                ColumnDefinition(id: "addresses", title: "Addresses", width: 220) {
                    $0.gatewayAddresses.isEmpty ? "—" : $0.gatewayAddresses.joined(separator: ", ")
                },
                ColumnDefinition(id: "listeners", title: "Listeners", width: 180) { $0.gatewayListenersSummary },
                conditionColumn("Accepted"), conditionColumn("Programmed"), Columns.age,
            ],
            detailSections: [DetailSectionDef(id: "gateway", title: "Gateway") { resource, _ in
                AnyView(GatewaySection(resource: resource))
            }]))

        catalog.register("GatewayClass", group: "gateway.networking.k8s.io", ResourceConfig(columns: [
            Columns.name,
            ColumnDefinition(id: "controller", title: "Controller", width: 300) {
                $0.spec?["controllerName"]?.stringValue ?? "—"
            },
            ColumnDefinition(id: "description", title: "Description", width: 240) {
                $0.spec?["description"]?.stringValue ?? "—"
            },
            conditionColumn("Accepted"), Columns.age,
        ]))

        for kind in ["HTTPRoute", "GRPCRoute", "TLSRoute", "TCPRoute", "UDPRoute"] {
            var columns = [Columns.name, Columns.namespace(),
                           ColumnDefinition(id: "parents", title: "Parents", width: 220) { $0.gatewayParentRefsSummary }]
            if ["HTTPRoute", "GRPCRoute", "TLSRoute"].contains(kind) {
                columns.append(ColumnDefinition(id: "hostnames", title: "Hostnames", width: 220) {
                    let hosts = ($0.spec?["hostnames"]?.arrayValue ?? []).compactMap(\.stringValue)
                    return hosts.isEmpty ? "*" : hosts.joined(separator: ", ")
                })
            }
            columns.append(ColumnDefinition(id: "backends", title: "Backends", width: 240) { $0.gatewayBackendsSummary })
            columns += [conditionColumn("Accepted", route: true), conditionColumn("ResolvedRefs", route: true), Columns.age]
            catalog.register(kind, group: "gateway.networking.k8s.io", ResourceConfig(
                columns: columns,
                detailSections: [DetailSectionDef(id: "route", title: "Route") { resource, _ in
                    AnyView(GatewayRouteSection(resource: resource))
                }]))
        }

        catalog.register("ReferenceGrant", group: "gateway.networking.k8s.io", ResourceConfig(columns: [
            Columns.name, Columns.namespace(),
            ColumnDefinition(id: "from", title: "From", width: 260) {
                ($0.spec?["from"]?.arrayValue ?? []).map {
                    "\($0["namespace"]?.stringValue ?? "?") / \($0["kind"]?.stringValue ?? "?")"
                }.joined(separator: ", ")
            },
            ColumnDefinition(id: "to", title: "To", width: 260) {
                ($0.spec?["to"]?.arrayValue ?? []).map {
                    "\($0["kind"]?.stringValue ?? "?") / \($0["name"]?.stringValue ?? "*")"
                }.joined(separator: ", ")
            },
            Columns.age,
        ]))
    }

    private static func conditionColumn(_ type: String, route: Bool = false) -> ColumnDefinition {
        let value: (KubeResource) -> String = {
            route ? $0.gatewayRouteCondition(type) : $0.gatewayCondition(type)
        }
        return ColumnDefinition(id: type.lowercased(), title: type == "ResolvedRefs" ? "Resolved Refs" : type,
                                width: 110, status: {
            switch value($0) {
            case "True": return .success
            case "False": return .warning
            case "Pending": return .info
            default: return .neutral
            }
        }, value: value)
    }
}

private struct GatewaySection: View {
    let resource: KubeResource

    var body: some View {
        DetailCard(title: "Gateway") {
            DetailRow(label: "Class", value: resource.spec?["gatewayClassName"]?.stringValue ?? "—")
            DetailRow(label: "Addresses", value: resource.gatewayAddresses.isEmpty ? "—" : resource.gatewayAddresses.joined(separator: ", "))
            ForEach(Array(resource.gatewayListeners.enumerated()), id: \.offset) { _, listener in
                VStack(alignment: .leading, spacing: Tokens.Spacing.xs) {
                    Text(listener["name"]?.stringValue ?? "Listener").font(.callout.weight(.medium))
                    DetailRow(label: "Protocol / Port", value: "\(listener["protocol"]?.stringValue ?? "?") / \(listener["port"]?.stringValue ?? "?")")
                    DetailRow(label: "Hostname", value: listener["hostname"]?.stringValue ?? "*")
                    if let mode = listener["tls"]?["mode"]?.stringValue {
                        DetailRow(label: "TLS mode", value: mode)
                    }
                    ForEach(Array((listener["tls"]?["certificateRefs"]?.arrayValue ?? []).enumerated()), id: \.offset) { _, ref in
                        DetailRow(label: "Certificate", value: resource.gatewayReference(ref, defaultKind: "Secret"))
                    }
                    if let status = (resource.status?["listeners"]?.arrayValue ?? []).first(where: {
                        $0["name"]?.stringValue == listener["name"]?.stringValue
                    }) {
                        DetailRow(label: "Attached routes", value: status["attachedRoutes"]?.stringValue ?? "0")
                        GatewayConditionsDetail(conditions: status["conditions"]?.arrayValue ?? [])
                    }
                }
            }
        }
    }
}

private struct GatewayRouteSection: View {
    let resource: KubeResource

    var body: some View {
        DetailCard(title: "Route") {
            DetailRow(label: "Parents", value: resource.gatewayParentRefsSummary)
            DetailRow(label: "Backends", value: resource.gatewayBackendsSummary)
            ForEach(Array(resource.gatewayRouteParents.enumerated()), id: \.offset) { _, parent in
                VStack(alignment: .leading, spacing: Tokens.Spacing.xs) {
                    Text(resource.gatewayReference(parent["parentRef"] ?? .object([:]), defaultKind: "Gateway"))
                        .font(.callout.weight(.medium))
                    DetailRow(label: "Controller", value: parent["controllerName"]?.stringValue ?? "—")
                    GatewayConditionsDetail(conditions: parent["conditions"]?.arrayValue ?? [])
                }
            }
        }
    }
}

private struct GatewayConditionsDetail: View {
    let conditions: [JSONValue]

    var body: some View {
        ForEach(Array(conditions.enumerated()), id: \.offset) { _, condition in
            DetailRow(label: condition["type"]?.stringValue ?? "Condition",
                      value: "\(condition["status"]?.stringValue ?? "Unknown") · \(condition["reason"]?.stringValue ?? "")")
            if let message = condition["message"]?.stringValue, !message.isEmpty {
                Text(message).font(.caption).foregroundStyle(.secondary).textSelection(.enabled)
            }
        }
    }
}
