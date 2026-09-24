#!/bin/bash
# Builds, signs, notarizes, and packages versioned Spectra DMG/ZIP artifacts.
# SKIP_ARCHIVE=1 ./scripts/release.sh reuses the existing archive/export.
set -euo pipefail

cd "$(dirname "$0")/.."
BUILD_DIR=build/release
ARCHIVE="$BUILD_DIR/Spectra.xcarchive"
EXPORT_DIR="$BUILD_DIR/export"
APP="$EXPORT_DIR/Spectra.app"
STAGING="$BUILD_DIR/dmg-staging"
# Defaults to MARKETING_VERSION in the Xcode project so the artifact names
# always match the CFBundleShortVersionString baked into the app.
PROJECT_VERSION=$(sed -nE 's/.*MARKETING_VERSION = ([^;]+);/\1/p' spectra.xcodeproj/project.pbxproj | head -1)
RELEASE_VERSION="${RELEASE_VERSION:-$PROJECT_VERSION}"
DMG="$BUILD_DIR/Spectra-${RELEASE_VERSION}.dmg"
ZIP="$BUILD_DIR/Spectra-${RELEASE_VERSION}.zip"
NOTARY_PROFILE="${NOTARY_PROFILE:-spectra-notary}"
SIGN_IDENTITY="${SIGN_IDENTITY:-Developer ID Application: Andre Brito (U672XBMNSZ)}"

python3 scripts/prepare-licenses.py --check

if [[ "${SKIP_ARCHIVE:-0}" == "1" && -d "$APP" ]]; then
  echo "==> Reusing existing export at $APP"
else
  rm -rf "$ARCHIVE" "$EXPORT_DIR"

  echo "==> Archiving (Release, universal)"
  xcodebuild archive \
    -project spectra.xcodeproj -scheme spectra -configuration Release \
    -destination 'generic/platform=macOS' \
    -archivePath "$ARCHIVE" | tail -2

  echo "==> Exporting with Developer ID signing"
  xcodebuild -exportArchive \
    -archivePath "$ARCHIVE" \
    -exportOptionsPlist scripts/ExportOptions.plist \
    -exportPath "$EXPORT_DIR" | tail -2
fi

python3 scripts/prepare-licenses.py --check --app "$APP"
codesign --verify --deep --strict "$APP"
echo "==> Signature OK: $(codesign -dvv "$APP" 2>&1 | grep '^Authority=Developer ID' || true)"

if [[ ! -f scripts/dmg-background.tiff ]]; then
  echo "==> Generating DMG background"
  swift scripts/make-dmg-background.swift
fi

echo "==> Staging clean DMG contents (app only)"
rm -rf "$STAGING" "$DMG"
mkdir -p "$STAGING"
cp -R "$APP" "$STAGING/"

echo "==> Creating Sparkle OTA archive"
ditto -c -k --sequesterRsrc --keepParent "$APP" "$ZIP"
echo "OTA archive: $ZIP"

echo "==> Building drag-and-drop DMG"
create-dmg \
  --volname "Spectra" \
  --volicon "$APP/Contents/Resources/AppIcon.icns" \
  --background scripts/dmg-background.tiff \
  --window-pos 200 120 --window-size 600 400 --icon-size 128 \
  --icon "Spectra.app" 150 185 \
  --app-drop-link 450 185 \
  --no-internet-enable \
  "$DMG" "$STAGING"

echo "==> Signing the DMG"
codesign --sign "$SIGN_IDENTITY" --timestamp "$DMG"

echo "==> Notarizing (this waits for Apple, usually 1-5 min)"
xcrun notarytool submit "$DMG" --keychain-profile "$NOTARY_PROFILE" --wait

echo "==> Stapling ticket"
xcrun stapler staple "$DMG"

echo "==> Gatekeeper check"
spctl -a -t open --context context:primary-signature -v "$DMG"

echo
echo "Done: $DMG — ready to send to testers."
