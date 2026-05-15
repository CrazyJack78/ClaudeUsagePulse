#!/bin/bash
set -e

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
APP="$SCRIPT_DIR/ClaudeBar.app"

echo "Baue ClaudeBar..."
cd "$SCRIPT_DIR"
swift build -c release

echo "Erstelle App Bundle..."
rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS"
mkdir -p "$APP/Contents/Resources"

cp .build/release/ClaudeBar "$APP/Contents/MacOS/ClaudeBar"
cp Sources/ClaudeBar/Resources/Info.plist "$APP/Contents/Info.plist"

echo "Installiere nach /Applications (einmalige Passwortabfrage)..."
pkill -x ClaudeBar 2>/dev/null || true
sleep 0.5

osascript -e "do shell script \"rm -rf /Applications/ClaudeBar.app && ditto '$APP' /Applications/ClaudeBar.app && xattr -dr com.apple.quarantine /Applications/ClaudeBar.app\" with administrator privileges"

echo "Starte ClaudeBar..."
open /Applications/ClaudeBar.app

echo ""
echo "Fertig! ClaudeBar läuft."
