//
//  CredentialProvider.swift
//  Spectra
//
//  Per-cluster actor that resolves a kubeconfig user into request credentials,
//  refreshing on expiry. Replaces the auth work Freelens delegated to the Go
//  proxy + @kubernetes/client-node. See 00-architecture §6.
//
//  NEVER log token or key material.
//

import Foundation

actor CredentialProvider {
    private let user: UserSpec
    private let extraPATH: String
    private var cached: RequestCredential?

    init(user: UserSpec, extraPATH: String) {
        self.user = user
        self.extraPATH = extraPATH
    }

    /// Returns a valid credential, resolving/refreshing as needed.
    func credential() async throws -> RequestCredential {
        if let cached, !cached.isExpired { return cached }
        let fresh = try await resolve()
        cached = fresh
        return fresh
    }

    func invalidate() {
        cached = nil
    }

    // MARK: - Resolution

    private func resolve() async throws -> RequestCredential {
        if let cert = clientCertMaterial() {
            return RequestCredential(clientCert: cert)
        }
        if let token = user.token, !token.isEmpty {
            return RequestCredential(authorizationHeader: "Bearer \(token)")
        }
        if let tokenFile = user.tokenFile {
            let token = try String(contentsOfFile: tokenFile, encoding: .utf8)
                .trimmingCharacters(in: .whitespacesAndNewlines)
            return RequestCredential(authorizationHeader: "Bearer \(token)")
        }
        if let username = user.username, let password = user.password {
            let raw = Data("\(username):\(password)".utf8).base64EncodedString()
            return RequestCredential(authorizationHeader: "Basic \(raw)")
        }
        if let exec = user.exec {
            return try await runExecPlugin(exec)
        }
        if let provider = user.authProvider, provider.name == "oidc" {
            return try await resolveOIDC(provider)
        }
        return .anonymous
    }

    /// Client certificate from inline data (base64 PEM) or file paths.
    private func clientCertMaterial() -> ClientCertMaterial? {
        let cert = decodeOrRead(data: user.clientCertificateData, file: user.clientCertificate)
        let key = decodeOrRead(data: user.clientKeyData, file: user.clientKey)
        guard let cert, let key else { return nil }
        return ClientCertMaterial(certPEM: cert, keyPEM: key)
    }

    /// `*-data` fields are base64-encoded PEM; otherwise read the referenced file.
    private func decodeOrRead(data base64: String?, file: String?) -> String? {
        if let base64, let decoded = Data(base64Encoded: base64),
           let text = String(data: decoded, encoding: .utf8) {
            return text
        }
        if let file, let text = try? String(contentsOfFile: file, encoding: .utf8) {
            return text
        }
        return nil
    }

    // MARK: - Exec credential plugins

    private func runExecPlugin(_ exec: ExecConfig) async throws -> RequestCredential {
        let apiVersion = exec.apiVersion ?? "client.authentication.k8s.io/v1beta1"
        let request = ExecCredential(apiVersion: apiVersion,
                                     spec: ExecCredentialSpec(interactive: false))
        let requestData = try JSONEncoder().encode(request)

        guard let executable = resolveExecutable(exec.command) else {
            throw AuthError.execNotFound(command: exec.command)
        }
        let process = Process()
        process.executableURL = executable
        process.arguments = exec.args ?? []
        process.environment = mergedEnvironment(exec.env,
                                                binDir: executable.deletingLastPathComponent().path)

        let stdin = Pipe()
        let stdout = Pipe()
        let stderr = Pipe()
        process.standardInput = stdin
        process.standardOutput = stdout
        process.standardError = stderr

        try process.run()
        stdin.fileHandleForWriting.write(requestData)
        try? stdin.fileHandleForWriting.close()

        let outData = stdout.fileHandleForReading.readDataToEndOfFile()
        let errData = stderr.fileHandleForReading.readDataToEndOfFile()
        process.waitUntilExit()

        guard process.terminationStatus == 0 else {
            let err = String(data: errData, encoding: .utf8) ?? ""
            throw AuthError.execFailed(command: exec.command,
                                       status: process.terminationStatus, stderr: err)
        }

        let response: ExecCredential
        do {
            response = try JSONDecoder().decode(ExecCredential.self, from: outData)
        } catch {
            throw AuthError.execBadOutput("\(error). Output began: \(Self.sanitizedSnippet(outData))")
        }
        guard let status = response.status else {
            throw AuthError.execBadOutput("missing status")
        }

        let expiry = status.expirationTimestamp.flatMap(Self.parseTimestamp)
        if let token = status.token, !token.isEmpty {
            Log.debug("Resolved exec credential (token) via \(exec.command)", .auth)
            return RequestCredential(authorizationHeader: "Bearer \(token)", expiresAt: expiry)
        }
        if let certData = status.clientCertificateData, let keyData = status.clientKeyData {
            Log.debug("Resolved exec credential (client cert) via \(exec.command)", .auth)
            return RequestCredential(
                clientCert: ClientCertMaterial(certPEM: certData, keyPEM: keyData),
                expiresAt: expiry)
        }
        throw AuthError.execBadOutput("status had neither token nor client certificate")
    }

    /// Resolve the plugin to a URL, or nil if it cannot be found anywhere.
    /// Goes through BinaryResolver (well-known dirs + login-shell fallback):
    /// tools installed by mise/asdf without shims — e.g. gke-gcloud-auth-plugin
    /// inside a mise-managed gcloud — are only visible to the login shell, never
    /// to the Launchd PATH or the shim dirs. Never fall back to /usr/bin/env:
    /// with the command name unresolved it runs bare `env`, which exits 0 and
    /// prints the environment, poisoning the credential parse downstream.
    private func resolveExecutable(_ command: String) -> URL? {
        if command.contains("/") { return URL(fileURLWithPath: command) }
        if let cached = resolvedCommands[command] { return URL(fileURLWithPath: cached) }
        guard let path = BinaryResolver.path(for: command, extraPATH: extraPATH) else {
            return nil
        }
        resolvedCommands[command] = path
        return URL(fileURLWithPath: path)
    }

    /// Login-shell resolution spawns a shell, so memoize per command; token
    /// refresh re-resolves the plugin every expiry (~hourly on GKE/EKS).
    private var resolvedCommands: [String: String] = [:]

    private func mergedEnvironment(_ extra: [ExecEnvVar]?, binDir: String) -> [String: String] {
        var env = ProcessInfo.processInfo.environment
        let existingPath = env["PATH"] ?? ""
        // Lead with the plugin's own directory so wrapper plugins can find
        // their sibling binaries (gcloud SDK layouts rely on this).
        env["PATH"] = "\(binDir):\(extraPATH):\(existingPath)"
        for entry in extra ?? [] {
            env[entry.name] = entry.value
        }
        return env
    }

    /// First bytes of plugin output for error reporting, with anything
    /// token-shaped (long base64-ish runs) redacted — NEVER log token material.
    static func sanitizedSnippet(_ data: Data) -> String {
        guard var text = String(data: data, encoding: .utf8)?
            .trimmingCharacters(in: .whitespacesAndNewlines), !text.isEmpty else {
            return "(no output)"
        }
        text = text.replacingOccurrences(of: #"[A-Za-z0-9+/=_.\-]{20,}"#,
                                         with: "…", options: .regularExpression)
        return String(text.prefix(160))
    }

    // MARK: - OIDC auth-provider

    private func resolveOIDC(_ provider: AuthProviderConfig) async throws -> RequestCredential {
        let config = provider.config ?? [:]
        guard let idToken = config["id-token"], !idToken.isEmpty else {
            throw AuthError.oidcUnsupported("no id-token present; configure kubelogin (exec)")
        }
        // Use the id-token if it is still valid.
        if let exp = Self.jwtExpiry(idToken), Date() < exp.addingTimeInterval(-10) {
            return RequestCredential(authorizationHeader: "Bearer \(idToken)", expiresAt: exp)
        }
        // Best-effort refresh via the discovered token endpoint.
        if let refreshToken = config["refresh-token"],
           let issuer = config["idp-issuer-url"],
           let clientID = config["client-id"] {
            let refreshed = try await refreshOIDC(issuer: issuer, clientID: clientID,
                                                  clientSecret: config["client-secret"],
                                                  refreshToken: refreshToken)
            return refreshed
        }
        // Expired but unusable to refresh — still send it; the server will reject
        // and we surface an unauthorized status.
        return RequestCredential(authorizationHeader: "Bearer \(idToken)")
    }

    private func refreshOIDC(issuer: String, clientID: String, clientSecret: String?,
                             refreshToken: String) async throws -> RequestCredential {
        guard let discoveryURL = URL(string: issuer.hasSuffix("/")
            ? "\(issuer).well-known/openid-configuration"
            : "\(issuer)/.well-known/openid-configuration") else {
            throw AuthError.oidcUnsupported("invalid issuer URL")
        }
        let (discoveryData, _) = try await URLSession.shared.data(from: discoveryURL)
        struct Discovery: Decodable { let token_endpoint: String }
        let discovery = try JSONDecoder().decode(Discovery.self, from: discoveryData)
        guard let tokenURL = URL(string: discovery.token_endpoint) else {
            throw AuthError.oidcUnsupported("no token endpoint")
        }

        var request = URLRequest(url: tokenURL)
        request.httpMethod = "POST"
        request.setValue("application/x-www-form-urlencoded", forHTTPHeaderField: "Content-Type")
        var params = [
            "grant_type": "refresh_token",
            "refresh_token": refreshToken,
            "client_id": clientID,
        ]
        if let clientSecret { params["client_secret"] = clientSecret }
        request.httpBody = params
            .map { "\($0.key)=\($0.value.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? $0.value)" }
            .joined(separator: "&")
            .data(using: .utf8)

        let (data, _) = try await URLSession.shared.data(for: request)
        struct TokenResponse: Decodable { let id_token: String? }
        let token = try JSONDecoder().decode(TokenResponse.self, from: data)
        guard let idToken = token.id_token else {
            throw AuthError.oidcUnsupported("refresh returned no id_token")
        }
        let exp = Self.jwtExpiry(idToken)
        return RequestCredential(authorizationHeader: "Bearer \(idToken)", expiresAt: exp)
    }

    // MARK: - Helpers

    /// Shared formatters: creating ISO8601DateFormatter is expensive and this
    /// runs in hot paths (every Age cell, list sorting). The class is documented
    /// thread-safe, hence nonisolated(unsafe).
    nonisolated(unsafe) private static let isoFractional: ISO8601DateFormatter = {
        let f = ISO8601DateFormatter()
        f.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return f
    }()
    nonisolated(unsafe) private static let isoPlain: ISO8601DateFormatter = {
        let f = ISO8601DateFormatter()
        f.formatOptions = [.withInternetDateTime]
        return f
    }()

    static func parseTimestamp(_ s: String) -> Date? {
        Self.isoFractional.date(from: s) ?? Self.isoPlain.date(from: s)
    }

    /// Decode a JWT's `exp` claim without verifying the signature (we only need
    /// to know when to refresh; the server enforces validity).
    static func jwtExpiry(_ jwt: String) -> Date? {
        let parts = jwt.split(separator: ".")
        guard parts.count >= 2 else { return nil }
        var base64 = String(parts[1])
            .replacingOccurrences(of: "-", with: "+")
            .replacingOccurrences(of: "_", with: "/")
        while base64.count % 4 != 0 { base64 += "=" }
        guard let data = Data(base64Encoded: base64),
              let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let exp = json["exp"] as? TimeInterval else { return nil }
        return Date(timeIntervalSince1970: exp)
    }
}
