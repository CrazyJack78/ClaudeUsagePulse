#!/bin/bash
set -e

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
APP="$SCRIPT_DIR/ClaudeUsagePulse.app"

echo "Baue ClaudeUsagePulse..."
cd "$SCRIPT_DIR"
swift build -c release

echo "Erstelle App Bundle..."
rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS"
mkdir -p "$APP/Contents/Resources"

cp .build/release/ClaudeUsagePulse "$APP/Contents/MacOS/ClaudeUsagePulse"
cp Sources/ClaudeUsagePulse/Resources/Info.plist "$APP/Contents/Info.plist"

echo "Signiere App Bundle..."
codesign --force --deep --sign - "$APP"

echo "Installiere nach /Applications (einmalige Passwortabfrage)..."
pkill -x ClaudeUsagePulse 2>/dev/null || true
sleep 0.5

osascript -e "do shell script \"rm -rf /Applications/ClaudeUsagePulse.app && ditto '$APP' /Applications/ClaudeUsagePulse.app && xattr -dr com.apple.quarantine /Applications/ClaudeUsagePulse.app\" with administrator privileges"

echo "Starte ClaudeUsagePulse..."
open /Applications/ClaudeUsagePulse.app

echo ""
echo "Fertig! ClaudeUsagePulse läuft."
