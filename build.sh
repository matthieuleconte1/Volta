#!/bin/zsh
# ./build.sh            → build/Volta.app
# ./build.sh --install  → idem, copié dans /Applications et lancé
# ./build.sh dist       → idem, plus build/Volta-<version>.dmg (avec LISEZ-MOI.txt) et build/Volta-<version>.zip,
#                         puis affiche la commande pour publier la release GitHub v<version>.
set -euo pipefail
cd "$(dirname "$0")"

VERSION=2.1.0
BUILD=3

swift build -c release --arch arm64
APP=build/Volta.app
rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"
if [[ ! -f Resources/AppIcon.icns || scripts/make_icon.swift -nt Resources/AppIcon.icns ]]; then
    mkdir -p Resources
    swift scripts/make_icon.swift Resources/AppIcon.icns
fi
cp Resources/AppIcon.icns "$APP/Contents/Resources/AppIcon.icns"
# Fonts of the Atelier Glyphe style, registered for the process at launch (see Fonts.swift).
if [[ -d Resources/Fonts ]]; then
    cp -R Resources/Fonts "$APP/Contents/Resources/Fonts"
fi
cp "$(swift build -c release --arch arm64 --show-bin-path)/Volta" "$APP/Contents/MacOS/Volta"

cat > "$APP/Contents/Info.plist" <<PLIST
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>CFBundleName</key><string>Volta</string>
    <key>CFBundleDisplayName</key><string>Volta</string>
    <key>CFBundleIdentifier</key><string>dev.volta.app</string>
    <key>CFBundleExecutable</key><string>Volta</string>
    <key>CFBundleIconFile</key><string>AppIcon</string>
    <key>CFBundlePackageType</key><string>APPL</string>
    <key>CFBundleShortVersionString</key><string>$VERSION</string>
    <key>CFBundleVersion</key><string>$BUILD</string>
    <key>LSMinimumSystemVersion</key><string>26.0</string>
    <key>LSUIElement</key><true/>
    <key>NSHighResolutionCapable</key><true/>
    <key>CFBundleDevelopmentRegion</key><string>fr</string>
</dict>
</plist>
PLIST

codesign --force --sign - "$APP"
echo "✓ $APP"

if [[ "${1:-}" == "--install" || "${1:-}" == "install" ]]; then
    # The app used to be called Wattchdog: its settings are migrated at first launch (Settings.swift).
    pkill -x Wattchdog 2>/dev/null || true
    rm -rf /Applications/Wattchdog.app
    pkill -x Volta 2>/dev/null || true
    rm -rf /Applications/Volta.app
    cp -R "$APP" /Applications/
    touch /Applications/Volta.app  # refresh the Finder / Dock icon cache
    open /Applications/Volta.app
    echo "✓ Installé dans /Applications et lancé"
fi

if [[ "${1:-}" == "dist" ]]; then
    DMG="build/Volta-$VERSION.dmg"
    ZIP="build/Volta-$VERSION.zip"
    STAGE=build/dmg
    rm -rf "$STAGE" "$DMG" "$ZIP"
    mkdir -p "$STAGE"
    cp -R "$APP" "$STAGE/"
    ln -s /Applications "$STAGE/Applications"
    cp Resources/LISEZ-MOI.txt "$STAGE/LISEZ-MOI.txt"
    hdiutil create -volname "Volta $VERSION" -srcfolder "$STAGE" -fs HFS+ -format UDZO -ov "$DMG" >/dev/null
    rm -rf "$STAGE"
    ditto -c -k --keepParent "$APP" "$ZIP"
    echo "✓ $DMG"
    echo "✓ $ZIP"
    echo "Pour publier :"
    echo "  gh release create v$VERSION $DMG $ZIP --title \"Volta $VERSION\" --notes-file <notes.md>"
fi
