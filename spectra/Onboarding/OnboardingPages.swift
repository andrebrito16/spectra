//
//  OnboardingPages.swift
//  Spectra
//
//  The individual onboarding scenes. Each page owns one idea and reads/writes
//  real app state (theme, clusters) so what people pick here is what they get.
//  Framing, navigation and animation plumbing live in OnboardingView.swift.
//

import SwiftUI

// MARK: - 1. Welcome

struct WelcomePage: View {
    @Environment(\.appEnv) private var env
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var floating = false

    var body: some View {
        VStack(spacing: Tokens.Spacing.xl) {
            Image(nsImage: NSApp.applicationIconImage)
                .resizable()
                .interpolation(.high)
                .frame(width: 164, height: 164)
                .shadow(color: env.theme.accent.opacity(0.45), radius: 36, y: 18)
                .offset(y: floating ? -6 : 6)
                .reveal(delay: 0)
                .onAppear {
                    guard !reduceMotion else { return }
                    withAnimation(.easeInOut(duration: 2.6).repeatForever(autoreverses: true)) {
                        floating = true
                    }
                }
                .accessibilityHidden(true)

            VStack(spacing: Tokens.Spacing.sm) {
                Text("Welcome to Spectra")
                    .font(.system(size: 46, weight: .bold, design: .rounded))
                    .reveal(delay: 0.12)
                Text("A Kubernetes IDE that feels at home on your Mac.")
                    .font(.title2)
                    .foregroundStyle(.secondary)
                    .reveal(delay: 0.2)
            }
            .multilineTextAlignment(.center)

            HStack(spacing: Tokens.Spacing.md) {
                pillar("bolt.fill", "Native and fast", delay: 0.32)
                pillar("cube.transparent", "Every kind, CRDs included", delay: 0.4)
                pillar("terminal.fill", "Logs, shells, port-forwards", delay: 0.48)
            }
        }
    }

    private func pillar(_ symbol: String, _ text: String, delay: Double) -> some View {
        Label(text, systemImage: symbol)
            .font(.callout.weight(.medium))
            .padding(.horizontal, Tokens.Spacing.lg)
            .padding(.vertical, Tokens.Spacing.sm)
            .glassEffect(in: .capsule)
            .reveal(delay: delay)
    }
}

// MARK: - 2. Look & feel

struct LookPage: View {
    @Environment(\.appEnv) private var env

    var body: some View {
        VStack(spacing: Tokens.Spacing.xl) {
            OnboardingTitle(eyebrow: "Make it yours",
                            title: "Pick a look",
                            subtitle: "Appearance and accent apply everywhere: the sidebar, "
                                + "tables, badges and the catalog. Change them anytime in Settings.")

            HStack(spacing: Tokens.Spacing.lg) {
                ForEach(Array(ThemeMode.allCases.enumerated()), id: \.element) { index, mode in
                    AppearanceCard(mode: mode, selected: env.theme.mode == mode,
                                   accent: env.theme.accent) {
                        withAnimation(.snappy) { env.theme.mode = mode }
                    }
                    .reveal(delay: 0.16 + Double(index) * 0.06)
                }
            }

            VStack(spacing: Tokens.Spacing.sm) {
                Text("Accent")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.secondary)
                HStack(spacing: Tokens.Spacing.md) {
                    AccentSwatch(color: .accentColor, selected: env.theme.usesDefaultAccent,
                                 title: "Default") { env.theme.resetAccent() }
                    ForEach(ClusterStyle.palette, id: \.hex) { entry in
                        let color = Color(hex: entry.hex) ?? .gray
                        AccentSwatch(color: color,
                                     selected: !env.theme.usesDefaultAccent
                                        && env.theme.accent.rgbHex == entry.hex,
                                     title: entry.name) {
                            env.theme.accent = color
                        }
                    }
                }
            }
            .reveal(delay: 0.38)
        }
    }
}

private struct AppearanceCard: View {
    let mode: ThemeMode
    let selected: Bool
    let accent: Color
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            VStack(spacing: Tokens.Spacing.md) {
                preview
                HStack(spacing: Tokens.Spacing.xs) {
                    Text(mode.label).font(.headline)
                    if selected {
                        Image(systemName: "checkmark.circle.fill")
                            .foregroundStyle(accent)
                            .transition(.scale.combined(with: .opacity))
                    }
                }
            }
            .padding(Tokens.Spacing.lg)
            .glassEffect(selected ? .regular.tint(accent.opacity(0.22)) : .regular,
                         in: .rect(cornerRadius: Tokens.Radius.lg))
            .overlay {
                RoundedRectangle(cornerRadius: Tokens.Radius.lg)
                    .strokeBorder(selected ? accent : .clear, lineWidth: 2)
            }
            .scaleEffect(selected ? 1.03 : 1)
        }
        .buttonStyle(.plain)
        .animation(.snappy, value: selected)
        .accessibilityLabel("\(mode.label) appearance")
        .accessibilityAddTraits(selected ? .isSelected : [])
    }

    @ViewBuilder
    private var preview: some View {
        switch mode {
        case .light:
            WindowMock(scheme: .light, accent: accent)
        case .dark:
            WindowMock(scheme: .dark, accent: accent)
        case .auto:
            ZStack {
                WindowMock(scheme: .light, accent: accent)
                WindowMock(scheme: .dark, accent: accent)
                    .mask(alignment: .trailing) {
                        Rectangle().frame(width: WindowMock.size.width / 2)
                    }
            }
        }
    }
}

/// A tiny schematic of the IDE window (sidebar + table). Colors are explicit
/// per scheme (not semantic) so each card previews its own appearance no
/// matter what the sheet itself is rendered in.
private struct WindowMock: View {
    static let size = CGSize(width: 188, height: 118)
    let scheme: ColorScheme
    let accent: Color

    private var window: Color { scheme == .dark ? Color(white: 0.12) : Color(white: 0.98) }
    private var sidebar: Color { scheme == .dark ? Color(white: 0.18) : Color(white: 0.92) }
    private var ink: Color { scheme == .dark ? Color(white: 0.85) : Color(white: 0.25) }
    private var bar: Color { scheme == .dark ? Color(white: 0.38) : Color(white: 0.74) }
    private var faint: Color { scheme == .dark ? Color(white: 0.3) : Color(white: 0.84) }

    var body: some View {
        HStack(spacing: 0) {
            VStack(alignment: .leading, spacing: 6) {
                ForEach(0..<6, id: \.self) { row in
                    Capsule()
                        .fill(row == 1 ? accent : bar)
                        .frame(width: row == 1 ? 36 : CGFloat(22 + (row * 7) % 16), height: 5)
                }
            }
            .padding(10)
            .frame(width: 58, alignment: .topLeading)
            .frame(maxHeight: .infinity, alignment: .top)
            .background(sidebar)

            VStack(alignment: .leading, spacing: 7) {
                Capsule().fill(ink).frame(width: 54, height: 6)
                ForEach(0..<5, id: \.self) { row in
                    HStack(spacing: 6) {
                        Circle().fill(row == 3 ? Color.orange : Color.green).frame(width: 5, height: 5)
                        Capsule().fill(bar)
                            .frame(width: CGFloat(48 + (row * 13) % 30), height: 5)
                        Spacer(minLength: 0)
                        Capsule().fill(faint).frame(width: 18, height: 5)
                    }
                }
            }
            .padding(10)
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        }
        .frame(width: Self.size.width, height: Self.size.height)
        .background(window)
        .clipShape(RoundedRectangle(cornerRadius: Tokens.Radius.md))
        .overlay {
            RoundedRectangle(cornerRadius: Tokens.Radius.md)
                .strokeBorder(.white.opacity(scheme == .dark ? 0.12 : 0.6))
        }
    }
}

private struct AccentSwatch: View {
    let color: Color
    let selected: Bool
    let title: String
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Circle()
                .fill(color)
                .frame(width: 26, height: 26)
                .overlay {
                    Circle().strokeBorder(.white.opacity(0.6), lineWidth: 1)
                }
                .overlay {
                    if selected {
                        Image(systemName: "checkmark")
                            .font(.system(size: 11, weight: .bold))
                            .foregroundStyle(.white)
                            .shadow(radius: 1)
                    }
                }
                .padding(3)
                .overlay {
                    Circle().strokeBorder(selected ? color : .clear, lineWidth: 2)
                }
                .scaleEffect(selected ? 1.12 : 1)
        }
        .buttonStyle(.plain)
        .animation(.snappy, value: selected)
        .help(title)
        .accessibilityLabel("\(title) accent")
        .accessibilityAddTraits(selected ? .isSelected : [])
    }
}

// MARK: - 3. Clusters

struct ClustersPage: View {
    @Environment(\.appEnv) private var env
    @State private var contexts: [KubeContextRef] = []
    @State private var showAddCluster = false

    private var addedCount: Int {
        contexts.filter { env.clusters.record(id: $0.id) != nil }.count
    }

    var body: some View {
        VStack(spacing: Tokens.Spacing.xl) {
            OnboardingTitle(eyebrow: "Your clusters",
                            title: contexts.isEmpty ? "Bring your clusters" : "Already here",
                            subtitle: contexts.isEmpty
                                ? "No kubeconfig was found at ~/.kube/config or $KUBECONFIG. "
                                    + "Open one, or paste its YAML, and Spectra takes it from there."
                                : "Spectra reads ~/.kube/config and $KUBECONFIG and keeps this "
                                    + "list in sync, so a new context shows up on its own.")

            GlassPanel {
                if contexts.isEmpty {
                    emptyState
                } else {
                    contextList
                }
            }
            .frame(maxWidth: 620)
            .frame(height: 250)
            .reveal(delay: 0.18)

            if !contexts.isEmpty {
                Button {
                    showAddCluster = true
                } label: {
                    Label("Add another kubeconfig…", systemImage: "plus.circle")
                }
                .buttonStyle(.plain)
                .foregroundStyle(.secondary)
                .reveal(delay: 0.3)
            }
        }
        .onAppear { contexts = env.clusters.availableContexts() }
        .sheet(isPresented: $showAddCluster, onDismiss: {
            contexts = env.clusters.availableContexts()
        }) {
            AddClusterView()
        }
    }

    private var emptyState: some View {
        VStack(spacing: Tokens.Spacing.lg) {
            Image(systemName: "doc.badge.plus")
                .font(.system(size: 44))
                .foregroundStyle(env.theme.accent)
            SpectraButton(title: "Open a kubeconfig file…", systemImage: "folder", prominent: true) {
                showAddCluster = true
            }
            Text("You can also skip this and add clusters later with ⇧⌘N.")
                .font(.caption)
                .foregroundStyle(.tertiary)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private var contextList: some View {
        VStack(spacing: 0) {
            HStack {
                Text("\(contexts.count) context\(contexts.count == 1 ? "" : "s") found")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.secondary)
                Spacer()
                Text("\(addedCount) added")
                    .font(.caption)
                    .foregroundStyle(.tertiary)
                    .contentTransition(.numericText())
            }
            .padding(.horizontal, Tokens.Spacing.lg)
            .padding(.vertical, Tokens.Spacing.md)
            Divider().opacity(0.4)
            ScrollView {
                VStack(spacing: 0) {
                    ForEach(Array(contexts.enumerated()), id: \.element.id) { index, ref in
                        ContextRow(ref: ref, added: env.clusters.record(id: ref.id) != nil,
                                   accent: env.theme.accent) {
                            withAnimation(.snappy) { _ = env.clusters.addCluster(ref) }
                        }
                        .reveal(delay: 0.24 + Double(min(index, 6)) * 0.05)
                        if index < contexts.count - 1 {
                            Divider().opacity(0.3).padding(.leading, 52)
                        }
                    }
                }
            }
        }
    }
}

private struct ContextRow: View {
    let ref: KubeContextRef
    let added: Bool
    let accent: Color
    let onAdd: () -> Void

    var body: some View {
        HStack(spacing: Tokens.Spacing.md) {
            Image(systemName: ClusterStyle.defaultSymbol)
                .font(.title3)
                .foregroundStyle(added ? AnyShapeStyle(accent) : AnyShapeStyle(.tertiary))
                .frame(width: 28)
            VStack(alignment: .leading, spacing: 1) {
                Text(ref.contextName).font(.body.weight(.medium)).lineLimit(1)
                Text(ref.server).font(.caption).foregroundStyle(.secondary).lineLimit(1)
            }
            Spacer()
            if added {
                Label("Added", systemImage: "checkmark.circle.fill")
                    .font(.caption.weight(.medium))
                    .foregroundStyle(.green)
                    .transition(.scale.combined(with: .opacity))
            } else {
                Button("Add", action: onAdd)
                    .buttonStyle(.glass)
                    .controlSize(.small)
            }
        }
        .padding(.horizontal, Tokens.Spacing.lg)
        .padding(.vertical, Tokens.Spacing.sm)
        .animation(.snappy, value: added)
    }
}

// MARK: - 4. Tools

struct ToolsPage: View {
    @Environment(\.appEnv) private var env
    @State private var results: [String: ProbeResult] = [:]

    private enum ProbeResult: Equatable {
        case found(String)
        case missing
    }

    private struct Probe: Identifiable {
        let id: String        // binary name
        let purpose: String
        let required: Bool
    }

    private let probes: [Probe] = [
        Probe(id: "kubectl", purpose: "Shells, node shells and port-forwards", required: true),
        Probe(id: "helm", purpose: "Helm charts and releases", required: false),
        Probe(id: "aws", purpose: "EKS credentials", required: false),
        Probe(id: "gke-gcloud-auth-plugin", purpose: "GKE credentials", required: false),
        Probe(id: "kubelogin", purpose: "AKS / OIDC credentials", required: false),
    ]

    private var kubectlMissing: Bool { results["kubectl"] == .missing }

    var body: some View {
        VStack(spacing: Tokens.Spacing.xl) {
            OnboardingTitle(eyebrow: "Your toolbelt",
                            title: "Checking your tools",
                            subtitle: "Spectra talks to the API server directly. A few things still "
                                + "shell out to the CLIs you already have, so here is what was found.")

            GlassPanel {
                VStack(spacing: 0) {
                    ForEach(Array(probes.enumerated()), id: \.element.id) { index, probe in
                        ToolRow(name: probe.id, purpose: probe.purpose, required: probe.required,
                                result: results[probe.id])
                            .reveal(delay: 0.18 + Double(index) * 0.05)
                        if index < probes.count - 1 {
                            Divider().opacity(0.3).padding(.leading, 52)
                        }
                    }
                }
                .padding(.vertical, Tokens.Spacing.xs)
            }
            .frame(maxWidth: 620)

            Text(kubectlMissing
                 ? "kubectl wasn't found. Install it (for example `brew install kubectl`) or add "
                    + "its folder under Settings → General → PATH. Browsing clusters works without it."
                 : "Cloud plugins are only needed for the clusters that use them. Anything missing "
                    + "can be added later under Settings → General → PATH.")
                .font(.caption)
                .foregroundStyle(kubectlMissing ? AnyShapeStyle(.orange) : AnyShapeStyle(.tertiary))
                .multilineTextAlignment(.center)
                .frame(maxWidth: 560)
                .reveal(delay: 0.45)
        }
        .task { await probeTools() }
    }

    private func probeTools() async {
        let extraPATH = env.clusters.extraPATH
        for probe in probes {
            let name = probe.id
            let path = await Task.detached(priority: .userInitiated) {
                BinaryResolver.path(for: name, extraPATH: extraPATH)
            }.value
            withAnimation(.snappy) {
                results[name] = path.map(ProbeResult.found) ?? .missing
            }
        }
    }

    private struct ToolRow: View {
        let name: String
        let purpose: String
        let required: Bool
        let result: ProbeResult?

        var body: some View {
            HStack(spacing: Tokens.Spacing.md) {
                statusIcon.frame(width: 28)
                VStack(alignment: .leading, spacing: 1) {
                    HStack(spacing: Tokens.Spacing.xs) {
                        Text(name).font(.system(.body, design: .monospaced).weight(.medium))
                        if !required {
                            Text("optional").font(.caption2).foregroundStyle(.tertiary)
                        }
                    }
                    Text(detail).font(.caption).foregroundStyle(.secondary).lineLimit(1)
                        .truncationMode(.middle)
                }
                Spacer()
            }
            .padding(.horizontal, Tokens.Spacing.lg)
            .padding(.vertical, Tokens.Spacing.sm)
        }

        private var detail: String {
            switch result {
            case .found(let path): return path
            case .missing: return purpose
            case nil: return purpose
            }
        }

        @ViewBuilder
        private var statusIcon: some View {
            switch result {
            case .found:
                Image(systemName: "checkmark.circle.fill")
                    .font(.title3)
                    .foregroundStyle(.green)
                    .transition(.scale.combined(with: .opacity))
            case .missing:
                Image(systemName: required ? "exclamationmark.triangle.fill" : "circle.dashed")
                    .font(.title3)
                    .foregroundStyle(required ? AnyShapeStyle(.orange) : AnyShapeStyle(.tertiary))
                    .transition(.scale.combined(with: .opacity))
            case nil:
                ProgressView().controlSize(.small)
            }
        }
    }
}

// MARK: - 5. Shortcuts

struct ShortcutsPage: View {
    @Environment(\.appEnv) private var env

    private let items: [(keys: [String], title: String, detail: String, symbol: String)] = [
        (["⌘", "K"], "Command palette", "Jump to any resource kind or cluster", "command"),
        (["⌘", "T"], "Terminal", "A shell with the active kubeconfig", "terminal"),
        (["⌘", "`"], "Dock", "Logs, shells and editors live here", "dock.rectangle"),
        (["⌘", "⌥", "→"], "Next cluster", "Switch spaces, Arc-style", "arrow.left.arrow.right"),
        (["⌘", "["], "Back", "Navigation history, like a browser", "chevron.left"),
        (["⌘", "/"], "All shortcuts", "The full list, whenever you need it", "keyboard"),
    ]

    var body: some View {
        VStack(spacing: Tokens.Spacing.xl) {
            OnboardingTitle(eyebrow: "Move fast",
                            title: "Keep your hands on the keys",
                            subtitle: "Everything in Spectra is a keystroke away. "
                                + "These six are the ones worth learning first.")

            LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: Tokens.Spacing.md), count: 3),
                      spacing: Tokens.Spacing.md) {
                ForEach(Array(items.enumerated()), id: \.offset) { index, item in
                    ShortcutTile(keys: item.keys, title: item.title, detail: item.detail,
                                 symbol: item.symbol, accent: env.theme.accent)
                        .reveal(delay: 0.16 + Double(index) * 0.06)
                }
            }
            .frame(maxWidth: 720)
        }
    }
}

private struct ShortcutTile: View {
    let keys: [String]
    let title: String
    let detail: String
    let symbol: String
    let accent: Color

    var body: some View {
        VStack(alignment: .leading, spacing: Tokens.Spacing.md) {
            HStack {
                Image(systemName: symbol)
                    .font(.title3)
                    .foregroundStyle(accent)
                Spacer()
                HStack(spacing: 4) {
                    ForEach(keys, id: \.self) { KeyCap(text: $0) }
                }
            }
            VStack(alignment: .leading, spacing: 2) {
                Text(title).font(.headline)
                Text(detail).font(.caption).foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .padding(Tokens.Spacing.lg)
        .frame(maxWidth: .infinity, minHeight: 112, alignment: .topLeading)
        .glassEffect(in: .rect(cornerRadius: Tokens.Radius.lg))
        .accessibilityElement(children: .combine)
        .accessibilityLabel("\(keys.joined()) \(title). \(detail)")
    }
}

/// A raised keyboard key.
struct KeyCap: View {
    let text: String

    var body: some View {
        Text(text)
            .font(.system(size: 13, weight: .semibold, design: .rounded))
            .frame(minWidth: 26, minHeight: 26)
            .padding(.horizontal, 5)
            .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 7))
            .overlay {
                RoundedRectangle(cornerRadius: 7).strokeBorder(.primary.opacity(0.12))
            }
            .shadow(color: .black.opacity(0.18), radius: 1, y: 1)
    }
}

// MARK: - 6. Ready

struct ReadyPage: View {
    @Environment(\.appEnv) private var env
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var sealed = false

    private var clusterCount: Int { env.clusters.records.count }

    var body: some View {
        VStack(spacing: Tokens.Spacing.xl) {
            ZStack {
                Circle()
                    .fill(env.theme.accent.opacity(0.18))
                    .frame(width: 168, height: 168)
                    .scaleEffect(sealed ? 1 : 0.4)
                    .blur(radius: 12)
                Image(systemName: "checkmark.seal.fill")
                    .font(.system(size: 108, weight: .medium))
                    .foregroundStyle(env.theme.accent)
                    .symbolRenderingMode(.hierarchical)
                    .scaleEffect(sealed ? 1 : 0.6)
                    .rotationEffect(.degrees(sealed ? 0 : -12))
            }
            .opacity(sealed ? 1 : 0)
            .onAppear {
                if reduceMotion {
                    sealed = true
                } else {
                    withAnimation(.spring(duration: 0.8, bounce: 0.38).delay(0.05)) { sealed = true }
                }
            }
            .accessibilityHidden(true)

            VStack(spacing: Tokens.Spacing.sm) {
                Text("You're all set")
                    .font(.system(size: 42, weight: .bold, design: .rounded))
                    .reveal(delay: 0.2)
                Text(clusterCount == 0
                     ? "Add a cluster whenever you're ready. Spectra will be waiting."
                     : "Pick a cluster from the catalog and start exploring.")
                    .font(.title3)
                    .foregroundStyle(.secondary)
                    .reveal(delay: 0.28)
            }
            .multilineTextAlignment(.center)

            HStack(spacing: Tokens.Spacing.md) {
                summaryChip("circle.hexagongrid.fill",
                            clusterCount == 1 ? "1 cluster ready"
                                              : "\(clusterCount) clusters ready", delay: 0.4)
                summaryChip("paintbrush.fill", "\(env.theme.mode.label) appearance", delay: 0.46)
                summaryChip("command", "⌘K whenever you're lost", delay: 0.52)
            }
        }
    }

    private func summaryChip(_ symbol: String, _ text: String, delay: Double) -> some View {
        Label(text, systemImage: symbol)
            .font(.callout.weight(.medium))
            .padding(.horizontal, Tokens.Spacing.lg)
            .padding(.vertical, Tokens.Spacing.sm)
            .glassEffect(in: .capsule)
            .reveal(delay: delay)
    }
}
