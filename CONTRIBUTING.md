# Contributing to Spectra

Issues and pull requests are welcome. For setup and architecture, start with [README.md](README.md) and [CLAUDE.md](CLAUDE.md).

## Development

- Use macOS 26 or newer and Xcode with the Metal toolchain installed.
- Keep changes focused and follow the existing SwiftUI resource configuration patterns.
- Run `bash scripts/test-resource-features.sh` and `python3 scripts/prepare-licenses.py --check`.
- Build Debug and Release with `CODE_SIGNING_ALLOWED=NO` if you do not have a signing identity. Signing is not needed to contribute source changes.
- Describe the problem, resulting behavior, validation, and any cluster types you tested in your pull request. Include screenshots for visual changes when useful.

## Licensing and provenance

Contributions intentionally submitted for inclusion are under Apache-2.0, as described in section 5 of [LICENSE](LICENSE). Submit only work you have the right to contribute. Identify any copied or adapted code, fonts, images, or other assets and preserve their original notices. For dependency changes, follow [THIRD_PARTY_NOTICES.md](THIRD_PARTY_NOTICES.md).

## Safe bug reports

Use synthetic manifests and redact kubeconfig credentials, tokens, private keys, cluster endpoints, and identifying resource data from logs and screenshots. Report vulnerabilities through the private process in [SECURITY.md](SECURITY.md), rather than a public issue.

Be respectful and constructive. Explain technical disagreements and avoid personal attacks, harassment, and sharing another person's private information.
