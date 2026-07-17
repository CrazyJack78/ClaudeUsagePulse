#!/bin/bash
set -e

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
APP="$SCRIPT_DIR/ClaudeUsagePulse.app"
VERSION=$(defaults read "$APP/Contents/Info" CFBundleShortVersionString 2>/dev/null || echo "0.1.6")
DMG_NAME="ClaudeUsagePulse-v${VERSION}.dmg"
DMG_TEMP="$SCRIPT_DIR/.dmg_build_$$.dmg"
DMG_FINAL="$SCRIPT_DIR/$DMG_NAME"
VOLUME_NAME="ClaudeUsagePulse"
MOUNT_DIR="/Volumes/$VOLUME_NAME"
BG_DIR="$SCRIPT_DIR/.dmg_bg_$$"

echo "Erstelle DMG-Installer v${VERSION}..."

# App prüfen
if [ ! -d "$APP" ]; then
    echo "Fehler: ClaudeUsagePulse.app nicht gefunden. Erst build.sh ausführen."
    exit 1
fi

# Aufräumen falls alte Version existiert
rm -f "$DMG_FINAL"
hdiutil detach "$MOUNT_DIR" 2>/dev/null || true
rm -rf "$BG_DIR"
mkdir -p "$BG_DIR"

# Hintergrundbild mit Python generieren (dunkler Hintergrund + Pfeil nach rechts)
echo "Generiere Hintergrundbild..."
export BG_DIR
python3 << 'PYTHON_EOF'
import struct, zlib, os

W, H = 540, 380
BG     = (42, 42, 42)
ARROW  = (110, 110, 110)

pixels = [BG] * (W * H)

def set_pixel(x, y, color):
    if 0 <= x < W and 0 <= y < H:
        pixels[y * W + x] = color

def fill_rect(x1, y1, x2, y2, color):
    for y in range(y1, y2 + 1):
        for x in range(x1, x2 + 1):
            set_pixel(x, y, color)

# Pfeil: Schaft + Dreieckspitze (zeigt nach rechts, zentriert)
cx, cy = W // 2, H // 2

# Schaft: 80px breit, 18px hoch
fill_rect(cx - 55, cy - 9, cx + 15, cy + 9, ARROW)

# Dreieckspitze: 50px breit, 56px hoch
for dx in range(50):
    ratio    = dx / 50.0
    half_h   = int(28 * (1.0 - ratio))
    fill_rect(cx + 15 + dx, cy - half_h, cx + 15 + dx, cy + half_h, ARROW)

# PNG schreiben
def chunk(name_bytes, data):
    c   = name_bytes + data
    crc = zlib.crc32(c) & 0xffffffff
    return struct.pack('>I', len(data)) + c + struct.pack('>I', crc)

rows = []
for y in range(H):
    row = bytearray([0])
    for x in range(W):
        r, g, b = pixels[y * W + x]
        row += bytearray([r, g, b])
    rows.append(bytes(row))

idat = zlib.compress(b''.join(rows), 6)

png = (b'\x89PNG\r\n\x1a\n'
    + chunk(b'IHDR', struct.pack('>IIBBBBB', W, H, 8, 2, 0, 0, 0))
    + chunk(b'IDAT', idat)
    + chunk(b'IEND', b''))

out = os.path.join(os.environ['BG_DIR'], 'background.png')
with open(out, 'wb') as f:
    f.write(png)
print(f"  → {out} ({W}x{H} px)")
PYTHON_EOF

# Temporäres beschreibbares DMG erstellen
echo "Erstelle temporäres DMG..."
hdiutil create \
    -size 60m \
    -fs "HFS+" \
    -volname "$VOLUME_NAME" \
    -quiet \
    "$DMG_TEMP"

# Mounten
echo "Mounte DMG..."
hdiutil attach "$DMG_TEMP" -mountpoint "$MOUNT_DIR" -noautoopen -quiet

# App und Background kopieren, Applications-Symlink
echo "Befülle DMG..."
cp -R "$APP" "$MOUNT_DIR/"
mkdir -p "$MOUNT_DIR/.background"
cp "$BG_DIR/background.png" "$MOUNT_DIR/.background/background.png"
ln -s /Applications "$MOUNT_DIR/Applications"

# Finder-Layout per AppleScript setzen
echo "Setze Finder-Layout..."
osascript << 'APPLESCRIPT_EOF'
tell application "Finder"
    tell disk "ClaudeUsagePulse"
        open
        set current view of container window to icon view
        set toolbar visible of container window to false
        set statusbar visible of container window to false
        set bounds of container window to {200, 120, 740, 510}
        set opts to the icon view options of container window
        set arrangement of opts to not arranged
        set icon size of opts to 100
        set background picture of opts to file ".background:background.png"
        set position of item "ClaudeUsagePulse.app" to {130, 195}
        set position of item "Applications" to {410, 195}
        close
        open
        update without registering applications
        delay 3
        close
    end tell
end tell
APPLESCRIPT_EOF

# Warten bis .DS_Store geschrieben ist
sleep 2

# Unmounten
echo "Unmounte DMG..."
hdiutil detach "$MOUNT_DIR" -quiet

# In komprimiertes schreibgeschütztes DMG konvertieren
echo "Konvertiere zu UDZO..."
hdiutil convert "$DMG_TEMP" -format UDZO -quiet -o "$DMG_FINAL"

# Aufräumen
rm -f "$DMG_TEMP"
rm -rf "$BG_DIR"

echo ""
echo "✓ DMG erstellt: $DMG_FINAL"
echo "  Größe: $(du -sh "$DMG_FINAL" | cut -f1)"
