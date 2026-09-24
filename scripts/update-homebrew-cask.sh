#!/bin/bash
set -euo pipefail

version="${1:?Usage: $0 VERSION SHA256}"
sha256="${2:?Usage: $0 VERSION SHA256}"
cask="packaging/homebrew/Casks/spectra-k8s.rb"

python3 - "$cask" "$version" "$sha256" <<'PY'
from pathlib import Path
import re, sys
path, version, sha = Path(sys.argv[1]), sys.argv[2], sys.argv[3]
text = path.read_text()
text = re.sub(r'version "[^"]+"', f'version "{version}"', text)
text = re.sub(r'sha256 "[^"]+"', f'sha256 "{sha}"', text)
path.write_text(text)
PY

echo "Updated $cask for v$version. Commit it to your Homebrew tap (homebrew-spectra-k8s/Casks/spectra-k8s.rb)."
