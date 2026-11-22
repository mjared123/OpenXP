"""Draw OpenXP 2.0's arrow styles, step list icons and quest map icons.

    python3 tools/make_ui_icons.py

Writes
  OpenXP/Media/Card/arrow_*.tga   the arrow's pointer styles (128 px, white,
                                  tinted in game; a soft dark edge is baked
                                  in so they read on snow)
  OpenXP/Media/Card/ring_thin.tga a thin dial ring
  OpenXP/Media/Card/glow.tga      a soft round glow
  OpenXP/Media/Card/history.tga   the card's step list button
  OpenXP/Media/Card/skip.tga      the "skipped" mark in the step list
  OpenXP/Media/Map/quest_*.tga    "!" and "?" in yellow and grey, drawn in
                                  the style quest addons use (128/64/32 px)
Needs Pillow and numpy. Reuses tools/make_icons.py's helpers.
"""
import math
import os
import sys

from PIL import Image, ImageDraw, ImageFilter, ImageFont

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import make_icons as mi  # noqa: E402

ROOT = mi.ROOT
CARD = os.path.join(ROOT, "OpenXP", "Media", "Card")
S = mi.S  # 512: drawn at 4x, saved at 128


def save(img, name, size=128, folder=CARD):
    im = mi.premultiplied_resize(img, size)
    if size <= 32:
        im = mi.sharpen_small(im)
    mi.write_tga(im, os.path.join(folder, name + ".tga"))


def shaped(draw_fn, edge=18, edge_alpha=150, blur=6):
    """A white shape with a soft dark edge around it (no offset: it turns)."""
    m = Image.new("L", (S, S), 0)
    draw_fn(ImageDraw.Draw(m))
    edge_mask = m.filter(ImageFilter.MaxFilter(edge | 1)).filter(ImageFilter.GaussianBlur(blur))
    out = mi.layer()
    dark = Image.new("RGBA", (S, S), (0, 0, 0, 255))
    dark.putalpha(edge_mask.point(lambda v: v * edge_alpha // 255))
    out.alpha_composite(dark)
    white = Image.new("RGBA", (S, S), (255, 255, 255, 255))
    white.putalpha(m)
    out.alpha_composite(white)
    return out


def rounded_poly(d, pts, r):
    """A polygon with rounded corners: the polygon plus a disc on each corner
    and thick edges."""
    d.polygon(pts, fill=255)
    for i, (x, y) in enumerate(pts):
        d.ellipse((x - r, y - r, x + r, y + r), fill=255)
        nx, ny = pts[(i + 1) % len(pts)]
        d.line((x, y, nx, ny), fill=255, width=int(r * 2))


def inset(pts, k):
    cx = sum(p[0] for p in pts) / len(pts)
    cy = sum(p[1] for p in pts) / len(pts)
    return [(cx + (x - cx) * k, cy + (y - cy) * k) for x, y in pts]


C = S // 2


def arrows():
    # chevron: a bold rounded "^" with a notch, like a car's nav arrow
    def chevron(d):
        pts = [(C, C - 190), (C + 150, C + 160), (C, C + 80), (C - 150, C + 160)]
        rounded_poly(d, inset(pts, 0.92), 18)
    save(shaped(chevron), "arrow_chevron")

    # needle: a slim compass needle, bright head and a dimmer tail
    head = shaped(lambda d: rounded_poly(d, [(C, C - 210), (C + 46, C), (C - 46, C)], 8))
    tail_m = Image.new("L", (S, S), 0)
    rounded_poly(ImageDraw.Draw(tail_m), [(C - 46, C), (C + 46, C), (C, C + 190)], 8)
    tail = Image.new("RGBA", (S, S), (255, 255, 255, 255))
    tail.putalpha(tail_m.point(lambda v: v * 95 // 255))
    needle = mi.layer()
    needle.alpha_composite(tail)
    needle.alpha_composite(head)
    hub = mi.layer()
    ImageDraw.Draw(hub).ellipse((C - 26, C - 26, C + 26, C + 26), fill=(255, 255, 255, 255),
                                outline=(0, 0, 0, 200), width=8)
    needle.alpha_composite(hub)
    save(needle, "arrow_needle")

    # triangle: a solid, rounded triangle
    save(shaped(lambda d: rounded_poly(d, [(C, C - 190), (C + 165, C + 150), (C - 165, C + 150)], 26)),
         "arrow_triangle")

    # orbit: a small pointer riding the ring (the texture turns, so it
    # circles the dial); a dot sits in the middle (filledcircle)
    save(shaped(lambda d: rounded_poly(d, [(C, 14), (C + 62, 104), (C - 62, 104)], 10), edge=14),
         "arrow_orbit")

    # thin ring and a soft glow
    ring = mi.layer()
    ImageDraw.Draw(ring).ellipse((24, 24, S - 24, S - 24), outline=(255, 255, 255, 255), width=14)
    save(ring, "ring_thin")
    gm = mi.disc_mask(236).filter(ImageFilter.GaussianBlur(40))
    glow = Image.new("RGBA", (S, S), (255, 255, 255, 255))
    glow.putalpha(gm.point(lambda v: v * 200 // 255))
    save(glow, "glow")


def small_icons():
    # history: a clock with an arrow going back round it
    def history(d):
        d.arc((C - 170, C - 170, C + 170, C + 170), 200, 520 - 40, fill=255, width=46)
        # arrow head at the start of the arc (about 200 deg)
        a = math.radians(200)
        x, y = C + math.cos(a) * 170, C + math.sin(a) * 170
        d.polygon([(x - 80, y - 10), (x + 70, y - 30), (x - 10, y + 100)], fill=255)
        d.line((C, C, C, C - 100), fill=255, width=40)
        d.line((C, C, C + 70, C + 50), fill=255, width=40)
        d.ellipse((C - 28, C - 28, C + 28, C + 28), fill=255)
    img = Image.new("RGBA", (S, S), (255, 255, 255, 0))
    m = Image.new("L", (S, S), 0)
    history(ImageDraw.Draw(m))
    img = Image.new("RGBA", (S, S), (255, 255, 255, 255))
    img.putalpha(m)
    save(img, "history", 32)

    # skip: two chevrons ">>"
    m = Image.new("L", (S, S), 0)
    d = ImageDraw.Draw(m)
    for dx in (-90, 70):
        d.line((C + dx - 70, C - 140, C + dx + 60, C, C + dx - 70, C + 140), fill=255, width=58, joint="curve")
    img = Image.new("RGBA", (S, S), (255, 255, 255, 255))
    img.putalpha(m)
    save(img, "skip", 32)


def quest_glyph(text, fill_top, fill_bottom, name):
    """A big "!" or "?" with a thick black outline and a vertical gradient:
    the look players know from quest addons, drawn from our own font."""
    font = ImageFont.truetype(mi.FONT, 430)
    m = Image.new("L", (S, S), 0)
    d = ImageDraw.Draw(m)
    box = d.textbbox((0, 0), text, font=font)
    w, h = box[2] - box[0], box[3] - box[1]
    x, y = (S - w) // 2 - box[0], (S - h) // 2 - box[1]
    d.text((x, y), text, font=font, fill=255)
    outline = m.filter(ImageFilter.MaxFilter(41))
    out = mi.layer()
    sh = mi.shadow(outline, blur=10, offset=8, strength=160)
    out.alpha_composite(sh)
    black = Image.new("RGBA", (S, S), (12, 8, 2, 255))
    black.putalpha(outline)
    out.alpha_composite(black)
    grad = Image.new("RGBA", (S, S))
    gd = ImageDraw.Draw(grad)
    top, bottom = y + box[1], y + box[3]
    for yy in range(S):
        t = min(1, max(0, (yy - top) / max(1, bottom - top)))
        gd.line((0, yy, S, yy), fill=tuple(int(fill_top[i] + (fill_bottom[i] - fill_top[i]) * t) for i in range(3)) + (255,))
    grad.putalpha(m)
    out.alpha_composite(grad)
    # a light rim on the top edge of the glyph
    hl = m.filter(ImageFilter.MinFilter(17))
    rim = Image.composite(Image.new("L", (S, S), 0), m, hl)
    top_half = Image.new("L", (S, S), 0)
    ImageDraw.Draw(top_half).rectangle((0, 0, S, S // 2), fill=110)
    rim = Image.composite(rim, Image.new("L", (S, S), 0), top_half)
    white = Image.new("RGBA", (S, S), (255, 255, 255, 255))
    white.putalpha(rim)
    out.alpha_composite(white)
    mi.save_tga(out, name)


def glyph_mask(draw_fn):
    m = Image.new("L", (S, S), 0)
    draw_fn(ImageDraw.Draw(m))
    return m


def save_glyph(m, name, size=64):
    img = Image.new("RGBA", (S, S), (255, 255, 255, 255))
    img.putalpha(m)
    save(img, name, size)


def step_icons():
    """The card's step badges (Media/Card/step_*.tga): flat white glyphs
    of one weight, tinted in game. 64 px: sharp at the badge's ~19 px and
    on a scaled-up card."""
    # kill: two crossed swords
    def sword(d):
        tip, base = C - 215, C + 95
        d.polygon([(C, tip), (C + 30, tip + 70), (C + 30, base), (C - 30, base), (C - 30, tip + 70)], fill=255)
        d.rounded_rectangle((C - 92, base, C + 92, base + 36), 14, fill=255)   # crossguard
        d.rectangle((C - 17, base + 36, C + 17, base + 120), fill=255)           # grip
        d.ellipse((C - 32, base + 112, C + 32, base + 176), fill=255)          # pommel
    one = glyph_mask(sword)
    a = one.rotate(45, resample=Image.BICUBIC, center=(C, C))
    b = one.rotate(-45, resample=Image.BICUBIC, center=(C, C))
    from PIL import ImageChops
    save_glyph(ImageChops.lighter(a, b), "step_kill")

    # loot: a tied sack
    def sack(d):
        d.ellipse((C - 175, C - 60, C + 175, C + 215), fill=255)
        d.polygon([(C - 70, C - 40), (C + 70, C - 40), (C + 115, C - 150), (C - 115, C - 150)], fill=255)
        d.rounded_rectangle((C - 95, C - 95, C + 95, C - 55), 16, fill=0)        # the tie
        d.rounded_rectangle((C - 80, C - 88, C + 80, C - 62), 12, fill=255)
    save_glyph(glyph_mask(sack), "step_loot")

    # travel: a winged boot's simpler cousin, a footprint pair
    def steps(d):
        for dx, dy in ((-85, 40), (85, -70)):
            x, y = C + dx, C + dy
            d.ellipse((x - 62, y - 120, x + 62, y + 60), fill=255)       # sole
            d.ellipse((x - 48, y + 82, x + 48, y + 170), fill=255)       # heel
    save_glyph(glyph_mask(steps), "step_travel")

    # town: a house
    def house(d):
        d.polygon([(C, C - 200), (C + 210, C - 10), (C - 210, C - 10)], fill=255)
        d.rectangle((C - 150, C - 30, C + 150, C + 190), fill=255)
        d.rectangle((C - 45, C + 60, C + 45, C + 190), fill=0)                  # door
        d.rectangle((C + 85, C - 175, C + 135, C - 70), fill=255)               # chimney
    save_glyph(glyph_mask(house), "step_town")


def main():
    arrows()
    step_icons()
    small_icons()
    yellow = ((255, 236, 110), (240, 168, 0))
    grey = ((214, 216, 222), (128, 130, 138))
    quest_glyph("!", *yellow, "quest_available")
    quest_glyph("!", *grey, "quest_available_grey")
    quest_glyph("?", *yellow, "quest_complete")
    quest_glyph("?", *grey, "quest_incomplete")


if __name__ == "__main__":
    main()
