#!/bin/bash
# Builds, signs, notarizes, and packages Spectra.dmg for distribution.
# SKIP_ARCHIVE=1 ./scripts/release.sh reuses the existing archive/export.
set -euo pipefail

cd "$(dirname "$0")/.."
BUILD_DIR=build/release
ARCHIVE="$BUILD_DIR/Spectra.xcarchive"
EXPORT_DIR="$BUILD_DIR/export"
APP="$EXPORT_DIR/Spectra.app"
STAGING="$BUILD_DIR/dmg-staging"
DMG="$BUILD_DIR/Spectra.dmg"
NOTARY_PROFILE=spectra-notary
SIGN_IDENTITY="Developer ID Application: Andre Brito (U672XBMNSZ)"

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
