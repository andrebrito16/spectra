//
//  ClusterConnection.swift
//  Spectra
//
//  Per-cluster actor that owns the authenticated URLSession, credential
//  provider, and connection status. Replaces Freelens's per-cluster Go proxy +
//  LensProxy with native, in-process auth. Phase 3's client + informers request
//  through this connection. See 00-architecture §4/§6, Phase 2.4.
//

import Foundation
import Security

actor ClusterConnection {
    nonisolated let id: String
    nonisolated let baseURL: URL
    nonisolated(unsafe) let session: URLSession
    nonisolated let state: ClusterConnectionState

    private let credentials: CredentialProvider
    private let tlsDelegate: KubeTLSDelegate
    private var identityResolved = false
    private var healthTask: Task<Void, Never>?

    init(resolved: ResolvedContext, extraPATH: String, state: ClusterConnectionState) throws {
        guard let url = URL(string: resolved.cluster.server) else {
            throw KubeError.invalidURL(resolved.cluster.server)
        }
        self.id = resolved.id
        self.baseURL = url
        self.state = state
        self.credentials = CredentialProvider(user: resolved.user, extraPATH: extraPATH)

        let anchors = PEM.certificates(
            pemData: resolved.cluster.certificateAuthorityData.flatMap { Data(base64Encoded: $0) },
            pemFile: resolved.cluster.certificateAuthority)
        let delegate = KubeTLSDelegate(
            anchors: anchors,
            insecureSkipVerify: resolved.cluster.insecureSkipTLSVerify ?? false,
            tlsServerName: resolved.cluster.tlsServerName)
        self.tlsDelegate = delegate

        let config = URLSessionConfiguration.ephemeral
        config.timeoutIntervalForRequest = 30
        config.timeoutIntervalForResource = 0  // allow long-lived watch streams
        // Informers stay warm for the whole session and fan out one watch per
        // selected namespace, so a browsing user accumulates many concurrent
        // long-lived streams. Over HTTP/1.1 (e.g. via a corporate proxy) each
        // stream pins a connection; an 8-connection cap starves interactive
        // requests (logs/exec) — they queue until the 15s log watchdog trips
        // with a misleading "kubelet unreachable" error. Give generous headroom.
        config.httpMaximumConnectionsPerHost = 100
        config.waitsForConnectivity = false
        if let proxy = resolved.cluster.proxyURL, let proxyURL = URL(string: proxy),
           let host = proxyURL.host, let port = proxyURL.port {
            config.connectionProxyDictionary = [
                kCFNetworkProxiesHTTPSEnable as String: true,
                kCFNetworkProxiesHTTPSProxy as String: host,
                kCFNetworkProxiesHTTPSPort as String: port,
            ]
        }
        self.session = URLSession(configuration: config, delegate: delegate, delegateQueue: nil)
    }

    // MARK: - Lifecycle

    func connect() async {
        await MainActor.run { self.state.set(.connecting) }
        do {
            let version = try await fetchVersion()
            await MainActor.run {
                self.state.set(.connected)
                self.state.setServerVersion(version)
            }
            startHealthLoop()
        } catch let error as KubeError {
            await applyError(error)
        } catch {
            await applyError(.transport(error.localizedDescription))
        }
    }

    /// True once the URLSession has been invalidated. Creating a task on an
    /// invalidated NSURLSession raises an uncatchable ObjC exception (crashes
    /// the app — seen via NodeMetricsProvider firing after Retry), so every
    /// request entry point checks this and throws a normal KubeError instead.
    private var invalidated = false

    func disconnect() {
        healthTask?.cancel()
        healthTask = nil
        invalidated = true
        session.invalidateAndCancel()
        Task { @MainActor in self.state.set(.disconnected) }
    }

    /// Stop background work and tear down the URLSession without mutating the
    /// shared connection state. Used when immediately reconnecting (Retry), so
    /// the old connection's health loop can't race a stale status onto the UI.
    func invalidate() {
        healthTask?.cancel()
        healthTask = nil
        invalidated = true
        session.invalidateAndCancel()
    }

    /// Open a streaming request (watch, logs). Refuses on a dead session —
    /// see `invalidated`.
    func bytes(for request: URLRequest) async throws -> (URLSession.AsyncBytes, URLResponse) {
        guard !invalidated else { throw KubeError.transport("connection closed") }
        return try await session.bytes(for: request)
    }

    func refreshStatus() async {
        do {
            let version = try await fetchVersion()
            await MainActor.run {
                self.state.set(.connected)
                self.state.setServerVersion(version)
            }
        } catch let error as KubeError {
            await applyError(error)
        } catch {
            await applyError(.transport(error.localizedDescription))
        }
    }

    private func applyError(_ error: KubeError) async {
        let status: ConnectionStatus
        switch error {
        case .unauthorized(let m): status = .unauthorized(m)
        default: status = .unreachable(error.shortDescription)
        }
        await MainActor.run { self.state.set(status) }
        Log.warning("Cluster \(id) status: \(status.label)", .client)
    }

    private func startHealthLoop() {
        healthTask?.cancel()
        healthTask = Task { [weak self] in
            while !Task.isCancelled {
                try? await Task.sleep(for: .seconds(30))
                if Task.isCancelled { break }
                await self?.refreshStatus()
            }
        }
    }

    // MARK: - Authorized requests (used by Phase 3 client + informers)

    /// Attach credentials to a request, resolving/refreshing as needed and
    /// configuring the client identity for mTLS on first use.
    func authorize(_ request: inout URLRequest) async throws {
        let credential = try await credentials.credential()
        if let header = credential.authorizationHeader {
            request.setValue(header, forHTTPHeaderField: "Authorization")
        }
        if let cert = credential.clientCert, !identityResolved {
            do {
                let identity = try ClientIdentityFactory.makeIdentity(
                    certPEM: cert.certPEM, keyPEM: cert.keyPEM)
                tlsDelegate.setClientIdentity(identity)
                identityResolved = true
            } catch {
                Log.error("Failed to build client identity: \(error.localizedDescription)", .auth)
                throw KubeError.auth(error.localizedDescription)
            }
        }
    }

    /// Build an authorized request for a path relative to the API server.
    func makeRequest(path: String, method: String = "GET",
                     queryItems: [URLQueryItem] = [], body: Data? = nil,
                     contentType: String? = nil, accept: String? = nil) async throws -> URLRequest {
        var components = URLComponents(url: baseURL.appendingPathComponent(path),
                                       resolvingAgainstBaseURL: false)
        if !queryItems.isEmpty { components?.queryItems = queryItems }
        guard let url = components?.url else { throw KubeError.invalidURL(path) }
        var request = URLRequest(url: url)
        request.httpMethod = method
        request.httpBody = body
        if let contentType { request.setValue(contentType, forHTTPHeaderField: "Content-Type") }
        request.setValue(accept ?? "application/json", forHTTPHeaderField: "Accept")
        try await authorize(&request)
        return request
    }

    /// Perform a non-streaming request, returning data + HTTP response.
    func perform(_ request: URLRequest) async throws -> (Data, HTTPURLResponse) {
        guard !invalidated else { throw KubeError.transport("connection closed") }
        let (data, response): (Data, URLResponse)
        do {
            (data, response) = try await session.data(for: request)
        } catch {
            throw KubeError.transport(error.localizedDescription)
        }
        guard let http = response as? HTTPURLResponse else {
            throw KubeError.transport("Non-HTTP response")
        }
        return (data, http)
    }

    private func fetchVersion() async throws -> String? {
        let request = try await makeRequest(path: "version")
        let (data, http) = try await perform(request)
        if http.statusCode == 401 {
            throw KubeError.unauthorized("invalid credentials")
        }
        if http.statusCode == 403 {
            // /version is usually public; 403 still means we reached the server.
            return nil
        }
        guard (200..<300).contains(http.statusCode) else {
            throw KubeError.http(status: http.statusCode, reason: nil, message: "version check failed")
        }
        struct VersionInfo: Decodable { let gitVersion: String? }
        let info = try? JSONDecoder().decode(VersionInfo.self, from: data)
        return info?.gitVersion
    }
}
