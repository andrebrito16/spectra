//
//  ConfigDetailSections.swift
//  Spectra
//
//  Detail sections for Config/Network/Storage/RBAC kinds: ConfigMap data, Secret
//  data (base64 decode with reveal/hide — handled securely, never logged),
//  Service ports, Ingress rules, RBAC rules and subjects.
//

import SwiftUI
import AppKit

struct ConfigMapDataSection: View {
    let resource: KubeResource

    private var data: [String: String] {
        var result: [String: String] = [:]
        for (key, value) in resource.json["data"]?.objectValue ?? [:] {
            result[key] = value.stringValue
        }
        return result
    }

    var body: some View {
        DetailCard(title: "Data (\(data.count) keys)") {
            if data.isEmpty {
                Text("No data").font(.caption).foregroundStyle(.tertiary)
            } else {
                VStack(alignment: .leading, spacing: Tokens.Spacing.sm) {
                    ForEach(data.sorted(by: { $0.key < $1.key }), id: \.key) { key, value in
                        VStack(alignment: .leading, spacing: 2) {
                            HStack {
                                Text(key).font(.callout.weight(.medium))
                                Spacer()
                                CopyButton(value: value)
                            }
                            Text(value)
                                .font(.system(.caption, design: .monospaced))
                                .textSelection(.enabled)
                                .lineLimit(8)
                        }
                        .padding(Tokens.Spacing.sm)
                        .background(.quaternary.opacity(0.4),
                                    in: RoundedRectangle(cornerRadius: Tokens.Radius.sm))
                    }
                }
            }
        }
    }
}

/// Secret data: keys + base64 values. Values are hidden until explicitly
/// revealed and decoded; never logged.
struct SecretDataSection: View {
    let resource: KubeResource
    @State private var revealed: Set<String> = []

    private var type: String { resource.json["type"]?.stringValue ?? "Opaque" }
    private var data: [String: String] {
        var result: [String: String] = [:]
        for (key, value) in resource.json["data"]?.objectValue ?? [:] {
            result[key] = value.stringValue
        }
        return result
    }

    private func decoded(_ base64: String) -> String {
        guard let data = Data(base64Encoded: base64),
              let text = String(data: data, encoding: .utf8) else {
            return "<binary>"
        }
        return text
    }

    var body: some View {
        DetailCard(title: "Data") {
            DetailRow(label: "Type", value: type)
            if data.isEmpty {
                Text("No data").font(.caption).foregroundStyle(.tertiary)
            } else {
                VStack(alignment: .leading, spacing: Tokens.Spacing.sm) {
                    ForEach(data.sorted(by: { $0.key < $1.key }), id: \.key) { key, base64 in
                        let isRevealed = revealed.contains(key)
                        VStack(alignment: .leading, spacing: 2) {
                            HStack {
                                Text(key).font(.callout.weight(.medium))
                                Spacer()
                                Button {
                                    if isRevealed { revealed.remove(key) } else { revealed.insert(key) }
                                } label: {
                                    Image(systemName: isRevealed ? "eye.slash" : "eye")
                                }
                                .buttonStyle(.plain)
                                if isRevealed { CopyButton(value: decoded(base64)) }
                            }
                            Text(isRevealed ? decoded(base64) : String(repeating: "•", count: 12))
                                .font(.system(.caption, design: .monospaced))
                                .textSelection(.enabled)
                                .lineLimit(8)
                        }
                        .padding(Tokens.Spacing.sm)
                        .background(.quaternary.opacity(0.4),
                                    in: RoundedRectangle(cornerRadius: Tokens.Radius.sm))
                    }
                }
            }
        }
    }
}

struct ServiceDetailSection: View {
    let resource: KubeResource

    private var ports: [JSONValue] { resource.spec?["ports"]?.arrayValue ?? [] }
    private var selector: [String: String] {
        var result: [String: String] = [:]
        for (key, value) in resource.spec?["selector"]?.objectValue ?? [:] {
            result[key] = value.stringValue
        }
        return result
    }

    var body: some View {
        DetailCard(title: "Service") {
            DetailRow(label: "Type", value: resource.serviceType ?? "ClusterIP")
            DetailRow(label: "Cluster IP", value: resource.clusterIP ?? "—")
            VStack(alignment: .leading, spacing: 2) {
                Text("Ports").font(.callout).foregroundStyle(.secondary)
                ForEach(Array(ports.enumerated()), id: \.offset) { _, port in
                    let p = port["port"]?.intValue ?? 0
                    let target = port["targetPort"]?.stringValue ?? port["targetPort"]?.intValue.map(String.init) ?? ""
                    let proto = port["protocol"]?.stringValue ?? "TCP"
                    Text("\(p) → \(target) / \(proto)").font(.caption).textSelection(.enabled)
                }
            }
            VStack(alignment: .leading, spacing: 2) {
                Text("Selector").font(.callout).foregroundStyle(.secondary)
                KeyValueChips(pairs: selector)
            }
        }
    }
}

struct IngressRulesSection: View {
    let resource: KubeResource

    private var rules: [JSONValue] { resource.spec?["rules"]?.arrayValue ?? [] }

    /// Hosts named under `spec.tls` are served over https; everything else http.
    private var tlsHosts: Set<String> {
        let entries = resource.spec?["tls"]?.arrayValue ?? []
        return Set(entries.flatMap { ($0["hosts"]?.arrayValue ?? []).compactMap(\.stringValue) })
    }

    /// An openable URL for a host (optionally with a path). Wildcard ("*…") and
    /// empty hosts have no concrete address, so they stay plain text.
    private func url(host: String, path: String = "") -> URL? {
        guard !host.isEmpty, !host.contains("*") else { return nil }
        let scheme = tlsHosts.contains(host) ? "https" : "http"
        let suffix = (path.isEmpty || path == "/") ? "" : path
        return URL(string: "\(scheme)://\(host)\(suffix)")
    }

    var body: some View {
        DetailCard(title: "Rules") {
            if rules.isEmpty {
                Text("No rules").font(.caption).foregroundStyle(.tertiary)
            } else {
                VStack(alignment: .leading, spacing: Tokens.Spacing.sm) {
                    ForEach(Array(rules.enumerated()), id: \.offset) { _, rule in
                        let host = rule["host"]?.stringValue ?? "*"
                        VStack(alignment: .leading, spacing: 2) {
                            if let hostURL = url(host: host) {
                                ExternalLinkLabel(title: host, url: hostURL,
                                                  font: .callout.weight(.medium))
                            } else {
                                Text(host).font(.callout.weight(.medium))
                            }
                            ForEach(Array((rule["http"]?["paths"]?.arrayValue ?? []).enumerated()),
                                    id: \.offset) { _, path in
                                let p = path["path"]?.stringValue ?? "/"
                                let svc = path["backend"]?["service"]?["name"]?.stringValue ?? "?"
                                let port = path["backend"]?["service"]?["port"]?["number"]?.intValue
                                let label = "\(p) → \(svc):\(port.map(String.init) ?? "")"
                                if let pathURL = url(host: host, path: p) {
                                    ExternalLinkLabel(title: label, url: pathURL, font: .caption)
                                } else {
                                    Text(label).font(.caption).foregroundStyle(.secondary)
                                }
                            }
                        }
                    }
                }
            }
        }
    }
}

/// A tappable label that opens `url` in the default browser — used for Ingress
/// hosts/paths. Tinted, with a trailing arrow glyph and a hover underline.
private struct ExternalLinkLabel: View {
    let title: String
    let url: URL
    var font: Font = .callout

    @State private var hovering = false

    var body: some View {
        Button {
            NSWorkspace.shared.open(url)
        } label: {
            HStack(spacing: 4) {
                Text(title).font(font).underline(hovering)
                Image(systemName: "arrow.up.right.square").font(.caption2).opacity(0.7)
            }
            .foregroundStyle(.tint)
        }
        .buttonStyle(.plain)
        .pointerStyle(.link)
        .onHover { hovering = $0 }
        .help("Open \(url.absoluteString)")
    }
}

struct RBACRulesSection: View {
    let resource: KubeResource

    private var rules: [JSONValue] { resource.json["rules"]?.arrayValue ?? [] }

    var body: some View {
        DetailCard(title: "Rules") {
            ForEach(Array(rules.enumerated()), id: \.offset) { _, rule in
                let groups = (rule["apiGroups"]?.arrayValue ?? []).compactMap { $0.stringValue }
                let resources = (rule["resources"]?.arrayValue ?? []).compactMap { $0.stringValue }
                let verbs = (rule["verbs"]?.arrayValue ?? []).compactMap { $0.stringValue }
                VStack(alignment: .leading, spacing: 2) {
                    Text(resources.joined(separator: ", ")).font(.callout.weight(.medium))
                    Text("apiGroups: \(groups.isEmpty ? "\"\"" : groups.joined(separator: ", "))")
                        .font(.caption2).foregroundStyle(.secondary)
                    Text("verbs: \(verbs.joined(separator: ", "))")
                        .font(.caption2).foregroundStyle(.secondary)
                }
                .padding(Tokens.Spacing.sm)
                .background(.quaternary.opacity(0.4),
                            in: RoundedRectangle(cornerRadius: Tokens.Radius.sm))
            }
        }
    }
}

struct RBACSubjectsSection: View {
    let resource: KubeResource

    private var subjects: [JSONValue] { resource.json["subjects"]?.arrayValue ?? [] }

    var body: some View {
        DetailCard(title: "Binding") {
            let roleKind = resource.json["roleRef"]?["kind"]?.stringValue ?? "?"
            let roleName = resource.json["roleRef"]?["name"]?.stringValue ?? "?"
            DetailRow(label: "Role Ref", value: "\(roleKind)/\(roleName)")
            VStack(alignment: .leading, spacing: 2) {
                Text("Subjects").font(.callout).foregroundStyle(.secondary)
                ForEach(Array(subjects.enumerated()), id: \.offset) { _, subject in
                    let kind = subject["kind"]?.stringValue ?? "?"
                    let name = subject["name"]?.stringValue ?? "?"
                    let ns = subject["namespace"]?.stringValue
                    Text("\(kind): \(name)\(ns.map { " (\($0))" } ?? "")")
                        .font(.caption).textSelection(.enabled)
                }
            }
        }
    }
}

private struct CopyButton: View {
    let value: String
    var body: some View {
        Button {
            NSPasteboard.general.clearContents()
            NSPasteboard.general.setString(value, forType: .string)
        } label: {
            Image(systemName: "doc.on.doc").font(.caption2)
        }
        .buttonStyle(.plain)
        .foregroundStyle(.secondary)
    }
}
