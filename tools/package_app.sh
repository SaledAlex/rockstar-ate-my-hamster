#!/bin/sh
# Build a release binary and wrap it as "Rock Star Ate My Hamster.app" in dist/.
set -e
cd "$(dirname "$0")/.."
if [ ! -f Sources/RockStar/Resources/messages.json ]; then echo "Run tools/setup_assets.sh first." >&2; exit 1; fi
swift build -c release
BIN=$(swift build -c release --show-bin-path)
APP="dist/Rock Star Ate My Hamster.app"
rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"
cp "$BIN/RockStar" "$APP/Contents/MacOS/RockStar"
cp -R "$BIN/RockStar_RockStar.bundle" "$APP/Contents/Resources/"
cat > "$APP/Contents/Info.plist" <<'EOF'
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0"><dict>
  <key>CFBundleName</key><string>Rock Star Ate My Hamster</string>
  <key>CFBundleIdentifier</key><string>local.reproj.rockstar</string>
  <key>CFBundleExecutable</key><string>RockStar</string>
  <key>CFBundlePackageType</key><string>APPL</string>
  <key>CFBundleShortVersionString</key><string>0.1</string>
  <key>LSMinimumSystemVersion</key><string>13.0</string>
  <key>NSHighResolutionCapable</key><true/>
</dict></plist>
EOF
codesign --force --deep -s - "$APP"
echo "built $APP"
