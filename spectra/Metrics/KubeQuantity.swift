//
//  KubeQuantity.swift
//  Spectra
//
//  Parses Kubernetes resource quantities (CPU cores, memory bytes) including
//  SI (m, k, M, G…) and binary (Ki, Mi, Gi…) suffixes. Used for metrics-server
//  usage and Node capacity/allocatable.
//

import Foundation

nonisolated enum KubeQuantity {
    /// Parse a CPU quantity into cores (e.g. "500m" → 0.5, "468173891n" → 0.468).
    static func cpuCores(_ string: String?) -> Double? {
        guard let string, !string.isEmpty else { return nil }
        let suffixes: [(String, Double)] = [
            ("n", 1e-9), ("u", 1e-6), ("m", 1e-3),
            ("k", 1e3), ("M", 1e6), ("G", 1e9),
        ]
        for (suffix, factor) in suffixes where string.hasSuffix(suffix) {
            if let value = Double(string.dropLast(suffix.count)) { return value * factor }
        }
        return Double(string)
    }

    /// Parse a memory quantity into bytes (e.g. "18484Mi" → bytes).
    static func memoryBytes(_ string: String?) -> Double? {
        guard let string, !string.isEmpty else { return nil }
        let binary: [(String, Double)] = [
            ("Ki", 1024), ("Mi", 1_048_576), ("Gi", 1_073_741_824),
            ("Ti", 1_099_511_627_776), ("Pi", 1_125_899_906_842_624),
        ]
        for (suffix, factor) in binary where string.hasSuffix(suffix) {
            if let value = Double(string.dropLast(suffix.count)) { return value * factor }
        }
        let decimal: [(String, Double)] = [
            ("k", 1e3), ("M", 1e6), ("G", 1e9), ("T", 1e12), ("P", 1e15),
        ]
        for (suffix, factor) in decimal where string.hasSuffix(suffix) {
            if let value = Double(string.dropLast(suffix.count)) { return value * factor }
        }
        return Double(string)
    }

    /// Human-readable bytes (e.g. 1.5 GiB).
    static func formatBytes(_ bytes: Double) -> String {
        let units = ["B", "KiB", "MiB", "GiB", "TiB"]
        var value = bytes, index = 0
        while value >= 1024 && index < units.count - 1 { value /= 1024; index += 1 }
        return String(format: "%.1f%@", value, units[index])
    }
}
