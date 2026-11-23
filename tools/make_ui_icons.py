"""Draw OpenXP 2.0's arrow styles, step list icons and quest map icons.

    python3 tools/make_ui_icons.py

Writes
  OpenXP/Media/Card/arrow_*.tga   the arrow's pointer styles (128 px, white,
                                  tinted in game; a soft dark edge is baked
                                  in so they read on snow)
  OpenXP/Media/Card/ring_thin.tga a thin dial ring
  OpenXP/Media/Card/glow.tga      a soft round glow
  OpenXP/Media/Card/arrive_glow.tga  the arrow's soft halo when you arrive
  OpenXP/Media/Card/history.tga   the card's step list button
  OpenXP/Media/Card/skip.tga      the "skipped" mark in the step list
  OpenXP/Media/Card/more.tga      the card's menu button (three dots)
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

    # thin ring
    ring = mi.layer()
    ImageDraw.Draw(ring).ellipse((24, 24, S - 24, S - 24), outline=(255, 255, 255, 255), width=14)
    save(ring, "ring_thin")


def white_from(mask, peak):
    """A white texture whose alpha is `mask` scaled so its brightest point is
    `peak` (0-255)."""
    top = max(mask.getextrema()[1], 1)
    img = Image.new("RGBA", (S, S), (255, 255, 255, 255))
    img.putalpha(mask.point(lambda v: min(255, v * peak // top)))
    return img


def glows():
    # glow: a soft round glow. The blurred disc has to fade to nothing well
    # inside the square: 2.0.0-dev3's (radius 236, blur 40) still had a
    # third of its alpha at the edges, so in game it showed as a blurry square.
    gm = mi.disc_mask(120).filter(ImageFilter.GaussianBlur(46))
    save(white_from(gm, 200), "glow")
    # arrive_glow: the arrow's "you're there" halo, a soft ring lying on the
    # dial's ring (drawn at 1.7x the dial, so the ring is at 151 of 256) and
    # fading out both ways, leaving the check mark clear
    rm = Image.new("L", (S, S), 0)
    ImageDraw.Draw(rm).ellipse((C - 151, C - 151, C + 151, C + 151), outline=255, width=28)
    save(white_from(rm.filter(ImageFilter.GaussianBlur(22)), 235), "arrive_glow")


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



def steps_icon():
    """Media/Card/steps(_32).tga: the card's Steps button, a timeline list
    (a dot and a bar per row; the middle row, where you are, is bigger)."""
    m = Image.new("L", (S, S), 0)
    d = ImageDraw.Draw(m)
    d.line((110, 120, 110, 392), fill=255, width=22)
    for y, cur in ((150, False), (256, True), (362, False)):
        r = 46 if cur else 34
        d.ellipse((110 - r, y - r, 110 + r, y + r), fill=255)
        d.rounded_rectangle((190, y - 26, 450 if cur else 400, y + 26), 26, fill=255)
    img = Image.new("RGBA", (S, S), (255, 255, 255, 255))
    img.putalpha(m)
    save(img, "steps", 64)
    save(img, "steps_32", 32)


def more_icon():
    """Media/Card/more(_32).tga: the card's menu button, three dots in a row
    (the list icon belongs to the step list, so the menu doesn't look like it)."""
    m = Image.new("L", (S, S), 0)
    d = ImageDraw.Draw(m)
    for x in (116, 256, 396):
        d.ellipse((x - 46, 256 - 46, x + 46, 256 + 46), fill=255)
    img = Image.new("RGBA", (S, S), (255, 255, 255, 255))
    img.putalpha(m)
    save(img, "more", 64)
    save(img, "more_32", 32)


def main():
    arrows()
    glows()
    steps_icon()
    more_icon()
    small_icons()
    yellow = ((255, 236, 110), (240, 168, 0))
    grey = ((214, 216, 222), (128, 130, 138))
    quest_glyph("!", *yellow, "quest_available")
    quest_glyph("!", *grey, "quest_available_grey")
    quest_glyph("?", *yellow, "quest_complete")
    quest_glyph("?", *grey, "quest_incomplete")


if __name__ == "__main__":
    main()
