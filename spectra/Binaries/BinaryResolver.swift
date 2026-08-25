//
//  BinaryResolver.swift
//  Spectra
//
//  Resolves `kubectl`/`helm` paths. A GUI app launched by Launchd does NOT
//  inherit the shell PATH, so tools installed via Homebrew, mise, or asdf are
//  invisible unless we look in their well-known locations. Order: bundled →
//  well-known dirs (incl. mise/asdf shims) + PATH → `mise/asdf which` →
//  login-shell `command -v`. Phase 12's BinaryManager builds on this.
//

import Foundation

nonisolated enum BinaryResolver {
    static func path(for tool: String, extraPATH: String = "") -> String? {
        if let bundled = bundledPath(for: tool) { return bundled }
        for dir in searchDirs(extraPATH: extraPATH) {
            let candidate = "\(dir)/\(tool)"
            if FileManager.default.isExecutableFile(atPath: candidate) {
                return candidate
            }
        }
        if let managed = resolveViaVersionManager(tool, extraPATH: extraPATH) {
            return managed
        }
        return resolveViaLoginShell(tool)
    }

    static func bundledPath(for tool: String) -> String? {
        #if arch(arm64)
        let arch = "arm64"
        #else
        let arch = "x86_64"
        #endif
        guard let resourceURL = Bundle.main.resourceURL else { return nil }
        let candidate = resourceURL.appendingPathComponent("binaries/\(arch)/\(tool)").path
        return FileManager.default.isExecutableFile(atPath: candidate) ? candidate : nil
    }

    /// Well-known tool locations + the user's extra PATH + the inherited PATH,
    /// de-duplicated, in priority order.
    static func searchDirs(extraPATH: String) -> [String] {
        let home = NSHomeDirectory()
        var dirs: [String] = []
        dirs += extraPATH.split(separator: ":").map(String.init)
        dirs += [
            "/opt/homebrew/bin", "/opt/homebrew/sbin",   // Homebrew (Apple Silicon)
            "/usr/local/bin",                            // Homebrew (Intel) / generic
            "\(home)/.local/bin",
            "\(home)/.local/share/mise/shims",           // mise shims
            "\(home)/.asdf/shims",                       // asdf shims
            "/usr/bin", "/bin",
        ]
        if let envPath = ProcessInfo.processInfo.environment["PATH"] {
            dirs += envPath.split(separator: ":").map(String.init)
        }
        var seen = Set<String>()
        return dirs.filter { !$0.isEmpty && seen.insert($0).inserted }
    }

    /// Ask mise/asdf directly where a tool lives (`mise which <tool>`).
    /// The shim-dir scan is not enough: both managers only create shims for
    /// binaries present when the tool version was installed, so a component
    /// added afterwards (e.g. gke-gcloud-auth-plugin inside a mise-managed
    /// gcloud) has no shim. The login-shell fallback can't see it either —
    /// `mise activate` typically lives in .zshrc, which non-interactive login
    /// shells never read.
    private static func resolveViaVersionManager(_ tool: String, extraPATH: String) -> String? {
        for manager in ["mise", "asdf"] {
            let managerPath = searchDirs(extraPATH: extraPATH)
                .map { "\($0)/\(manager)" }
                .first { FileManager.default.isExecutableFile(atPath: $0) }
            guard let managerPath else { continue }
            let process = Process()
            process.executableURL = URL(fileURLWithPath: managerPath)
            process.arguments = ["which", tool]
            let pipe = Pipe()
            process.standardOutput = pipe
            process.standardError = Pipe()
            do {
                try process.run()
            } catch {
                continue
            }
            let data = pipe.fileHandleForReading.readDataToEndOfFile()
            process.waitUntilExit()
            guard process.terminationStatus == 0 else { continue }
            let path = String(data: data, encoding: .utf8)?
                .trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
            if FileManager.default.isExecutableFile(atPath: path) { return path }
        }
        return nil
    }

    /// Last resort: ask the user's login shell to resolve the tool (catches
    /// non-standard setups). Runs synchronously, so only reached if the dir
    /// scan above fails.
    private static func resolveViaLoginShell(_ tool: String) -> String? {
        let shell = ProcessInfo.processInfo.environment["SHELL"] ?? "/bin/zsh"
        let process = Process()
        process.executableURL = URL(fileURLWithPath: shell)
        process.arguments = ["-lc", "command -v \(tool)"]
        let pipe = Pipe()
        process.standardOutput = pipe
        process.standardError = Pipe()
        do {
            try process.run()
        } catch {
            return nil
        }
        let data = pipe.fileHandleForReading.readDataToEndOfFile()
        process.waitUntilExit()
        guard process.terminationStatus == 0 else { return nil }
        let path = String(data: data, encoding: .utf8)?
            .trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        return FileManager.default.isExecutableFile(atPath: path) ? path : nil
    }
}
