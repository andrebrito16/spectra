//
//  Notifications.swift
//  Spectra
//
//  App-wide toast/inline notification surface. `AppEnvironment.notifications`
//  exposes `notify(...)`; the status bar / overlay (Phase 4) renders these.
//

import SwiftUI

@Observable
@MainActor
final class NotificationCenterModel {
    enum Level: Sendable {
        case info, success, warning, error

        var status: SpectraStatus {
            switch self {
            case .info: return .info
            case .success: return .success
            case .warning: return .warning
            case .error: return .error
            }
        }

        var systemImage: String {
            switch self {
            case .info: return "info.circle"
            case .success: return "checkmark.circle"
            case .warning: return "exclamationmark.triangle"
            case .error: return "xmark.octagon"
            }
        }
    }

    struct Item: Identifiable, Sendable {
        let id = UUID()
        let level: Level
        let title: String
        let message: String?
        let date: Date
    }

    private(set) var items: [Item] = []

    func notify(_ level: Level, _ title: String, message: String? = nil) {
        let item = Item(level: level, title: title, message: message, date: Date())
        items.append(item)
        switch level {
        case .error: Log.error("\(title)\(message.map { ": \($0)" } ?? "")", .ui)
        case .warning: Log.warning("\(title)\(message.map { ": \($0)" } ?? "")", .ui)
        default: Log.info("\(title)\(message.map { ": \($0)" } ?? "")", .ui)
        }
        // Auto-dismiss non-error toasts.
        if level != .error {
            let id = item.id
            Task { [weak self] in
                try? await Task.sleep(for: .seconds(4))
                self?.dismiss(id)
            }
        }
    }

    func dismiss(_ id: UUID) {
        items.removeAll { $0.id == id }
    }

    func dismissAll() {
        items.removeAll()
    }
}
