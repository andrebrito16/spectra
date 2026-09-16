import AppKit
import Foundation
import SwiftUI
import SwiftData

@main
struct ResourceFeatureChecks {
    static func main() throws {
        try discoveryAndNavigation()
        try gatewayStatus()
        try routeStatus()
        try argoResources()
        try loadingStates()
        try clusterAppearance()
        print("Resource feature checks passed: discovery, navigation, Gateway status, Argo resources, templates, loading, and cluster appearance.")
    }

    struct CheckFailed: Error { let message: String }

    static func check(_ condition: @autoclosure () -> Bool, _ message: String) throws {
        if !condition() { throw CheckFailed(message: message) }
    }

    static func decode<T: Decodable>(_ type: T.Type, _ json: String) throws -> T {
        try JSONDecoder().decode(type, from: Data(json.utf8))
    }

    static func discoveryAndNavigation() throws {
        let group = try decode(APIGroupEntry.self, #"""
        {"name":"gateway.networking.k8s.io",
         "preferredVersion":{"groupVersion":"gateway.networking.k8s.io/v1","version":"v1"},
         "versions":[{"groupVersion":"gateway.networking.k8s.io/v1beta1","version":"v1beta1"},
                     {"groupVersion":"gateway.networking.k8s.io/v1","version":"v1"},
                     {"groupVersion":"gateway.networking.k8s.io/v1alpha2","version":"v1alpha2"}]}
        """#)
        try check(group.orderedVersions.map(\.version) == ["v1", "v1beta1", "v1alpha2"], "Preferred version must be queried first, once")
        let stable = try decode(APIResourceList.self, #"""
        {"groupVersion":"gateway.networking.k8s.io/v1","resources":[
            {"name":"gateways","kind":"Gateway","namespaced":true,"verbs":["get","list","watch"]},
            {"name":"gateways/status","kind":"Gateway","namespaced":true},
            {"name":"gatewayclasses","kind":"GatewayClass","namespaced":false},
            {"name":"httproutes","kind":"HTTPRoute","namespaced":true}]}
        """#)
        let beta = try decode(APIResourceList.self, #"""
        {"groupVersion":"gateway.networking.k8s.io/v1beta1","resources":[
            {"name":"gateways","kind":"Gateway","namespaced":true},
            {"name":"referencegrants","kind":"ReferenceGrant","namespaced":true}]}
        """#)
        let alpha = try decode(APIResourceList.self, #"""
        {"groupVersion":"gateway.networking.k8s.io/v1alpha2","resources":[
            {"name":"tcproutes","kind":"TCPRoute","namespaced":true}]}
        """#)
        let discovered = APIResourceList.preferredResources(from: [stable, beta, alpha])
        try check(discovered.count == 5, "Keep resources in non-preferred versions, skipping duplicates and subresources")
        let gateway = discovered.first { $0.kind == "Gateway" }!
        try check(gateway.version == "v1", "Prefer stable Gateway")
        try check(gateway.collectionPath(namespace: "team") == "/apis/gateway.networking.k8s.io/v1/namespaces/team/gateways", "Gateway uses its own API endpoint")
        let gatewayClass = discovered.first { $0.kind == "GatewayClass" }!
        try check(gatewayClass.collectionPath(namespace: "team") == "/apis/gateway.networking.k8s.io/v1/gatewayclasses", "GatewayClass remains cluster scoped")
        try check(discovered.first { $0.kind == "ReferenceGrant" }?.version == "v1beta1", "Find beta ReferenceGrants")
        try check(discovered.first { $0.kind == "TCPRoute" }?.version == "v1alpha2", "Find alpha TCPRoutes")
        try check(APIResourceList.preferredResources(from: [beta]).first?.version == "v1beta1", "Fall back when preferred discovery fails")

        let argoKinds = ["Application", "ApplicationSet", "AppProject", "Rollout", "AnalysisRun", "AnalysisTemplate", "ClusterAnalysisTemplate", "Experiment"]
        let argo = argoKinds.map {
            GroupVersionResource(group: "argoproj.io", version: "v1alpha1", resource: $0.lowercased() + "s",
                                 kind: $0, namespaced: $0 != "ClusterAnalysisTemplate")
        }
        let unrelated = GroupVersionResource(group: "networking.istio.io", version: "v1", resource: "gateways", kind: "Gateway", namespaced: true)
        let unrelatedApp = GroupVersionResource(group: "example.com", version: "v1", resource: "applications", kind: "Application", namespaced: true)
        var duplicateGateway = gateway
        duplicateGateway.version = "v1beta1"
        let sections = NavGrouping.build(from: discovered + argo + [unrelated, unrelatedApp, duplicateGateway])
        let network = sections.first { $0.section == .network }!
        try check(network.entries.filter { $0.kind == "Gateway" }.map(\.id) == [gateway.id], "Only the Gateway API kind belongs in Network, once")
        try check(network.entries.contains { $0.title == "Gateway Classes" }, "Use readable menu labels")
        try check(sections.first { $0.section == .argoCD }?.entries.map(\.kind) == argoKinds, "Argo CD contains applications, rollouts, and analysis resources")
        let custom = sections.first { $0.section == .customResources }!
        try check(Set(custom.subgroups.flatMap(\.entries).map(\.id)) == [unrelated.id, unrelatedApp.id], "Unrelated custom kinds keep their own group")
        try check(NavGrouping.build(from: []).isEmpty, "Do not advertise uninstalled resources")
        var unlistable = gateway
        unlistable.verbs = ["get"]
        try check(NavGrouping.build(from: [unlistable]).isEmpty, "Do not advertise resources without a list verb")
        for entry in sections.flatMap(\.entries) {
            try check(NSImage(systemSymbolName: entry.icon, accessibilityDescription: nil) != nil, "Missing SF Symbol: \(entry.icon)")
        }
        try check(CreateTemplates.template(for: gateway).hasPrefix("apiVersion: gateway.networking.k8s.io/v1\n"), "Gateway create skeleton uses the discovered version")
        try check(!CreateTemplates.template(for: gatewayClass).contains("namespace:"), "Cluster-scoped create skeleton omits namespace")
    }

    static func gatewayStatus() throws {
        var gateway = try decode(KubeResource.self, #"""
        {"apiVersion":"gateway.networking.k8s.io/v1","kind":"Gateway",
         "metadata":{"name":"public","namespace":"team","generation":2},
         "spec":{"gatewayClassName":"gke-l7-global-external-managed","listeners":[{"name":"https","protocol":"HTTPS","port":443}]},
         "status":{"addresses":[{"type":"IPAddress","value":"192.0.2.1"},{"type":"Hostname","value":"example.test"}],
                   "conditions":[{"type":"Programmed","status":"True","observedGeneration":2}]}}
        """#)
        try check(gateway.gatewayAddresses == ["192.0.2.1", "example.test"], "Show both IP and hostname addresses")
        try check(gateway.gatewayListenersSummary == "HTTPS:443", "Show listener protocol and port")
        try check(gateway.gatewayCondition("Programmed") == "True", "Current programmed status")
        try check(gateway.gatewayCondition("Accepted") == "Unknown", "Missing status is unknown")
        try check(gateway.apiGroup == "gateway.networking.k8s.io", "Identify resources by API group")
        var body = gateway.json.objectValue!
        body["metadata"] = .object(["generation": .int(3)])
        gateway.json = .object(body)
        try check(gateway.gatewayCondition("Programmed") == "Pending", "An older observed generation must not appear ready")
        let unobserved: [JSONValue] = [.object(["type": .string("Accepted"), "status": .string("True")])]
        try check(gateway.gatewayCondition("Accepted", in: unobserved) == "Unknown", "Missing observed generation is not confirmed ready")
        let empty = KubeResource(json: .object([:]))
        try check(empty.gatewayCondition("Programmed") == "Unknown" && empty.gatewayAddresses.isEmpty, "Pending gateways render without inventing addresses or readiness")
    }

    static func routeStatus() throws {
        var route = try decode(KubeResource.self, #"""
        {"metadata":{"namespace":"team","generation":1},
         "spec":{"parentRefs":[{"name":"public"},{"name":"internal","namespace":"infra"}],
                 "rules":[{"backendRefs":[{"name":"web","port":8080},{"name":"api","namespace":"backend","port":80}]}]},
         "status":{"parents":[
            {"parentRef":{"name":"public"},"conditions":[{"type":"Accepted","status":"True","observedGeneration":1}]},
            {"parentRef":{"name":"internal","namespace":"infra"},"conditions":[{"type":"Accepted","status":"False","observedGeneration":1}]}]}}
        """#)
        try check(route.gatewayRouteCondition("Accepted") == "False", "One rejected parent must not be hidden by another accepted parent")
        try check(route.gatewayRouteCondition("ResolvedRefs") == "Unknown", "Conditions absent from parent status are unknown")
        try check(route.gatewayParentRefsSummary == "Gateway team/public, Gateway infra/internal", "Respect parent namespace defaults and overrides")
        try check(route.gatewayBackendsSummary == "Service team/web:8080, Service backend/api:80", "Resolve backend namespaces and ports")
        var body = route.json.objectValue!
        body["status"] = .object(["parents": .array([route.gatewayRouteParents[0]])])
        route.json = .object(body)
        try check(route.gatewayRouteCondition("Accepted") == "Unknown", "An unreported parent makes attachment incomplete")
        body["spec"] = .object(["parentRefs": .array([.object(["name": .string("public")])])])
        route.json = .object(body)
        try check(route.gatewayRouteCondition("Accepted") == "True", "A current accepted parent is reported correctly")
    }

    static func argoResources() throws {
        let application = try decode(KubeResource.self, #"""
        {"apiVersion":"argoproj.io/v1alpha1","kind":"Application",
         "spec":{"source":{"repoURL":"ignored"},"sources":[{"repoURL":"https://example.test/app.git","targetRevision":"main"},
                  {"repoURL":"https://example.test/charts","targetRevision":"1.2.3"}],"destination":{"name":"production","namespace":"web"}},
         "status":{"sync":{"status":"OutOfSync"},"health":{"status":"Degraded"}}}
        """#)
        try check(application.argoRepositories == "https://example.test/app.git, https://example.test/charts", "Multi-source Applications take precedence over source")
        try check(application.argoTargetRevisions == "main, 1.2.3", "Show all target revisions")
        try check(application.argoDestination == "production", "Support named cluster destinations")
        try check(application.argoSyncStatus == "OutOfSync" && application.argoHealthStatus == "Degraded", "Keep sync and health independent")
        let single = try decode(KubeResource.self, #"{"spec":{"source":{"repoURL":"https://example.test/one.git"},"destination":{"server":"https://kubernetes.default.svc"}}}"#)
        try check(single.argoRepositories == "https://example.test/one.git", "Support single-source Applications")
        try check(single.argoDestination == "https://kubernetes.default.svc", "Support server destinations")
        let rollout = try decode(KubeResource.self, #"{"spec":{"strategy":{"canary":{}},"replicas":0},"status":{"phase":"Healthy"}}"#)
        try check(rollout.argoRolloutStrategy == "Canary" && rollout.argoRolloutReplicas == "0/0", "Preserve scaled-to-zero rollouts")
        let blueGreen = try decode(KubeResource.self, #"{"spec":{"strategy":{"blueGreen":{}},"paused":true}}"#)
        try check(blueGreen.argoRolloutStrategy == "Blue/Green" && blueGreen.argoRolloutPhase == "Paused", "Recognize blue/green and paused rollouts")
        try check(blueGreen.argoRolloutReplicas == "0/1", "Honor the default desired replica count")
        let empty = KubeResource(json: .object([:]))
        try check(empty.argoHealthStatus == "Unknown" && empty.argoRolloutPhase == "Unknown", "Missing status is not healthy")
    }

    static func loadingStates() throws {
        var state = ResourceLoadState()
        try check(state.isLoading, "A new tab must show loading before its informer starts")
        state.reset(scopes: ["fast", "slow"])
        state.setLoading(true, scope: "fast")
        state.setLoading(true, scope: "slow")
        state.complete(scope: "fast")
        state.setLoading(false, scope: "fast")
        try check(state.isLoading, "One namespace completing must not hide loading for another")
        state.complete(scope: "slow")
        try check(!state.isLoading, "An empty result is final only once every namespace completes")
        state.setLoading(true, scope: "slow")
        try check(state.isLoading, "Relists show loading")
        state.complete(scope: "slow")
        try check(!state.isLoading, "Errors settle loading so the error state can appear")
        state.reset(scopes: [nil])
        state.setLoading(false, scope: nil)
        try check(state.isLoading, "A loading callback cannot finish the first request before its result is published")
        state.complete(scope: nil)
        try check(!state.isLoading, "A warm tab remains settled without another request")
    }

    static func clusterAppearance() throws {
        try check(Color(hex: "#5B4FE9")?.rgbHex == "#5B4FE9", "Custom colors round-trip in sRGB")
        try check(Color(hex: "invalid") == nil && Color(hex: nil) == nil, "Invalid saved colors fall back safely")
        for preset in ClusterStyle.gradients {
            try check(Color(hex: preset.start) != nil && Color(hex: preset.end) != nil, "Gradient presets use valid colors")
        }
        let container = try ModelContainer(for: ClusterRecord.self,
                                          configurations: ModelConfiguration(isStoredInMemoryOnly: true))
        let context = ModelContext(container)
        let record = ClusterRecord(id: "appearance-test", kubeconfigPath: "/test/config", contextName: "test")
        try check(record.gradientEndColorHex == nil && record.gradientAngle == nil, "Existing solid-color defaults stay optional")
        record.iconColorHex = "#5B4FE9"
        record.gradientEndColorHex = "#28C6B7"
        record.gradientAngle = 35
        context.insert(record)
        try context.save()
        let reopened = ModelContext(container)
        let saved = try reopened.fetch(FetchDescriptor<ClusterRecord>()).first!
        try check(saved.iconColorHex == "#5B4FE9" && saved.gradientEndColorHex == "#28C6B7" && saved.gradientAngle == 35,
                  "Persist both gradient colors and direction per cluster")
        saved.gradientEndColorHex = nil
        saved.gradientAngle = nil
        try reopened.save()
        try check(saved.customColor?.rgbHex == "#5B4FE9" && saved.gradientEndColor == nil, "Switching back to a solid color keeps the primary color")
    }
}
