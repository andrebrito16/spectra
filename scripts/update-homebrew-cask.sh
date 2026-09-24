#!/bin/bash
set -euo pipefail

version="${1:?Usage: $0 VERSION SHA256}"
sha256="${2:?Usage: $0 VERSION SHA256}"
cask="packaging/homebrew/Casks/spectra-k8s.rb"

python3 - "$cask" "$version" "$sha256" <<'PY'
from pathlib import Path
import sys
path, version, sha = Path(sys.argv[1]), sys.argv[2], sys.argv[3]
text = path.read_text()
text = text.replace('version "0.0.1"', f'version "{version}"')
text = text.replace('sha256 "REPLACE_WITH_RELEASE_SHA256"', f'sha256 "{sha}"')
path.write_text(text)
PY

echo "Updated $cask for v$version. Commit it to your Homebrew tap (for example homebrew-spectra/Casks/s/spectra-k8s.rb)."
