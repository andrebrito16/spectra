# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## What this is

**Spectra** is a native macOS Kubernetes IDE (Swift 6 / SwiftUI / Liquid Glass) targeting macOS 26 (Tahoe), built as a feature-parity alternative to Freelens (Electron, in `reference/freelens/`). The 12-phase build plan is in `plan/` — start with `plan/00-architecture.md` and `plan/README.md` to understand intent before non-trivial work.

## Build / run

```bash
# Resolve SPM deps (Yams, SwiftTerm) — only needed manually if package state is stale
xcodebuild -resolvePackageDependencies -scheme spectra

# Debug build (always run from the repo root, with -project)
xcodebuild -project spectra.xcodeproj -scheme spectra -configuration Debug \
  -destination 'platform=macOS' build

# Release build (wholemodule, stricter — use as a final gate)
xcodebuild -project spectra.xcodeproj -scheme spectra -configuration Release \
  -destination 'platform=macOS' build

# Launch the built app (note the binary is Spectra.app, capital S — PRODUCT_NAME=Spectra)
open ~/Library/Developer/Xcode/DerivedData/spectra-*/Build/Products/Debug/Spectra.app
```

There is **no test target yet** (Phase 12 deliverable). When adding XCTest, the project uses an Xcode-16 file-system-synchronized root group (`PBXFileSystemSynchronizedRootGroup`), so files dropped under `spectra/` auto-compile — no `project.pbxproj` edits for source files.

### One-time prerequisite

SwiftTerm uses Metal shaders. On a fresh Xcode install the build fails with `cannot execute tool 'metal'`. Fix once:

```bash
xcodebuild -downloadComponent MetalToolchain
```

## Project-specific gotchas (real ones we hit)

These are non-obvious and have all caused build/runtime breakage; the cause is documented in commit/PR history of the relevant files.

- **Swift 6 + default MainActor isolation.** `SWIFT_DEFAULT_ACTOR_ISOLATION = MainActor` is on. UI types are MainActor automatically; **data/infra types must be marked `nonisolated`** (the model structs in `Kubeconfig/`, `Auth/`, `KubeClient/Model/`, `Metrics/`, `Informers/WatchEvent`, `Persistence/Models` enums, `Core/Log`, etc.). Symptom of missing this: `Decodable` conformance can't be used in nonisolated context, or `Cannot call value of non-function type 'Binding<Subject>'` cascades.
- **App is not sandboxed, ATS is disabled.** `spectra/Info.plist` sets `NSAppTransportSecurity.NSAllowsArbitraryLoads=true`. Without this, EKS (and any private-CA cluster) fails TLS with `-1200 / -9802` *even though* `KubeTLSDelegate` validates the CA correctly — ATS rejects the cert beneath the delegate. Do not remove this.
- **`KubeTLSDelegate` must use the sync completion-handler form**, not `async`. URLSession in the signed app context invokes the async form but does not honor its return value (trust evaluates `true`, connection still fails). The sync `@Sendable` completion-handler is the reliable form.
- **GUI apps launched by Launchd do NOT inherit your shell PATH.** `BinaryResolver` searches well-known dirs explicitly (Homebrew, mise shims at `~/.local/share/mise/shims`, asdf shims) plus a login-shell `command -v` fallback. Tools installed by mise/asdf are invisible without this. **Just as important: any child process we spawn (kubectl `port-forward`/`exec`/`debug`) must be given a real `PATH` in its `environment`, not the bare Launchd one** — otherwise kubectl launches but can't find the kubeconfig's exec credential plugin (`aws`, `aws-iam-authenticator`, `gke-gcloud-auth-plugin`), so on EKS/GKE the action dies immediately. Build the child `PATH` from `BinaryResolver.searchDirs(extraPATH:)` (see `AppEnvironment.toolPATH` and `PortForwardManager.start`). Also **read the child's stderr** — `kubectl port-forward` reports "no such resource", "address already in use", and missing-plugin errors there; an unread stderr pipe turns every failure into a silent "Stopped".
- **Exec credential plugins may be resolvable ONLY by asking the version manager itself.** mise/asdf create shims only for binaries present when the tool version was installed — a gcloud component added later (`gke-gcloud-auth-plugin`) gets **no shim**, and `mise activate` lives in `.zshrc`, which a non-interactive login shell (`zsh -lc`) never reads, so BinaryResolver's login-shell fallback misses it too. `BinaryResolver` therefore also tries `mise which` / `asdf which`. And never fall back to `/usr/bin/env` without prepending the command name: bare `env` exits 0 and prints the environment, which then surfaces as the baffling `Credential plugin returned unexpected output: … Unexpected character 'L'` (the first env var, e.g. `LaunchInstanceID=…`). `CredentialProvider` throws `AuthError.execNotFound` instead.
- **Metrics over the K8s API-server `/proxy/` to pods times out on EKS** (SG/NetworkPolicy). `MetricsService` discovers the metrics backend's service, then **prefers an Ingress URL** for it (Mimir/Thanos/Prom), querying directly via `URLSession.shared`; the API-server proxy is only the fallback.
- **`systemImage: ""`** is invalid — SF Symbols logs `No symbol named '' found` and can break menu rendering. For "show a checkmark only when selected" rows, use a conditional `Label`/`Text` (see `checkmarkLabel` in `ResourceListView`).
- **Don't starve the URLSession connection pool — `httpMaximumConnectionsPerHost` must stay generous (100).** Informers stay warm for the whole session (`ResourceStore.unsubscribe()` is a deliberate no-op) and `ResourceStore.restart` opens **one watch stream per selected namespace**, so a browsing user accumulates many concurrent long-lived `connection.bytes(...)` streams. Over HTTP/1.1 (e.g. via a corporate/EKS proxy, where streams can't multiplex) each stream pins a connection. A low cap (was 8) lets warm informers consume every slot; the next interactive stream (logs/exec) then **queues forever** until the `LogStreamer` 15s watchdog trips with the *misleading* `Timed out… The API server may be unable to reach this node's kubelet` error. Tell-tale: resource lists (same `bytes(for:)` path) work, but logs opened *afterward* fail. Set in `ClusterConnection` URLSession config.
- **The SwiftData store has an explicit, app-owned URL — never go back to the bare OS-default `default.store`.** The container is built by `PersistenceStore.makeContainer` (called from `SpectraApp.init`), which points `ModelConfiguration(url:)` at `~/Library/Application Support/Spectra/Spectra.store` (next to the logs), migrates the legacy `default.store` once, retries a transient open, and quarantines an unopenable store (`*.corrupt`) rather than `fatalError`. The original `ModelConfiguration(schema:isStoredInMemoryOnly:false)` (no `url`) put the store at the shared `~/Library/Application Support/default.store`, which intermittently failed to open (`NSCocoaErrorDomain 256 "default.store couldn't be opened", NSSQLiteErrorDomain=1`). An empty read then trips GUARD 2 in `ClusterManager.syncFromKubeconfig` (the `spectra.hasPersistedClusters` UserDefaults marker), pinning the catalog on the "Your saved cluster list is empty" recovery screen every launch — and re-detect can't restore the lost org grouping / custom names because they're gone from disk. Keep the store off the default path.

## Architecture in one screen

```
Kubeconfig/      YAML → Kubeconfig models; ClusterIdentity = md5(path:context)
Auth/            CredentialProvider (actor) — token / tokenFile / basic / exec plugin / OIDC.
                 TLSDelegate (sync @Sendable form) — CA anchor trust + mTLS via SecIdentity
                 built from openssl-converted PKCS#12.
KubeClient/
  Model/         JSONValue + KubeResource (dynamic, all kinds incl. CRDs) + GVR + KubeError +
                 typed facets (computed accessors on KubeResource, not separate structs).
  API/           KubeAPIClient (struct) — generic list/get/CRUD/patch/scale/evict/apply.
  Discovery/    server version, /api+/apis → GVR table, namespaces, SelfSubjectAccessReview.
Informers/       Informer (actor): list → watch via URLSession.bytes; relist on 410; backoff.
                 ResourceStore (@MainActor @Observable): ref-counted subs, byUID dedup,
                 ~250ms debounce flush.
ClusterSession/  ClusterConnection (actor: URLSession + delegate + CredentialProvider).
                 ClusterManager (@MainActor): registry, attach SwiftData, syncFromKubeconfig
                 on attach. ClusterSession (@MainActor): per-cluster runtime — client,
                 discovery, gvrs, namespaces, CRD cache (for printer columns), store cache.
                 PortForwardManager — kubectl port-forward processes + SwiftData persistence.
Metrics/         MetricsService (actor): Mimir/Thanos/Prom discovery → Ingress URL or proxy;
                 PromQLTemplates per scope; X-Scope-OrgID supported.
                 NodeMetricsProvider (@MainActor): polls metrics-server (metrics.k8s.io) for
                 node CPU/RAM bars (drives NodeUsageCell).
                 KubeQuantity — parses k8s quantities (Ki/Mi/Gi, n/u/m).
Helm/            HelmService (actor): shell out to helm CLI, --output json parsing.
Terminal/        TerminalView (NSViewRepresentable → SwiftTerm LocalProcessTerminalView).
Binaries/        BinaryResolver — brew / mise / asdf / login-shell.
UI/
  Shell/         MainWindow (NavigationSplitView + tab bar + dock + status bar),
                 NavigationModel (tabs[] + route + back/forward + UI flags),
                 SidebarView (collapsible DisclosureGroups; Workloads expanded by default),
                 ContentRouter (.id(route) — fixes view-switch refresh),
                 ContentTabBar, ClusterSideScroll (MX Master 3 thumbwheel switching),
                 DockRegion, StatusBarView, NotificationsOverlay, KeyboardShortcutsView.
  ResourceList/  ResourceListView (native SwiftUI Table + TableColumnForEach),
                 ResourceListConfig (ColumnDefinition + DetailSectionDef + ResourceCatalog),
                 CreateTemplates.
  ResourceDetail/ DetailDrawer, DetailSections (Metadata/Conditions/Events), ObjectActions
                 (universal + .scale/.logs/.shell/.nodeShell/.portForward interactions),
                 ScaleDialog, YAMLEditor (NSTextView), YAMLViewerSheet.
  Dock/          DockModel + LogView (native API streaming).
  Features/      Per-area configs registered into ResourceCatalog.shared at bootstrap
                 (WorkloadConfigs / ConfigNetworkStorageConfigs / ClusterScopeConfigs /
                 DockActions / Helm views / PortForwardsView / NodeUsageCell / PodDetail).
                 New kinds are added by registering a ResourceConfig — no bespoke views.
Catalog/         CatalogView, AddClusterView, CommandPalette, RenameClusterSheet.
App/             SpectraApp (@main), AppEnvironment (@MainActor @Observable — root DI),
                 AppCommands (menu bar bound to env), Notifications.
Core/            Log (os.Logger + rotating file sink in Application Support), Diagnostics.
Persistence/     SwiftData @Model: ClusterRecord, Favorite, SavedPortForward, AppSettings.
```

### The generic resource engine (the core abstraction)

Adding support for a new resource kind is **config-only**, not a new screen:

1. Add columns to a `ResourceConfig` in `UI/Features/*Configs.swift`. Optional fields: `detailSections` (drawer cards), `actions` (right-click + drawer menu — see `ObjectAction` + `ActionInteraction` for UI-routed actions like Logs/Shell/Scale/PortForward).
2. Register in the relevant `*Configs.register(into:)`, which is called from `FeatureRegistry.registerAll()` at bootstrap.
3. CRDs need **no code** — their columns come from `ClusterSession.printerColumns(forGVR:)` via the CRD's `additionalPrinterColumns`; their detail drawer falls back to Metadata/Conditions/Events/YAML automatically.

`ColumnDefinition.cell` is an optional `(KubeResource) -> AnyView` for custom cells (the node CPU/RAM bars use it).

### Cluster session lifecycle (where things start)

`AppEnvironment.openCluster(id)` → resets `NavigationModel` to an Overview tab → `ClusterManager.connect(id)` creates `ClusterConnection` (actor, opens authenticated `URLSession`) and `ClusterSession` (@MainActor, owns client/discovery/store cache) → on success, `session.bootstrap()` runs discovery (server version, GVR table, namespaces, CRD cache) and `NodeMetricsProvider.start(session:)` begins polling metrics-server. The sidebar nav tree is built from `session.gvrs` via `NavGrouping.build(...)`.

`ResourceListView` subscribes to `session.store(for: gvr)` on appear; the store reference-counts informers. `Informer` lists then watches (URLSession.bytes line-stream), relists on 410, debounces store updates ~250ms.

### Plan-driven development

When adding a feature, locate the matching phase doc under `plan/phase-*.md` first (each phase doc lists Freelens reference paths + acceptance criteria). Architectural invariants and tech-stack decisions are in `plan/00-architecture.md`. The Freelens source we're porting from is at `reference/freelens/` — when behavior is unclear, grep there before guessing.
