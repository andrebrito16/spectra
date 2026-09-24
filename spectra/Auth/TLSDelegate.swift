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
                return
            }

            // The SSL policy enforces the Web PKI certificate lifetime limit of 398
            // days, which has no bearing on a private cluster CA. Apple exempts roots
            // added to the keychain by a user or an administrator, but not anchors
            // supplied at runtime through SecTrustSetAnchorCertificates — so a managed
            // control plane whose API server certificate outlives that limit is rejected
            // here while kubectl and Lens accept it.
            //
            // Retry only for that specific failure, and only when we pinned our own
            // anchors. The basic X.509 policy still verifies the chain, the signatures
            // and the expiry date; hostname and extended key usage are checked below,
            // since that policy does not cover them.
            let host = state.serverName ?? challenge.protectionSpace.host
            if let error,
               CFErrorGetCode(error) == Int(errSecCertificateValidityPeriodTooLong),
               !state.anchors.isEmpty,
               Self.evaluateAgainstPrivateAnchors(trust: trust, anchors: state.anchors, host: host) {
                Log.notice("Accepted private CA chain for \(host): certificate lifetime exceeds the Web PKI limit, which does not apply to anchors pinned from kubeconfig", .auth)
                completionHandler(.useCredential, URLCredential(trust: trust))
                return
            }

            Log.warning("Server trust evaluation failed: \(error.map { "\($0)" } ?? "unknown")", .auth)
            completionHandler(.cancelAuthenticationChallenge, nil)

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

// MARK: - Private CA fallback

private extension KubeTLSDelegate {
    /// Re-evaluates a chain that the SSL policy rejected solely for violating a Web
    /// PKI rule, using the basic X.509 policy plus the checks that policy omits.
    ///
    /// The basic policy still validates the chain up to our pinned anchors, the
    /// signatures and the validity dates. What it does not do is match the hostname
    /// or require the server extended key usage, so both are verified here. The net
    /// effect is the SSL policy minus the certificate lifetime limit, which exists to
    /// protect the public web and has no bearing on a CA that only this kubeconfig
    /// trusts.
    static func evaluateAgainstPrivateAnchors(trust: SecTrust, anchors: [SecCertificate], host: String) -> Bool {
        guard let leaf = SecTrustGetCertificateAtIndex(trust, 0) else { return false }
        guard hasServerAuthUsage(leaf), matches(host: host, certificate: leaf) else { return false }

        let chain = (0..<SecTrustGetCertificateCount(trust)).compactMap {
            SecTrustGetCertificateAtIndex(trust, $0)
        }
        var rebuilt: SecTrust?
        guard SecTrustCreateWithCertificates(chain as CFArray, SecPolicyCreateBasicX509(), &rebuilt) == errSecSuccess,
              let rebuilt else { return false }
        SecTrustSetAnchorCertificates(rebuilt, anchors as CFArray)
        SecTrustSetAnchorCertificatesOnly(rebuilt, true)
        return SecTrustEvaluateWithError(rebuilt, nil)
    }

    /// True when the certificate carries no extended key usage at all, or carries one
    /// that includes server authentication. An absent extension is unconstrained by
    /// RFC 5280; a present one that omits serverAuth means the key was issued for
    /// something else and must not terminate TLS.
    static func hasServerAuthUsage(_ certificate: SecCertificate) -> Bool {
        guard let values = SecCertificateCopyValues(certificate, [kSecOIDExtendedKeyUsage] as CFArray, nil) as? [String: Any],
              let eku = values[kSecOIDExtendedKeyUsage as String] as? [String: Any],
              let entries = eku["value"] as? [Any]
        else { return true }

        // 1.3.6.1.5.5.7.3.1 — id-kp-serverAuth
        let serverAuth = Data([0x2B, 0x06, 0x01, 0x05, 0x05, 0x07, 0x03, 0x01])
        return entries.contains { entry in
            if let data = entry as? Data { return data == serverAuth }
            if let string = entry as? String { return string == "1.3.6.1.5.5.7.3.1" }
            return false
        }
    }

    /// Matches `host` against the certificate's subject alternative names, the only
    /// source RFC 6125 allows once a SAN extension is present. The common name is
    /// deliberately ignored.
    static func matches(host: String, certificate: SecCertificate) -> Bool {
        guard let values = SecCertificateCopyValues(certificate, [kSecOIDSubjectAltName] as CFArray, nil) as? [String: Any],
              let san = values[kSecOIDSubjectAltName as String] as? [String: Any],
              let entries = san["value"] as? [[String: Any]]
        else { return false }

        let target = host.lowercased()
        for entry in entries {
            guard let label = entry["label"] as? String, let value = entry["value"] as? String else { continue }
            switch label {
            case "DNS Name" where matches(host: target, pattern: value.lowercased()):
                return true
            case "IP Address" where value == host:
                return true
            default:
                continue
            }
        }
        return false
    }

    /// Wildcards cover exactly one leftmost label, so `*.example.com` matches
    /// `api.example.com` but neither `example.com` nor `a.b.example.com`.
    static func matches(host: String, pattern: String) -> Bool {
        if pattern == host { return true }
        guard pattern.hasPrefix("*.") else { return false }
        let suffix = pattern.dropFirst()
        guard host.hasSuffix(suffix) else { return false }
        let label = host.dropLast(suffix.count)
        return !label.isEmpty && !label.contains(".")
    }
}
