//
//  YAMLEditor.swift
//  Spectra
//
//  NSTextView-backed YAML editor with lightweight syntax highlighting (keys,
//  comments, strings). Used for view/edit/create and (Phase 10) Helm values.
//  Data surface: solid + legible, never glass. See 00-architecture §9.
//

import SwiftUI
import AppKit
import Yams

// MARK: - JSONValue ⇄ Foundation + YAML

extension JSONValue {
    /// Convert to a Foundation object suitable for YAML emission.
    var foundationObject: Any {
        switch self {
        case .null: return NSNull()
        case .bool(let b): return b
        case .int(let i): return i
        case .double(let d): return d
        case .string(let s): return s
        case .array(let a): return a.map(\.foundationObject)
        case .object(let o): return o.mapValues(\.foundationObject)
        }
    }
}

extension KubeResource {
    /// Render the resource as YAML for the editor / copy.
    func yamlString() throws -> String {
        try Yams.dump(object: json.foundationObject)
    }
}

/// A read-only or editable YAML text view.
struct YAMLEditor: NSViewRepresentable {
    @Binding var text: String
    var isEditable: Bool = true

    func makeNSView(context: Context) -> NSScrollView {
        let scrollView = NSTextView.scrollableTextView()
        guard let textView = scrollView.documentView as? NSTextView else { return scrollView }
        textView.isEditable = isEditable
        textView.isRichText = false
        textView.font = NSFont.monospacedSystemFont(ofSize: 12, weight: .regular)
        textView.isAutomaticQuoteSubstitutionEnabled = false
        textView.isAutomaticSpellingCorrectionEnabled = false
        textView.isAutomaticDashSubstitutionEnabled = false
        textView.allowsUndo = true
        textView.backgroundColor = .textBackgroundColor
        textView.textContainerInset = NSSize(width: 6, height: 8)
        textView.delegate = context.coordinator
        textView.string = text
        context.coordinator.highlight(textView)
        return scrollView
    }

    func updateNSView(_ scrollView: NSScrollView, context: Context) {
        guard let textView = scrollView.documentView as? NSTextView else { return }
        textView.isEditable = isEditable
        if textView.string != text {
            textView.string = text
            context.coordinator.highlight(textView)
        }
    }

    func makeCoordinator() -> Coordinator { Coordinator(text: $text) }

    final class Coordinator: NSObject, NSTextViewDelegate {
        private let text: Binding<String>

        init(text: Binding<String>) { self.text = text }

        func textDidChange(_ notification: Notification) {
            guard let textView = notification.object as? NSTextView else { return }
            text.wrappedValue = textView.string
            highlight(textView)
        }

        /// Minimal YAML highlighting: comments, keys, and quoted strings.
        func highlight(_ textView: NSTextView) {
            guard let storage = textView.textStorage else { return }
            let full = NSRange(location: 0, length: storage.length)
            storage.removeAttribute(.foregroundColor, range: full)
            storage.addAttribute(.foregroundColor, value: NSColor.textColor, range: full)
            storage.addAttribute(.font,
                                 value: NSFont.monospacedSystemFont(ofSize: 12, weight: .regular),
                                 range: full)
            let string = storage.string
            apply(pattern: "(?m)^\\s*#.*$", color: .systemGreen, in: string, storage: storage)
            apply(pattern: "(?m)^\\s*[-\\s]*([\\w./-]+)\\s*:", color: .systemBlue,
                  in: string, storage: storage, group: 1)
            apply(pattern: "\"[^\"]*\"", color: .systemRed, in: string, storage: storage)
        }

        private func apply(pattern: String, color: NSColor, in string: String,
                           storage: NSTextStorage, group: Int = 0) {
            guard let regex = try? NSRegularExpression(pattern: pattern) else { return }
            let range = NSRange(string.startIndex..., in: string)
            for match in regex.matches(in: string, range: range) where match.numberOfRanges > group {
                storage.addAttribute(.foregroundColor, value: color, range: match.range(at: group))
            }
        }
    }
}

/// Dock-hosted YAML editor for edit/create with apply + validation errors —
/// opens in the bottom dock (GCP/AWS-console style) instead of a modal sheet,
/// so the list stays visible and usable while editing.
struct YAMLEditorPanel: View {
    let spec: YAMLEditSpec
    let tabID: DockTab.ID

    @Environment(\.appEnv) private var env
    @State private var yaml: String
    @State private var applying = false
    @State private var errorMessage: String?

    init(spec: YAMLEditSpec, tabID: DockTab.ID) {
        self.spec = spec
        self.tabID = tabID
        _yaml = State(initialValue: spec.yaml)
    }

    private var title: String {
        switch spec.intent {
        case .edit: "Edit \(spec.name ?? "Resource")"
        case .create: "Create Resource"
        }
    }

    var body: some View {
        VStack(spacing: 0) {
            HStack(spacing: Tokens.Spacing.md) {
                Text(title).font(.headline)
                if applying { ProgressView().controlSize(.small) }
                if let errorMessage {
                    Label(errorMessage, systemImage: "exclamationmark.triangle")
                        .font(.caption).foregroundStyle(.red)
                        .lineLimit(1)
                        .help(errorMessage)
                }
                Spacer()
                Button("Cancel") { env.dock.close(tabID) }
                Button("Apply") { apply() }
                    .buttonStyle(.borderedProminent)
                    .keyboardShortcut(.defaultAction)
                    .disabled(applying)
            }
            .padding(.horizontal, Tokens.Spacing.md)
            .padding(.vertical, Tokens.Spacing.sm)

            Divider()

            YAMLEditor(text: $yaml)
        }
        .background(Color(nsColor: .textBackgroundColor))
    }

    private func apply() {
        applying = true
        errorMessage = nil
        Task {
            defer { applying = false }
            do {
                try await applyYAML()
                env.notifications.notify(.success, "Applied",
                                         message: spec.name ?? "resource")
                env.dock.close(tabID)
            } catch {
                errorMessage = error.localizedDescription
            }
        }
    }

    private func applyYAML() async throws {
        // Parse to resolve apiVersion/kind/name/namespace if not provided.
        guard let object = try Yams.load(yaml: yaml) as? [String: Any] else {
            throw KubeError.decoding("YAML root must be a mapping")
        }
        let kind = object["kind"] as? String ?? ""
        let meta = object["metadata"] as? [String: Any]
        let parsedName = spec.name ?? (meta?["name"] as? String) ?? ""
        let parsedNamespace = spec.namespace ?? (meta?["namespace"] as? String)
        guard let resolvedGVR = spec.gvr ?? spec.session.gvr(forKind: kind) else {
            throw KubeError.notFound("Unknown kind \(kind)")
        }

        let data = try JSONSerialization.data(withJSONObject: object)
        let resource = try JSONDecoder().decode(KubeResource.self, from: data)

        switch spec.intent {
        case .create:
            _ = try await spec.session.client.create(resolvedGVR, namespace: parsedNamespace,
                                                     resource: resource)
        case .edit:
            _ = try await spec.session.client.update(resolvedGVR, namespace: parsedNamespace,
                                                     name: parsedName, resource: resource)
        }
    }
}
