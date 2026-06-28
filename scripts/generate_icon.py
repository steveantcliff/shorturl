#!/usr/bin/env python3
"""Generate app icon for short.url — a blue rounded-rect with a link symbol.
Pure Python, no dependencies beyond the standard library."""

import struct
import zlib
import sys
import os


def create_png(width, height, pixels):
    """pixels is a list of (r, g, b) tuples, row-major."""
    def chunk(ctype, data):
        c = ctype + data
        crc = zlib.crc32(c) & 0xFFFFFFFF
        return struct.pack('>I', len(data)) + c + struct.pack('>I', crc)

    # Build raw image data with filter byte 0 per row
    raw = b''
    for y in range(height):
        raw += b'\x00'  # filter: None
        for x in range(width):
            r, g, b = pixels[y * width + x]
            raw += bytes([r, g, b])

    ihdr = struct.pack('>IIBBBBB', width, height, 8, 2, 0, 0, 0)

    return (
        b'\x89PNG\r\n\x1a\n'
        + chunk(b'IHDR', ihdr)
        + chunk(b'IDAT', zlib.compress(raw))
        + chunk(b'IEND', b'')
    )


def blend(bg, fg, alpha):
    """Alpha blend fg over bg. alpha is 0-255."""
    a = alpha / 255.0
    return tuple(int(bg[i] * (1 - a) + fg[i] * a) for i in range(3))


def draw_rounded_rect(pixels, w, h, x0, y0, x1, y1, radius, color):
    """Draw a filled rounded rectangle."""
    for y in range(max(0, y0), min(h, y1)):
        for x in range(max(0, x0), min(w, x1)):
            # Check rounded corners
            inside = True
            if x < x0 + radius:
                dx = x0 + radius - x
                if y < y0 + radius:
                    dy = y0 + radius - y
                    inside = (dx * dx + dy * dy) <= radius * radius
                elif y >= y1 - radius:
                    dy = y - (y1 - radius)
                    inside = (dx * dx + dy * dy) <= radius * radius
            elif x >= x1 - radius:
                dx = x - (x1 - radius)
                if y < y0 + radius:
                    dy = y0 + radius - y
                    inside = (dx * dx + dy * dy) <= radius * radius
                elif y >= y1 - radius:
                    dy = y - (y1 - radius)
                    inside = (dx * dx + dy * dy) <= radius * radius
            if inside:
                pixels[y * w + x] = color


def draw_circle(pixels, w, h, cx, cy, r, color):
    """Draw a filled circle."""
    for y in range(max(0, int(cy - r)), min(h, int(cy + r + 1))):
        for x in range(max(0, int(cx - r)), min(w, int(cx + r + 1))):
            dx = x - cx
            dy = y - cy
            if dx * dx + dy * dy <= r * r:
                pixels[y * w + x] = color


def draw_chain_link(pixels, w, h, cx, cy, size, color):
    """Draw a chain-link icon using two overlapping rounded shapes."""
    s = size
    # Top link (left-leaning oval)
    link_w = int(s * 0.55)
    link_h = int(s * 0.22)
    link_spacing = int(s * 0.35)
    thickness = max(3, int(s * 0.08))

    # Draw two overlapping links
    for i, (lx, ly) in enumerate([(cx - link_spacing // 2, cy - s // 6),
                                  (cx + link_spacing // 2, cy + s // 6)]):
        # Draw elongated circle (ellipse approximation)
        for y in range(max(0, ly - link_h), min(h, ly + link_h + 1)):
            for x in range(max(0, lx - link_w), min(w, lx + link_w + 1)):
                # Ellipse check
                dx = (x - lx) / link_w
                dy = (y - ly) / link_h
                d = dx * dx + dy * dy
                if d <= 1.0 and d >= 0.6:  # ring shape
                    pixels[y * w + x] = color


def generate_icon(size):
    """Generate a square icon at given size. Returns PNG bytes."""
    pixels = [(0, 0, 0, 0)] * (size * size)  # We'll use 4-tuples temporarily

    # Background: gradient blue
    bg_top = (60, 140, 240)
    bg_bottom = (20, 80, 200)

    for y in range(size):
        t = y / size
        r = int(bg_top[0] * (1 - t) + bg_bottom[0] * t)
        g = int(bg_top[1] * (1 - t) + bg_bottom[1] * t)
        b = int(bg_top[2] * (1 - t) + bg_bottom[2] * t)
        for x in range(size):
            pixels[y * size + x] = (r, g, b)

    # Rounded rectangle mask (for icon shape)
    margin = int(size * 0.18)
    radius = int(size * 0.22)

    # Draw chain-link symbol in white
    cx, cy = size // 2, size // 2
    link_size = int(size * 0.45)
    white = (255, 255, 255)

    # Draw two interlocking rounded shapes
    draw_chain_link(pixels, size, size, cx, cy, link_size, white)

    # Convert to 3-tuple RGB
    return [(p[0], p[1], p[2]) for p in pixels]


def main():
    iconset_dir = sys.argv[1] if len(sys.argv) > 1 else "ShortURL.iconset"

    # Icon sizes for macOS iconset
    sizes = {
        "icon_16x16.png": 16,
        "icon_16x16@2x.png": 32,
        "icon_32x32.png": 32,
        "icon_32x32@2x.png": 64,
        "icon_128x128.png": 128,
        "icon_128x128@2x.png": 256,
        "icon_256x256.png": 256,
        "icon_256x256@2x.png": 512,
        "icon_512x512.png": 512,
        "icon_512x512@2x.png": 1024,
    }

    os.makedirs(iconset_dir, exist_ok=True)

    for filename, size in sizes.items():
        filepath = os.path.join(iconset_dir, filename)
        png_data = create_png(size, size, generate_icon(size))
        with open(filepath, 'wb') as f:
            f.write(png_data)
        print(f"  Created {filename} ({size}x{size})")

    print(f"Iconset created at: {iconset_dir}")


if __name__ == "__main__":
    main()
