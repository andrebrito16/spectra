# Spectra

A native macOS Kubernetes IDE in Swift 6 / SwiftUI — a from-scratch alternative to [Lens](https://k8slens.dev/) / [Freelens](https://freelens.app/).

> **Early alpha.** macOS 26 (Tahoe) only. Tested so far against a single EKS cluster. Expect rough edges. Bug reports and PRs welcome.

## Why

Lens-style Kubernetes IDEs today are Electron apps with a Node main process, a Chromium renderer, and a Go proxy per cluster. Spectra is a **single native process**: it speaks the Kubernetes API directly from Swift, with Liquid Glass chrome, fast launch, and no proxy hops.

## What works today

- Connect with `aws` exec auth, browse all built-in resources + CRDs live.
- Multi-cluster: kubeconfig auto-detect, per-cluster rename, **Arc-style switching** (MX Master 3 thumb-wheel side-scroll, sidebar swipe, ⌥⌘← / ⌥⌘→, indicator dots).
- Tabbed content area, collapsible sidebar (Workloads expanded by default), ⌘K command palette.
- Generic config-driven list/detail engine — Workloads, Config, Network, Storage, Cluster, RBAC, Helm.
- Argo CD menu: Applications, Application Sets, Projects, Rollouts, analysis runs/templates, and experiments, with sync, health, and rollout status.
- Network views for [Gateway API](https://gateway-api.sigs.k8s.io/concepts/api-overview/): Gateways, Gateway Classes, HTTP/GRPC/TLS/TCP/UDP Routes, and Reference Grants. Works with GKE and other Gateway API controllers; entries appear when their APIs are installed.
- Namespace filtering: click a name to select only that namespace; use the left checkboxes to select several while keeping the selector open.
- CRDs and their custom resources appear automatically (columns derived from CRD `additionalPrinterColumns`, no per-CRD code).
- Auth: client cert (mTLS), bearer token, `exec` plugins (aws / gke-gcloud-auth-plugin / kubelogin / doctl / …), OIDC.
- Native log streaming, SwiftTerm-backed terminal, pod / node shell (`kubectl debug node`), port-forward manager.
- Helm (v3 & v4 basic flows) via the bundled mise/brew/asdf-aware tool resolver.
- Metrics: auto-detects **Grafana Mimir** / Thanos / Prometheus (prefers Ingress URL because the EKS API-proxy often times out); node CPU/RAM bars via metrics-server.
- Rotating diagnostics log + "Collect Diagnostics" bundle for bug reports.
- Homebrew Cask and signed Sparkle OTA update packaging: see [OTA.md](OTA.md) and [packaging/homebrew/Casks/spectra.rb](packaging/homebrew/Casks/spectra.rb).

## What's missing / unverified

- No XCTest suite yet.
- No signed / notarized DMG release builds — clone and build from source.
- Verified against EKS; **GKE / AKS / kind / minikube unverified**.
- Some Freelens features still to port (hotbar, full Workloads dashboard, per-cluster bundled kubectl version, auto-update).

## Requirements

- macOS **26 (Tahoe)** or newer.
- Xcode **26.x** with the Metal Toolchain component (one-time download below).
- `kubectl` and `helm` somewhere standard (Homebrew, mise, asdf — the binary resolver finds them automatically).

## Build & run

```bash
# One-time: SwiftTerm uses Metal shaders, so the Metal toolchain is required.
xcodebuild -downloadComponent MetalToolchain

# Build
xcodebuild -project spectra.xcodeproj -scheme spectra \
  -configuration Debug -destination 'platform=macOS' build

# Launch
open ~/Library/Developer/Xcode/DerivedData/spectra-*/Build/Products/Debug/Spectra.app
```

Or just open `spectra.xcodeproj` in Xcode and press ⌘R.

## Resource regression checks

```bash
bash scripts/test-resource-features.sh
```

Compiles the production models and runs local fixtures for discovery across API versions, sidebar grouping, Gateway status, Argo resource fields, and create templates. Requires Xcode, with no cluster connection or app launch.

For a UI smoke check, connect to a cluster with Argo and Gateway API resources, open their new menu entries, and inspect a resource's details. In a namespaced list, check two namespace boxes, then click a namespace name: only that namespace should remain selected and the selector should close. Reopen it and verify that checkboxes preserve the other selections; **All Namespaces** clears the filter. Search and ↑/↓/Return should still work.

## Contributing

This is early — issues, discussions, and PRs all welcome. Quick orientation:

- [`CLAUDE.md`](CLAUDE.md) — architecture map, module layout, and the project-specific gotchas worth knowing before changing anything (Swift 6 isolation, the load-bearing ATS exception in `Info.plist`, why `KubeTLSDelegate` uses the sync completion-handler form, why GUI apps don't see your `$PATH`, why metrics go through Ingress instead of the API-proxy on EKS, …).
- New resource kinds are usually a **config**, not a screen — see `UI/Features/*Configs.swift` and the `ResourceConfig` / `ColumnDefinition` / `ObjectAction` types.

## Acknowledgments

Architecturally inspired by **[Freelens](https://freelens.app/)** (itself a fork of OpenLens). Where behavior is unclear, Spectra defers to Freelens's prior art.

Built with [Yams](https://github.com/jpsim/Yams) and [SwiftTerm](https://github.com/migueldeicaza/SwiftTerm).

## License

[Apache License 2.0](LICENSE).
