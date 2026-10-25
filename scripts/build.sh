#!/bin/bash
# Build calmtile.app (menu bar app) and the core self-test with plain swiftc.
# Needs only the Xcode Command Line Tools (no Xcode, no XCTest).
#
#   scripts/build.sh           build to build/calmtile.app and run the self-test
#   scripts/build.sh install   additionally copy to ~/Applications
set -euo pipefail
cd "$(dirname "$0")/.."

OUT=build
APP="$OUT/calmtile.app"
WORK="$(mktemp -d)"
trap 'rm -rf "$WORK"' EXIT
mkdir -p "$OUT" "$WORK/mc" "$WORK/app" "$WORK/test"

# The sources are split in two SwiftPM targets; for swiftc we compile them as one module.
strip_import() { sed '/^import CalmCore/d' "$1" > "$2"; }

echo "== self-test"
strip_import Sources/calmcore-selftest/main.swift "$WORK/test/main.swift"
swiftc -module-cache-path "$WORK/mc" -o "$WORK/test/selftest" Sources/CalmCore/*.swift "$WORK/test/main.swift"
"$WORK/test/selftest"

echo "== app"
for f in Sources/calmtile/*.swift; do strip_import "$f" "$WORK/app/$(basename "$f")"; done
rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS"
swiftc -O -module-cache-path "$WORK/mc" -o "$APP/Contents/MacOS/calmtile" Sources/CalmCore/*.swift "$WORK/app"/*.swift

cat > "$APP/Contents/Info.plist" <<'PLIST'
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
  <key>CFBundleIdentifier</key><string>local.calmtile</string>
  <key>CFBundleName</key><string>calmtile</string>
  <key>CFBundleExecutable</key><string>calmtile</string>
  <key>CFBundlePackageType</key><string>APPL</string>
  <key>CFBundleShortVersionString</key><string>0.1.0</string>
  <key>LSUIElement</key><true/>
  <key>LSMinimumSystemVersion</key><string>11.0</string>
</dict>
</plist>
PLIST

# Sign with a stable identity when one exists (override with CALMTILE_SIGN_ID): macOS then keeps the
# Accessibility permission across rebuilds. An ad-hoc signature changes every build and loses it.
SIGN_ID="${CALMTILE_SIGN_ID:-$(security find-identity -v -p codesigning | awk '/Apple Development/ {print $2; exit}')}"
if [ -n "$SIGN_ID" ]; then
  codesign --force --sign "$SIGN_ID" "$APP"
else
  echo "no signing identity found: ad-hoc signature (Accessibility must be re-granted after each build)"
  codesign --force --sign - "$APP"
fi
echo "built $APP"

if [ "${1:-}" = "install" ]; then
  mkdir -p "$HOME/Applications"
  rm -rf "$HOME/Applications/calmtile.app"
  cp -R "$APP" "$HOME/Applications/calmtile.app"
  echo "installed ~/Applications/calmtile.app"
fi
