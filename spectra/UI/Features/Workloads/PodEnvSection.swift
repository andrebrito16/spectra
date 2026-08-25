//
//  PodEnvSection.swift
//  Spectra
//
//  Pod detail "Environment" card. Handles both:
//    - explicit `env` entries (literal values, secretKeyRef, configMapKeyRef,
//      fieldRef, resourceFieldRef);
//    - `envFrom` entries that bulk-import all keys from a Secret or ConfigMap
//      (the common Helm pattern), expandable on demand.
//  Secret values are fetched and base64-decoded only when revealed; never logged.
//

import SwiftUI
import AppKit

struct PodEnvSection: View {
    let resource: KubeResource
    let session: ClusterSession

    private struct ContainerEnv: Identifiable {
        let id = UUID()
        let name: String
        let isInit: Bool
        let env: [JSONValue]
        let envFrom: [JSONValue]
    }

    private var containers: [ContainerEnv] {
        var result: [ContainerEnv] = []
        for container in resource.initContainers {
            let env = container["env"]?.arrayValue ?? []
            let envFrom = container["envFrom"]?.arrayValue ?? []
            if !env.isEmpty || !envFrom.isEmpty {
                result.append(ContainerEnv(name: container["name"]?.stringValue ?? "?",
                                           isInit: true, env: env, envFrom: envFrom))
            }
        }
        for container in resource.containers {
            let env = container["env"]?.arrayValue ?? []
            let envFrom = container["envFrom"]?.arrayValue ?? []
            if !env.isEmpty || !envFrom.isEmpty {
                result.append(ContainerEnv(name: container["name"]?.stringValue ?? "?",
                                           isInit: false, env: env, envFrom: envFrom))
            }
        }
        return result
    }

    var body: some View {
        if !containers.isEmpty {
            DetailCard(title: "Environment") {
                VStack(alignment: .leading, spacing: Tokens.Spacing.md) {
                    ForEach(containers) { container in
                        VStack(alignment: .leading, spacing: Tokens.Spacing.xs) {
                            HStack(spacing: Tokens.Spacing.xs) {
                                Text(container.name).font(.callout.weight(.medium))
                                if container.isInit {
                                    Text("init").font(.caption2).foregroundStyle(.secondary)
                                }
                            }
                            ForEach(Array(container.envFrom.enumerated()), id: \.offset) { _, entry in
                                EnvFromRow(entry: entry, pod: resource, session: session)
                            }
                            ForEach(Array(container.env.enumerated()), id: \.offset) { _, envVar in
                                EnvVarRow(envVar: envVar, pod: resource, session: session)
                            }
                        }
                    }
                }
            }
        }
    }
}

// MARK: - Explicit env entry

private struct EnvVarRow: View {
    let envVar: JSONValue
    let pod: KubeResource
    let session: ClusterSession

    @Environment(\.appEnv) private var env
    @State private var revealed: String?
    @State private var loading = false

    private var key: String { envVar["name"]?.stringValue ?? "?" }
    private var directValue: String? { envVar["value"]?.stringValue }
    private var secretRef: (name: String, key: String)? {
        guard let n = envVar["valueFrom"]?["secretKeyRef"]?["name"]?.stringValue,
              let k = envVar["valueFrom"]?["secretKeyRef"]?["key"]?.stringValue else { return nil }
        return (n, k)
    }
    private var configMapRef: (name: String, key: String)? {
        guard let n = envVar["valueFrom"]?["configMapKeyRef"]?["name"]?.stringValue,
              let k = envVar["valueFrom"]?["configMapKeyRef"]?["key"]?.stringValue else { return nil }
        return (n, k)
    }
    private var fieldRef: String? {
        envVar["valueFrom"]?["fieldRef"]?["fieldPath"]?.stringValue
    }
    private var resourceFieldRef: String? {
        envVar["valueFrom"]?["resourceFieldRef"]?["resource"]?.stringValue
    }

    var body: some View {
        HStack(alignment: .top, spacing: Tokens.Spacing.sm) {
            Text(key)
                .font(.system(.caption, design: .monospaced))
                .frame(minWidth: 140, alignment: .leading)
                .textSelection(.enabled)
            valueView.frame(maxWidth: .infinity, alignment: .leading)
        }
        .padding(.vertical, 1)
    }

    @ViewBuilder
    private var valueView: some View {
        if let value = directValue {
            Text(value).font(.system(.caption, design: .monospaced))
                .textSelection(.enabled).lineLimit(2)
        } else if let ref = secretRef {
            referenceRow(kind: "Secret", name: ref.name, refKey: ref.key, isSecret: true)
        } else if let ref = configMapRef {
            referenceRow(kind: "ConfigMap", name: ref.name, refKey: ref.key, isSecret: false)
        } else if let field = fieldRef {
            Text("from field: \(field)").font(.caption2).foregroundStyle(.secondary)
        } else if let res = resourceFieldRef {
            Text("from resource: \(res)").font(.caption2).foregroundStyle(.secondary)
        } else {
            Text("—").font(.caption2).foregroundStyle(.tertiary)
        }
    }

    @ViewBuilder
    private func referenceRow(kind: String, name: String, refKey: String, isSecret: Bool) -> some View {
        if let revealed {
            HStack(spacing: Tokens.Spacing.xs) {
                Text(revealed).font(.system(.caption, design: .monospaced))
                    .textSelection(.enabled).lineLimit(4)
                Spacer(minLength: 0)
                copyButton(revealed)
                Button { self.revealed = nil } label: { Image(systemName: "eye.slash").font(.caption2) }
                    .buttonStyle(.plain).foregroundStyle(.secondary).help("Hide")
            }
        } else {
            HStack(spacing: Tokens.Spacing.xs) {
                Text("\(kind) \(name) / \(refKey)").font(.caption)
                    .foregroundStyle(.secondary).lineLimit(1)
                if loading {
                    ProgressView().controlSize(.mini)
                } else {
                    Button { reveal(kind: kind, name: name, refKey: refKey, isSecret: isSecret) } label: {
                        Image(systemName: "eye").font(.caption2)
                    }
                    .buttonStyle(.plain).foregroundStyle(.secondary)
                    .help(isSecret ? "Reveal Secret value" : "Reveal ConfigMap value")
                }
            }
        }
    }

    private func reveal(kind: String, name: String, refKey: String, isSecret: Bool) {
        guard let namespace = pod.namespace,
              let gvr = session.gvr(forKind: kind) else { return }
        loading = true
        Task {
            defer { loading = false }
            do {
                let object = try await session.client.get(gvr, namespace: namespace, name: name)
                let raw = object.json["data"]?[refKey]?.stringValue
                if isSecret, let raw, let decoded = Data(base64Encoded: raw),
                   let text = String(data: decoded, encoding: .utf8) {
                    revealed = text
                } else {
                    revealed = raw ?? "<missing key \(refKey)>"
                }
            } catch {
                env.notifications.notify(.error, "\(kind) \(name)/\(refKey)",
                                         message: error.localizedDescription)
            }
        }
    }
}

// MARK: - envFrom (Secret/ConfigMap bulk import)

private struct EnvFromRow: View {
    let entry: JSONValue
    let pod: KubeResource
    let session: ClusterSession

    @Environment(\.appEnv) private var env
    @State private var expanded = false
    @State private var loading = false
    @State private var data: [String: String] = [:]   // key → raw value (base64 for secrets, plain for configmap)
    @State private var error: String?

    private var isSecret: Bool { entry["secretRef"] != nil }
    private var kind: String { isSecret ? "Secret" : "ConfigMap" }
    private var name: String? {
        entry["secretRef"]?["name"]?.stringValue
            ?? entry["configMapRef"]?["name"]?.stringValue
    }
    private var prefix: String? { entry["prefix"]?.stringValue }
    private var optional: Bool {
        entry["secretRef"]?["optional"]?.boolValue
            ?? entry["configMapRef"]?["optional"]?.boolValue ?? false
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            Button { toggleExpand() } label: {
                HStack(spacing: Tokens.Spacing.xs) {
                    Image(systemName: expanded ? "chevron.down" : "chevron.right")
                        .font(.caption2)
                    Text(headerText)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                    if loading { ProgressView().controlSize(.mini) }
                    Spacer(minLength: 0)
                }
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)

            if expanded {
                if let error {
                    Text(error).font(.caption2).foregroundStyle(.red)
                        .padding(.leading, Tokens.Spacing.md)
                } else if !loading && data.isEmpty {
                    Text("No keys")
                        .font(.caption2).foregroundStyle(.tertiary)
                        .padding(.leading, Tokens.Spacing.md)
                } else {
                    VStack(alignment: .leading, spacing: 1) {
                        ForEach(data.sorted(by: { $0.key < $1.key }), id: \.key) { k, v in
                            EnvFromKeyRow(key: (prefix ?? "") + k, raw: v, isSecret: isSecret)
                        }
                    }
                    .padding(.leading, Tokens.Spacing.md)
                }
            }
        }
    }

    private var headerText: String {
        let suffix = prefix.map { " (prefix: \($0))" } ?? ""
        return "From \(kind) \(name ?? "?")\(suffix)\(optional ? " (optional)" : "")"
    }

    private func toggleExpand() {
        expanded.toggle()
        if expanded && data.isEmpty && error == nil { load() }
    }

    private func load() {
        guard let name, let namespace = pod.namespace,
              let gvr = session.gvr(forKind: kind) else { return }
        loading = true
        Task {
            defer { loading = false }
            do {
                let object = try await session.client.get(gvr, namespace: namespace, name: name)
                var result: [String: String] = [:]
                for (k, v) in object.json["data"]?.objectValue ?? [:] {
                    result[k] = v.stringValue ?? ""
                }
                data = result
            } catch {
                self.error = error.localizedDescription
                if !optional {
                    env.notifications.notify(.warning, "\(kind) \(name)",
                                             message: error.localizedDescription)
                }
            }
        }
    }
}

private struct EnvFromKeyRow: View {
    let key: String
    let raw: String
    let isSecret: Bool
    @State private var revealed = false

    private var decoded: String {
        if let data = Data(base64Encoded: raw), let text = String(data: data, encoding: .utf8) {
            return text
        }
        return "<binary>"
    }

    private var displayValue: String {
        if !isSecret { return raw }
        return revealed ? decoded : String(repeating: "•", count: 12)
    }

    private var copyValue: String { isSecret ? decoded : raw }

    var body: some View {
        HStack(alignment: .top, spacing: Tokens.Spacing.sm) {
            Text(key)
                .font(.system(.caption, design: .monospaced))
                .frame(minWidth: 140, alignment: .leading)
                .textSelection(.enabled)
            Text(displayValue)
                .font(.system(.caption, design: .monospaced))
                .textSelection(.enabled)
                .lineLimit(3)
                .frame(maxWidth: .infinity, alignment: .leading)
            if isSecret {
                Button { revealed.toggle() } label: {
                    Image(systemName: revealed ? "eye.slash" : "eye").font(.caption2)
                }
                .buttonStyle(.plain).foregroundStyle(.secondary)
                .help(revealed ? "Hide" : "Reveal")
            }
            if !isSecret || revealed {
                copyButton(copyValue)
            }
        }
        .padding(.vertical, 1)
    }
}

// MARK: - shared

@ViewBuilder
private func copyButton(_ value: String) -> some View {
    Button {
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(value, forType: .string)
    } label: { Image(systemName: "doc.on.doc").font(.caption2) }
    .buttonStyle(.plain)
    .foregroundStyle(.secondary)
    .help("Copy")
}
