#!/usr/bin/env python3
"""App icons for the native apps (macOS, Windows, Linux, Android, iOS) from the web icon's gear.

The gear outline is traced once from web/icons/Icon-512.png and redrawn at every size, so the
1024 px icons stay sharp and every platform matches the web app's icon.

    python3 tools/gen_app_icons.py

Needs Pillow, numpy and opencv-python.
"""
import json
import os

import cv2
import numpy as np
from PIL import Image, ImageDraw, ImageFilter

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
YELLOW = (0xF2, 0xB0, 0x1E)
NAVY = (0x1B, 0x2A, 0x41)
SS = 4  # supersampling for smooth edges

# Proportions measured on web/icons/Icon-512.png.
CORNER = 0.18      # rounded-square corner radius / side
GEAR_ROUND = 0.39  # gear tip radius / side, rounded-square icons
GEAR_FULL = 0.33   # full-bleed icons (iOS rounds the corners itself)
GEAR_ADAPTIVE = 0.29  # Android adaptive foreground: inside the 66 dp safe circle of 108 dp


def trace_gear():
    """Returns (outer, hole): polygons in units of the gear's tip radius, centred on the hub."""
    im = Image.open(os.path.join(ROOT, 'web', 'icons', 'Icon-512.png')).convert('RGBA')
    big = im.resize((2048, 2048), Image.Resampling.BICUBIC)
    rgba = np.asarray(big)
    dark = (rgba[:, :, :3].astype(np.int32).sum(axis=2) < 360) & (rgba[:, :, 3] > 128)
    mask = dark.astype(np.uint8) * 255
    contours, hierarchy = cv2.findContours(mask, cv2.RETR_CCOMP, cv2.CHAIN_APPROX_NONE)
    outer_i = max(range(len(contours)), key=lambda i: cv2.contourArea(contours[i]))
    holes = [i for i in range(len(contours)) if hierarchy[0][i][3] == outer_i]
    hole_i = max(holes, key=lambda i: cv2.contourArea(contours[i]))
    (cx, cy), _ = cv2.minEnclosingCircle(contours[hole_i])
    outer = cv2.approxPolyDP(contours[outer_i], 1.0, True).reshape(-1, 2).astype(float)
    hole = cv2.approxPolyDP(contours[hole_i], 1.0, True).reshape(-1, 2).astype(float)
    radius = float(np.hypot(outer[:, 0] - cx, outer[:, 1] - cy).max())
    norm = lambda pts: [((x - cx) / radius, (y - cy) / radius) for x, y in pts]
    return norm(outer), norm(hole)


OUTER, HOLE = trace_gear()


def gear_mask(size, centre, radius):
    """L-mode mask (supersampled, then reduced) with the gear, hub hole cut out."""
    s = size * SS
    m = Image.new('L', (s, s), 0)
    d = ImageDraw.Draw(m)
    place = lambda pts: [((centre[0] + x * radius) * SS, (centre[1] + y * radius) * SS) for x, y in pts]
    d.polygon(place(OUTER), fill=255)
    d.polygon(place(HOLE), fill=0)
    return m.resize((size, size), Image.Resampling.LANCZOS)


def rounded_mask(size, box, corner):
    s = size * SS
    m = Image.new('L', (s, s), 0)
    x0, y0, x1, y1 = (v * SS for v in box)
    ImageDraw.Draw(m).rounded_rectangle((x0, y0, x1 - 1, y1 - 1), radius=corner * SS, fill=255)
    return m.resize((size, size), Image.Resampling.LANCZOS)


def solid(size, rgb, mask):
    im = Image.new('RGBA', (size, size), rgb + (0,))
    im.putalpha(mask)
    return im


def rounded_icon(size, inset=0.0, shadow=False):
    """Yellow rounded square with the navy gear, like the web icon. inset = margin / side."""
    pad = round(size * inset)
    side = size - 2 * pad
    box = (pad, pad, pad + side, pad + side)
    im = Image.new('RGBA', (size, size), (0, 0, 0, 0))
    plate = rounded_mask(size, box, side * CORNER)
    if shadow:
        sh = Image.new('L', (size, size), 0)
        sh.paste(plate.point(lambda a: a * 0.3), (0, round(size * 0.01)))
        sh = sh.filter(ImageFilter.GaussianBlur(size * 0.012))
        im = Image.alpha_composite(im, solid(size, (0, 0, 0), sh))
    im = Image.alpha_composite(im, solid(size, YELLOW, plate))
    gear = gear_mask(size, (size / 2, size / 2), side * GEAR_ROUND)
    return Image.alpha_composite(im, solid(size, NAVY, gear))


def full_bleed_icon(size):
    im = Image.new('RGB', (size, size), YELLOW)
    im.paste(Image.new('RGB', (size, size), NAVY), (0, 0), gear_mask(size, (size / 2, size / 2), size * GEAR_FULL))
    return im


def path(*parts):
    p = os.path.join(ROOT, *parts)
    os.makedirs(os.path.dirname(p), exist_ok=True)
    return p


def main():
    # macOS: Apple's grid puts the 824 px plate inside a 1024 px canvas, with a soft shadow.
    mac = rounded_icon(1024, inset=100 / 1024, shadow=True)
    for n in (16, 32, 64, 128, 256, 512, 1024):
        img = mac if n == 1024 else mac.resize((n, n), Image.Resampling.LANCZOS)
        img.save(path('macos', 'Runner', 'Assets.xcassets', 'AppIcon.appiconset', f'app_icon_{n}.png'))

    # Windows: one .ico with the usual sizes.
    win = rounded_icon(256)
    win.save(path('windows', 'runner', 'resources', 'app_icon.ico'),
             sizes=[(16, 16), (24, 24), (32, 32), (48, 48), (64, 64), (128, 128), (256, 256)])

    # Linux: window icon, installed into the bundle's data folder.
    rounded_icon(256).save(path('linux', 'runner', 'resources', 'app_icon.png'))

    # iOS: full-bleed squares without transparency (iOS masks the corners).
    ios_dir = ('ios', 'Runner', 'Assets.xcassets', 'AppIcon.appiconset')
    contents = json.load(open(path(*ios_dir, 'Contents.json')))
    for img in contents['images']:
        if not img.get('filename'):
            continue
        pts = float(img['size'].split('x')[0])
        n = round(pts * int(img['scale'].rstrip('x')))
        full_bleed_icon(n).save(path(*ios_dir, img['filename']))

    # Android: legacy launcher icons, plus an adaptive icon (yellow background, gear foreground)
    # whose foreground also serves as the monochrome (themed) icon.
    res = ('android', 'app', 'src', 'main', 'res')
    for dpi, scale in (('mdpi', 1), ('hdpi', 1.5), ('xhdpi', 2), ('xxhdpi', 3), ('xxxhdpi', 4)):
        rounded_icon(round(48 * scale), inset=0.04).save(path(*res, f'mipmap-{dpi}', 'ic_launcher.png'))
        n = round(108 * scale)
        solid(n, NAVY, gear_mask(n, (n / 2, n / 2), n * GEAR_ADAPTIVE)).save(
            path(*res, f'mipmap-{dpi}', 'ic_launcher_foreground.png'))
    with open(path(*res, 'mipmap-anydpi-v26', 'ic_launcher.xml'), 'w') as f:
        f.write('<?xml version="1.0" encoding="utf-8"?>\n'
                '<adaptive-icon xmlns:android="http://schemas.android.com/apk/res/android">\n'
                '    <background android:drawable="@color/ic_launcher_background"/>\n'
                '    <foreground android:drawable="@mipmap/ic_launcher_foreground"/>\n'
                '    <monochrome android:drawable="@mipmap/ic_launcher_foreground"/>\n'
                '</adaptive-icon>\n')
    with open(path(*res, 'values', 'ic_launcher_background.xml'), 'w') as f:
        f.write('<?xml version="1.0" encoding="utf-8"?>\n<resources>\n'
                '    <color name="ic_launcher_background">#F2B01E</color>\n</resources>\n')
    print(f'gear: {len(OUTER)} outline points, {len(HOLE)} hub points; icons written')


if __name__ == '__main__':
    main()
