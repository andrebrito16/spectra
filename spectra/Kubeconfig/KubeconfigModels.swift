//
//  KubeconfigModels.swift
//  Spectra
//
//  Typed kubeconfig model decoded from YAML (Yams). Mirrors the kubeconfig
//  schema (clusters/users/contexts) including all auth fields needed by the
//  CredentialProvider. See Phase 2 / 00-architecture §6.
//

import Foundation

/// Top-level kubeconfig document.
nonisolated struct Kubeconfig: Codable, Sendable {
    var apiVersion: String?
    var kind: String?
    var currentContext: String?
    var clusters: [NamedCluster]
    var users: [NamedUser]
    var contexts: [NamedContext]

    enum CodingKeys: String, CodingKey {
        case apiVersion, kind, clusters, users, contexts
        case currentContext = "current-context"
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        apiVersion = try c.decodeIfPresent(String.self, forKey: .apiVersion)
        kind = try c.decodeIfPresent(String.self, forKey: .kind)
        currentContext = try c.decodeIfPresent(String.self, forKey: .currentContext)
        clusters = try c.decodeIfPresent([NamedCluster].self, forKey: .clusters) ?? []
        users = try c.decodeIfPresent([NamedUser].self, forKey: .users) ?? []
        contexts = try c.decodeIfPresent([NamedContext].self, forKey: .contexts) ?? []
    }
}

nonisolated struct NamedCluster: Codable, Sendable {
    var name: String
    var cluster: ClusterSpec
}

nonisolated struct ClusterSpec: Codable, Sendable {
    var server: String
    var certificateAuthority: String?
    var certificateAuthorityData: String?
    var insecureSkipTLSVerify: Bool?
    var tlsServerName: String?
    var proxyURL: String?

    enum CodingKeys: String, CodingKey {
        case server
        case certificateAuthority = "certificate-authority"
        case certificateAuthorityData = "certificate-authority-data"
        case insecureSkipTLSVerify = "insecure-skip-tls-verify"
        case tlsServerName = "tls-server-name"
        case proxyURL = "proxy-url"
    }
}

nonisolated struct NamedUser: Codable, Sendable {
    var name: String
    var user: UserSpec
}

nonisolated struct UserSpec: Codable, Sendable {
    var token: String?
    var tokenFile: String?
    var clientCertificate: String?
    var clientCertificateData: String?
    var clientKey: String?
    var clientKeyData: String?
    var username: String?
    var password: String?
    var exec: ExecConfig?
    var authProvider: AuthProviderConfig?

    enum CodingKeys: String, CodingKey {
        case token, tokenFile, username, password, exec
        case clientCertificate = "client-certificate"
        case clientCertificateData = "client-certificate-data"
        case clientKey = "client-key"
        case clientKeyData = "client-key-data"
        case authProvider = "auth-provider"
    }
}

/// `user.exec` credential plugin configuration.
nonisolated struct ExecConfig: Codable, Sendable {
    var apiVersion: String?
    var command: String
    var args: [String]?
    var env: [ExecEnvVar]?
    var installHint: String?
    var provideClusterInfo: Bool?
    var interactiveMode: String?
}

nonisolated struct ExecEnvVar: Codable, Sendable {
    var name: String
    var value: String
}

/// Legacy `auth-provider` (e.g. oidc, gcp, azure).
nonisolated struct AuthProviderConfig: Codable, Sendable {
    var name: String
    var config: [String: String]?
}

nonisolated struct NamedContext: Codable, Sendable {
    var name: String
    var context: ContextSpec
}

nonisolated struct ContextSpec: Codable, Sendable {
    var cluster: String
    var user: String?
    var namespace: String?
}
