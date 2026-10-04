#!/bin/bash
# Builds build/NotchPlayer.app: the Swift binary plus the bundled
# mediaremote-adapter (Perl script + framework) it uses to read Now Playing.
set -euo pipefail
ROOT=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)
CONFIG=${CONFIG:-release}
APP="$ROOT/build/NotchPlayer.app"

if [ ! -e "$ROOT/build/MediaRemoteAdapter.framework/MediaRemoteAdapter" ]; then
  "$ROOT/scripts/build-adapter.sh"
fi

swift build -c "$CONFIG" --package-path "$ROOT"
BIN_DIR=$(swift build -c "$CONFIG" --package-path "$ROOT" --show-bin-path)

rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources" "$APP/Contents/Frameworks"
cp "$BIN_DIR/NotchPlayer" "$APP/Contents/MacOS/NotchPlayer"
cp "$ROOT/App/Info.plist" "$APP/Contents/Info.plist"
cp "$ROOT/vendor/mediaremote-adapter/bin/mediaremote-adapter.pl" "$APP/Contents/Resources/"
cp -R "$ROOT/build/MediaRemoteAdapter.framework" "$APP/Contents/Frameworks/"
# macOS ties permissions (Accessibility, Calendar, Location) to the signature.
# Ad-hoc signatures change on every build, so permissions reset; a real
# identity (e.g. "Apple Development", free with an Apple ID in Xcode) keeps
# them. Override with SIGN_IDENTITY=... if needed.
IDENTITY=${SIGN_IDENTITY:-$(security find-identity -v -p codesigning 2>/dev/null \
  | awk -F'"' '/Apple Development|Developer ID Application/ { print $2; exit }' || true)}
codesign --force --deep --sign "${IDENTITY:--}" "$APP"
echo "Built $APP"
