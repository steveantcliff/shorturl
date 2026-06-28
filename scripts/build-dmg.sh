#!/bin/bash
set -euo pipefail

# Build script for short.url macOS app
# Produces: ShortURL.app and ShortURL.dmg for Apple Silicon (M-series)

PROJECT_DIR="$(cd "$(dirname "$0")/.." && pwd)"
BUILD_DIR="$PROJECT_DIR/.build"
RELEASE_DIR="$BUILD_DIR/release"
APP_NAME="ShortURL"
APP_BUNDLE="$APP_NAME.app"
DMG_NAME="ShortURL.dmg"
STAGING="$PROJECT_DIR/staging"

echo "═══ Building short.url for macOS (Apple Silicon) ═══"
echo ""

# ── Step 1: Build the Swift package ──
echo "→ Building Swift package (release, arm64)…"
cd "$PROJECT_DIR"
swift build -c release --arch arm64 2>&1 | tail -5

BINARY="$BUILD_DIR/arm64-apple-macosx/release/$APP_NAME"
if [ ! -f "$BINARY" ]; then
    # Fallback: check the default release path
    BINARY="$RELEASE_DIR/$APP_NAME"
fi

if [ ! -f "$BINARY" ]; then
    echo "ERROR: Could not find built binary at $BINARY"
    echo "Searching..."
    find "$BUILD_DIR" -name "$APP_NAME" -type f 2>/dev/null
    exit 1
fi

echo "   Binary: $BINARY"
echo "   Size: $(stat -f%z "$BINARY") bytes"
echo "   Architecture: $(lipo -info "$BINARY" 2>/dev/null || file "$BINARY")"

# ── Step 2: Create the .app bundle ──
echo ""
echo "→ Creating .app bundle…"
rm -rf "$STAGING"
mkdir -p "$STAGING/$APP_BUNDLE/Contents/MacOS"
mkdir -p "$STAGING/$APP_BUNDLE/Contents/Resources"

# Copy binary
cp "$BINARY" "$STAGING/$APP_BUNDLE/Contents/MacOS/$APP_NAME"
chmod +x "$STAGING/$APP_BUNDLE/Contents/MacOS/$APP_NAME"

# Copy Info.plist
cp "$PROJECT_DIR/Resources/Info.plist" "$STAGING/$APP_BUNDLE/Contents/Info.plist"

# Create PkgInfo
echo -n 'APPL????' > "$STAGING/$APP_BUNDLE/Contents/PkgInfo"

# ── Step 3: Generate app icon (simple link-chain icon) ──
echo "→ Generating app icon…"
ICONSET="$STAGING/ShortURL.iconset"
mkdir -p "$ICONSET"

# Generate a simple icon using Python (AppleScript-style workaround)
# We create a minimal 1024x1024 PNG with a blue rounded-rect + link symbol
python3 "$PROJECT_DIR/scripts/generate_icon.py" "$ICONSET" 2>/dev/null || {
    echo "   Python icon generator not available; using generic icon."
    # Create a minimal valid PNG as placeholder (1x1 blue pixel)
    # This won't look great but makes the bundle valid
    python3 -c "
import struct, zlib
def create_png(w, h, r, g, b):
    def chunk(ctype, data):
        c = ctype + data
        return struct.pack('>I', len(data)) + c + struct.pack('>I', zlib.crc32(c) & 0xffffffff)
    raw = b''
    for y in range(h):
        raw += b'\x00'
        for x in range(w):
            raw += bytes([r, g, b])
    return b'\x89PNG\r\n\x1a\n' + chunk(b'IHDR', struct.pack('>IIBBBBB', w, h, 8, 2, 0, 0, 0)) + chunk(b'IDAT', zlib.compress(raw)) + chunk(b'IEND', b'')
png = create_png(1024, 1024, 30, 100, 220)
with open('$ICONSET/icon_512x512@2x.png', 'wb') as f:
    f.write(png)
" 2>/dev/null || true
}

# Use iconutil to create .icns from the iconset
if ls "$ICONSET"/icon_*.png >/dev/null 2>&1; then
    iconutil -c icns "$ICONSET" -o "$STAGING/$APP_BUNDLE/Contents/Resources/AppIcon.icns" 2>/dev/null && \
    echo "   Icon created successfully" || \
    echo "   Warning: iconutil failed, app will use default icon"
fi
rm -rf "$ICONSET"

# ── Step 4: Ad-hoc code sign ──
echo ""
echo "→ Signing app (ad-hoc)…"
codesign --force --deep --sign - "$STAGING/$APP_BUNDLE" 2>&1 || {
    echo "   Warning: ad-hoc signing failed; app may require right-click → Open"
}

echo "   App bundle created: $STAGING/$APP_BUNDLE"

# ── Step 5: Create .dmg ──
echo ""
echo "→ Creating .dmg…"
DMG_PATH="$PROJECT_DIR/$DMG_NAME"
rm -f "$DMG_PATH"

# Create a temporary mount point
TMP_DMG="$STAGING/tmp.dmg"

# Create the DMG
hdiutil create -volname "ShortURL" \
    -srcfolder "$STAGING/$APP_BUNDLE" \
    -ov -format UDZO \
    -imagekey zlib-level=9 \
    "$TMP_DMG" 2>&1 | tail -1

# Move to final location
mv "$TMP_DMG" "$DMG_PATH"

echo ""
echo "═══ Build Complete ═══"
echo ""
echo "  App:  $STAGING/$APP_BUNDLE"
echo "  DMG:  $DMG_PATH"
echo ""
echo "To run the app:"
echo "  open $STAGING/$APP_BUNDLE"
echo ""
echo "To use short.url links, add this line to /etc/hosts:"
echo "  127.0.0.1  short.url"
echo "  (sudo nano /etc/hosts)"
echo ""
echo "Then open http://short.url:8080 in your browser."
echo ""
echo "For Apple Silicon Gatekeeper bypass:"
echo "  Right-click the app → Open (first launch only)"
