#!/usr/bin/env python3
"""Create a signed Sparkle appcast from a release archive and signature."""
import argparse
import hashlib
import html
from pathlib import Path

parser = argparse.ArgumentParser()
parser.add_argument("--version", required=True)
parser.add_argument("--build", required=True)
parser.add_argument("--archive", type=Path, required=True)
parser.add_argument("--signature", required=True, help="Base64 Ed25519 signature from Sparkle sign_update")
parser.add_argument("--output", type=Path, default=Path("appcast.xml"))
parser.add_argument("--download-url", required=True)
args = parser.parse_args()

archive = args.archive.resolve()
if not archive.is_file():
    raise SystemExit(f"Archive does not exist: {archive}")
size = archive.stat().st_size
sha = hashlib.sha256(archive.read_bytes()).hexdigest()
url = html.escape(args.download_url, quote=True)
signature = html.escape(args.signature.strip(), quote=True)
version = html.escape(args.version, quote=True)
build = html.escape(args.build, quote=True)

args.output.write_text(f'''<?xml version="1.0" encoding="utf-8"?>
<rss version="2.0" xmlns:sparkle="http://www.andymatuschak.org/xml-namespaces/sparkle">
  <channel>
    <title>Spectra Updates</title>
    <item>
      <title>Spectra {version}</title>
      <sparkle:releaseNotesLink>https://github.com/andrebrito16/spectra/releases/tag/v{version}</sparkle:releaseNotesLink>
      <pubDate>{__import__('email.utils').utils.formatdate(usegmt=True)}</pubDate>
      <sparkle:minimumSystemVersion>26.0</sparkle:minimumSystemVersion>
      <enclosure url="{url}" sparkle:version="{build}" sparkle:shortVersionString="{version}" length="{size}" type="application/octet-stream" sparkle:edSignature="{signature}" sparkle:sha256="{sha}" />
    </item>
  </channel>
</rss>
''')
print(f"Wrote {args.output} ({size} bytes, sha256 {sha})")
