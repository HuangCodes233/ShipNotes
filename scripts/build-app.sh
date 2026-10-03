#!/usr/bin/env bash
# Wrap the SwiftPM-built ShipNotes executable into a real macOS .app bundle.
#
# Output:        dist/ShipNotes.app
# Bundle ID:     org.shipnotes.app
# Min macOS:     14.0
#
# Environment overrides:
#   CONFIG=release|debug   (default: release)
#   VERSION=0.1.0          (CFBundleShortVersionString; auto-derived from git tags if unset)
#   BUILD=1                (CFBundleVersion)
#   SIGN_IDENTITY=""       (default: auto-detect Apple Development/Developer ID; "-" = ad-hoc)
#   NOTARIZE=true          (optional: submit to Apple notarization; requires real identity)
#   ASC_KEY_PATH=...       (App Store Connect API key .p8 path, for notarization)
#   ASC_KEY_ID=...         (App Store Connect API key ID, for notarization)
#   ASC_ISSUER_ID=...      (App Store Connect Issuer ID, for notarization)
#
# Usage:
#   scripts/build-app.sh
#   open dist/ShipNotes.app

set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
DIST="$ROOT/dist"
APP="$DIST/ShipNotes.app"
CONFIG="${CONFIG:-release}"
VERSION="${VERSION:-$(git -C "$ROOT" describe --tags --abbrev=0 2>/dev/null | sed 's/^v//' || echo '0.1.0')}"
BUILD="${BUILD:-1}"
SIGN_IDENTITY="${SIGN_IDENTITY:-}"
BUNDLE_ID="org.shipnotes.app"
APPICON_SRC="$ROOT/Sources/ShipNotes/Resources/Assets.xcassets/AppIcon.appiconset"

if [[ -z "$SIGN_IDENTITY" ]]; then
    SIGN_IDENTITY="$(
        security find-identity -v -p codesigning 2>/dev/null \
            | sed -nE 's/.*"(Apple Development: [^"]+)".*/\1/p; s/.*"(Developer ID Application: [^"]+)".*/\1/p' \
            | head -n 1
    )"
fi
if [[ -z "$SIGN_IDENTITY" ]]; then
    SIGN_IDENTITY="-"
fi

cd "$ROOT"

# ─── Build ────────────────────────────────────────────────────────────────
echo "→ swift build -c $CONFIG"
swift build -c "$CONFIG" --product ShipNotes

BIN_DIR="$(swift build -c "$CONFIG" --show-bin-path)"
BIN="$BIN_DIR/ShipNotes"
RES_BUNDLE="$BIN_DIR/ShipNotes_ShipNotes.bundle"
if [[ ! -x "$BIN" ]]; then
    echo "✗ Built binary not found at $BIN" >&2
    exit 1
fi
if [[ ! -d "$RES_BUNDLE" ]]; then
    echo "✗ SwiftPM resource bundle not found at $RES_BUNDLE" >&2
    exit 1
fi

# ─── Layout ───────────────────────────────────────────────────────────────
echo "→ Building $APP"
rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS"
mkdir -p "$APP/Contents/Resources"

# Executable
cp "$BIN" "$APP/Contents/MacOS/ShipNotes"
chmod +x "$APP/Contents/MacOS/ShipNotes"

# SwiftPM resource bundle.
# We place it in the proper Contents/Resources/ location (so codesign is happy)
# and rely on Localization.swift's `resourceBundle` to probe via Bundle.main.url().
cp -R "$RES_BUNDLE" "$APP/Contents/Resources/ShipNotes_ShipNotes.bundle"
RES_INFO="$APP/Contents/Resources/ShipNotes_ShipNotes.bundle/Info.plist"
if [[ -f "$APP/Contents/Resources/ShipNotes_ShipNotes.bundle/Contents/Info.plist" ]]; then
    RES_INFO="$APP/Contents/Resources/ShipNotes_ShipNotes.bundle/Contents/Info.plist"
fi
plutil -replace CFBundleIdentifier -string "$BUNDLE_ID.resources" "$RES_INFO"
plutil -replace CFBundleName -string "ShipNotesResources" "$RES_INFO"
plutil -replace CFBundlePackageType -string "BNDL" "$RES_INFO"
plutil -replace CFBundleInfoDictionaryVersion -string "6.0" "$RES_INFO"
plutil -replace CFBundleVersion -string "$BUILD" "$RES_INFO"

# ─── AppIcon: .appiconset → .iconset → .icns ──────────────────────────────
echo "→ Building AppIcon.icns from .appiconset"
TMP_ICON_DIR="$(mktemp -d "${TMPDIR:-/tmp}/shipnotes-icon.XXXXXX")"
trap 'rm -rf "$TMP_ICON_DIR"' EXIT
TMP_ICONSET="$TMP_ICON_DIR/AppIcon.iconset"
mkdir -p "$TMP_ICONSET"

# .iconset filename convention vs our .appiconset PNGs.
cp "$APPICON_SRC/AppIcon-16.png"   "$TMP_ICONSET/icon_16x16.png"
cp "$APPICON_SRC/AppIcon-32.png"   "$TMP_ICONSET/icon_16x16@2x.png"
cp "$APPICON_SRC/AppIcon-32.png"   "$TMP_ICONSET/icon_32x32.png"
cp "$APPICON_SRC/AppIcon-64.png"   "$TMP_ICONSET/icon_32x32@2x.png"
cp "$APPICON_SRC/AppIcon-128.png"  "$TMP_ICONSET/icon_128x128.png"
cp "$APPICON_SRC/AppIcon-256.png"  "$TMP_ICONSET/icon_128x128@2x.png"
cp "$APPICON_SRC/AppIcon-256.png"  "$TMP_ICONSET/icon_256x256.png"
cp "$APPICON_SRC/AppIcon-512.png"  "$TMP_ICONSET/icon_256x256@2x.png"
cp "$APPICON_SRC/AppIcon-512.png"  "$TMP_ICONSET/icon_512x512.png"
cp "$APPICON_SRC/AppIcon-1024.png" "$TMP_ICONSET/icon_512x512@2x.png"

iconutil -c icns -o "$APP/Contents/Resources/AppIcon.icns" "$TMP_ICONSET"

# ─── Info.plist ───────────────────────────────────────────────────────────
echo "→ Writing Info.plist"
cat > "$APP/Contents/Info.plist" <<EOF
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>CFBundleDevelopmentRegion</key>
    <string>en</string>
    <key>CFBundleDisplayName</key>
    <string>ShipNotes</string>
    <key>CFBundleExecutable</key>
    <string>ShipNotes</string>
    <key>CFBundleIconFile</key>
    <string>AppIcon</string>
    <key>CFBundleIconName</key>
    <string>AppIcon</string>
    <key>CFBundleIdentifier</key>
    <string>$BUNDLE_ID</string>
    <key>CFBundleInfoDictionaryVersion</key>
    <string>6.0</string>
    <key>CFBundleLocalizations</key>
    <array>
        <string>en</string>
        <string>zh-Hans</string>
        <string>ja</string>
    </array>
    <key>CFBundleName</key>
    <string>ShipNotes</string>
    <key>CFBundlePackageType</key>
    <string>APPL</string>
    <key>CFBundleShortVersionString</key>
    <string>$VERSION</string>
    <key>CFBundleVersion</key>
    <string>$BUILD</string>
    <key>LSApplicationCategoryType</key>
    <string>public.app-category.developer-tools</string>
    <key>LSMinimumSystemVersion</key>
    <string>14.0</string>
    <key>NSHighResolutionCapable</key>
    <true/>
    <key>NSHumanReadableCopyright</key>
    <string>© 2026 ShipNotes contributors</string>
    <key>NSPrincipalClass</key>
    <string>NSApplication</string>
    <key>NSSupportsAutomaticTermination</key>
    <true/>
    <key>NSSupportsSuddenTermination</key>
    <true/>
</dict>
</plist>
EOF

# Classic bundle marker. Modern apps do not strictly require it, but including
# it helps LaunchServices treat hand-built bundles consistently.
printf "APPL????" > "$APP/Contents/PkgInfo"

# Files copied from previous builds or generated assets can carry provenance
# xattrs. Clear them before signing so LaunchServices/Gatekeeper do not trip on
# stale metadata from the staging tree.
xattr -cr "$APP" 2>/dev/null || true

# ─── Codesign (ad-hoc by default, Hardened Runtime for real identities) ────
echo "→ Codesigning (identity: $SIGN_IDENTITY)"
# Sign nested code first, then the outer bundle WITHOUT --deep: --deep is
# deprecated, would re-sign the nested bundle (undoing its dedicated flags),
# and signs helpers with the wrong entitlements if any are ever added.
if [[ "$SIGN_IDENTITY" != "-" ]]; then
    # Developer ID: enable Hardened Runtime (required for notarization).
    codesign --force --options runtime --sign "$SIGN_IDENTITY" "$APP/Contents/Resources/ShipNotes_ShipNotes.bundle"
    codesign --force --options runtime --sign "$SIGN_IDENTITY" "$APP"
else
    # Ad-hoc: Hardened Runtime is meaningless without a real identity.
    codesign --force --sign "$SIGN_IDENTITY" "$APP/Contents/Resources/ShipNotes_ShipNotes.bundle"
    codesign --force --sign "$SIGN_IDENTITY" "$APP"
fi

# ─── Notarize (optional: NOTARIZE=true) ───────────────────────────────────
# Requires ASC_KEY_PATH, ASC_KEY_ID, ASC_ISSUER_ID environment variables.
# Use `xcrun notarytool store-credentials` for interactive setup, or pass:
#   ASC_KEY_PATH=~/.appstoreconnect/private_keys/AuthKey_XXXX.p8
#   ASC_KEY_ID=XXXX
#   ASC_ISSUER_ID=yyyy-yyyy-yyyy
if [[ "${NOTARIZE:-}" == "true" ]]; then
    if [[ "$SIGN_IDENTITY" != Developer\ ID\ Application:* ]]; then
        echo "✗ Notarization requires a Developer ID Application identity." >&2
        exit 1
    fi
    : "${ASC_KEY_PATH:?Set ASC_KEY_PATH to your App Store Connect API key .p8 file}"
    : "${ASC_KEY_ID:?Set ASC_KEY_ID}"
    : "${ASC_ISSUER_ID:?Set ASC_ISSUER_ID}"
    ZIP="$DIST/ShipNotes-$VERSION.zip"
    echo "→ Notarizing (this may take several minutes)"
    ditto -c -k --keepParent "$APP" "$ZIP"
    xcrun notarytool submit "$ZIP" \
        --key "$ASC_KEY_PATH" --key-id "$ASC_KEY_ID" --issuer "$ASC_ISSUER_ID" --wait
    xcrun stapler staple "$APP"
    rm -f "$ZIP"
    echo "✓ Notarized and stapled"
fi

# Bump mtime so LaunchServices re-registers (Finder/Dock icon refresh).
touch "$APP"

echo ""
echo "✓ ShipNotes.app built at:"
echo "   $APP"
echo ""
echo "Quick checks:"
echo "   open \"$APP\""
echo "   /usr/libexec/PlistBuddy -c 'Print CFBundleIdentifier' \"$APP/Contents/Info.plist\""
echo "   codesign -dvv \"$APP\""
