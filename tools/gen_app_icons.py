#!/usr/bin/env python3
"""App icons for every platform (web, macOS, iOS, Android, Windows, Linux) and the in-app logo, from the icon master.

The icon is "Geared Ring": a navy planet whose ring is the RoboCore gear seen edge-on, in one
flat ink on the RoboCore-yellow plate. tools/app_icon/layout.js lays the master geometry out on
each plate shape (the same geometry as the Figma file "RoboCore IDE — App Icon"); this script
rasterises it with supersampling and writes the files each platform expects.

    python3 tools/gen_app_icons.py [--preview DIR]

Needs Node, Pillow and numpy. --preview also writes a contact sheet of the main sizes to DIR.
"""
import argparse
import json
import math
import os
import re
import struct
import subprocess
import sys
from io import BytesIO

import numpy as np
from PIL import Image, ImageDraw, ImageFilter

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
CANVAS = 1024
MAC = ('macos', 'Runner', 'Assets.xcassets', 'AppIcon.appiconset')
MAC_ICON = ('macos', 'Runner', 'AppIcon.icon')
IOS = ('ios', 'Runner', 'Assets.xcassets', 'AppIcon.appiconset')
RES = ('android', 'app', 'src', 'main', 'res')
ANDROID_DPI = (('mdpi', 1), ('hdpi', 1.5), ('xhdpi', 2), ('xxhdpi', 3), ('xxxhdpi', 4))


def load_layout():
    out = subprocess.run(['node', os.path.join(ROOT, 'tools', 'app_icon', 'layout.js')],
                         check=True, capture_output=True, text=True).stdout
    return json.loads(out)


# ---------- path data → polygons ----------

def subpaths(d, px_per_unit):
    """Absolute M/L/C/Z path data → list of closed polygons, curves flattened to short chords."""
    tokens = re.findall(r'[MLCZ]|-?\d*\.?\d+(?:e[-+]?\d+)?', d)
    polys, cur, i, cmd = [], [], 0, None
    while i < len(tokens):
        t = tokens[i]
        if t in 'MLCZ':
            cmd = t
            i += 1
            if cmd == 'Z':
                if cur:
                    polys.append(cur)
                cur = []
            continue
        if cmd == 'M':
            if cur:
                polys.append(cur)
            cur = [(float(tokens[i]), float(tokens[i + 1]))]
            i += 2
        elif cmd == 'L':
            cur.append((float(tokens[i]), float(tokens[i + 1])))
            i += 2
        elif cmd == 'C':
            p0 = cur[-1]
            p1, p2, p3 = [(float(tokens[i + k]), float(tokens[i + k + 1])) for k in (0, 2, 4)]
            ctrl = math.dist(p0, p1) + math.dist(p1, p2) + math.dist(p2, p3)
            n = max(2, min(256, math.ceil(ctrl * px_per_unit / 4)))  # chords of 4 px or less
            for k in range(1, n + 1):
                u = k / n
                a, b, c, e = (1 - u) ** 3, 3 * (1 - u) ** 2 * u, 3 * (1 - u) * u * u, u ** 3
                cur.append((a * p0[0] + b * p1[0] + c * p2[0] + e * p3[0],
                            a * p0[1] + b * p1[1] + c * p2[1] + e * p3[1]))
            i += 6
        else:
            raise ValueError(f'unexpected token {t!r} in path data')
    if cur:
        polys.append(cur)
    return polys


def inside(pt, poly):
    x, y = pt
    hit = False
    for (x0, y0), (x1, y1) in zip(poly, poly[1:] + poly[:1]):
        if (y0 > y) != (y1 > y) and x < x0 + (y - y0) * (x1 - x0) / (y1 - y0):
            hit = not hit
    return hit


def is_hole(poly, drawn):
    sample = poly[::max(1, len(poly) // 16)]
    return any(all(inside(pt, p) for pt in sample) for p in drawn)


def mask(d, size, ss):
    """Supersampled coverage mask (L mode, size*ss square) of a path on the 1024 canvas.
    Pieces are unioned (the ring's halves meet edge to edge); a piece inside another is a hole."""
    s = size * ss / CANVAS
    m = Image.new('L', (size * ss, size * ss), 0)
    draw = ImageDraw.Draw(m)
    drawn = []
    for poly in subpaths(d, s):
        hole = is_hole(poly, drawn)
        draw.polygon([(x * s, y * s) for x, y in poly], fill=0 if hole else 255)
        drawn.append(poly)
    return m


def coverage(m, size, ss):
    """Box-filter a supersampled mask down to size × size coverage in 0..1."""
    a = np.asarray(m, dtype=np.float32).reshape(size, ss, size, ss)
    return np.divide(a.mean(axis=(1, 3)), 255.0)


def supersample(size):
    return max(4, math.ceil(2048 / size))


def rgb(hex_colour):
    return np.array([int(hex_colour[k:k + 2], 16) for k in (1, 3, 5)], dtype=np.float32)


# ---------- icons ----------

def render_icon(layout, shape, size, look='Default', small=None):
    """Plate + glyph. small=None picks the small glyph at 32 px and below where the shape has one."""
    if small is None:
        small = size <= 32 and shape + '/small' in layout['icons']
    spec = layout['icons'][shape + '/small' if small else shape]
    colours = layout['looks'][look]
    ss = supersample(size)
    plate_hr = mask(spec['plate'], size, ss)
    glyph_hr = Image.fromarray(np.minimum(np.asarray(mask(spec['glyph'], size, ss)), np.asarray(plate_hr)))
    p = coverage(plate_hr, size, ss)
    g = coverage(glyph_hr, size, ss)
    plate_only = np.subtract(p, g)
    premult = np.add(np.multiply(g[..., None], rgb(colours['ink'])),
                     np.multiply(plate_only[..., None], rgb(colours['plate'])))
    alpha = p
    if spec['shadow']:
        sh = spec['shadow']
        k = size * ss / CANVAS
        shadow_hr = Image.new('L', plate_hr.size, 0)
        shadow_hr.paste(plate_hr, (0, round(sh['dy'] * k)))
        # Figma's blur radius is twice the Gaussian sigma
        shadow_hr = shadow_hr.filter(ImageFilter.GaussianBlur(sh['blur'] / 2 * k))
        s = np.multiply(coverage(shadow_hr, size, ss), sh['opacity'])
        alpha = np.add(p, np.multiply(s, np.subtract(1.0, p)))  # black shadow under the plate
    return to_image(premult, alpha)


def render_glyph(layout, kind, size, look='Default'):
    """Glyph on a transparent canvas."""
    spec = layout['glyphOnly'][kind]
    ss = supersample(size)
    g = coverage(mask(spec['glyph'], size, ss), size, ss)
    premult = np.multiply(g[..., None], rgb(layout['looks'][look]['ink']))
    return to_image(premult, g)


def to_image(premult, alpha):
    safe = np.maximum(alpha, 1e-6)[..., None]
    colour = np.where(alpha[..., None] > 0, np.divide(premult, safe), 0.0)
    rgba = np.concatenate([colour, np.multiply(alpha, 255.0)[..., None]], axis=2)
    im = Image.fromarray(np.clip(np.rint(rgba), 0, 255).astype(np.uint8), 'RGBA')
    return im.convert('RGB') if alpha.min() >= 1.0 else im


def densify(poly, step=1.0):
    out = []
    for a, b in zip(poly, poly[1:] + poly[:1]):
        n = max(1, math.ceil(math.dist(a, b) / step))
        out += [(a[0] + (b[0] - a[0]) * k / n, a[1] + (b[1] - a[1]) * k / n) for k in range(n)]
    return out


def edge_margin(layout, shape):
    """Smallest distance (1024 grid) from the glyph to the plate edge, measured on the outlines."""
    spec = layout['icons'][shape]
    plate = np.array([pt for poly in subpaths(spec['plate'], 4) for pt in densify(poly)])
    glyph = np.array([pt for poly in subpaths(spec['glyph'], 4) for pt in poly])
    best = math.inf
    for chunk in np.array_split(glyph, max(1, len(glyph) // 512)):
        dx = np.subtract.outer(chunk[:, 0], plate[:, 0])
        dy = np.subtract.outer(chunk[:, 1], plate[:, 1])
        best = min(best, float(np.sqrt(np.add(np.square(dx), np.square(dy))).min()))
    return best


# ---------- files ----------

def path(*parts):
    p = os.path.join(ROOT, *parts)
    os.makedirs(os.path.dirname(p), exist_ok=True)
    return p


def save(im, *parts):
    im.save(path(*parts), optimize=True)


def write_ico(images, *parts):
    """.ico with one PNG per size (Windows Vista and later read PNG entries)."""
    blobs = []
    for im in images:
        buf = BytesIO()
        im.save(buf, 'PNG', optimize=True)
        blobs.append(buf.getvalue())
    offset = 6 + 16 * len(images)
    out = [struct.pack('<HHH', 0, 1, len(images))]
    for im, blob in zip(images, blobs):
        w = im.width if im.width < 256 else 0
        out.append(struct.pack('<BBBBHHII', w, w, 0, 0, 1, 32, len(blob), offset))
        offset += len(blob)
    with open(path(*parts), 'wb') as f:
        f.write(b''.join(out + blobs))


def write_text(text, *parts):
    with open(path(*parts), 'w') as f:
        f.write(text)


def favicon_svg(layout):
    """Small glyph on the rounded plate; switches to the Dark look with the browser's theme."""
    spec = layout['icons']['Rounded/small']
    d, n = layout['looks']['Default'], layout['looks']['Dark']
    return ('<svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 1024 1024">\n'
            f'<style>.p{{fill:{d["plate"]}}}.i{{fill:{d["ink"]}}}'
            f'@media (prefers-color-scheme:dark){{.p{{fill:{n["plate"]}}}.i{{fill:{n["ink"]}}}}}</style>\n'
            f'<path class="p" d="{one_decimal(spec["plate"])}"/>\n'
            f'<path class="i" d="{one_decimal(spec["glyph"])}"/>\n'
            '</svg>\n')


def one_decimal(d):
    return re.sub(r'(\.\d)\d+', r'\1', d)


def layout_ink(layout):
    return layout['looks']['Default']['ink']


def mark_svg(layout, fit, ink):
    """The glyph alone, cropped to its bounds: the in-app logo mark (recoloured by the app)."""
    m = layout['marks'][fit]
    x0, y0, x1, y1 = m['box']
    paths = ''.join(f'<path fill="{ink}" fill-rule="evenodd" d="{one_decimal(l["d"])}"/>\n' for l in m['layers'])
    return (f'<svg xmlns="http://www.w3.org/2000/svg" viewBox="{x0:g} {y0:g} {x1 - x0:.1f} {y1 - y0:.1f}">\n'
            f'{paths}</svg>\n')


def app_icon_svg(layout):
    """The Rounded app icon (Default look) as the app shows it, e.g. on the Welcome card."""
    look, k = layout['looks']['Default'], layout['roundedScale']
    paths = ''.join(f'<path fill-rule="evenodd" d="{one_decimal(l["d"])}"/>\n' for l in layout['marks']['master']['layers'])
    return ('<svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 1024 1024">\n'
            f'<path fill="{look["plate"]}" d="{one_decimal(layout["icons"]["Rounded"]["plate"])}"/>\n'
            f'<g fill="{look["ink"]}" transform="translate(512 512) scale({k:.4f}) translate(-512 -512)">\n{paths}</g>\n'
            '</svg>\n')


def srgb(hex_colour):
    return 'srgb:' + ','.join(f'{v / 255:.5f}' for v in rgb(hex_colour)) + ',1.00000'


def icon_composer_glyph(layout):
    """The full-bleed glyph on the 1024 canvas, the one layer of the Icon Composer icon."""
    return ('<svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 1024 1024">\n'
            f'<path fill="{layout_ink(layout)}" fill-rule="evenodd" d="{one_decimal(layout["icons"]["Square"]["glyph"])}"/>\n'
            '</svg>\n')


def icon_composer_json(layout):
    """macOS 26 draws app icons with Liquid Glass. Given only PNGs it turns the flat glyph into frosted
    glass, which looks blurred in the Dock, so the icon is an Icon Composer document: the plate colour
    as the fill and the glyph as one layer with the glass off. In dark, clear and tinted the system draws
    its own backdrop, and the glyph takes the Dark or Tinted ink."""
    looks = layout['looks']

    def solid(hex_colour):
        return {'solid': srgb(hex_colour)}

    return {
        'fill': solid(looks['Default']['plate']),
        'groups': [{
            'layers': [{
                'fill-specializations': [
                    {'appearance': 'dark', 'value': solid(looks['Dark']['ink'])},
                    {'appearance': 'tinted', 'value': solid(looks['Tinted']['ink'])},
                ],
                'glass': False,
                'image-name': 'GearedRing.svg',
                'name': 'GearedRing',
            }],
            'shadow': {'kind': 'none', 'opacity': 0},
            'translucency': {'enabled': False, 'value': 0},
        }],
        'supported-platforms': {'squares': ['macOS']},
    }


IOS_CONTENTS = {
    'images': [
        {'filename': 'Icon-App-1024x1024@1x.png', 'idiom': 'universal', 'platform': 'ios', 'size': '1024x1024'},
        {'appearances': [{'appearance': 'luminosity', 'value': 'dark'}],
         'filename': 'Icon-App-Dark-1024x1024@1x.png', 'idiom': 'universal', 'platform': 'ios', 'size': '1024x1024'},
        {'appearances': [{'appearance': 'luminosity', 'value': 'tinted'}],
         'filename': 'Icon-App-Tinted-1024x1024@1x.png', 'idiom': 'universal', 'platform': 'ios', 'size': '1024x1024'},
    ],
    'info': {'author': 'xcode', 'version': 1},
}

ADAPTIVE_ICON = '''<?xml version="1.0" encoding="utf-8"?>
<adaptive-icon xmlns:android="http://schemas.android.com/apk/res/android">
    <background android:drawable="@color/ic_launcher_background"/>
    <foreground android:drawable="@mipmap/ic_launcher_foreground"/>
    <monochrome android:drawable="@mipmap/ic_launcher_monochrome"/>
</adaptive-icon>
'''


def main():
    ap = argparse.ArgumentParser(description=__doc__.split('\n')[0])
    ap.add_argument('--preview', metavar='DIR', help='also write a contact sheet to DIR')
    args = ap.parse_args()
    L = load_layout()

    # macOS: Apple's grid (824 plate in a 1024 canvas, shadow inside); 16 and 32 use the small glyph.
    for n in (16, 32, 64, 128, 256, 512, 1024):
        save(render_icon(L, 'macOS', n), *MAC, f'app_icon_{n}.png')
    # macOS 26 and later: the Icon Composer document. Xcode 26 uses it instead of the PNGs above (and
    # makes the images for older macOS from it); older Xcode versions still use the PNGs.
    write_text(icon_composer_glyph(L), *MAC_ICON, 'Assets', 'GearedRing.svg')
    write_text(json.dumps(icon_composer_json(L), indent=2) + '\n', *MAC_ICON, 'icon.json')

    # iOS: one opaque square 1024 per appearance; Xcode makes the smaller sizes.
    # Dark is the glyph on transparent (iOS draws the dark backdrop); Tinted is greyscale.
    save(render_icon(L, 'Square', 1024), *IOS, 'Icon-App-1024x1024@1x.png')
    save(render_glyph(L, 'ios-dark', 1024, 'Dark'), *IOS, 'Icon-App-Dark-1024x1024@1x.png')
    save(render_icon(L, 'Square', 1024, 'Tinted'), *IOS, 'Icon-App-Tinted-1024x1024@1x.png')
    write_text(json.dumps(IOS_CONTENTS, indent=2) + '\n', *IOS, 'Contents.json')
    ios_dir = os.path.join(ROOT, *IOS)
    for f in os.listdir(ios_dir):  # the per-size PNGs of the old Contents.json
        if f.endswith('.png') and f not in {i['filename'] for i in IOS_CONTENTS['images']}:
            os.remove(os.path.join(ios_dir, f))

    # Android: adaptive icon (yellow colour background, glyph foreground inside the 66 dp safe
    # circle, monochrome layer for themed icons), the legacy 48 dp icon and the Play Store icon.
    for dpi, scale in ANDROID_DPI:
        save(render_icon(L, 'Rounded', round(48 * scale)), *RES, f'mipmap-{dpi}', 'ic_launcher.png')
        layer = render_glyph(L, 'android', round(108 * scale))
        save(layer, *RES, f'mipmap-{dpi}', 'ic_launcher_foreground.png')
        save(layer, *RES, f'mipmap-{dpi}', 'ic_launcher_monochrome.png')
    write_text(ADAPTIVE_ICON, *RES, 'mipmap-anydpi-v26', 'ic_launcher.xml')
    write_text('<?xml version="1.0" encoding="utf-8"?>\n<resources>\n'
               f'    <color name="ic_launcher_background">{L["looks"]["Default"]["plate"]}</color>\n'
               '</resources>\n', *RES, 'values', 'ic_launcher_background.xml')
    save(render_icon(L, 'Square', 512), 'android', 'play_store_512.png')

    # Windows: unmasked, so the rounded plate is part of the art.
    write_ico([render_icon(L, 'Rounded', n) for n in (16, 24, 32, 48, 64, 256)],
              'windows', 'runner', 'resources', 'app_icon.ico')

    # Linux: window icon, installed into the bundle's data folder.
    save(render_icon(L, 'Rounded', 256), 'linux', 'runner', 'resources', 'app_icon.png')

    # Web: SVG favicon (light and dark), PNG fallback, PWA icons and the iOS home-screen icon.
    write_text(favicon_svg(L), 'web', 'favicon.svg')
    save(render_icon(L, 'Rounded', 32), 'web', 'favicon.png')
    for n in (192, 512):
        save(render_icon(L, 'Rounded', n), 'web', 'icons', f'Icon-{n}.png')
        save(render_icon(L, 'Maskable', n), 'web', 'icons', f'Icon-maskable-{n}.png')
    save(render_icon(L, 'Square', 180), 'web', 'icons', 'apple-touch-icon.png')

    # In-app logo (top bar, Welcome card): the small mark and the app icon, as SVG.
    write_text(mark_svg(L, 'small', layout_ink(L)), 'assets', 'images', 'app_mark.svg')
    write_text(app_icon_svg(L), 'assets', 'images', 'app_icon.svg')

    for shape in L['icons']:
        print(f'{shape:14} glyph {edge_margin(L, shape):5.1f} px from the plate edge (1024 grid)')
    if args.preview:
        contact_sheet(L, args.preview)
    print('icons written')


def contact_sheet(L, out_dir):
    """Main sizes side by side, the small ones also enlarged 8× (nearest neighbour)."""
    os.makedirs(out_dir, exist_ok=True)
    rows = []
    for shape, look in (('macOS', 'Default'), ('Rounded', 'Default'), ('Rounded', 'Dark'),
                        ('Square', 'Tinted'), ('Maskable', 'Default')):
        tiles = [render_icon(L, shape, 256, look)]
        for n in (32, 16):
            im = render_icon(L, shape, n, look).convert('RGBA')
            tiles += [im, im.resize((n * 8, n * 8), Image.Resampling.NEAREST)]
        rows.append(tiles)
    w = max(sum(t.width + 24 for t in r) for r in rows) + 24
    h = sum(max(t.height for t in r) + 24 for r in rows) + 24
    sheet = Image.new('RGBA', (w, h), (233, 226, 210, 255))
    y = 24
    for r in rows:
        x = 24
        for t in r:
            sheet.alpha_composite(t.convert('RGBA'), (x, y))
            x += t.width + 24
        y += max(t.height for t in r) + 24
    sheet.save(os.path.join(out_dir, 'contact_sheet.png'))
    big = Image.new('RGBA', (2048 + 72, 1024 + 48), (233, 226, 210, 255))
    big.alpha_composite(render_icon(L, 'macOS', 1024).convert('RGBA'), (24, 24))
    big.alpha_composite(render_icon(L, 'Rounded', 1024).convert('RGBA'), (1072, 24))
    big.save(os.path.join(out_dir, 'master_1024.png'))
    print('preview written to', out_dir)


if __name__ == '__main__':
    sys.exit(main())
