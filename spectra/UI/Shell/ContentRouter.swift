//
//  ContentRouter.swift
//  Spectra
//
//  Routes the main content area based on NavigationModel.route. Phase 5 swaps the
//  `.kind` case for the real ResourceListView; Phase 8 enriches the overview;
//  Phase 10 fills the Helm `.special` routes.
//

import SwiftUI

struct ContentRouter: View {
    @Environment(\.appEnv) private var env

    var body: some View {
        // A failed connection on the active cluster supersedes the route: show a
        // retry surface instead of an empty overview (or bouncing to the catalog).
        if let id = env.clusters.activeClusterId,
           let status = env.clusters.states[id]?.status, status.isFailure {
            ClusterConnectionErrorView(
                name: env.clusters.record(id: id)?.effectiveName ?? "this cluster",
                status: status,
                onRetry: { env.retryConnection(id) })
        } else {
            routedContent
        }
    }

    @ViewBuilder
    private var routedContent: some View {
        switch env.navigation.route {
        case .catalog:
            CatalogView()
        case .overview:
            if let session = env.clusters.activeSession {
                ClusterOverviewView(session: session)
            } else {
                CatalogView()
            }
        case .kind(let id):
            if let session = env.clusters.activeSession, let gvr = session.gvr(byID: id) {
                ResourceListView(session: session, gvr: gvr)
            } else {
                CatalogView()
            }
        case .special(let id):
            specialContent(id)
        }
    }

    @ViewBuilder
    private func specialContent(_ id: String) -> some View {
        if let session = env.clusters.activeSession {
            switch id {
            case "network/portforwards": PortForwardsView(session: session)
            case "helm/charts": HelmChartsView(session: session)
            case "helm/releases": HelmReleasesView(session: session)
            default: FeaturePlaceholder(title: id)
            }
        } else {
            CatalogView()
        }
    }
}

/// Shown in the content area when the active cluster's connection failed, with a
/// button to rebuild the connection (`AppEnvironment.retryConnection`).
struct ClusterConnectionErrorView: View {
    let name: String
    let status: ConnectionStatus
    let onRetry: () -> Void

    var body: some View {
        ContentUnavailableView {
            Label("Couldn't connect to \(name)", systemImage: status.failureIcon)
        } description: {
            if let detail = status.detail {
                Text(detail)
                    .textSelection(.enabled)
            }
        } actions: {
            Button("Retry Connection", systemImage: "arrow.clockwise", action: onRetry)
                .buttonStyle(.glassProminent)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(.background)
    }
}

/// Lightweight cluster overview (counts). Phase 8/11 enrich with health + charts.
struct ClusterOverviewView: View {
    let session: ClusterSession

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: Tokens.Spacing.lg) {
                Text("Cluster Overview")
                    .font(.largeTitle.weight(.semibold))
                HStack(spacing: Tokens.Spacing.lg) {
                    OverviewStat(title: "Server", value: session.serverVersion ?? "—",
                                 systemImage: "server.rack")
                    OverviewStat(title: "Resource Kinds", value: "\(session.gvrs.count)",
                                 systemImage: "square.stack.3d.up")
                    OverviewStat(title: "Namespaces", value: "\(session.namespaces.count)",
                                 systemImage: "square.dashed")
                }
                if let error = session.bootstrapError {
                    Label(error, systemImage: "exclamationmark.triangle")
                        .foregroundStyle(.orange)
                }
                ClusterUsageDonuts(session: session)
                DetailCard(title: "Cluster Metrics") {
                    MetricsChartView(session: session, scope: .cluster)
                }
            }
            .padding(Tokens.Spacing.xl)
            .padding(.top, Tokens.Spacing.lg)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .background(.background)
    }
}

private struct OverviewStat: View {
    let title: String
    let value: String
    let systemImage: String

    var body: some View {
        VStack(alignment: .leading, spacing: Tokens.Spacing.xs) {
            Label(title, systemImage: systemImage)
                .font(.caption)
                .foregroundStyle(.secondary)
            Text(value)
                .font(.title2.weight(.semibold))
        }
        .padding(Tokens.Spacing.lg)
        .frame(minWidth: 160, alignment: .leading)
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: Tokens.Radius.md))
    }
}

struct FeaturePlaceholder: View {
    let title: String

    var body: some View {
        EmptyStateView(title: title, systemImage: "shippingbox",
                       message: "This feature is implemented in a later phase.")
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .background(.background)
    }
}
