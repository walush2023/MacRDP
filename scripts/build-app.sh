#!/bin/bash
# Builds build/MacRDP.app. Bundles build/freerdp if present (run scripts/build-freerdp.sh first).
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
APP="$ROOT/build/MacRDP.app"
VERSION="$(cat "$ROOT/VERSION" 2>/dev/null || echo 0.1.0)"

# Code signing. A stable identity matters: the Keychain remembers which app may read a saved password by
# its signature. Ad-hoc signatures change on every build, so macOS would ask for the Keychain password
# again after each rebuild. Set SIGN_IDENTITY to choose one, or SIGN_IDENTITY=- to force ad-hoc.
if [ -z "${SIGN_IDENTITY:-}" ]; then
  IDS="$(security find-identity -v -p codesigning 2>/dev/null)"
  SIGN_IDENTITY="$( (echo "$IDS" | grep '"Developer ID Application'; echo "$IDS" | grep '"Apple Development') \
                    | head -1 | awk '{print $2}' || true)"
  SIGN_IDENTITY="${SIGN_IDENTITY:--}"
fi
# RELEASE=1 (set by scripts/release.sh) adds the hardened runtime and a secure timestamp, which
# notarization requires. Local builds skip the timestamp so they work offline and build faster.
if [ "${RELEASE:-0}" = 1 ] && [ "$SIGN_IDENTITY" != "-" ]; then
  SIGN_FLAGS=(--options runtime --timestamp)
else
  SIGN_FLAGS=(--timestamp=none)
fi
sign() { codesign --force "${SIGN_FLAGS[@]}" --sign "$SIGN_IDENTITY" "$@" >/dev/null 2>&1; }

cd "$ROOT"
echo "==> Compiling"
swift build -c release --arch arm64 >/dev/null
BIN="$(swift build -c release --arch arm64 --show-bin-path)/MacRDP"

echo "==> Self test"
"$BIN" --self-test

echo "==> Assembling $APP"
rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"
cp "$BIN" "$APP/Contents/MacOS/MacRDP"
cp "$ROOT/Resources/AppIcon.icns" "$APP/Contents/Resources/" 2>/dev/null || true

cat > "$APP/Contents/Info.plist" <<EOF
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
  <key>CFBundleName</key><string>MacRDP</string>
  <key>CFBundleDisplayName</key><string>MacRDP</string>
  <key>CFBundleIdentifier</key><string>com.walush.macrdp</string>
  <key>CFBundleExecutable</key><string>MacRDP</string>
  <key>CFBundlePackageType</key><string>APPL</string>
  <key>CFBundleShortVersionString</key><string>$VERSION</string>
  <key>CFBundleVersion</key><string>$VERSION</string>
  <key>CFBundleIconFile</key><string>AppIcon</string>
  <key>LSMinimumSystemVersion</key><string>14.0</string>
  <key>LSApplicationCategoryType</key><string>public.app-category.utilities</string>
  <key>NSHighResolutionCapable</key><true/>
  <key>NSPrincipalClass</key><string>NSApplication</string>
  <key>NSLocalNetworkUsageDescription</key><string>MacRDP connects to Remote Desktop PCs on your local network.</string>
  <key>NSMicrophoneUsageDescription</key><string>Used when microphone redirection is turned on for a connection.</string>
  <key>CFBundleDocumentTypes</key>
  <array>
    <dict>
      <key>CFBundleTypeName</key><string>Remote Desktop Connection</string>
      <key>CFBundleTypeRole</key><string>Viewer</string>
      <key>LSHandlerRank</key><string>Alternate</string>
      <key>CFBundleTypeExtensions</key><array><string>rdp</string></array>
    </dict>
  </array>
</dict>
</plist>
EOF

if [ -x "$ROOT/build/freerdp/bin/sdl-freerdp" ]; then
  echo "==> Bundling FreeRDP as a helper app"
  # sdl-freerdp lives in its own bundle so macOS can show (and remember) the Local Network prompt for it;
  # a bare executable is denied silently. Libraries go to Contents/lib (@loader_path/../lib).
  HELPER="$APP/Contents/Helpers/MacRDP Session.app"
  mkdir -p "$HELPER/Contents/MacOS"
  cp "$ROOT/build/freerdp/bin/sdl-freerdp" "$HELPER/Contents/MacOS/sdl-freerdp"
  cp -R "$ROOT/build/freerdp/lib" "$HELPER/Contents/lib"
  echo "==> Bundling Homebrew libraries (ffmpeg, SDL3, OpenSSL, …)"
  "$ROOT/scripts/bundle-dylibs.sh" "$HELPER/Contents/lib" "$HELPER/Contents/MacOS/sdl-freerdp"
  cat > "$HELPER/Contents/Info.plist" <<EOF
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
  <key>CFBundleName</key><string>MacRDP Session</string>
  <key>CFBundleDisplayName</key><string>MacRDP Session</string>
  <key>CFBundleIdentifier</key><string>com.walush.macrdp.session</string>
  <key>CFBundleExecutable</key><string>sdl-freerdp</string>
  <key>CFBundlePackageType</key><string>APPL</string>
  <key>CFBundleShortVersionString</key><string>$VERSION</string>
  <key>CFBundleIconFile</key><string>AppIcon</string>
  <key>LSMinimumSystemVersion</key><string>14.0</string>
  <key>NSHighResolutionCapable</key><true/>
  <key>NSLocalNetworkUsageDescription</key><string>The remote desktop session connects to PCs on your local network.</string>
  <key>NSMicrophoneUsageDescription</key><string>Used when microphone redirection is turned on for a connection.</string>
</dict>
</plist>
EOF
  if [ -f "$ROOT/Resources/AppIcon.icns" ]; then
    mkdir -p "$HELPER/Contents/Resources"; cp "$ROOT/Resources/AppIcon.icns" "$HELPER/Contents/Resources/"
  fi
  for lib in "$HELPER/Contents/lib/"*.dylib; do [ -L "$lib" ] || sign "$lib"; done
  sign --identifier com.walush.macrdp.session --entitlements "$ROOT/Resources/Session.entitlements" "$HELPER"
else
  echo "!!  build/freerdp not found: the app will fall back to Homebrew's sdl-freerdp (no UDP)."
fi

if [ "$SIGN_IDENTITY" = "-" ]; then
  echo "==> Signing ad-hoc (no signing certificate found: macOS will ask for the Keychain password after each rebuild)"
else
  echo "==> Signing with $(security find-identity -v -p codesigning | grep "$SIGN_IDENTITY" | sed -E 's/.*"(.*)"/\1/' | sed -E 's/\(.*\)//')"
fi
sign --identifier com.walush.macrdp "$APP"
echo "==> Done: $APP"
