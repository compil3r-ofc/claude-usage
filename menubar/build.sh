#!/bin/bash
# Build ClaudeUsage.app from ClaudeUsage.swift. Needs only Xcode Command Line Tools.
set -euo pipefail
cd "$(dirname "${BASH_SOURCE[0]}")"

APP="ClaudeUsage.app"
rm -rf "$APP" ClaudeUsage
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"

swiftc -O -swift-version 5 \
  -framework AppKit \
  -o "$APP/Contents/MacOS/ClaudeUsage" \
  UsageCore.swift main.swift

cat > "$APP/Contents/Info.plist" <<'PLIST'
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
  <key>CFBundleName</key>              <string>ClaudeUsage</string>
  <key>CFBundleDisplayName</key>       <string>Claude Usage</string>
  <key>CFBundleIdentifier</key>        <string>local.claude-usage.menubar</string>
  <key>CFBundleVersion</key>           <string>1.0</string>
  <key>CFBundleShortVersionString</key><string>1.0</string>
  <key>CFBundlePackageType</key>       <string>APPL</string>
  <key>CFBundleExecutable</key>        <string>ClaudeUsage</string>
  <key>LSMinimumSystemVersion</key>    <string>13.0</string>
  <!-- menu bar only: no Dock icon, no app switcher entry -->
  <key>LSUIElement</key>               <true/>
</dict>
</plist>
PLIST

# Ad-hoc signature so macOS will run it without a developer account.
codesign --force --deep --sign - "$APP" 2>/dev/null || echo "note: ad-hoc signing skipped"

echo "Built $(pwd)/$APP"
echo
echo "Run it:            open $APP"
echo "Install it:        cp -R $APP /Applications/"
echo "Start at login:    System Settings > General > Login Items > +"
