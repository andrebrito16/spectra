//
//  HelmService.swift
//  Spectra
//
//  Actor wrapping the `helm` CLI (mirrors Freelens): runs commands against the
//  active cluster's kubeconfig/context, parses `--output json`, manages temp
//  values files, and surfaces structured errors.
//

import Foundation

actor HelmService {
    private let helmPath: String
    private let kubeconfigPath: String
    private let context: String
    private let extraPATH: String

    init(helmPath: String, kubeconfigPath: String, context: String, extraPATH: String) {
        self.helmPath = helmPath
        self.kubeconfigPath = kubeconfigPath
        self.context = context
        self.extraPATH = extraPATH
    }

    // MARK: - Releases

    func listReleases() async throws -> [HelmRelease] {
        let data = try await run(["list", "--all-namespaces", "--output", "json"], needsCluster: true)
        return try decode([HelmRelease].self, from: data)
    }

    func history(name: String, namespace: String) async throws -> [HelmHistoryEntry] {
        let data = try await run(["history", name, "-n", namespace, "--output", "json"],
                                 needsCluster: true)
        return try decode([HelmHistoryEntry].self, from: data)
    }

    func getValues(name: String, namespace: String) async throws -> String {
        let data = try await run(["get", "values", name, "-n", namespace], needsCluster: true)
        return String(data: data, encoding: .utf8) ?? ""
    }

    func getManifest(name: String, namespace: String) async throws -> String {
        let data = try await run(["get", "manifest", name, "-n", namespace], needsCluster: true)
        return String(data: data, encoding: .utf8) ?? ""
    }

    func install(name: String, chart: String, namespace: String,
                 version: String?, values: String) async throws {
        let valuesFile = try writeTempValues(values)
        defer { try? FileManager.default.removeItem(at: valuesFile) }
        var args = ["install", name, chart, "-n", namespace, "-f", valuesFile.path,
                    "--create-namespace"]
        if let version { args += ["--version", version] }
        _ = try await run(args, needsCluster: true)
    }

    func upgrade(name: String, chart: String, namespace: String,
                 version: String?, values: String) async throws {
        let valuesFile = try writeTempValues(values)
        defer { try? FileManager.default.removeItem(at: valuesFile) }
        var args = ["upgrade", name, chart, "-n", namespace, "-f", valuesFile.path]
        if let version { args += ["--version", version] }
        _ = try await run(args, needsCluster: true)
    }

    func rollback(name: String, namespace: String, revision: Int) async throws {
        _ = try await run(["rollback", name, "\(revision)", "-n", namespace], needsCluster: true)
    }

    func uninstall(name: String, namespace: String) async throws {
        _ = try await run(["uninstall", name, "-n", namespace], needsCluster: true)
    }

    /// Resolve a deployed release's chart metadata — the `"<name>-<version>"`
    /// string `helm list` reports (e.g. `"ingress-nginx-4.0.6"`) — into an
    /// installable chart reference for `helm upgrade` (e.g. `"ingress-nginx/ingress-nginx"`).
    ///
    /// `helm upgrade` REQUIRES a locatable chart; the bare metadata string is not
    /// one, so an upgrade that passed it straight through always failed — which is
    /// why editing release values appeared to do nothing. We split off the chart
    /// name and match it against the user's added repos, returning the repo
    /// reference plus the installed version (so an edit-values upgrade keeps the
    /// same chart version instead of silently bumping to the repo's latest).
    ///
    /// Returns `nil` if no added repo provides the chart (the caller surfaces a
    /// "add the repo" message — helm fundamentally can't upgrade without it).
    func resolveChartReference(forReleaseChart chartMeta: String)
        async throws -> (reference: String, version: String?)? {
        let (name, version) = Self.splitChartMeta(chartMeta)
        let hits = try await searchCharts(name)
        guard let match = hits.first(where: { $0.name == name || $0.name.hasSuffix("/\(name)") })
        else { return nil }
        return (match.name, version ?? match.version)
    }

    /// Split `"<chart-name>-<version>"` into its parts at the last `-` that begins
    /// a version (a digit, or `v` then a digit). Chart names may themselves contain
    /// hyphens and digits, so we scan from the end: `"ingress-nginx-4.0.6"` →
    /// `("ingress-nginx", "4.0.6")`, `"cert-manager-v1.13.0"` → `("cert-manager", "v1.13.0")`.
    static func splitChartMeta(_ meta: String) -> (name: String, version: String?) {
        let chars = Array(meta)
        for i in stride(from: chars.count - 2, through: 0, by: -1) where chars[i] == "-" {
            let next = chars[i + 1]
            let startsVersion = next.isNumber
                || (next == "v" && i + 2 < chars.count && chars[i + 2].isNumber)
            if startsVersion {
                return (String(chars[0..<i]), String(chars[(i + 1)...]))
            }
        }
        return (meta, nil)
    }

    // MARK: - Repositories & charts

    func listRepos() async throws -> [HelmRepo] {
        do {
            let data = try await run(["repo", "list", "--output", "json"], needsCluster: false)
            return try decode([HelmRepo].self, from: data)
        } catch {
            return []  // no repos configured
        }
    }

    func addRepo(name: String, url: String) async throws {
        _ = try await run(["repo", "add", name, url], needsCluster: false)
    }

    func removeRepo(name: String) async throws {
        _ = try await run(["repo", "remove", name], needsCluster: false)
    }

    func updateRepos() async throws {
        _ = try await run(["repo", "update"], needsCluster: false)
    }

    func searchCharts(_ query: String) async throws -> [HelmChartHit] {
        let args = query.isEmpty
            ? ["search", "repo", "--output", "json"]
            : ["search", "repo", query, "--output", "json"]
        do {
            let data = try await run(args, needsCluster: false)
            return try decode([HelmChartHit].self, from: data)
        } catch {
            return []
        }
    }

    func showValues(chart: String, version: String?) async throws -> String {
        var args = ["show", "values", chart]
        if let version { args += ["--version", version] }
        let data = try await run(args, needsCluster: false)
        return String(data: data, encoding: .utf8) ?? ""
    }

    func showReadme(chart: String, version: String?) async throws -> String {
        var args = ["show", "readme", chart]
        if let version { args += ["--version", version] }
        let data = try await run(args, needsCluster: false)
        return String(data: data, encoding: .utf8) ?? ""
    }

    // MARK: - Process

    private func run(_ args: [String], needsCluster: Bool) async throws -> Data {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: helmPath)
        var allArgs = args
        if needsCluster { allArgs += ["--kube-context", context] }
        process.arguments = allArgs

        var env = ProcessInfo.processInfo.environment
        env["KUBECONFIG"] = kubeconfigPath
        env["PATH"] = "\(extraPATH):\(env["PATH"] ?? "")"
        process.environment = env

        let outPipe = Pipe()
        let errPipe = Pipe()
        process.standardOutput = outPipe
        process.standardError = errPipe

        try process.run()
        async let outData = readToEnd(outPipe.fileHandleForReading)
        async let errData = readToEnd(errPipe.fileHandleForReading)
        let out = await outData
        let err = await errData
        process.waitUntilExit()

        guard process.terminationStatus == 0 else {
            throw HelmError.command(String(data: err, encoding: .utf8) ?? "helm failed")
        }
        return out
    }

    private func readToEnd(_ handle: FileHandle) async -> Data {
        await withCheckedContinuation { continuation in
            DispatchQueue.global().async {
                continuation.resume(returning: handle.readDataToEndOfFile())
            }
        }
    }

    private func decode<T: Decodable>(_ type: T.Type, from data: Data) throws -> T {
        do {
            return try JSONDecoder().decode(T.self, from: data)
        } catch {
            throw HelmError.command("Failed to parse helm output: \(error)")
        }
    }

    private func writeTempValues(_ values: String) throws -> URL {
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("spectra-helm-\(UUID().uuidString).yaml")
        try values.write(to: url, atomically: true, encoding: .utf8)
        return url
    }
}
