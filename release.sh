#!/bin/bash
# Builds a Developer ID-signed, notarized, stapled IP-info.app and zips it for
# download; optionally tags and publishes a GitHub release.
#
#   ./release.sh 1.1.0             # -> dist/IP-info-1.1.0.zip (+ .sha256)
#   ./release.sh 1.1.0 --publish   # …and tag v1.1.0, push, create the GitHub release
#
# One-time setup:
#   1. A "Developer ID Application" certificate in your login keychain
#      (Xcode ▸ Settings ▸ Accounts ▸ Manage Certificates…). Auto-detected;
#      override with CODESIGN_IDENTITY.
#   2. Notarization credentials saved under a keychain profile (default name
#      "developer"; override with NOTARY_PROFILE):
#        xcrun notarytool store-credentials developer --apple-id you@example.com --team-id TEAMID
#      using an app-specific password from https://account.apple.com.
#   3. For --publish: `gh auth login`.
set -euo pipefail

ROOT="$(cd "$(dirname "$0")" && pwd)"
APP_NAME="IP-info"
APP="$ROOT/$APP_NAME.app"
DIST="$ROOT/dist"

VERSION="${1:?usage: release.sh <version> [--publish]}"
PUBLISH=false
[[ "${2:-}" == "--publish" ]] && PUBLISH=true
PROFILE="${NOTARY_PROFILE:-developer}"
ZIP="$DIST/$APP_NAME-$VERSION.zip"

IDENTITY="${CODESIGN_IDENTITY:-$(security find-identity -v -p codesigning \
    | grep -o '"Developer ID Application: [^"]*"' | head -1 | tr -d '"')}"
if [[ -z "$IDENTITY" ]]; then
    echo "No 'Developer ID Application' certificate in the keychain (see the setup notes at the top of this script)." >&2
    exit 1
fi
if $PUBLISH && [[ -n "$(git -C "$ROOT" status --porcelain)" ]]; then
    echo "Working tree is not clean — commit before publishing." >&2
    exit 1
fi

echo "==> Building $APP_NAME $VERSION, signing as: $IDENTITY"
VERSION="$VERSION" CODESIGN_IDENTITY="$IDENTITY" "$ROOT/build-app.sh"

mkdir -p "$DIST"
rm -f "$ZIP" "$ZIP.sha256"
ditto -c -k --keepParent "$APP" "$ZIP"

echo "==> Notarizing (this usually takes a minute or two)"
xcrun notarytool submit "$ZIP" --keychain-profile "$PROFILE" --wait --output-format plist > "$DIST/notary.plist"
STATUS="$(plutil -extract status raw -o - "$DIST/notary.plist")"
SUBMISSION_ID="$(plutil -extract id raw -o - "$DIST/notary.plist")"
if [[ "$STATUS" != "Accepted" ]]; then
    echo "Notarization $STATUS (submission $SUBMISSION_ID). Log:" >&2
    xcrun notarytool log "$SUBMISSION_ID" --keychain-profile "$PROFILE" >&2 || true
    exit 1
fi

echo "==> Stapling the notarization ticket"
xcrun stapler staple "$APP"
rm -f "$ZIP"
ditto -c -k --keepParent "$APP" "$ZIP"   # re-zip so the download carries the ticket

echo "==> Verifying"
codesign --verify --strict --verbose=2 "$APP"
spctl --assess --type execute --verbose=2 "$APP"
(cd "$DIST" && shasum -a 256 "$(basename "$ZIP")" | tee "$(basename "$ZIP").sha256")
echo "Release artifact: $ZIP"

if $PUBLISH; then
    TAG="v$VERSION"
    echo "==> Publishing $TAG"
    git -C "$ROOT" tag -a "$TAG" -m "$APP_NAME $VERSION"
    git -C "$ROOT" push origin HEAD "$TAG"
    gh release create "$TAG" "$ZIP" "$ZIP.sha256" \
        --repo "$(git -C "$ROOT" remote get-url origin | sed -E 's#.*github.com[:/](.*)\.git#\1#')" \
        --title "$APP_NAME $VERSION" --generate-notes
fi
