"""Draw OpenXP's objective icons: plain silver glyphs with a thin dark
outline and a soft shadow, no circle behind them (the look quest-map
addons use), in OpenXP's own drawings.

    python3 tools/make_objective_icons.py

Writes OpenXP/Media/Map/<name>.tga, <name>_64.tga and <name>_32.tga for
kill (a sword), loot (a sack), object (a cog: use or click), talk (a speech
bubble), boss (a skull), chest, event (a star), travel (footsteps) and
town (a house), and objective_glow (a soft white disc the map tints in
each objective's colour behind its icon). The same files are the
card's step icons and the nameplate markers, so every OpenXP icon matches.
The "!" and "?" quest icons are tools/make_ui_icons.py's quest_* files.
Needs Pillow (numpy optional). Reuses tools/make_icons.py's helpers.
"""
import math
import os
import sys

from PIL import Image, ImageChops, ImageDraw, ImageFilter

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import make_icons as mi  # noqa: E402

S = mi.S          # drawn at 512, saved at 128 / 64 / 32
C = S // 2
OUT = mi.OUT


def mask(draw_fn):
    m = Image.new("L", (S, S), 0)
    draw_fn(ImageDraw.Draw(m))
    return m


def silver(m, outline=26, shadow_offset=14):
    """Silver glyph (light at the top, darker below), a thin dark outline
    and a soft drop shadow."""
    out = Image.new("RGBA", (S, S), (0, 0, 0, 0))
    # shadow
    sh = m.filter(ImageFilter.MaxFilter(outline | 1)).filter(ImageFilter.GaussianBlur(18))
    sh = ImageChops.offset(sh, shadow_offset, shadow_offset).point(lambda v: v * 140 // 255)
    dark = Image.new("RGBA", (S, S), (0, 0, 0, 255))
    dark.putalpha(sh)
    out.alpha_composite(dark)
    # outline
    edge = m.filter(ImageFilter.MaxFilter(outline | 1))
    ol = Image.new("RGBA", (S, S), (22, 22, 26, 255))
    ol.putalpha(edge)
    out.alpha_composite(ol)
    # silver body: vertical gradient
    grad = Image.new("RGBA", (S, S))
    gd = ImageDraw.Draw(grad)
    for y in range(S):
        t = y / (S - 1)
        v = int(242 - 80 * t)
        gd.line((0, y, S, y), fill=(v, v, min(255, v + 6), 255))
    grad.putalpha(m)
    out.alpha_composite(grad)
    # a faint highlight line along the top edges
    hi = ImageChops.subtract(m, ImageChops.offset(m, 0, 10)).point(lambda v: v * 90 // 255)
    white = Image.new("RGBA", (S, S), (255, 255, 255, 255))
    white.putalpha(hi)
    out.alpha_composite(white)
    return out


def save(img, name):
    for size in (128, 64, 32):
        im = mi.premultiplied_resize(img, size)
        if size <= 32:
            im = mi.sharpen_small(im)
        mi.write_tga(im, os.path.join(OUT, name + ("" if size == 128 else "_%d" % size) + ".tga"))


def sword(d):
    """One sword, point up-right (like a slay icon)."""
    m = Image.new("L", (S, S), 0)
    dd = ImageDraw.Draw(m)
    tip, base = C - 210, C + 90
    dd.polygon([(C, tip), (C + 36, tip + 80), (C + 36, base), (C - 36, base), (C - 36, tip + 80)], fill=255)
    dd.rounded_rectangle((C - 105, base, C + 105, base + 40), 16, fill=255)
    dd.rectangle((C - 20, base + 40, C + 20, base + 125), fill=255)
    dd.ellipse((C - 38, base + 115, C + 38, base + 191), fill=255)
    return m.rotate(-45, resample=Image.BICUBIC, center=(C, C))


def sack(d):
    d.ellipse((C - 185, C - 50, C + 185, C + 215), fill=255)
    d.polygon([(C - 75, C - 30), (C + 75, C - 30), (C + 125, C - 165), (C - 125, C - 165)], fill=255)
    d.rounded_rectangle((C - 105, C - 100, C + 105, C - 52), 18, fill=0)
    d.rounded_rectangle((C - 88, C - 92, C + 88, C - 60), 14, fill=255)


def cog(d):
    r_out, r_in, teeth = 205, 150, 8
    pts = []
    for i in range(teeth * 4):
        a = math.pi * 2 * i / (teeth * 4)
        r = r_out if (i % 4) in (1, 2) else r_in
        pts.append((C + math.cos(a) * r, C + math.sin(a) * r))
    d.polygon(pts, fill=255)
    d.ellipse((C - 62, C - 62, C + 62, C + 62), fill=0)


def bubble(d):
    d.rounded_rectangle((C - 215, C - 175, C + 215, C + 115), 70, fill=255)
    d.polygon([(C - 120, C + 100), (C - 20, C + 100), (C - 150, C + 215)], fill=255)
    for dx in (-110, 0, 110):
        d.ellipse((C + dx - 34, C - 64, C + dx + 34, C + 4), fill=0)


def skull(d):
    d.ellipse((C - 190, C - 215, C + 190, C + 125), fill=255)
    d.rounded_rectangle((C - 115, C + 60, C + 115, C + 210), 30, fill=255)
    d.ellipse((C - 130, C - 80, C - 30, C + 30), fill=0)
    d.ellipse((C + 30, C - 80, C + 130, C + 30), fill=0)
    d.polygon([(C, C + 40), (C - 30, C + 95), (C + 30, C + 95)], fill=0)
    for dx in (-60, 0, 60):
        d.rectangle((C + dx - 12, C + 140, C + dx + 12, C + 210), fill=0)


def chest(d):
    d.rounded_rectangle((C - 210, C - 150, C + 210, C - 10), 60, fill=255)   # lid
    d.rectangle((C - 210, C + 10, C + 210, C + 190), fill=255)              # box
    d.rounded_rectangle((C - 40, C - 50, C + 40, C + 70), 14, fill=0)       # lock hole
    d.rounded_rectangle((C - 24, C - 34, C + 24, C + 54), 10, fill=255)


def star(d):
    pts = []
    for i in range(10):
        a = -math.pi / 2 + math.pi * i / 5
        r = 225 if i % 2 == 0 else 95
        pts.append((C + math.cos(a) * r, C + math.sin(a) * r))
    d.polygon(pts, fill=255)


def steps(d):
    for dx, dy in ((-90, 45), (90, -75)):
        x, y = C + dx, C + dy
        d.ellipse((x - 66, y - 125, x + 66, y + 62), fill=255)
        d.ellipse((x - 50, y + 84, x + 50, y + 175), fill=255)


def house(d):
    d.polygon([(C, C - 215), (C + 225, C - 10), (C - 225, C - 10)], fill=255)
    d.rectangle((C - 160, C - 30, C + 160, C + 200), fill=255)
    d.rectangle((C - 48, C + 65, C + 48, C + 200), fill=0)
    d.rectangle((C + 90, C - 185, C + 145, C - 75), fill=255)


def glow_disc():
    """A soft white disc: solid in the middle, fading out at the rim. The
    map tints it per objective and draws it just bigger than the icon."""
    m = Image.new("L", (S, S), 0)
    r = int(S * 0.40)
    ImageDraw.Draw(m).ellipse((C - r, C - r, C + r, C + r), fill=255)
    m = m.filter(ImageFilter.GaussianBlur(S // 28))
    out = Image.new("RGBA", (S, S), (255, 255, 255, 0))
    out.putalpha(m.point(lambda v: v * 230 // 255))
    return out


def main():
    save(silver(sword(None)), "kill")
    save(silver(mask(sack)), "loot")
    save(silver(mask(cog)), "object")
    save(silver(mask(bubble)), "talk")
    save(silver(mask(skull)), "boss")
    save(silver(mask(chest)), "chest")
    save(silver(mask(star)), "event")
    save(silver(mask(steps)), "travel")
    save(silver(mask(house)), "town")
    save(glow_disc(), "objective_glow")


if __name__ == "__main__":
    main()
