#!/bin/bash
# Builds the current checkout as "Spectra Canary" and installs it next to the
# stable app. The Canary configuration is Release-optimised but uses its own
# bundle id (com.andrebritodev.spectra.canary), product name, yellow icon,
# Application Support folder and no Sparkle — so both apps run side by side.
#
#   scripts/canary.sh              build, install to /Applications, launch
#   scripts/canary.sh --no-launch  build + install only
#   CANARY_DEST=~/Applications scripts/canary.sh   install somewhere else
set -euo pipefail

cd "$(dirname "$0")/.."
BUILD_DIR=build/canary
DEST_DIR="${CANARY_DEST:-/Applications}"
APP_NAME="Spectra Canary"
LAUNCH=1
[[ "${1:-}" == "--no-launch" ]] && LAUNCH=0

# Version the build so Settings shows which commit is installed:
#   0.0.1-canary.9d42d9b (202609241730), "+dirty" when the tree has local edits.
BASE_VERSION=$(sed -nE 's/.*MARKETING_VERSION = ([^;]+);/\1/p' spectra.xcodeproj/project.pbxproj | head -1)
SHA=$(git rev-parse --short HEAD)
DIRTY=""; git diff --quiet HEAD -- . ':!build' 2>/dev/null || DIRTY="+dirty"
VERSION="${BASE_VERSION}-canary.${SHA}${DIRTY}"
BUILD_NUMBER=$(date +%Y%m%d%H%M)

echo "==> Building $APP_NAME $VERSION ($BUILD_NUMBER)"
xcodebuild -project spectra.xcodeproj -scheme spectra -configuration Canary \
  -destination 'platform=macOS' -derivedDataPath "$BUILD_DIR" \
  MARKETING_VERSION="$VERSION" CURRENT_PROJECT_VERSION="$BUILD_NUMBER" \
  build 2>&1 | grep -E "error:|BUILD (SUCCEEDED|FAILED)" || true

APP="$BUILD_DIR/Build/Products/Canary/$APP_NAME.app"
[[ -d "$APP" ]] || { echo "Build failed: $APP not found" >&2; exit 1; }
[[ "$(/usr/libexec/PlistBuddy -c 'Print :CFBundleIdentifier' "$APP/Contents/Info.plist")" == "com.andrebritodev.spectra.canary" ]] \
  || { echo "Refusing to install: bundle id is not the canary one" >&2; exit 1; }

echo "==> Installing to $DEST_DIR/$APP_NAME.app"
pkill -x "$APP_NAME" 2>/dev/null && sleep 1 || true
rm -rf "$DEST_DIR/$APP_NAME.app"
ditto "$APP" "$DEST_DIR/$APP_NAME.app"

if [[ $LAUNCH == 1 ]]; then
  echo "==> Launching"
  open "$DEST_DIR/$APP_NAME.app"
fi
echo "Done: $APP_NAME $VERSION installed at $DEST_DIR/$APP_NAME.app"
