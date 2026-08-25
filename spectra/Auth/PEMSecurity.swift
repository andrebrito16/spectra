//
//  PEMSecurity.swift
//  Spectra
//
//  PEM → Security framework bridging for the TLS delegate: parse CA certificates
//  for custom anchor trust, and build a SecIdentity (cert + private key) for
//  client-certificate mTLS. Key material is handled in-memory / in 0600 temp
//  files that are deleted immediately; it is NEVER logged.
//

import Foundation
import Security

nonisolated enum PEMError: LocalizedError {
    case noCertificate
    case badCertificate
    case identityCreationFailed(String)

    var errorDescription: String? {
        switch self {
        case .noCertificate: return "No certificate found in PEM data"
        case .badCertificate: return "Certificate data could not be parsed"
        case .identityCreationFailed(let m): return "Could not build client identity: \(m)"
        }
    }
}

nonisolated enum PEM {
    /// Extract DER blocks of a given PEM type (e.g. "CERTIFICATE").
    static func derBlocks(fromPEM pem: String, type: String) -> [Data] {
        let begin = "-----BEGIN \(type)-----"
        let end = "-----END \(type)-----"
        var blocks: [Data] = []
        var searchRange = pem.startIndex..<pem.endIndex
        while let beginRange = pem.range(of: begin, range: searchRange),
              let endRange = pem.range(of: end, range: beginRange.upperBound..<pem.endIndex) {
            let base64 = pem[beginRange.upperBound..<endRange.lowerBound]
                .replacingOccurrences(of: "\n", with: "")
                .replacingOccurrences(of: "\r", with: "")
                .trimmingCharacters(in: .whitespaces)
            if let data = Data(base64Encoded: base64, options: .ignoreUnknownCharacters) {
                blocks.append(data)
            }
            searchRange = endRange.upperBound..<pem.endIndex
        }
        return blocks
    }

    /// Parse all certificates from PEM text into SecCertificates.
    static func certificates(fromPEM pem: String) -> [SecCertificate] {
        derBlocks(fromPEM: pem, type: "CERTIFICATE").compactMap {
            SecCertificateCreateWithData(nil, $0 as CFData)
        }
    }

    /// Parse certificates from either inline PEM text or a file path.
    static func certificates(pemData: Data?, pemFile: String?) -> [SecCertificate] {
        if let pemData, let text = String(data: pemData, encoding: .utf8) {
            let certs = certificates(fromPEM: text)
            if !certs.isEmpty { return certs }
        }
        if let pemFile, let text = try? String(contentsOfFile: pemFile, encoding: .utf8) {
            return certificates(fromPEM: text)
        }
        return []
    }
}

/// Builds a SecIdentity from PEM cert + key for client-certificate mTLS.
///
/// Implementation note: macOS has no public API to assemble a SecIdentity from a
/// loose cert + key without a keychain or a PKCS#12 blob. We convert the PEM pair
/// into an ephemeral, password-protected PKCS#12 via the system `openssl` and
/// import it with `SecPKCS12Import`. Temp files are 0600 and removed immediately.
nonisolated enum ClientIdentityFactory {
    static func makeIdentity(certPEM: String, keyPEM: String) throws -> SecIdentity {
        let fm = FileManager.default
        let dir = fm.temporaryDirectory.appendingPathComponent("spectra-mtls-\(UUID().uuidString)")
        try fm.createDirectory(at: dir, withIntermediateDirectories: true,
                               attributes: [.posixPermissions: 0o700])
        defer { try? fm.removeItem(at: dir) }

        let certURL = dir.appendingPathComponent("cert.pem")
        let keyURL = dir.appendingPathComponent("key.pem")
        let p12URL = dir.appendingPathComponent("identity.p12")
        let passphrase = UUID().uuidString

        try writeSecure(certPEM, to: certURL)
        try writeSecure(keyPEM, to: keyURL)

        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/openssl")
        process.arguments = [
            "pkcs12", "-export",
            "-inkey", keyURL.path,
            "-in", certURL.path,
            "-out", p12URL.path,
            "-passout", "pass:\(passphrase)",
        ]
        let errPipe = Pipe()
        process.standardError = errPipe
        process.standardOutput = Pipe()
        try process.run()
        process.waitUntilExit()
        guard process.terminationStatus == 0 else {
            let err = String(data: errPipe.fileHandleForReading.readDataToEndOfFile(),
                             encoding: .utf8) ?? "openssl failed"
            throw PEMError.identityCreationFailed(err)
        }

        let p12Data = try Data(contentsOf: p12URL)
        let options: [String: Any] = [kSecImportExportPassphrase as String: passphrase]
        var items: CFArray?
        let status = SecPKCS12Import(p12Data as CFData, options as CFDictionary, &items)
        guard status == errSecSuccess,
              let array = items as? [[String: Any]],
              let first = array.first,
              let identityRef = first[kSecImportItemIdentity as String] else {
            throw PEMError.identityCreationFailed("SecPKCS12Import status \(status)")
        }
        return identityRef as! SecIdentity
    }

    private static func writeSecure(_ text: String, to url: URL) throws {
        try text.write(to: url, atomically: true, encoding: .utf8)
        try FileManager.default.setAttributes([.posixPermissions: 0o600],
                                              ofItemAtPath: url.path)
    }
}
