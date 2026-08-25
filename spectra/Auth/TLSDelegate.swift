//
//  TLSDelegate.swift
//  Spectra
//
//  URLSession delegate implementing Kubernetes TLS: trust the cluster CA via a
//  custom anchor (or honor insecure-skip-tls-verify / tls-server-name), and
//  present a client identity for mTLS. See 00-architecture §4 / Phase 2.2.
//

import Foundation
import Security

nonisolated final class KubeTLSDelegate: NSObject, URLSessionDelegate, @unchecked Sendable {
    private let lock = NSLock()
    private var _anchors: [SecCertificate]
    private var _insecureSkipVerify: Bool
    private var _tlsServerName: String?
    private var _clientIdentity: SecIdentity?

    init(anchors: [SecCertificate], insecureSkipVerify: Bool, tlsServerName: String?) {
        self._anchors = anchors
        self._insecureSkipVerify = insecureSkipVerify
        self._tlsServerName = tlsServerName
    }

    func setClientIdentity(_ identity: SecIdentity?) {
        lock.lock(); defer { lock.unlock() }
        _clientIdentity = identity
    }

    private var snapshot: (anchors: [SecCertificate], insecure: Bool, serverName: String?, identity: SecIdentity?) {
        lock.lock(); defer { lock.unlock() }
        return (_anchors, _insecureSkipVerify, _tlsServerName, _clientIdentity)
    }

    func urlSession(
        _ session: URLSession,
        didReceive challenge: URLAuthenticationChallenge,
        completionHandler: @escaping @Sendable (URLSession.AuthChallengeDisposition, URLCredential?) -> Void
    ) {
        let method = challenge.protectionSpace.authenticationMethod
        let state = snapshot

        switch method {
        case NSURLAuthenticationMethodServerTrust:
            guard let trust = challenge.protectionSpace.serverTrust else {
                completionHandler(.performDefaultHandling, nil)
                return
            }
            if state.insecure {
                completionHandler(.useCredential, URLCredential(trust: trust))
                return
            }
            if let serverName = state.serverName {
                SecTrustSetPolicies(trust, SecPolicyCreateSSL(true, serverName as CFString))
            }
            if !state.anchors.isEmpty {
                SecTrustSetAnchorCertificates(trust, state.anchors as CFArray)
                SecTrustSetAnchorCertificatesOnly(trust, true)
            }
            var error: CFError?
            if SecTrustEvaluateWithError(trust, &error) {
                completionHandler(.useCredential, URLCredential(trust: trust))
            } else {
                Log.warning("Server trust evaluation failed: \(error.map { "\($0)" } ?? "unknown")", .auth)
                completionHandler(.cancelAuthenticationChallenge, nil)
            }

        case NSURLAuthenticationMethodClientCertificate:
            if let identity = state.identity {
                completionHandler(.useCredential, URLCredential(identity: identity,
                                                               certificates: nil,
                                                               persistence: .forSession))
            } else {
                completionHandler(.performDefaultHandling, nil)
            }

        default:
            completionHandler(.performDefaultHandling, nil)
        }
    }
}
