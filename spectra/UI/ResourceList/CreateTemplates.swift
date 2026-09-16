//
//  CreateTemplates.swift
//  Spectra
//
//  Starter YAML templates for "create from template" (Phase 5.4). Mirrors
//  Freelens's resource-templates. Falls back to a minimal skeleton keyed by kind.
//

import Foundation

nonisolated enum CreateTemplates {
    static func template(for gvr: GroupVersionResource) -> String {
        var lines = template(forKind: gvr.kind).components(separatedBy: "\n")
        lines[0] = "apiVersion: \(gvr.groupVersion)"
        if !gvr.namespaced { lines.removeAll { $0 == "  namespace: default" } }
        return lines.joined(separator: "\n")
    }

    static func template(forKind kind: String) -> String {
        switch kind {
        case "Namespace":
            return """
            apiVersion: v1
            kind: Namespace
            metadata:
              name: my-namespace
            """
        case "ConfigMap":
            return """
            apiVersion: v1
            kind: ConfigMap
            metadata:
              name: my-config
              namespace: default
            data:
              key: value
            """
        case "Secret":
            return """
            apiVersion: v1
            kind: Secret
            metadata:
              name: my-secret
              namespace: default
            type: Opaque
            stringData:
              key: value
            """
        case "Service":
            return """
            apiVersion: v1
            kind: Service
            metadata:
              name: my-service
              namespace: default
            spec:
              selector:
                app: my-app
              ports:
                - port: 80
                  targetPort: 8080
            """
        case "Deployment":
            return """
            apiVersion: apps/v1
            kind: Deployment
            metadata:
              name: my-deployment
              namespace: default
            spec:
              replicas: 1
              selector:
                matchLabels:
                  app: my-app
              template:
                metadata:
                  labels:
                    app: my-app
                spec:
                  containers:
                    - name: app
                      image: nginx:latest
                      ports:
                        - containerPort: 80
            """
        default:
            return """
            apiVersion: v1
            kind: \(kind.isEmpty ? "Resource" : kind)
            metadata:
              name: my-\(kind.lowercased())
              namespace: default
            """
        }
    }
}
