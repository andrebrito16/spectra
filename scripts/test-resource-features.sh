#!/bin/bash
set -euo pipefail

# Compile the production discovery/navigation/resource models directly, without
# an app launch, a live cluster, package downloads, or a separate test target.
repo_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$repo_root"
test_build_dir="$repo_root/build/resource-feature-tests"
mkdir -p "$test_build_dir"

xcrun swiftc -swift-version 6 -default-isolation MainActor -parse-as-library \
  -module-cache-path "$test_build_dir/ModuleCache" \
  spectra/KubeClient/Model/JSONValue.swift \
  spectra/KubeClient/Model/KubeResource.swift \
  spectra/KubeClient/Model/GVR.swift \
  spectra/KubeClient/Model/ArgoCDFacets.swift \
  spectra/KubeClient/Model/GatewayFacets.swift \
  spectra/KubeClient/Discovery/APIResourceDiscovery.swift \
  spectra/UI/Shell/NavGrouping.swift \
  spectra/DesignSystem/ResourceKindIcon.swift \
  spectra/UI/ResourceList/CreateTemplates.swift \
  spectra/Auth/CredentialProvider.swift \
  spectra/Auth/Credential.swift \
  spectra/Auth/ExecCredential.swift \
  spectra/Kubeconfig/KubeconfigModels.swift \
  spectra/Binaries/BinaryResolver.swift \
  spectra/Core/Log.swift \
  spectra/Informers/ResourceLoadState.swift \
  spectra/Persistence/Models.swift \
  spectra/DesignSystem/Theme.swift \
  spectra/DesignSystem/ClusterStyle.swift \
  tests/ResourceFeatureChecks.swift \
  -o "$test_build_dir/resource-feature-checks"

"$test_build_dir/resource-feature-checks"
