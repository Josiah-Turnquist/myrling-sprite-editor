#!/usr/bin/env python3
# Draws the app icon. The icon is itself a 16 pixel sprite, drawn the way the editor
# wants creatures drawn, scaled up with hard pixels. Writes:
#   mac/AppIcon.iconset/*  and  mac/AppIcon.icns   (via iconutil, macOS only)
#   docs/logo.png                                   (256 px, for the README)
#   docs/favicon.png                                (32 px, embedded in index.html)
# Only the standard library. Run from the repo root: python3 mac/make-icon.py

import os
import struct
import subprocess
import zlib

# a rootling: a small green creature with a sprout, on the editor's own dark canvas
ART = [
    "................",
    "................",
    ".......LL.......",
    "......L..L......",
    ".......GG.......",
    ".....DGGGGD.....",
    "....DGLGGGGD....",
    "...DGLGGGGGGD...",
    "...DGEGGGEGGD...",
    "...DGEGGGEGGD...",
    "...DGGGGGGGGD...",
    "...DGGGDDGGGD...",
    "....DGGGGGGD....",
    ".....DD..DD.....",
    ".....DD..DD.....",
    "................",
]
PAL = {
    'D': (0x4e, 0x7a, 0x2b, 255),   # dark green, the seams
    'G': (0x8b, 0xc2, 0x50, 255),   # the body, the editor's own example colour
    'L': (0xb4, 0xe0, 0x7e, 255),   # light green, the sprout and the lit side
    'E': (0x14, 0x18, 0x0f, 255),   # eyes
}
BG = ((0x12, 0x14, 0x1a, 255), (0x17, 0x1a, 0x20, 255))   # the canvas checkerboard
W = H = 16


def base_pixels():
    px = []
    for y in range(H):
        row = []
        for x in range(W):
            # 2 px of stepped corner so the big sizes read as a rounded tile
            dx, dy = min(x, W - 1 - x), min(y, H - 1 - y)
            if (dx, dy) in ((0, 0), (0, 1), (1, 0)):
                row.append((0, 0, 0, 0))
                continue
            c = ART[y][x]
            row.append(PAL[c] if c in PAL else BG[((x // 4) + (y // 4)) % 2])
        px.append(row)
    return px


def scaled(px, f):
    out = []
    for row in px:
        big = []
        for p in row:
            big.extend([p] * f)
        out.extend([big] * f)
    return out


def write_png(path, px):
    h, w = len(px), len(px[0])
    raw = b''.join(b'\x00' + b''.join(struct.pack('4B', *p) for p in row) for row in px)

    def chunk(tag, data):
        body = tag + data
        return struct.pack('>I', len(data)) + body + struct.pack('>I', zlib.crc32(body))

    with open(path, 'wb') as f:
        f.write(b'\x89PNG\r\n\x1a\n')
        f.write(chunk(b'IHDR', struct.pack('>IIBBBBB', w, h, 8, 6, 0, 0, 0)))
        f.write(chunk(b'IDAT', zlib.compress(raw, 9)))
        f.write(chunk(b'IEND', b''))


def main():
    here = os.path.dirname(os.path.abspath(__file__))
    root = os.path.dirname(here)
    iconset = os.path.join(here, 'AppIcon.iconset')
    docs = os.path.join(root, 'docs')
    os.makedirs(iconset, exist_ok=True)
    os.makedirs(docs, exist_ok=True)

    px = base_pixels()
    # every icon size is a whole multiple of 16, so the pixels stay hard all the way up
    for name, size in [
        ('icon_16x16.png', 16), ('icon_16x16@2x.png', 32),
        ('icon_32x32.png', 32), ('icon_32x32@2x.png', 64),
        ('icon_128x128.png', 128), ('icon_128x128@2x.png', 256),
        ('icon_256x256.png', 256), ('icon_256x256@2x.png', 512),
        ('icon_512x512.png', 512), ('icon_512x512@2x.png', 1024),
    ]:
        write_png(os.path.join(iconset, name), scaled(px, size // 16))
    write_png(os.path.join(docs, 'logo.png'), scaled(px, 16))
    write_png(os.path.join(docs, 'favicon.png'), scaled(px, 2))

    try:
        subprocess.run(['iconutil', '-c', 'icns', iconset, '-o', os.path.join(here, 'AppIcon.icns')], check=True)
        print('Wrote mac/AppIcon.icns, docs/logo.png, docs/favicon.png')
    except (OSError, subprocess.CalledProcessError):
        print('Wrote the PNGs. iconutil was not available, so no .icns; run this on macOS for that.')


if __name__ == '__main__':
    main()
