#!/bin/bash
# Builds IP-info.app.
#
#   ./build-app.sh              # ad-hoc signed — fine for your own Mac
#   ./build-app.sh --install    # …and copy to /Applications
#
# Environment:
#   VERSION            CFBundleShortVersionString (default 1.1.1)
#   BUILD              CFBundleVersion (default: git commit count)
#   CODESIGN_IDENTITY  "-" (ad-hoc, default) or a "Developer ID Application: …"
#                      identity for distribution — see release.sh.
set -euo pipefail

ROOT="$(cd "$(dirname "$0")" && pwd)"
APP_NAME="IP-info"
APP="$ROOT/$APP_NAME.app"
VERSION="${VERSION:-1.1.1}"
BUILD="${BUILD:-$(git -C "$ROOT" rev-list --count HEAD 2>/dev/null || echo 1)}"
IDENTITY="${CODESIGN_IDENTITY:--}"

# Universal binary: build each arch separately and lipo them together.
# (swift build --arch arm64 --arch x86_64 needs full Xcode; --triple works
# with just the Command Line Tools.)
for TRIPLE in arm64-apple-macosx x86_64-apple-macosx; do
    swift build -c release --product ExitIPApp --triple "$TRIPLE"
done
UNIVERSAL_BIN="$ROOT/.build/ExitIPApp-universal"
lipo -create -output "$UNIVERSAL_BIN" \
    "$(swift build -c release --product ExitIPApp --triple arm64-apple-macosx --show-bin-path)/ExitIPApp" \
    "$(swift build -c release --product ExitIPApp --triple x86_64-apple-macosx --show-bin-path)/ExitIPApp"

rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"
cp "$UNIVERSAL_BIN" "$APP/Contents/MacOS/$APP_NAME"
cp "$ROOT/Assets/AppIcon.icns" "$APP/Contents/Resources/AppIcon.icns"

cat > "$APP/Contents/Info.plist" <<PLIST
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>CFBundleName</key><string>$APP_NAME</string>
    <key>CFBundleDisplayName</key><string>$APP_NAME</string>
    <key>CFBundleIdentifier</key><string>com.lec77.ipinfo</string>
    <key>CFBundleVersion</key><string>$BUILD</string>
    <key>CFBundleShortVersionString</key><string>$VERSION</string>
    <key>CFBundlePackageType</key><string>APPL</string>
    <key>CFBundleExecutable</key><string>$APP_NAME</string>
    <key>CFBundleIconFile</key><string>AppIcon</string>
    <key>LSUIElement</key><true/>
    <key>LSMinimumSystemVersion</key><string>13.0</string>
    <key>LSApplicationCategoryType</key><string>public.app-category.utilities</string>
    <key>NSHumanReadableCopyright</key><string>Personal project — use freely.</string>
    <!-- The captive-portal fallback probe is plain HTTP on purpose. -->
    <key>NSAppTransportSecurity</key>
    <dict>
        <key>NSExceptionDomains</key>
        <dict>
            <key>gstatic.com</key>
            <dict>
                <key>NSIncludesSubdomains</key><true/>
                <key>NSExceptionAllowsInsecureHTTPLoads</key><true/>
            </dict>
        </dict>
    </dict>
</dict>
</plist>
PLIST

if [[ "$IDENTITY" == "-" ]]; then
    # Ad-hoc: enough for UNUserNotificationCenter to behave on a local build.
    codesign --force --sign - "$APP"
else
    # Hardened runtime + secure timestamp are required for notarization.
    codesign --force --options runtime --timestamp --sign "$IDENTITY" "$APP"
fi

echo "Built $APP ($VERSION build $BUILD, signed: $IDENTITY)"

if [[ "${1:-}" == "--install" ]]; then
    rm -rf "/Applications/$APP_NAME.app"
    cp -R "$APP" "/Applications/$APP_NAME.app"
    echo "Installed to /Applications/$APP_NAME.app"
fi
