//
//  KubeError.swift
//  Spectra
//
//  Typed error surfaced across the client/connection layers and bubbled to the
//  notification/status-bar system. Decodes the Kubernetes `Status` object on API
//  errors. See 00-architecture §12.
//

import Foundation

/// The Kubernetes API `Status` object returned on errors.
nonisolated struct KubeStatus: Decodable, Sendable {
    var status: String?
    var message: String?
    var reason: String?
    var code: Int?
}

nonisolated enum KubeError: LocalizedError, Sendable {
    case invalidURL(String)
    case transport(String)
    case http(status: Int, reason: String?, message: String?)
    case unauthorized(String)
    case forbidden(String)
    case notFound(String)
    case conflict(String)
    case decoding(String)
    case auth(String)
    case apiStatus(KubeStatus)

    var errorDescription: String? {
        switch self {
        case .invalidURL(let u): return "Invalid URL: \(u)"
        case .transport(let m): return "Network error: \(m)"
        case .http(let status, let reason, let message):
            return "HTTP \(status)\(reason.map { " \($0)" } ?? "")\(message.map { ": \($0)" } ?? "")"
        case .unauthorized(let m): return "Unauthorized: \(m)"
        case .forbidden(let m): return "Forbidden: \(m)"
        case .notFound(let m): return "Not found: \(m)"
        case .conflict(let m): return "Conflict: \(m)"
        case .decoding(let m): return "Failed to decode response: \(m)"
        case .auth(let m): return "Authentication error: \(m)"
        case .apiStatus(let s):
            return s.message ?? s.reason ?? "Kubernetes API error"
        }
    }

    /// Short, human-friendly summary for status indicators.
    var shortDescription: String {
        switch self {
        case .invalidURL: return "invalid URL"
        case .transport(let m): return m
        case .http(let status, _, _): return "HTTP \(status)"
        case .unauthorized: return "unauthorized"
        case .forbidden: return "forbidden"
        case .notFound: return "not found"
        case .conflict: return "conflict"
        case .decoding: return "decode error"
        case .auth(let m): return m
        case .apiStatus(let s): return s.reason ?? "API error"
        }
    }

    /// Build a typed error from an HTTP status + optional decoded Status body.
    static func from(httpStatus: Int, data: Data) -> KubeError {
        let status = try? JSONDecoder().decode(KubeStatus.self, from: data)
        let message = status?.message
        switch httpStatus {
        case 401: return .unauthorized(message ?? "invalid credentials")
        case 403: return .forbidden(message ?? "access denied")
        case 404: return .notFound(message ?? "resource not found")
        case 409: return .conflict(message ?? "conflict")
        default:
            if let status { return .apiStatus(status) }
            return .http(status: httpStatus, reason: nil, message: message)
        }
    }
}
