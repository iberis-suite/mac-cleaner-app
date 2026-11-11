#!/bin/zsh
set -euo pipefail
cd "${0:A:h}"
VERSION=0.1.1
APP="build/Mac Cleaner.app"
swift build -c release
BIN="$(swift build -c release --show-bin-path)/MacCleanerBar"
rm -rf build
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"
cp "$BIN" "$APP/Contents/MacOS/MacCleanerBar"
cp Resources/askpass "$APP/Contents/Resources/askpass"
chmod 755 "$APP/Contents/Resources/askpass"
cp Resources/AppIcon.icns "$APP/Contents/Resources/AppIcon.icns"
CLI_SRC=${MAC_CLEANER_CLI_SRC:-../mac-cleaner/mac-cleaner}
[[ -f $CLI_SRC ]] || { print -u2 "CLI mac-cleaner introuvable : $CLI_SRC (clone iberis-suite/mac-cleaner à côté de ce dépôt, ou définis MAC_CLEANER_CLI_SRC=/chemin/vers/mac-cleaner)"; exit 1; }
cp "$CLI_SRC" "$APP/Contents/Resources/mac-cleaner"
chmod 755 "$APP/Contents/Resources/mac-cleaner"
cat > "$APP/Contents/Info.plist" <<PLIST
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
  <key>CFBundleExecutable</key><string>MacCleanerBar</string>
  <key>CFBundleIconFile</key><string>AppIcon</string>
  <key>CFBundleIdentifier</key><string>com.iberis-suite.mac-cleaner</string>
  <key>CFBundleName</key><string>Mac Cleaner</string>
  <key>CFBundleDisplayName</key><string>Mac Cleaner</string>
  <key>CFBundlePackageType</key><string>APPL</string>
  <key>CFBundleShortVersionString</key><string>$VERSION</string>
  <key>CFBundleVersion</key><string>$VERSION</string>
  <key>LSMinimumSystemVersion</key><string>13.0</string>
  <key>LSUIElement</key><true/>
  <key>NSHighResolutionCapable</key><true/>
</dict>
</plist>
PLIST
IDENTITY=$(security find-identity -v -p codesigning | awk -F'"' '/Developer ID Application/{print $2; exit}')
xattr -cr "$APP"
SCRIPTS=( "$APP/Contents/Resources/mac-cleaner" "$APP/Contents/Resources/askpass" )
if [[ -n $IDENTITY ]]; then
  codesign --force --options runtime --timestamp --sign "$IDENTITY" $SCRIPTS
  codesign --force --options runtime --timestamp --sign "$IDENTITY" "$APP"
else
  codesign --force --sign - $SCRIPTS
  codesign --force --sign - "$APP"
fi
codesign --verify --strict "$APP"
ditto -c -k --keepParent "$APP" "build/MacCleaner-$VERSION.zip"
print "OK: $APP"
