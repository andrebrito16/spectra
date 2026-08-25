//
//  Credential.swift
//  Spectra
//
//  Resolved request credentials produced by the CredentialProvider and consumed
//  by the API client (Authorization header) and the TLS delegate (client
//  identity for mTLS).
//

import Foundation

/// PEM cert + key for client-certificate mTLS (from kubeconfig or an exec plugin).
nonisolated struct ClientCertMaterial: Sendable, Equatable {
    var certPEM: String
    var keyPEM: String
}

/// The credential to apply to an outgoing request.
nonisolated struct RequestCredential: Sendable {
    /// Value for the `Authorization` header (e.g. "Bearer …" / "Basic …"), if any.
    var authorizationHeader: String?
    /// Client identity material for mTLS, if the user authenticates with a cert.
    var clientCert: ClientCertMaterial?
    /// When this credential expires (exec/OIDC) — nil means it does not expire.
    var expiresAt: Date?

    static let anonymous = RequestCredential()

    var isExpired: Bool {
        guard let expiresAt else { return false }
        // Refresh slightly early to avoid races near the boundary.
        return Date().addingTimeInterval(10) >= expiresAt
    }
}

nonisolated enum AuthError: LocalizedError {
    case execNotFound(command: String)
    case execFailed(command: String, status: Int32, stderr: String)
    case execBadOutput(String)
    case oidcUnsupported(String)
    case missingCredential

    var errorDescription: String? {
        switch self {
        case .execNotFound(let cmd):
            return "Credential plugin '\(cmd)' was not found — searched well-known tool "
                + "directories and the login shell PATH. Install it, or add its directory "
                + "under Settings → PATH."
        case .execFailed(let cmd, let status, let stderr):
            return "Credential plugin '\(cmd)' exited \(status): \(stderr)"
        case .execBadOutput(let detail):
            return "Credential plugin returned unexpected output: \(detail)"
        case .oidcUnsupported(let detail):
            return "OIDC auth-provider not fully supported: \(detail)"
        case .missingCredential:
            return "No usable credential found for this user"
        }
    }
}
