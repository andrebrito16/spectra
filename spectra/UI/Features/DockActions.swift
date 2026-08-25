//
//  DockActions.swift
//  Spectra
//
//  Actions that open dock tabs (logs, shell, node shell) or start a port-forward.
//  Routed by the host views to AppEnvironment, which owns the dock and the
//  port-forward manager.
//

import Foundation

@MainActor
enum DockActions {
    static let logs = ObjectAction(id: "logs", title: "Logs", systemImage: "doc.plaintext",
                                   interaction: .logs, perform: { _, _ in })
    static let shell = ObjectAction(id: "shell", title: "Shell", systemImage: "terminal",
                                    interaction: .shell, perform: { _, _ in })
    static let nodeShell = ObjectAction(id: "node-shell", title: "Node Shell",
                                        systemImage: "terminal", interaction: .nodeShell,
                                        perform: { _, _ in })
    static let portForward = ObjectAction(id: "port-forward", title: "Forward Port",
                                          systemImage: "arrow.left.arrow.right",
                                          interaction: .portForward, perform: { _, _ in })
}
