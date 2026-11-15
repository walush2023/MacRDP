#!/bin/bash
# Builds a signed, notarized and stapled DMG for distribution: build/MacRDP-<version>.dmg
#
# Needs:
#   - a "Developer ID Application" certificate in your login keychain
#   - notarization credentials saved once as a keychain profile (default name "macrdp-notary"):
#       xcrun notarytool store-credentials macrdp-notary \
#         --apple-id <your Apple ID> --team-id <TEAMID> --password <app-specific password>
#     (create the app-specific password at https://account.apple.com → Sign-In and Security)
# Options (env): NOTARY_PROFILE=<name>, SKIP_NOTARIZE=1 (build + sign the DMG only)
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
VERSION="$(cat "$ROOT/VERSION")"
APP="$ROOT/build/MacRDP.app"
DMG="$ROOT/build/MacRDP-$VERSION.dmg"
PROFILE="${NOTARY_PROFILE:-macrdp-notary}"

IDS="$(security find-identity -v -p codesigning)"
SIGN_IDENTITY="${SIGN_IDENTITY:-$(echo "$IDS" | grep '"Developer ID Application' | head -1 | awk '{print $2}' || true)}"
[ -n "$SIGN_IDENTITY" ] || { echo "No Developer ID Application certificate found."; exit 1; }
export SIGN_IDENTITY RELEASE=1

[ -x "$ROOT/build/freerdp/bin/sdl-freerdp" ] || "$ROOT/scripts/build-freerdp.sh"
"$ROOT/scripts/build-app.sh"

echo "==> Checking signature"
codesign --verify --deep --strict --verbose=1 "$APP" 2>&1 | tail -1
[[ "$(codesign -dv "$APP" 2>&1)" == *"(runtime)"* ]] || { echo "hardened runtime missing"; exit 1; }

echo "==> Creating $DMG"
STAGE="$ROOT/build/dmg"
rm -rf "$STAGE" "$DMG"
mkdir -p "$STAGE"
cp -R "$APP" "$STAGE/"
ln -s /Applications "$STAGE/Applications"
hdiutil create -volname "MacRDP $VERSION" -srcfolder "$STAGE" -fs HFS+ -format ULFO -ov "$DMG" >/dev/null
rm -rf "$STAGE"
codesign --force --timestamp --sign "$SIGN_IDENTITY" "$DMG"

if [ "${SKIP_NOTARIZE:-0}" = 1 ]; then
  echo "==> Skipping notarization (SKIP_NOTARIZE=1): $DMG"
  exit 0
fi
if ! xcrun notarytool history --keychain-profile "$PROFILE" >/dev/null 2>&1; then
  cat <<EOF
!!  Notarization profile "$PROFILE" not found. Save it once with:
      xcrun notarytool store-credentials $PROFILE --apple-id <Apple ID> --team-id <TEAMID> --password <app-specific password>
    then run this script again. The signed (not notarized) DMG is at:
    $DMG
EOF
  exit 2
fi

echo "==> Notarizing (usually 1–5 minutes)"
xcrun notarytool submit "$DMG" --keychain-profile "$PROFILE" --wait | tee "$ROOT/build/notary.log"
grep -q "status: Accepted" "$ROOT/build/notary.log" || {
  ID="$(awk '/  id:/{print $2; exit}' "$ROOT/build/notary.log")"
  echo "Notarization failed. Details: xcrun notarytool log $ID --keychain-profile $PROFILE"
  exit 1
}

echo "==> Stapling"
xcrun stapler staple "$DMG"
spctl -a -t open --context context:primary-signature -v "$DMG" 2>&1 | tail -1
echo "==> Done: $DMG"
