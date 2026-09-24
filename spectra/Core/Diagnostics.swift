//
//  Diagnostics.swift
//  Spectra
//
//  Diagnostics surface (Phase 12): reveal the rotating logs in Finder and
//  collect a bundle (logs + app/cluster versions) for bug reports. Logs never
//  contain secrets/tokens, so the bundle needs no extra scrubbing.
//

import Foundation
import AppKit

@MainActor
enum Diagnostics {
    /// Reveal the diagnostics logs directory in Finder.
    static func revealLogs() {
        NSWorkspace.shared.activateFileViewerSelecting([FileLogSink.shared.directory])
    }

    /// Collect a zipped diagnostics bundle and reveal it. Returns the zip URL.
    @discardableResult
    static func collect(appVersion: String, clusterSummaries: [String]) -> URL? {
        let fm = FileManager.default
        let stamp = ISO8601DateFormatter().string(from: Date())
            .replacingOccurrences(of: ":", with: "-")
        let bundleDir = fm.temporaryDirectory
            .appendingPathComponent("spectra-diagnostics-\(stamp)", isDirectory: true)
        try? fm.createDirectory(at: bundleDir, withIntermediateDirectories: true)

        // Copy log files.
        let logsDir = FileLogSink.shared.directory
        if let logs = try? fm.contentsOfDirectory(at: logsDir, includingPropertiesForKeys: nil) {
            for log in logs {
                try? fm.copyItem(at: log, to: bundleDir.appendingPathComponent(log.lastPathComponent))
            }
        }

        // Write versions summary.
        let summary = """
        \(AppInfo.displayName) \(appVersion)
        macOS \(ProcessInfo.processInfo.operatingSystemVersionString)
        Generated \(stamp)

        Clusters:
        \(clusterSummaries.map { "- \($0)" }.joined(separator: "\n"))
        """
        try? summary.write(to: bundleDir.appendingPathComponent("versions.txt"),
                           atomically: true, encoding: .utf8)

        // Zip via the system `zip` tool.
        let zipURL = bundleDir.appendingPathExtension("zip")
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/zip")
        process.arguments = ["-r", "-q", zipURL.path, bundleDir.lastPathComponent]
        process.currentDirectoryURL = bundleDir.deletingLastPathComponent()
        try? process.run()
        process.waitUntilExit()

        let result = fm.fileExists(atPath: zipURL.path) ? zipURL : bundleDir
        NSWorkspace.shared.activateFileViewerSelecting([result])
        return result
    }
}
