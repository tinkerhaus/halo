#!/bin/bash
set -euo pipefail

APP_NAME="Halo"
BUNDLE_ID="com.halo.app"
VERSION="${VERSION:-0.1.0}"   # override per release: VERSION=0.1.1 ./package.sh
BUILD="${BUILD:-1}"           # CFBundleVersion (the update check compares this). BUILD=2 ./package.sh

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

# Bundle our processed resources (the menu-bar glyph and logo) into the app. SwiftPM
# emits them as a sibling `Halo_Halo.bundle` next to the binary but does NOT copy it
# into a hand-assembled .app — and its generated `Bundle.module` accessor then falls
# back to the BUILD MACHINE's absolute .build path and `fatalError`s when that path is
# absent. On any other Mac that trapped the app on launch (the menu-bar icon is loaded
# during MenuBarExtra setup) — which is why an installed copy "couldn't launch at all".
# We place the bundle under Contents/Resources, where the code signature seals it, and
# load it via `Bundle.main` (see `Bundle.halo`) instead of `Bundle.module`.
#
# It must go under Contents/: anything at the .app ROOT (where SwiftPM's accessor
# actually looks, since it resolves against Bundle.main.bundleURL = the .app dir)
# breaks the signature resource seal — codesign warns "unsealed contents present in
# the bundle root" and the signature fails to verify. That's also why we DON'T ship
# the dependency bundles (swift-transformers_Hub, swift-crypto_Crypto): their accessors
# look at the root too, so we couldn't satisfy them without breaking the seal. They are
# not loaded on Halo's Whisper path (Hub's bundle is only read by a tokenizer-config
# fallback that Whisper models don't trigger; Crypto's is a privacy manifest never read
# at runtime), so leaving them out keeps the signature valid with no functional loss.
BINDIR="$(dirname "$BIN")"
[ -d "$BINDIR/Halo_Halo.bundle" ] && cp -R "$BINDIR/Halo_Halo.bundle" "$APP/Contents/Resources/Halo_Halo.bundle"

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
    <!-- LLM steps talk to a user-configured OpenAI-compatible endpoint, often a
         local/LAN/tailnet server reached over plain HTTP. Allow cleartext so those
         work; HTTPS endpoints (cloud providers) are unaffected. Not sandboxed, so
         no network entitlement is needed. -->
    <key>NSAppTransportSecurity</key>
    <dict>
        <key>NSAllowsArbitraryLoads</key> <true/>
    </dict>
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
</dict>
</plist>
ENT

if [ -z "$IDENTITY" ]; then
    IDENTITY="-"
    echo "▸ Ad-hoc signing (TCC grants reset each rebuild — run ./create-dev-cert.sh once to fix)."
else
    echo "▸ Signing with stable identity: Halo Developer ($IDENTITY)"
fi

codesign --force --sign "$IDENTITY" --options runtime --entitlements "$ENTITLEMENTS" "$APP"
rm -f "$ENTITLEMENTS"

echo ""
echo "✅ Built $APP"
echo "   Launch:  open \"$APP\""
echo "   Install: mv \"$APP\" /Applications/"
