#!/usr/bin/env python3
"""Generate/check the notices copied into Spectra.app by Xcode. No network use."""
import argparse
import json
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent
parser = argparse.ArgumentParser(description=__doc__)
parser.add_argument("--check", action="store_true", help="Fail if the inventory or bundled notices are stale")
parser.add_argument("--app", type=Path, help="Also verify notices inside a built .app")
args = parser.parse_args()

inventory = json.loads((ROOT / "licenses/dependencies.json").read_text())
resolved = json.loads((ROOT / "spectra.xcodeproj/project.xcworkspace/xcshareddata/swiftpm/Package.resolved").read_text())
pins = {pin["identity"]: {key: pin["state"].get(key) for key in ("version", "revision")} for pin in resolved["pins"]}
if pins != inventory["packages"]:
    raise SystemExit("Dependencies changed. Review upstream licenses and update licenses/dependencies.json before generating notices.")

sections = ["Spectra — Open Source Licenses\n\n" + (ROOT / "NOTICE").read_text().strip(),
            "Spectra — Apache License 2.0\n\n" + (ROOT / "LICENSE").read_text().strip()]
for notice in inventory["notices"]:
    license_text = (ROOT / "licenses" / notice["file"]).read_text().strip()
    if not license_text or "license" not in license_text.lower() and "permission" not in license_text.lower():
        raise SystemExit(f"Missing or invalid license text: {notice['file']}")
    sections.append(f"{notice['name']} — {notice['license']}\n{notice['source']}\n{notice['scope']}\n\n{license_text}")
expected = ("\n\n" + "=" * 72 + "\n\n").join(sections) + "\n"
output = ROOT / "spectra/Resources/OpenSourceNotices.txt"
if args.check:
    if not output.exists() or output.read_text() != expected:
        raise SystemExit("Bundled notices are stale. Run python3 scripts/prepare-licenses.py and commit the result.")
else:
    output.parent.mkdir(parents=True, exist_ok=True)
    output.write_text(expected)

if args.app:
    resources = args.app / "Contents/Resources"
    candidates = [resources / "OpenSourceNotices.txt", resources / "Resources/OpenSourceNotices.txt"]
    if not any(file.is_file() and file.read_text() == expected for file in candidates):
        raise SystemExit(f"Missing or outdated OpenSourceNotices.txt in {args.app}")
print("License inventory and notices verified." if args.check else f"Generated {output.relative_to(ROOT)}")
