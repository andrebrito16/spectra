//
//  Log.swift
//  Spectra
//
//  App-wide logging facade over os.Logger, mirrored to a rotating log file in
//  Application Support. Replaces Freelens's winston-based `packages/logger`.
//  NEVER log secrets or tokens.
//

import Foundation
import os

/// Logical subsystems, one per major area, so logs can be filtered in Console.app
/// and in the rotating diagnostics file.
nonisolated enum LogCategory: String, CaseIterable, Sendable {
    case app
    case auth
    case client
    case informer
    case discovery
    case helm
    case shell
    case metrics
    case ui
    case persistence
}

nonisolated enum LogLevel: Int, Sendable, Comparable {
    case debug = 0, info, notice, warning, error

    static func < (lhs: LogLevel, rhs: LogLevel) -> Bool { lhs.rawValue < rhs.rawValue }

    var label: String {
        switch self {
        case .debug: return "DEBUG"
        case .info: return "INFO"
        case .notice: return "NOTE"
        case .warning: return "WARN"
        case .error: return "ERROR"
        }
    }
}

/// Global logging entry point. All methods are `nonisolated` so any actor can log.
nonisolated enum Log {
    static let subsystem = "app.spectra.Spectra"

    /// Minimum level that reaches the console + file sink. Configurable from
    /// Preferences (Phase 12); defaults to `.info` in release, `.debug` in debug.
    nonisolated(unsafe) static var minimumLevel: LogLevel = {
        #if DEBUG
        return .debug
        #else
        return .info
        #endif
    }()

    private static let loggers: [LogCategory: Logger] = {
        var map: [LogCategory: Logger] = [:]
        for category in LogCategory.allCases {
            map[category] = Logger(subsystem: subsystem, category: category.rawValue)
        }
        return map
    }()

    static func debug(_ message: @autoclosure () -> String, _ category: LogCategory = .app) {
        emit(.debug, category, message())
    }

    static func info(_ message: @autoclosure () -> String, _ category: LogCategory = .app) {
        emit(.info, category, message())
    }

    static func notice(_ message: @autoclosure () -> String, _ category: LogCategory = .app) {
        emit(.notice, category, message())
    }

    static func warning(_ message: @autoclosure () -> String, _ category: LogCategory = .app) {
        emit(.warning, category, message())
    }

    static func error(_ message: @autoclosure () -> String, _ category: LogCategory = .app) {
        emit(.error, category, message())
    }

    private static func emit(_ level: LogLevel, _ category: LogCategory, _ message: String) {
        guard level >= minimumLevel else { return }
        let logger = loggers[category] ?? Logger(subsystem: subsystem, category: category.rawValue)
        switch level {
        case .debug: logger.debug("\(message, privacy: .public)")
        case .info: logger.info("\(message, privacy: .public)")
        case .notice: logger.notice("\(message, privacy: .public)")
        case .warning: logger.warning("\(message, privacy: .public)")
        case .error: logger.error("\(message, privacy: .public)")
        }
        FileLogSink.shared.append(level: level, category: category, message: message)
    }
}

/// Thread-safe, size-rotating file sink. Writes to
/// `~/Library/Application Support/Spectra/Logs/spectra.log`
/// (`Spectra Canary/Logs/` for canary builds).
nonisolated final class FileLogSink: @unchecked Sendable {
    static let shared = FileLogSink()

    private let queue = DispatchQueue(label: "app.spectra.logsink")
    private let maxBytes = 5 * 1024 * 1024
    private let fileURL: URL
    private let backupURL: URL
    private let formatter: ISO8601DateFormatter
    private var handle: FileHandle?

    /// Directory that holds the rotating logs; surfaced by "Reveal diagnostics" (Phase 12).
    let directory: URL

    private init() {
        let base = (try? FileManager.default.url(
            for: .applicationSupportDirectory, in: .userDomainMask,
            appropriateFor: nil, create: true))
            ?? URL(fileURLWithPath: NSTemporaryDirectory())
        directory = base.appendingPathComponent("\(AppInfo.supportDirectoryName)/Logs", isDirectory: true)
        fileURL = directory.appendingPathComponent("spectra.log")
        backupURL = directory.appendingPathComponent("spectra.1.log")
        formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        try? FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
    }

    func append(level: LogLevel, category: LogCategory, message: String) {
        let timestamp = formatter.string(from: Date())
        let line = "\(timestamp) [\(level.label)] [\(category.rawValue)] \(message)\n"
        queue.async { [weak self] in
            self?.write(line)
        }
    }

    private func write(_ line: String) {
        guard let data = line.data(using: .utf8) else { return }
        if handle == nil {
            if !FileManager.default.fileExists(atPath: fileURL.path) {
                FileManager.default.createFile(atPath: fileURL.path, contents: nil)
            }
            handle = try? FileHandle(forWritingTo: fileURL)
            try? handle?.seekToEnd()
        }
        guard let handle else { return }
        try? handle.write(contentsOf: data)
        rotateIfNeeded()
    }

    private func rotateIfNeeded() {
        guard let size = try? handle?.offset(), size > UInt64(maxBytes) else { return }
        do { try handle?.close() } catch {}
        handle = nil
        _ = try? FileManager.default.removeItem(at: backupURL)
        _ = try? FileManager.default.moveItem(at: fileURL, to: backupURL)
    }
}
