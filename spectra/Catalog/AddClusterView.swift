//
//  AddClusterView.swift
//  Spectra
//
//  Add-cluster flow: pick contexts from the default kubeconfig(s), open a
//  kubeconfig file, or paste raw YAML. The loader lives in Kubeconfig/; this is
//  just the UI. Deduplicates by cluster id.
//

import SwiftUI
import UniformTypeIdentifiers

struct AddClusterView: View {
    @Environment(\.appEnv) private var env
    @Environment(\.dismiss) private var dismiss

    @State private var mode: Mode = .kubeconfig
    @State private var contexts: [KubeContextRef] = []
    @State private var pastedYAML = ""
    @State private var importing = false
    @State private var errorMessage: String?

    enum Mode: String, CaseIterable, Identifiable {
        case kubeconfig = "Default kubeconfig"
        case file = "Open file"
        case paste = "Paste YAML"
        var id: String { rawValue }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: Tokens.Spacing.md) {
            Text("Add Cluster")
                .font(.title2.weight(.semibold))

            Picker("Source", selection: $mode) {
                ForEach(Mode.allCases) { Text($0.rawValue).tag($0) }
            }
            .pickerStyle(.segmented)
            .labelsHidden()

            switch mode {
            case .kubeconfig: kubeconfigList
            case .file: fileImport
            case .paste: pasteEditor
            }

            if let errorMessage {
                Label(errorMessage, systemImage: "exclamationmark.triangle")
                    .font(.caption)
                    .foregroundStyle(.red)
            }

            HStack {
                Spacer()
                Button("Done") { dismiss() }
                    .keyboardShortcut(.defaultAction)
            }
        }
        .padding(Tokens.Spacing.xl)
        .frame(width: 520, height: 420)
        .onAppear(perform: loadDefault)
        .fileImporter(isPresented: $importing,
                      allowedContentTypes: [.yaml, .data, .item],
                      allowsMultipleSelection: false) { result in
            handleFileImport(result)
        }
    }

    private var kubeconfigList: some View {
        Group {
            if contexts.isEmpty {
                EmptyStateView(title: "No contexts found",
                               systemImage: "doc.questionmark",
                               message: "No readable kubeconfig at ~/.kube/config or $KUBECONFIG.")
            } else {
                List(contexts) { ContextRow(ref: $0) }
                    .listStyle(.inset)
            }
        }
    }

    private var fileImport: some View {
        VStack(spacing: Tokens.Spacing.md) {
            Spacer()
            SpectraButton(title: "Choose Kubeconfig File…", systemImage: "folder",
                          prominent: true) { importing = true }
            if !contexts.isEmpty {
                List(contexts) { ContextRow(ref: $0) }
            }
            Spacer()
        }
    }

    private var pasteEditor: some View {
        VStack(alignment: .leading, spacing: Tokens.Spacing.sm) {
            TextEditor(text: $pastedYAML)
                .font(.system(.body, design: .monospaced))
                .frame(minHeight: 160)
                .overlay(RoundedRectangle(cornerRadius: Tokens.Radius.sm).stroke(.quaternary))
            Button("Parse") { parsePasted() }
            if !contexts.isEmpty {
                List(contexts) { ContextRow(ref: $0) }
            }
        }
    }

    private func loadDefault() {
        guard mode == .kubeconfig else { return }
        contexts = env.clusters.availableContexts()
    }

    private func handleFileImport(_ result: Result<[URL], Error>) {
        switch result {
        case .success(let urls):
            guard let url = urls.first else { return }
            let accessed = url.startAccessingSecurityScopedResource()
            defer { if accessed { url.stopAccessingSecurityScopedResource() } }
            contexts = env.clusters.contexts(inFile: url.path)
            if contexts.isEmpty { errorMessage = "No contexts found in that file." }
        case .failure(let error):
            errorMessage = error.localizedDescription
        }
    }

    private func parsePasted() {
        errorMessage = nil
        do {
            let config = try KubeconfigLoader().parse(yaml: pastedYAML)
            // Persist pasted YAML to a temp file so the resolved context can be
            // re-read at connect time.
            let tmp = FileManager.default.temporaryDirectory
                .appendingPathComponent("spectra-pasted-\(UUID().uuidString).yaml")
            try pastedYAML.write(to: tmp, atomically: true, encoding: .utf8)
            contexts = KubeconfigLoader().contextRefs(path: tmp.path, config: config)
            if contexts.isEmpty { errorMessage = "No contexts found in pasted YAML." }
        } catch {
            errorMessage = error.localizedDescription
        }
    }
}

private struct ContextRow: View {
    @Environment(\.appEnv) private var env
    let ref: KubeContextRef

    private var alreadyAdded: Bool {
        env.clusters.record(id: ref.id) != nil
    }

    var body: some View {
        HStack {
            VStack(alignment: .leading, spacing: 0) {
                Text(ref.contextName).font(.body)
                Text(ref.server).font(.caption).foregroundStyle(.secondary).lineLimit(1)
            }
            Spacer()
            if alreadyAdded {
                Label("Added", systemImage: "checkmark.circle.fill")
                    .labelStyle(.iconOnly)
                    .foregroundStyle(.green)
            } else {
                Button("Add") { env.clusters.addCluster(ref) }
            }
        }
    }
}
