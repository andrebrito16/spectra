//
//  ConnectionStatus.swift
//  Spectra
//
//  Connection lifecycle states for a cluster, mirrored into a @MainActor
//  observable for SwiftUI.
//

import Foundation

nonisolated enum ConnectionStatus: Sendable, Equatable {
    case disconnected
    case connecting
    case connected
    case unreachable(String)
    case unauthorized(String)

    var isConnected: Bool {
        if case .connected = self { return true }
        return false
    }

    var status: SpectraStatus {
        switch self {
        case .disconnected: return .neutral
        case .connecting: return .info
        case .connected: return .success
        case .unreachable: return .error
        case .unauthorized: return .warning
        }
    }

    var label: String {
        switch self {
        case .disconnected: return "Disconnected"
        case .connecting: return "Connecting…"
        case .connected: return "Connected"
        case .unreachable(let m): return "Unreachable: \(m)"
        case .unauthorized(let m): return "Unauthorized: \(m)"
        }
    }

    /// A terminal failure the user can retry from (vs. transient/loading states).
    var isFailure: Bool {
        switch self {
        case .unreachable, .unauthorized: return true
        default: return false
        }
    }

    /// The underlying error message for a failed connection, if any.
    var detail: String? {
        switch self {
        case .unreachable(let m), .unauthorized(let m): return m
        default: return nil
        }
    }

    /// SF Symbol describing a failed connection.
    var failureIcon: String {
        switch self {
        case .unauthorized: return "lock.fill"
        default: return "exclamationmark.triangle.fill"
        }
    }
}

/// @MainActor observable holding the displayed status + server version for a
/// cluster, updated by the `ClusterConnection` actor.
@MainActor
@Observable
final class ClusterConnectionState {
    var status: ConnectionStatus = .disconnected
    var serverVersion: String?

    func set(_ status: ConnectionStatus) {
        self.status = status
    }

    func setServerVersion(_ version: String?) {
        self.serverVersion = version
    }
}
