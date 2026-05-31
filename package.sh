#!/bin/bash
set -euo pipefail

APP_NAME="Halo"
BUNDLE_ID="com.halo.app"
VERSION="0.1.0"
BUILD="1"

ROOT="$(cd "$(dirname "$0")" && pwd)"
APP="$ROOT/build/$APP_NAME.app"

echo "▸ Building $APP_NAME (release)…"
swift build -c release --product "$APP_NAME"
BIN="$(swift build -c release --product "$APP_NAME" --show-bin-path)/$APP_NAME"

echo "▸ Assembling $APP"
rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"
cp "$BIN" "$APP/Contents/MacOS/$APP_NAME"
chmod +x "$APP/Contents/MacOS/$APP_NAME"
printf 'APPL????' > "$APP/Contents/PkgInfo"
[ -f "$ROOT/Resources/AppIcon.icns" ] && cp "$ROOT/Resources/AppIcon.icns" "$APP/Contents/Resources/AppIcon.icns"

# Sparkle is a *dynamic* framework (Yams/WhisperKit are static source), so it has
# to be copied into the bundle and reachable at runtime. SPM links it as
# @rpath/Sparkle.framework/… but bakes no app-relative rpath, so add one.
echo "▸ Embedding Sparkle.framework"
SPARKLE_FW="$(find "$ROOT/.build/artifacts" -type d -name Sparkle.framework -path '*macos-arm64*' | head -1)"
[ -n "$SPARKLE_FW" ] || { echo "✗ Sparkle.framework not found — run 'swift build' first."; exit 1; }
mkdir -p "$APP/Contents/Frameworks"
ditto "$SPARKLE_FW" "$APP/Contents/Frameworks/Sparkle.framework"
install_name_tool -add_rpath "@executable_path/../Frameworks" "$APP/Contents/MacOS/$APP_NAME"

cat > "$APP/Contents/Info.plist" <<PLIST
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>CFBundleName</key>                  <string>$APP_NAME</string>
    <key>CFBundleDisplayName</key>           <string>$APP_NAME</string>
    <key>CFBundleExecutable</key>            <string>$APP_NAME</string>
    <key>CFBundleIdentifier</key>            <string>$BUNDLE_ID</string>
    <key>CFBundleVersion</key>               <string>$BUILD</string>
    <key>CFBundleShortVersionString</key>    <string>$VERSION</string>
    <key>CFBundlePackageType</key>           <string>APPL</string>
    <key>CFBundleIconFile</key>              <string>AppIcon</string>
    <key>LSMinimumSystemVersion</key>        <string>14.0</string>
    <key>LSUIElement</key>                   <true/>
    <key>NSHighResolutionCapable</key>       <true/>
    <key>NSPrincipalClass</key>              <string>NSApplication</string>
    <key>NSMicrophoneUsageDescription</key>
    <string>Halo uses the microphone to dictate when you release the wheel at its center. Audio is processed on-device.</string>
    <key>NSSpeechRecognitionUsageDescription</key>
    <string>Halo transcribes your dictation on-device.</string>
    <key>SUFeedURL</key>                      <string>https://tinkerhaus.github.io/halo/appcast.xml</string>
    <key>SUPublicEDKey</key>                  <string>m1galZQk0Cqt7fguZtkJdezgtIzbrfSP30J12zwUOTA=</string>
    <key>SUEnableAutomaticChecks</key>        <true/>
    <key>SUScheduledCheckInterval</key>       <integer>86400</integer>
</dict>
</plist>
PLIST

# Prefer a stable self-signed identity so Accessibility/Input-Monitoring grants
# survive rebuilds (TCC binds to the code hash). Run ./create-dev-cert.sh once.
IDENTITY="$(security find-identity -p codesigning 2>/dev/null | grep '"Halo Developer"' | head -1 | awk '{print $2}')"
ENTITLEMENTS="$(mktemp -t halo-ent).plist"
cat > "$ENTITLEMENTS" <<ENT
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>com.apple.security.device.audio-input</key> <true/>
    <key>com.apple.security.cs.allow-jit</key>       <true/>
    <!-- Load the embedded Sparkle.framework: self-signed certs carry no Team ID,
         so hardened-runtime library validation would otherwise reject it. -->
    <key>com.apple.security.cs.disable-library-validation</key> <true/>
</dict>
</plist>
ENT

if [ -z "$IDENTITY" ]; then
    IDENTITY="-"
    echo "▸ Ad-hoc signing (TCC grants reset each rebuild — run ./create-dev-cert.sh once to fix)."
else
    echo "▸ Signing with stable identity: Halo Developer ($IDENTITY)"
fi

# Sign Sparkle inside-out: nested helpers first, then the framework, then the app
# last so its seal covers everything. Same identity as the app, so the app's
# hardened-runtime library validation accepts the framework. Helpers get hardened
# runtime but none of the app's entitlements (they don't need mic/JIT).
FW="$APP/Contents/Frameworks/Sparkle.framework"
for nested in \
    "$FW/Versions/Current/XPCServices/Downloader.xpc" \
    "$FW/Versions/Current/XPCServices/Installer.xpc" \
    "$FW/Versions/Current/Updater.app" \
    "$FW/Versions/Current/Autoupdate"; do
    [ -e "$nested" ] && codesign --force --options runtime --sign "$IDENTITY" "$nested"
done
codesign --force --options runtime --sign "$IDENTITY" "$FW"

codesign --force --sign "$IDENTITY" --options runtime --entitlements "$ENTITLEMENTS" "$APP"
rm -f "$ENTITLEMENTS"

echo ""
echo "✅ Built $APP"
echo "   Launch:  open \"$APP\""
echo "   Install: mv \"$APP\" /Applications/"
