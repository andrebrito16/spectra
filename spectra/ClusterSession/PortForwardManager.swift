//
//  PortForwardManager.swift
//  Spectra
//
//  Spawns and supervises `kubectl port-forward` processes (mirrors Freelens),
//  parses the actually-bound local port, tracks lifecycle, and persists active
//  forwards to SwiftData for auto-resume.
//

import SwiftUI
import SwiftData
import AppKit

@MainActor
@Observable
final class PortForwardManager {
    struct Forward: Identifiable {
        let id: String
        let clusterId: String
        let kind: String
        let name: String
        let namespace: String
        let remotePort: Int
        var localPort: Int?
        var status: SpectraStatus
        var statusText: String
    }

    private(set) var forwards: [Forward] = []
    private var processes: [String: Process] = [:]
    /// Accumulated stderr per forward — surfaced as the failure reason if the
    /// process dies before binding a local port.
    private var stderr: [String: String] = [:]
    /// Forwards that should pop open in the browser once the local port binds.
    private var openOnConnect: Set<String> = []
    private var modelContext: ModelContext?

    func attach(modelContext: ModelContext) {
        self.modelContext = modelContext
    }

    func forwards(forCluster clusterId: String) -> [Forward] {
        forwards.filter { $0.clusterId == clusterId }
    }

    /// Start a port-forward. `localPort == nil` lets kubectl pick a free port.
    /// `extraPATH` is the user's configured tool PATH; it (plus well-known tool
    /// dirs) is handed to the child so kubectl can find the exec credential
    /// plugin (aws / gke-gcloud-auth-plugin / …) its kubeconfig needs.
    func start(clusterId: String, kubeconfigPath: String, context: String, kubectl: String,
               extraPATH: String = "", kind: String, name: String, namespace: String,
               remotePort: Int, localPort: Int? = nil, openInBrowser: Bool = false) {
        let id = "\(clusterId):\(namespace):\(kind)/\(name):\(remotePort)"
        guard processes[id] == nil else { return }

        let forward = Forward(id: id, clusterId: clusterId, kind: kind, name: name,
                              namespace: namespace, remotePort: remotePort,
                              localPort: localPort, status: .info, statusText: "Starting…")
        forwards.removeAll { $0.id == id }
        forwards.append(forward)
        stderr[id] = ""
        if openInBrowser { openOnConnect.insert(id) } else { openOnConnect.remove(id) }

        let process = Process()
        process.executableURL = URL(fileURLWithPath: kubectl)
        let portArg = localPort.map { "\($0):\(remotePort)" } ?? ":\(remotePort)"
        process.arguments = ["port-forward", "-n", namespace, "\(kind.lowercased())/\(name)",
                             portArg, "--context", context]
        // A Launchd-spawned app has a minimal PATH; without the tool dirs kubectl
        // fails to launch its exec credential plugin and the forward dies before
        // binding. Prepend kubectl's own dir, then the resolver's search dirs.
        var env = ProcessInfo.processInfo.environment
        env["KUBECONFIG"] = kubeconfigPath
        let kubectlDir = (kubectl as NSString).deletingLastPathComponent
        env["PATH"] = ([kubectlDir] + BinaryResolver.searchDirs(extraPATH: extraPATH))
            .joined(separator: ":")
        process.environment = env

        let outPipe = Pipe()
        process.standardOutput = outPipe
        let errPipe = Pipe()
        process.standardError = errPipe
        outPipe.fileHandleForReading.readabilityHandler = { [weak self] handle in
            let data = handle.availableData
            guard !data.isEmpty else { handle.readabilityHandler = nil; return }
            guard let text = String(data: data, encoding: .utf8) else { return }
            if let bound = Self.parseBoundPort(text) {
                Task { @MainActor in self?.markConnected(id: id, localPort: bound) }
            }
        }
        errPipe.fileHandleForReading.readabilityHandler = { [weak self] handle in
            let data = handle.availableData
            guard !data.isEmpty else { handle.readabilityHandler = nil; return }
            guard let text = String(data: data, encoding: .utf8) else { return }
            Task { @MainActor in self?.appendStderr(id: id, text: text) }
        }
        process.terminationHandler = { [weak self] proc in
            let code = proc.terminationStatus
            Task { @MainActor in self?.handleTermination(id: id, code: code) }
        }

        do {
            try process.run()
            processes[id] = process
            if let index = forwards.firstIndex(where: { $0.id == id }) {
                forwards[index].statusText = "Connecting…"
            }
            persist(forward, active: true)
        } catch {
            markFailed(id: id, message: error.localizedDescription)
        }
    }

    func stop(id: String) {
        processes[id]?.terminate()
        processes[id] = nil
        stderr[id] = nil
        openOnConnect.remove(id)
        forwards.removeAll { $0.id == id }
        removePersisted(id: id)
    }

    private func markConnected(id: String, localPort: Int) {
        guard let index = forwards.firstIndex(where: { $0.id == id }) else { return }
        forwards[index].localPort = localPort
        forwards[index].status = .success
        forwards[index].statusText = "127.0.0.1:\(localPort)"
        // Open once, on the *bound* port (correct even when the local port was auto).
        if openOnConnect.remove(id) != nil,
           let url = URL(string: "http://127.0.0.1:\(localPort)") {
            NSWorkspace.shared.open(url)
        }
    }

    private func appendStderr(id: String, text: String) {
        guard stderr[id] != nil else { return }
        stderr[id]?.append(text)
    }

    /// kubectl exited. If it had bound a port it was a healthy forward that ended
    /// (Stopped); otherwise it never came up — surface the stderr so the user
    /// sees the real reason (auth plugin missing, port in use, no such resource…).
    private func handleTermination(id: String, code: Int32) {
        processes[id] = nil
        openOnConnect.remove(id)
        defer { stderr[id] = nil }
        guard let index = forwards.firstIndex(where: { $0.id == id }) else { return }
        if forwards[index].status == .success {
            forwards[index].status = .neutral
            forwards[index].statusText = "Stopped"
        } else {
            let detail = (stderr[id] ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
            forwards[index].status = .error
            forwards[index].statusText = detail.isEmpty
                ? "Failed (exit \(code))"
                : Self.lastMeaningfulLine(detail)
        }
    }

    private func markFailed(id: String, message: String) {
        guard let index = forwards.firstIndex(where: { $0.id == id }) else { return }
        forwards[index].status = .error
        forwards[index].statusText = message
    }

    /// kubectl's last non-empty line is the actionable error; earlier lines are
    /// usually warnings (e.g. deprecated-flag notices).
    nonisolated static func lastMeaningfulLine(_ text: String) -> String {
        text.split(separator: "\n", omittingEmptySubsequences: true)
            .map { $0.trimmingCharacters(in: .whitespaces) }
            .last { !$0.isEmpty } ?? text
    }

    nonisolated static func parseBoundPort(_ text: String) -> Int? {
        guard let regex = try? NSRegularExpression(pattern: "Forwarding from 127\\.0\\.0\\.1:(\\d+)")
        else { return nil }
        let range = NSRange(text.startIndex..., in: text)
        guard let match = regex.firstMatch(in: text, range: range),
              let portRange = Range(match.range(at: 1), in: text) else { return nil }
        return Int(text[portRange])
    }

    // MARK: - Persistence

    private func persist(_ forward: Forward, active: Bool) {
        guard let modelContext else { return }
        let record = SavedPortForward(id: forward.id, clusterId: forward.clusterId,
                                      kind: forward.kind, name: forward.name,
                                      namespace: forward.namespace,
                                      localPort: forward.localPort ?? 0,
                                      remotePort: forward.remotePort)
        record.active = active
        modelContext.insert(record)
        try? modelContext.save()
    }

    private func removePersisted(id: String) {
        guard let modelContext else { return }
        let descriptor = FetchDescriptor<SavedPortForward>(predicate: #Predicate { $0.id == id })
        if let record = try? modelContext.fetch(descriptor).first {
            modelContext.delete(record)
            try? modelContext.save()
        }
    }
}
