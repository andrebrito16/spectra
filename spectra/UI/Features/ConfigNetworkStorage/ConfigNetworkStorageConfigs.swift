//
//  ConfigNetworkStorageConfigs.swift
//  Spectra
//
//  Registers Config, Network, Storage, and Access Control (RBAC) kinds into the
//  ResourceCatalog: columns + detail sections. Cluster-scoped kinds omit the
//  namespace column automatically (the engine drops it based on the GVR flag).
//

import SwiftUI
import AppKit

@MainActor
enum ConfigNetworkStorageConfigs {
    static func register(into catalog: ResourceCatalog) {
        registerConfig(catalog)
        registerNetwork(catalog)
        registerStorage(catalog)
        registerRBAC(catalog)
    }

    private static func keysColumn(_ field: String) -> ColumnDefinition {
        ColumnDefinition(id: "keys", title: "Keys", width: 60, alignment: .trailing) {
            "\($0.json[field]?.objectValue?.count ?? 0)"
        }
    }

    // MARK: - Config

    private static func registerConfig(_ catalog: ResourceCatalog) {
        catalog.register("ConfigMap", ResourceConfig(
            columns: [Columns.name, Columns.namespace(), keysColumn("data"), Columns.age],
            detailSections: [section("configmap-data", "Data") { r, _ in
                AnyView(ConfigMapDataSection(resource: r))
            }]))

        catalog.register("Secret", ResourceConfig(
            columns: [
                Columns.name, Columns.namespace(),
                ColumnDefinition(id: "type", title: "Type", width: 200) {
                    $0.json["type"]?.stringValue ?? "Opaque"
                },
                keysColumn("data"), Columns.age,
            ],
            detailSections: [section("secret-data", "Data") { r, _ in
                AnyView(SecretDataSection(resource: r))
            }]))

        catalog.register("HorizontalPodAutoscaler", ResourceConfig(columns: [
            Columns.name, Columns.namespace(),
            ColumnDefinition(id: "min", title: "Min", width: 50, alignment: .trailing) {
                "\($0.spec?["minReplicas"]?.intValue ?? 0)"
            },
            ColumnDefinition(id: "max", title: "Max", width: 50, alignment: .trailing) {
                "\($0.spec?["maxReplicas"]?.intValue ?? 0)"
            },
            ColumnDefinition(id: "replicas", title: "Replicas", width: 70, alignment: .trailing) {
                "\($0.status?["currentReplicas"]?.intValue ?? 0)"
            },
            Columns.age,
        ]))

        catalog.register("ResourceQuota", ResourceConfig(columns: [
            Columns.name, Columns.namespace(), Columns.age,
        ]))
        catalog.register("LimitRange", ResourceConfig(columns: [
            Columns.name, Columns.namespace(), Columns.age,
        ]))
        catalog.register("PodDisruptionBudget", ResourceConfig(columns: [
            Columns.name, Columns.namespace(),
            ColumnDefinition(id: "min", title: "Min Available", width: 100) {
                $0.spec?["minAvailable"]?.stringValue ?? "—"
            },
            ColumnDefinition(id: "allowed", title: "Allowed Disruptions", width: 140, alignment: .trailing) {
                "\($0.status?["disruptionsAllowed"]?.intValue ?? 0)"
            },
            Columns.age,
        ]))
        catalog.register("PriorityClass", ResourceConfig(columns: [
            Columns.name,
            ColumnDefinition(id: "value", title: "Value", width: 100, alignment: .trailing) {
                "\($0.json["value"]?.intValue ?? 0)"
            },
            Columns.age,
        ]))
    }

    // MARK: - Network

    private static func registerNetwork(_ catalog: ResourceCatalog) {
        catalog.register("Service", ResourceConfig(
            columns: [
                Columns.name, Columns.namespace(),
                ColumnDefinition(id: "type", title: "Type", width: 110) { $0.serviceType ?? "ClusterIP" },
                ColumnDefinition(id: "clusterip", title: "Cluster IP", width: 130) { $0.clusterIP ?? "—" },
                ColumnDefinition(id: "ports", title: "Ports", width: 160) { $0.servicePortsSummary },
                Columns.age,
            ],
            detailSections: [section("service", "Service") { r, _ in
                AnyView(ServiceDetailSection(resource: r))
            }],
            actions: [DockActions.portForward]))

        catalog.register("Ingress", ResourceConfig(
            columns: [
                Columns.name, Columns.namespace(),
                ColumnDefinition(id: "class", title: "Class", width: 120) {
                    $0.spec?["ingressClassName"]?.stringValue ?? "—"
                },
                ColumnDefinition(id: "hosts", title: "Hosts", width: 200) {
                    ($0.spec?["rules"]?.arrayValue ?? []).compactMap { $0["host"]?.stringValue }
                        .joined(separator: ", ")
                },
                ColumnDefinition(id: "loadbalancers", title: "LoadBalancers", width: 240) {
                    let lbs = $0.ingressLoadBalancers
                    return lbs.isEmpty ? "—" : lbs.joined(separator: ", ")
                },
                Columns.age,
            ],
            detailSections: [section("ingress", "Rules") { r, _ in
                AnyView(IngressRulesSection(resource: r))
            }],
            actions: [copyLoadBalancerAction]))

        catalog.register("NetworkPolicy", ResourceConfig(columns: [
            Columns.name, Columns.namespace(), Columns.age,
        ]))
        catalog.register("Endpoints", ResourceConfig(columns: [
            Columns.name, Columns.namespace(), Columns.age,
        ]))
        catalog.register("EndpointSlice", ResourceConfig(columns: [
            Columns.name, Columns.namespace(),
            ColumnDefinition(id: "addrtype", title: "Address Type", width: 120) {
                $0.json["addressType"]?.stringValue ?? "—"
            },
            Columns.age,
        ]))
        catalog.register("IngressClass", ResourceConfig(columns: [
            Columns.name,
            ColumnDefinition(id: "controller", title: "Controller", width: 240) {
                $0.spec?["controller"]?.stringValue ?? "—"
            },
            Columns.age,
        ]))
    }

    // MARK: - Storage

    private static func registerStorage(_ catalog: ResourceCatalog) {
        catalog.register("PersistentVolumeClaim", ResourceConfig(columns: [
            Columns.name, Columns.namespace(),
            ColumnDefinition(id: "status", title: "Status", width: 90,
                             status: { $0.pvcPhase == "Bound" ? .success : .warning }) {
                $0.pvcPhase ?? "—"
            },
            ColumnDefinition(id: "capacity", title: "Capacity", width: 90, alignment: .trailing) {
                $0.pvcCapacity ?? "—"
            },
            ColumnDefinition(id: "sc", title: "Storage Class", width: 140) { $0.storageClassName ?? "—" },
            Columns.age,
        ]))

        catalog.register("PersistentVolume", ResourceConfig(columns: [
            Columns.name,
            ColumnDefinition(id: "capacity", title: "Capacity", width: 90, alignment: .trailing) {
                $0.spec?["capacity"]?["storage"]?.stringValue ?? "—"
            },
            ColumnDefinition(id: "status", title: "Status", width: 100) { $0.pvcPhase ?? "—" },
            ColumnDefinition(id: "claim", title: "Claim", width: 180) {
                $0.spec?["claimRef"]?["name"]?.stringValue ?? "—"
            },
            Columns.age,
        ]))

        catalog.register("StorageClass", ResourceConfig(columns: [
            Columns.name,
            ColumnDefinition(id: "provisioner", title: "Provisioner", width: 220) {
                $0.json["provisioner"]?.stringValue ?? "—"
            },
            ColumnDefinition(id: "reclaim", title: "Reclaim", width: 100) {
                $0.json["reclaimPolicy"]?.stringValue ?? "—"
            },
            Columns.age,
        ]))
    }

    // MARK: - RBAC

    private static func registerRBAC(_ catalog: ResourceCatalog) {
        catalog.register("ServiceAccount", ResourceConfig(columns: [
            Columns.name, Columns.namespace(), Columns.age,
        ]))

        let rulesSection = section("rbac-rules", "Rules") { r, _ in
            AnyView(RBACRulesSection(resource: r))
        }
        catalog.register("Role", ResourceConfig(
            columns: [Columns.name, Columns.namespace(), Columns.age],
            detailSections: [rulesSection]))
        catalog.register("ClusterRole", ResourceConfig(
            columns: [Columns.name, Columns.age], detailSections: [rulesSection]))

        let subjectsSection = section("rbac-subjects", "Binding") { r, _ in
            AnyView(RBACSubjectsSection(resource: r))
        }
        catalog.register("RoleBinding", ResourceConfig(
            columns: [Columns.name, Columns.namespace(), Columns.age],
            detailSections: [subjectsSection]))
        catalog.register("ClusterRoleBinding", ResourceConfig(
            columns: [Columns.name, Columns.age], detailSections: [subjectsSection]))
    }

    private static func section(_ id: String, _ title: String,
                                _ make: @escaping (KubeResource, ClusterSession) -> AnyView) -> DetailSectionDef {
        DetailSectionDef(id: id, title: title, makeView: make)
    }

    /// Right-click action on Ingress rows to copy the LoadBalancer hostname(s).
    private static let copyLoadBalancerAction = ObjectAction(
        id: "copy-loadbalancer", title: "Copy LoadBalancer", systemImage: "doc.on.doc",
        isAvailable: { !$0.ingressLoadBalancers.isEmpty },
        perform: { resource, _ in
            let value = resource.ingressLoadBalancers.joined(separator: "\n")
            NSPasteboard.general.clearContents()
            NSPasteboard.general.setString(value, forType: .string)
        })
}
