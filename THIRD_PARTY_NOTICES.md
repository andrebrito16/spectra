# Third-party notices

Spectra's original code and assets are licensed under [Apache-2.0](LICENSE). Third-party components keep their own licenses. The full texts and copyright notices are in [licenses](licenses/) and the generated [app notices](spectra/Resources/OpenSourceNotices.txt), available through **Help → Open Source Licenses** in the built app.

| Component | Version / inclusion | License |
| --- | --- | --- |
| Yams | 5.4.0; linked YAML library | MIT |
| Sparkle | 2.6.4; linked OTA update framework | MIT and included external notices |
| LibYAML | Embedded by Yams as CYaml | MIT |
| SwiftTerm | 1.13.0; linked terminal library | MIT |
| xterm.js, SourceLair, Christopher Jeffrey | Attributions preserved in SwiftTerm's license | MIT |
| libsixel | Color conversion code identified by SwiftTerm as a port | MIT |
| Ghostty | URL/path pattern identified by SwiftTerm as adapted | MIT |
| Swift Argument Parser | 1.8.1; resolved for SwiftTerm's separate termcast tool, not linked into Spectra | Apache-2.0 with Swift exception |

Exact Swift package revisions, license sources, and inclusion notes are recorded in [the inventory](licenses/dependencies.json). The libsixel and Ghostty port comments do not identify originating revisions; the included upstream license copies were reviewed on 2026-09-15. They are attribution notices, not additional dependencies.

`kubectl`, `helm`, and credential plugins are external programs found on the user's machine. The current release script does not bundle them. If that changes, review and include their licenses before distribution.

macOS frameworks and SF Symbols are Apple platform resources used through system APIs. They are not relicensed by Spectra's Apache license. Lens, Freelens, and Arc are design references; Spectra does not include their code or artwork, as confirmed by the maintainer.

## Updating dependencies

1. Review the changed dependency's license, embedded components, copyright notices, and target dependencies.
2. Update the license copies and `licenses/dependencies.json` to match `Package.resolved`.
3. Run `python3 scripts/prepare-licenses.py` and commit the generated app notices.
4. Run `python3 scripts/prepare-licenses.py --check --app /path/to/Spectra.app` after building.

The check detects inventory drift and missing bundled notices. It does not replace the review of new dependencies or third-party material.
