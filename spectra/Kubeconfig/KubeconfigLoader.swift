//
//  KubeconfigLoader.swift
//  Spectra
//
//  Loads kubeconfig files from ~/.kube/config and every $KUBECONFIG entry,
//  parses them via Yams, and exposes selectable contexts. Each (file, context)
//  pair is a distinct cluster identity (id = md5(path:context)), matching
//  Freelens — we do NOT merge configs into one blob.
//

import Foundation
import CryptoKit
import Yams

/// Stable cluster id derived from the (kubeconfig path, context name) pair.
nonisolated enum ClusterIdentity {
    static func id(kubeconfigPath: String, contextName: String) -> String {
        let input = "\(kubeconfigPath):\(contextName)"
        let digest = Insecure.MD5.hash(data: Data(input.utf8))
        return digest.map { String(format: "%02x", $0) }.joined()
    }
}

/// A selectable context, surfaced in the catalog's "add cluster" flow (Phase 4).
nonisolated struct KubeContextRef: Identifiable, Sendable, Hashable {
    let id: String
    let kubeconfigPath: String
    let contextName: String
    let clusterName: String
    let userName: String?
    let namespace: String?
    let server: String
}

/// A fully resolved context: the cluster + user specs needed to connect.
nonisolated struct ResolvedContext: Sendable {
    let id: String
    let kubeconfigPath: String
    let contextName: String
    let cluster: ClusterSpec
    let user: UserSpec
    let namespace: String?
}

nonisolated enum KubeconfigError: LocalizedError {
    case fileNotFound(String)
    case parseFailed(String, underlying: String)
    case contextNotFound(String)
    case clusterNotFound(String)
    case userNotFound(String)

    var errorDescription: String? {
        switch self {
        case .fileNotFound(let p): return "Kubeconfig not found at \(p)"
        case .parseFailed(let p, let u): return "Failed to parse kubeconfig \(p): \(u)"
        case .contextNotFound(let c): return "Context '\(c)' not found in kubeconfig"
        case .clusterNotFound(let c): return "Cluster '\(c)' not found in kubeconfig"
        case .userNotFound(let u): return "User '\(u)' not found in kubeconfig"
        }
    }
}

nonisolated struct KubeconfigLoader: Sendable {
    /// Default kubeconfig file paths: ~/.kube/config plus every $KUBECONFIG entry.
    static func defaultPaths() -> [String] {
        var paths: [String] = []
        if let env = ProcessInfo.processInfo.environment["KUBECONFIG"], !env.isEmpty {
            paths.append(contentsOf: env.split(separator: ":").map(String.init))
        }
        let home = FileManager.default.homeDirectoryForCurrentUser
        let defaultPath = home.appendingPathComponent(".kube/config").path
        if !paths.contains(defaultPath) {
            paths.insert(defaultPath, at: 0)
        }
        return paths.filter { FileManager.default.fileExists(atPath: $0) }
    }

    func load(path: String) throws -> Kubeconfig {
        guard FileManager.default.fileExists(atPath: path) else {
            throw KubeconfigError.fileNotFound(path)
        }
        let text: String
        do {
            text = try String(contentsOfFile: path, encoding: .utf8)
        } catch {
            throw KubeconfigError.parseFailed(path, underlying: error.localizedDescription)
        }
        do {
            return try YAMLDecoder().decode(Kubeconfig.self, from: text)
        } catch {
            throw KubeconfigError.parseFailed(path, underlying: "\(error)")
        }
    }

    /// Parse raw YAML pasted by the user (no file on disk yet).
    func parse(yaml: String) throws -> Kubeconfig {
        do {
            return try YAMLDecoder().decode(Kubeconfig.self, from: yaml)
        } catch {
            throw KubeconfigError.parseFailed("<pasted>", underlying: "\(error)")
        }
    }

    /// All selectable contexts across the default kubeconfig paths.
    func availableContexts() -> [KubeContextRef] {
        var refs: [KubeContextRef] = []
        for path in Self.defaultPaths() {
            guard let config = try? load(path: path) else {
                Log.warning("Skipping unreadable kubeconfig at \(path)", .auth)
                continue
            }
            refs.append(contentsOf: contextRefs(path: path, config: config))
        }
        return refs
    }

    func contextRefs(path: String, config: Kubeconfig) -> [KubeContextRef] {
        config.contexts.compactMap { named in
            guard let cluster = config.clusters.first(where: { $0.name == named.context.cluster })
            else { return nil }
            return KubeContextRef(
                id: ClusterIdentity.id(kubeconfigPath: path, contextName: named.name),
                kubeconfigPath: path,
                contextName: named.name,
                clusterName: named.context.cluster,
                userName: named.context.user,
                namespace: named.context.namespace,
                server: cluster.cluster.server)
        }
    }

    /// Resolve a context into the concrete cluster + user specs to connect.
    func resolve(path: String, contextName: String) throws -> ResolvedContext {
        let config = try load(path: path)
        guard let context = config.contexts.first(where: { $0.name == contextName }) else {
            throw KubeconfigError.contextNotFound(contextName)
        }
        guard let cluster = config.clusters.first(where: { $0.name == context.context.cluster }) else {
            throw KubeconfigError.clusterNotFound(context.context.cluster)
        }
        let user: UserSpec
        if let userName = context.context.user,
           let named = config.users.first(where: { $0.name == userName }) {
            user = named.user
        } else {
            user = UserSpec()  // anonymous
        }
        return ResolvedContext(
            id: ClusterIdentity.id(kubeconfigPath: path, contextName: contextName),
            kubeconfigPath: path,
            contextName: contextName,
            cluster: cluster.cluster,
            user: user,
            namespace: context.context.namespace)
    }
}
