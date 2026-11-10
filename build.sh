#!/bin/zsh
set -euo pipefail
cd "${0:A:h}"
VERSION=1.3.0
APP="build/Mac Cleaner.app"
swift build -c release
BIN="$(swift build -c release --show-bin-path)/MacCleanerBar"
rm -rf build
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"
cp "$BIN" "$APP/Contents/MacOS/MacCleanerBar"
cp Resources/askpass "$APP/Contents/Resources/askpass"
chmod 755 "$APP/Contents/Resources/askpass"
cp Resources/AppIcon.icns "$APP/Contents/Resources/AppIcon.icns"
CLI_SRC=${MAC_CLEANER_CLI_SRC:-../mac-cleaner}
[[ -f $CLI_SRC ]] || { print -u2 "CLI introuvable : $CLI_SRC"; exit 1; }
cp "$CLI_SRC" "$APP/Contents/Resources/mac-cleaner"
chmod 755 "$APP/Contents/Resources/mac-cleaner"
cat > "$APP/Contents/Info.plist" <<PLIST
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
  <key>CFBundleExecutable</key><string>MacCleanerBar</string>
  <key>CFBundleIconFile</key><string>AppIcon</string>
  <key>CFBundleIdentifier</key><string>com.chaibialaa.mac-cleaner-bar</string>
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
if [[ -n $IDENTITY ]]; then
  codesign --force --options runtime --timestamp --sign "$IDENTITY" "$APP"
else
  codesign --force --sign - "$APP"
fi
codesign --verify --strict "$APP"
ditto -c -k --keepParent "$APP" "build/MacCleanerBar-$VERSION.zip"
print "OK: $APP"
