//
//  ExecCredential.swift
//  Spectra
//
//  client.authentication.k8s.io ExecCredential model — the JSON contract between
//  kubectl-style exec credential plugins (aws, gke-gcloud-auth-plugin, kubelogin,
//  doctl) and the client. We write the request on stdin and parse the response.
//

import Foundation

nonisolated struct ExecCredential: Codable, Sendable {
    var apiVersion: String
    var kind: String
    var spec: ExecCredentialSpec?
    var status: ExecCredentialStatus?

    init(apiVersion: String, spec: ExecCredentialSpec? = nil, status: ExecCredentialStatus? = nil) {
        self.apiVersion = apiVersion
        self.kind = "ExecCredential"
        self.spec = spec
        self.status = status
    }
}

nonisolated struct ExecCredentialSpec: Codable, Sendable {
    var interactive: Bool?
}

nonisolated struct ExecCredentialStatus: Codable, Sendable {
    var expirationTimestamp: String?
    var token: String?
    var clientCertificateData: String?
    var clientKeyData: String?
}
