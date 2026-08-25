//
//  PersistenceStore.swift
//  Spectra
//
//  Owns the SwiftData store location and a hardened container open.
//
//  Why this exists: Spectra used to persist to the OS-default location
//  (`~/Library/Application Support/default.store`) because `ModelConfiguration`
//  was built without an explicit `url`. That bare, effectively-shared path is
//  fragile — it intermittently failed to open ("default.store couldn't be
//  opened", NSSQLiteErrorDomain=1). A failed open left the cluster store reading
//  back empty, which (via the `hasPersistedClusters` guard in ClusterManager)
//  trapped the catalog on its "saved cluster list is empty" recovery screen on
//  every launch, with re-detect the only escape. We now keep the store in an
//  app-owned directory next to the logs (`Application Support/Spectra/`),
//  migrate the old file once, retry a transient open, and — only as a last
//  resort — quarantine an unopenable store so the app still launches instead of
//  crashing on `fatalError`.
//

import Foundation
import SwiftData

enum PersistenceStore {
    /// App-owned store location, alongside `Spectra/Logs`. Replaces the shared
    /// OS-default `~/Library/Application Support/default.store`.
    static var storeURL: URL {
        let dir = applicationSupport.appendingPathComponent("Spectra", isDirectory: true)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir.appendingPathComponent("Spectra.store")
    }

    /// Legacy OS-default location used before the store had an explicit URL.
    private static var legacyStoreURL: URL {
        applicationSupport.appendingPathComponent("default.store")
    }

    private static var applicationSupport: URL {
        (try? FileManager.default.url(
            for: .applicationSupportDirectory, in: .userDomainMask,
            appropriateFor: nil, create: true))
            ?? URL(fileURLWithPath: NSTemporaryDirectory())
    }

    /// SQLite keeps a `-wal` (write-ahead log) and `-shm` (shared memory) sidecar
    /// next to the main store; all three move/quarantine together.
    private static let sidecarSuffixes = ["", "-wal", "-shm"]

    /// Build the container at the app-owned URL. Migrates the legacy store once,
    /// retries a transient open failure, and only as a last resort quarantines an
    /// unopenable store so the app still launches (the catalog's recovery screen
    /// + the sticky `hasPersistedClusters` marker handle the resulting empty read).
    static func makeContainer(schema: Schema) -> ModelContainer {
        migrateLegacyStoreIfNeeded()
        let url = storeURL
        let configuration = ModelConfiguration(schema: schema, url: url)

        // Retry: a transient SQLite lock (another instance mid-shutdown, a slow
        // volume) can make the first open throw where the next succeeds.
        var lastError: Error?
        for attempt in 1...3 {
            do {
                return try ModelContainer(for: schema, configurations: configuration)
            } catch {
                lastError = error
                Log.error("ModelContainer open attempt \(attempt)/3 failed: \(error)", .persistence)
                Thread.sleep(forTimeInterval: 0.2)
            }
        }

        // Still failing after retries: move the on-disk store aside (preserved as
        // `*.corrupt` for manual recovery) and open a fresh one so we launch
        // rather than crash.
        quarantineStore(at: url)
        do {
            let container = try ModelContainer(for: schema, configurations: configuration)
            Log.error("Recovered with a fresh store after quarantining the unopenable one "
                      + "(original error: \(lastError.map { "\($0)" } ?? "unknown"))", .persistence)
            return container
        } catch {
            Log.error("ModelContainer open failed even with a fresh store: \(error)", .persistence)
            fatalError("Could not create ModelContainer: \(error)")
        }
    }

    /// One-time move of the legacy `default.store` (and its `-wal`/`-shm`
    /// sidecars) into the app-owned location, preserving existing data. Runs only
    /// while the destination is absent, so it never clobbers the new store.
    private static func migrateLegacyStoreIfNeeded() {
        let fm = FileManager.default
        let dest = storeURL
        let src = legacyStoreURL
        guard !fm.fileExists(atPath: dest.path), fm.fileExists(atPath: src.path) else { return }
        for suffix in sidecarSuffixes {
            let from = URL(fileURLWithPath: src.path + suffix)
            let to = URL(fileURLWithPath: dest.path + suffix)
            guard fm.fileExists(atPath: from.path) else { continue }
            do {
                try fm.moveItem(at: from, to: to)
            } catch {
                Log.error("Legacy store migration failed for \(from.lastPathComponent): \(error)",
                          .persistence)
            }
        }
        Log.info("Migrated cluster store from default.store to \(dest.lastPathComponent)", .persistence)
    }

    /// Rename an unopenable store (and sidecars) to `*.corrupt` so a fresh store
    /// can be created, keeping the bad file around for inspection. Overwrites any
    /// previous quarantine — we only need the most recent failure.
    private static func quarantineStore(at url: URL) {
        let fm = FileManager.default
        for suffix in sidecarSuffixes {
            let from = URL(fileURLWithPath: url.path + suffix)
            guard fm.fileExists(atPath: from.path) else { continue }
            let to = URL(fileURLWithPath: url.path + suffix + ".corrupt")
            try? fm.removeItem(at: to)
            try? fm.moveItem(at: from, to: to)
        }
        Log.error("Quarantined unopenable store at \(url.lastPathComponent) (renamed to *.corrupt)",
                  .persistence)
    }
}
