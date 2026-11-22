"""Draw OpenXP 2.0's map, minimap and nameplate icons (Media/Map/*.tga).

Every icon is drawn at 4x and scaled down to 128, 64 and 32 px
(name.tga, name_64.tga, name_32.tga). The game draws a texture without
mipmaps, so a 128 px icon shown 14 px wide on the minimap came out jagged;
the pins pick the file nearest their size on screen (Nav/Pins.lua Icon). Run from the repo root: python3 tools/make_icons.py
Needs Pillow. The "!" and "?" use Atkinson Hyperlegible Bold from
Media/Fonts (SIL Open Font License, see Media/Fonts/licenses).
"""
import math
import os
import struct

from PIL import Image, ImageDraw, ImageFilter, ImageFont

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
OUT = os.path.join(ROOT, "OpenXP", "Media", "Map")
FONT = os.path.join(ROOT, "OpenXP", "Media", "Fonts", "AtkinsonHyperlegible-Bold.ttf")
SIZE = 128
SS = 4
S = SIZE * SS  # drawing size


def write_tga(img, path):
    """32-bit uncompressed TGA, top-left origin (like the other Media files)."""
    img = img.convert("RGBA")
    w, h = img.size
    header = struct.pack("<BBBHHBHHHHBB", 0, 0, 2, 0, 0, 0, 0, 0, w, h, 32, 0x28)
    px = img.tobytes("raw", "BGRA")
    with open(path, "wb") as f:
        f.write(header + px)


def premultiplied_resize(img, size):
    """Resize without dark fringes: scale colour weighted by alpha."""
    img = img.convert("RGBA")
    try:
        import numpy as np
    except ImportError:  # Pillow's own premultiplied mode does the same
        return img.convert("RGBa").resize((size, size), Image.LANCZOS).convert("RGBA")
    a = np.asarray(img).astype("float32") / 255.0
    rgb, al = a[..., :3] * a[..., 3:4], a[..., 3:4]
    pre = Image.fromarray((np.concatenate([rgb, al], axis=2) * 255).astype("uint8"), "RGBA")
    pre = pre.resize((size, size), Image.LANCZOS)
    b = np.asarray(pre).astype("float32") / 255.0
    al = b[..., 3:4]
    rgb = np.where(al > 0.0001, b[..., :3] / np.maximum(al, 0.0001), 0)
    out = np.concatenate([np.clip(rgb, 0, 1), al], axis=2)
    return Image.fromarray((out * 255 + 0.5).astype("uint8"), "RGBA")


def save_tga(img, name):
    for size in SIZES:
        im = premultiplied_resize(img, size)
        if size <= 32:
            im = sharpen_small(im)
        write_tga(im, os.path.join(OUT, name + ("" if size == 128 else "_%d" % size) + ".tga"))


SIZES = (128, 64, 32)


def finish(img):
    """The 128 px icon; save_tga writes the smaller ones from the full drawing."""
    return img


def sharpen_small(im):
    # a touch of sharpening after the big downscale keeps the outlines crisp
    return im.filter(ImageFilter.UnsharpMask(radius=0.6, percent=60, threshold=0))


def layer():
    return Image.new("RGBA", (S, S), (0, 0, 0, 0))


def shadow(shape_alpha, blur=10, offset=6, strength=150):
    """A soft drop shadow from an alpha mask."""
    sh = Image.new("RGBA", (S, S), (0, 0, 0, 0))
    a = shape_alpha.filter(ImageFilter.GaussianBlur(blur * SS / 4))
    a = a.point(lambda v: v * strength // 255)
    sh.putalpha(a)
    out = layer()
    out.paste(sh, (0, offset * SS // 4), sh)
    return out


def disc_mask(r, cx=S // 2, cy=S // 2):
    m = Image.new("L", (S, S), 0)
    ImageDraw.Draw(m).ellipse((cx - r, cy - r, cx + r, cy + r), fill=255)
    return m


def gradient_disc(r, top, bottom, cx=S // 2, cy=S // 2):
    """A disc filled with a vertical gradient (lighter on top)."""
    g = Image.new("RGBA", (S, S))
    d = ImageDraw.Draw(g)
    for y in range(S):
        t = min(1, max(0, (y - (cy - r)) / (2 * r)))
        c = tuple(int(top[i] + (bottom[i] - top[i]) * t) for i in range(3)) + (255,)
        d.line((0, y, S, y), fill=c)
    out = layer()
    out.paste(g, (0, 0), disc_mask(r, cx, cy))
    return out


def badge(fill_top, fill_bottom, ring, r=200, ring_w=22, rim=(12, 13, 17)):
    """A round badge, flat and high-contrast so it reads at 12 px: a soft
    shadow, a dark rim, a light ring and a gently shaded fill."""
    img = layer()
    img.alpha_composite(shadow(disc_mask(r + 16), blur=8, offset=5, strength=110))
    rim_layer = gradient_disc(r + 16, rim, rim)
    img.alpha_composite(rim_layer)
    if ring_w > 0:
        img.alpha_composite(gradient_disc(r, tuple(min(255, c + 25) for c in ring), ring))
    img.alpha_composite(gradient_disc(r - ring_w, fill_top, fill_bottom))
    # a faint lighter top edge inside the ring, no glossy band
    hl = layer()
    inner = r - ring_w
    ImageDraw.Draw(hl).ellipse((S // 2 - inner, S // 2 - inner, S // 2 + inner, S // 2 + inner),
                               outline=(255, 255, 255, 40), width=10)
    top = Image.new("L", (S, S), 0)
    ImageDraw.Draw(top).rectangle((0, 0, S, S // 2), fill=255)
    hl.putalpha(Image.composite(hl.getchannel("A"), Image.new("L", (S, S), 0), top))
    img.alpha_composite(hl)
    return img


def glyph(img, text, size, color=(255, 255, 255), dy=0, outline=(40, 22, 0, 200)):
    """A bold glyph with a crisp dark edge (not a blur: blurs go muddy small)."""
    font = ImageFont.truetype(FONT, size)
    d = ImageDraw.Draw(img)
    box = d.textbbox((0, 0), text, font=font)
    w, h = box[2] - box[0], box[3] - box[1]
    x, y = (S - w) // 2 - box[0], (S - h) // 2 - box[1] + dy
    edge = layer()
    ImageDraw.Draw(edge).text((x, y + 5), text, font=font, fill=outline, stroke_width=9, stroke_fill=outline)
    img.alpha_composite(edge)
    d.text((x, y), text, font=font, fill=color + (255,))


def icon_shape(draw_fn, color=(255, 255, 255)):
    """An icon drawn white on its own layer, with a crisp dark edge under it."""
    m = Image.new("L", (S, S), 0)
    draw_fn(ImageDraw.Draw(m))
    ic = Image.new("RGBA", (S, S), color + (255,))
    ic.putalpha(m)
    edge_mask = m.filter(ImageFilter.MaxFilter(13))
    edge = Image.new("RGBA", (S, S), (20, 10, 8, 170))
    edge.putalpha(edge_mask.point(lambda v: v * 170 // 255))
    out = layer()
    out.alpha_composite(edge, (0, 6))
    out.alpha_composite(ic)
    return out


def skull(d, scale=1.0, cx=S // 2, cy=S // 2):
    k = scale
    # cranium and jaw
    d.ellipse((cx - 112 * k, cy - 120 * k, cx + 112 * k, cy + 70 * k), fill=255)
    d.rounded_rectangle((cx - 66 * k, cy + 20 * k, cx + 66 * k, cy + 118 * k), radius=26 * k, fill=255)
    # eyes and nose cut out
    d.ellipse((cx - 78 * k, cy - 40 * k, cx - 18 * k, cy + 22 * k), fill=0)
    d.ellipse((cx + 18 * k, cy - 40 * k, cx + 78 * k, cy + 22 * k), fill=0)
    d.polygon([(cx, cy + 30 * k), (cx - 18 * k, cy + 62 * k), (cx + 18 * k, cy + 62 * k)], fill=0)
    # teeth gaps
    for x in (-34, 0, 34):
        d.rectangle((cx + (x - 5) * k, cy + 84 * k, cx + (x + 5) * k, cy + 118 * k), fill=0)


def pouch(d):
    cx, cy = S // 2, S // 2
    d.ellipse((cx - 112, cy - 40, cx + 112, cy + 128), fill=255)
    d.polygon([(cx - 60, cy - 30), (cx + 60, cy - 30), (cx + 34, cy - 84), (cx - 34, cy - 84)], fill=255)
    d.polygon([(cx - 34, cy - 84), (cx - 92, cy - 132), (cx - 20, cy - 112)], fill=255)
    d.polygon([(cx + 34, cy - 84), (cx + 92, cy - 132), (cx + 20, cy - 112)], fill=255)
    d.ellipse((cx - 26, cy - 122, cx + 26, cy - 92), fill=255)
    # the tie
    d.rounded_rectangle((cx - 72, cy - 52, cx + 72, cy - 28), radius=10, fill=0)


def chest(d):
    cx, cy = S // 2, S // 2
    d.rounded_rectangle((cx - 124, cy - 20, cx + 124, cy + 104), radius=16, fill=255)
    d.pieslice((cx - 124, cy - 120, cx + 124, cy + 60), 180, 360, fill=255)
    d.rectangle((cx - 124, cy - 26, cx + 124, cy - 10), fill=0)  # lid seam
    d.rounded_rectangle((cx - 24, cy - 40, cx + 24, cy + 24), radius=8, fill=0)  # lock plate
    d.rounded_rectangle((cx - 12, cy - 26, cx + 12, cy + 10), radius=4, fill=255)


def sparkle(d):
    cx, cy = S // 2, S // 2
    def star(r1, r2, x, y, rot=0):
        pts = []
        for i in range(8):
            a = rot + i * math.pi / 4
            r = r1 if i % 2 == 0 else r2
            pts.append((x + math.cos(a) * r, y + math.sin(a) * r))
        d.polygon(pts, fill=255)
    star(132, 30, cx - 10, cy + 10, -math.pi / 2)
    star(62, 14, cx + 86, cy - 84, -math.pi / 2)


def hand(d):
    """Talk to / use: a speech bubble."""
    cx, cy = S // 2, S // 2
    d.rounded_rectangle((cx - 130, cy - 104, cx + 130, cy + 60), radius=56, fill=255)
    d.polygon([(cx - 60, cy + 40), (cx - 90, cy + 124), (cx + 10, cy + 50)], fill=255)
    for x in (-62, 0, 62):
        d.ellipse((cx + x - 20, cy - 42, cx + x + 20, cy - 2), fill=0)


def small_marker(fill, ring, shape, name):
    img = badge(tuple(min(255, c + 30) for c in fill), fill, ring, r=196, ring_w=20)
    ic = icon_shape(shape)
    ic = ic.resize((int(S * 0.7), int(S * 0.7)), Image.LANCZOS)
    off = (S - ic.size[0]) // 2
    img.alpha_composite(ic, (off, off))
    save_tga(finish(img), name)


def main():
    os.makedirs(OUT, exist_ok=True)

    # Step badges: dark disc (untinted) + white ring (tinted by kind in game) + glow
    save_tga(finish(badge((40, 44, 54), (18, 20, 26), (60, 64, 76), r=196, ring_w=0)), "step_disc")
    ring = layer()
    ImageDraw.Draw(ring).ellipse((S // 2 - 200, S // 2 - 200, S // 2 + 200, S // 2 + 200), outline=(255, 255, 255, 255), width=30)
    save_tga(finish(ring), "step_ring")
    glow = layer()
    gm = disc_mask(232).filter(ImageFilter.GaussianBlur(28))
    hole = disc_mask(150)
    gm = Image.composite(Image.new("L", (S, S), 0), gm, hole)
    glow = Image.new("RGBA", (S, S), (255, 255, 255, 255))
    glow.putalpha(gm)
    save_tga(finish(glow), "step_glow")

    # Quest givers and turn-ins: gold badges with the glyph baked in
    gold_top, gold_bottom, gold_ring = (255, 214, 84), (226, 150, 22), (255, 236, 160)
    img = badge(gold_top, gold_bottom, gold_ring, r=196, ring_w=18)
    glyph(img, "!", 300, dy=-6)
    save_tga(finish(img), "accept")
    img = badge(gold_top, gold_bottom, gold_ring, r=196, ring_w=18)
    glyph(img, "?", 290, dy=-6)
    save_tga(finish(img), "turnin")
    # a turn-in that isn't ready yet: grey
    img = badge((150, 154, 164), (96, 100, 110), (190, 194, 204), r=196, ring_w=18)
    glyph(img, "?", 290, dy=-6, color=(235, 236, 240))
    save_tga(finish(img), "turnin_grey")

    # Mob and object markers
    small_marker((196, 52, 48), (255, 128, 112), lambda d: skull(d), "kill")
    small_marker((214, 142, 34), (255, 210, 120), pouch, "loot")
    small_marker((34, 150, 140), (120, 230, 214), sparkle, "object")
    small_marker((150, 96, 30), (255, 206, 110), chest, "chest")
    small_marker((52, 120, 210), (140, 200, 255), hand, "talk")
    # a named mob or boss: bigger skull, dark red, gold ring
    img = badge((150, 30, 36), (84, 12, 18), (255, 204, 96), r=200, ring_w=24)
    ic = icon_shape(lambda d: skull(d)).resize((int(S * 0.66), int(S * 0.66)), Image.LANCZOS)
    off = (S - ic.size[0]) // 2
    img.alpha_composite(ic, (off, off + 4))
    save_tga(finish(img), "boss")

    # Nameplate marker: a downward chevron with a soft glow (tinted in game)
    m = Image.new("L", (S, S), 0)
    d = ImageDraw.Draw(m)
    cx = S // 2
    d.polygon([(cx - 170, 120), (cx, 300), (cx + 170, 120), (cx + 170, 196), (cx, 376), (cx - 170, 196)], fill=255)
    chev = Image.new("RGBA", (S, S), (255, 255, 255, 255))
    chev.putalpha(m)
    out = layer()
    g = Image.new("RGBA", (S, S), (255, 255, 255, 255))
    g.putalpha(m.filter(ImageFilter.GaussianBlur(26)).point(lambda v: v * 200 // 255))
    out.alpha_composite(g)
    out.alpha_composite(shadow(m, blur=6, offset=6, strength=200))
    out.alpha_composite(chev)
    save_tga(finish(out), "plate_chevron")


def route_textures():
    """The route line's own textures: a soft-edged stroke, a round cap and a
    direction chevron, all white (tinted in game)."""
    # line: 64 x 32, solid across the middle 16 px with a 4 px soft edge each side
    w, h = 64, 32
    line = Image.new("RGBA", (w, h), (255, 255, 255, 0))
    px = line.load()
    for y in range(h):
        d = abs(y + 0.5 - h / 2)
        a = 1.0 if d <= 8 else max(0.0, 1 - (d - 8) / 6)
        for x in range(w):
            px[x, y] = (255, 255, 255, int(a * 255 + 0.5))
    write_tga(line, os.path.join(OUT, "line.tga"))
    # dot: an anti-aliased disc with the same soft edge (joints and the end)
    dot = layer()
    m = disc_mask(int(S * 0.36)).filter(ImageFilter.GaussianBlur(S * 0.03))
    dot = Image.new("RGBA", (S, S), (255, 255, 255, 255))
    dot.putalpha(m)
    for size in (64, 32):
        write_tga(premultiplied_resize(dot, size), os.path.join(OUT, "dot" + ("" if size == 64 else "_32") + ".tga"))
    # chevron pointing right
    m = Image.new("L", (S, S), 0)
    d = ImageDraw.Draw(m)
    c = S // 2
    d.polygon([(c - 120, c - 170), (c + 60, c), (c - 120, c + 170), (c - 40, c + 170), (c + 140, c), (c - 40, c - 170)],
              fill=255)
    ch = Image.new("RGBA", (S, S), (255, 255, 255, 255))
    ch.putalpha(m)
    write_tga(premultiplied_resize(ch, 32), os.path.join(OUT, "chevron.tga"))


if __name__ == "__main__":
    main()
    route_textures()
