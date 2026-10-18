"""Ground and decor of the Vertebre maps, drawn in code.

A map visual (Content/Maps/<id>.json) is made of:
  - ONE background element: the whole floor pre-rendered here (every cell tile, decals, vignette);
  - sortable elements: props (pillars, rocks, mushrooms...) as small PNGs, y-sorted with the actors.
Screen space (pre GRID_SHIFT): the centre of cell `c` is
    x = (c % 14) * 86 + 43 * odd_row,  y = (c // 14) * 21.5,  odd_row = (c // 14) % 2
and a Sprite2D is centred on its `t` translation.
"""
from __future__ import annotations

import math
import random

from PIL import Image, ImageChops, ImageDraw, ImageFilter

import rigs
from art import Part, ellipse_pts, spline
from rigs import mix, rrect, shade, shape, spikes

CW, CH = 86.0, 43.0
MAP_W, MAP_H = 14 * 86 + 43, 39 * 21.5  # extent of the cell centres
PAD_X, PAD_Y = 90, 50
ART_W, ART_H = int(MAP_W + 2 * PAD_X), int(MAP_H + 2 * PAD_Y)
SS = 2


def cell_xy(c: int) -> tuple[float, float]:
    row = c // 14
    return (c % 14) * 86 + (43 if row % 2 else 0), row * 21.5


def cell_at(col: int, row: int) -> int:
    return row * 14 + col


# ── themes ─────────────────────────────────────────────────────────────────────

THEMES = {
    "camp": dict(bg=(36, 30, 34), tiles=[(122, 104, 82), (112, 95, 74), (131, 112, 88)], line=(78, 62, 48), accent=(255, 190, 90), style="dirt"),
    "roots": dict(bg=(18, 26, 20), tiles=[(78, 104, 66), (70, 94, 60), (86, 112, 72)], line=(40, 56, 38), accent=(170, 110, 255), style="moss"),
    "marsh": dict(bg=(26, 24, 26), tiles=[(106, 102, 100), (96, 92, 90), (116, 112, 108)], line=(58, 54, 54), accent=(255, 120, 50), style="ash"),
    "city": dict(bg=(24, 22, 24), tiles=[(150, 120, 70), (138, 108, 62), (160, 130, 78)], line=(86, 64, 36), accent=(70, 220, 200), style="brass"),
    "archive": dict(bg=(12, 20, 40), tiles=[(78, 100, 150), (70, 90, 140), (88, 110, 160)], line=(36, 50, 90), accent=(230, 220, 160), style="wet"),
    "crown": dict(bg=(70, 60, 110), tiles=[(206, 200, 224), (194, 188, 214), (216, 210, 232)], line=(150, 140, 180), accent=(255, 220, 100), style="marble"),
}


def _tile_poly(cx, cy, k=1.0):
    return [(cx - CW / 2 * k, cy), (cx, cy - CH / 2 * k), (cx + CW / 2 * k, cy), (cx, cy + CH / 2 * k)]


def _vary(c, rnd, amt=0.07):
    k = 1 + rnd.uniform(-amt, amt)
    return tuple(max(0, min(255, int(v * k))) for v in c)


def render_ground(cells_void: set[int], theme: str, seed: int, decals: list | None = None) -> Image.Image:
    """The whole floor as one RGBA image of ART_W x ART_H (cells in `cells_void` are pits, not floor)."""
    th = THEMES[theme]
    rnd = random.Random(seed)
    W, H = ART_W * SS, ART_H * SS
    im = Image.new("RGBA", (W, H), th["bg"] + (255,))
    d = ImageDraw.Draw(im)

    def P(pts):
        return [((x + PAD_X) * SS, (y + PAD_Y) * SS) for x, y in pts]

    style = th["style"]
    for c in range(560):
        cx, cy = cell_xy(c)
        poly = _tile_poly(cx, cy, 1.0)
        if c in cells_void:
            d.polygon(P(_tile_poly(cx, cy, 1.0)), fill=shade(th["bg"], 0.55) + (255,))
            continue
        col = _vary(rnd.choice(th["tiles"]), rnd, 0.05)
        d.polygon(P(poly), fill=col + (255,))
        # bevel: lit top-left edges, darker bottom-right edges
        pts = _tile_poly(cx, cy, 1.0)
        d.line(P([pts[3], pts[0], pts[1]]), fill=mix(col, (255, 255, 255), 0.18) + (255,), width=2 * SS // 2 + 1)
        d.line(P([pts[1], pts[2], pts[3]]), fill=shade(col, 0.72) + (255,), width=2 * SS // 2 + 1)
        d.polygon(P(_tile_poly(cx, cy, 0.9)), outline=th["line"] + (110,))
        if style == "brass":  # rivets
            for px, py in ((cx - 26, cy), (cx + 26, cy), (cx, cy - 12), (cx, cy + 12)):
                d.ellipse([(px + PAD_X - 1.5) * SS, (py + PAD_Y - 1.5) * SS, (px + PAD_X + 1.5) * SS, (py + PAD_Y + 1.5) * SS], fill=shade(col, 0.6) + (255,))
        elif style == "marble" and rnd.random() < 0.5:  # gold inlay
            d.polygon(P(_tile_poly(cx, cy, 0.5)), outline=th["accent"] + (190,))
        elif style == "wet" and rnd.random() < 0.35:  # ripples of reflected light
            d.arc([(cx - 14 + PAD_X) * SS, (cy - 4 + PAD_Y) * SS, (cx + 14 + PAD_X) * SS, (cy + 6 + PAD_Y) * SS], 0, 180, fill=th["accent"] + (90,), width=SS)
        elif style == "ash" and rnd.random() < 0.3:  # cracks glowing faintly
            x0, y0 = cx + rnd.uniform(-20, 10), cy + rnd.uniform(-6, 6)
            d.line(P([(x0, y0), (x0 + rnd.uniform(5, 14), y0 + rnd.uniform(-5, 5)), (x0 + rnd.uniform(15, 26), y0 + rnd.uniform(-6, 6))]), fill=th["accent"] + (150,), width=SS)
    # texture: fine noise + large soft patches
    noise = Image.effect_noise((W, H), 20).convert("L")
    noise = ImageChops.screen(Image.new("L", (W, H), 108), noise.point(lambda v: int(v * 0.35)))
    base = im.convert("RGB")
    tex = Image.merge("RGB", [noise] * 3)
    im = Image.blend(base, ImageChops.multiply(base, tex.point(lambda v: min(255, int(v * 1.9)))), 0.4).convert("RGBA")
    d = ImageDraw.Draw(im)
    # style decals (moss patches, puddles, soot, glints) scattered over the floor
    for _ in range(46):
        c = rnd.randrange(560)
        if c in cells_void:
            continue
        cx, cy = cell_xy(c)
        x, y = (cx + rnd.uniform(-30, 30) + PAD_X) * SS, (cy + rnd.uniform(-10, 10) + PAD_Y) * SS
        r = rnd.uniform(4, 11) * SS
        if style == "moss":
            d.ellipse([x - r, y - r * 0.5, x + r, y + r * 0.5], fill=(60, 96, 52, 120))
        elif style == "ash":
            d.ellipse([x - r, y - r * 0.5, x + r, y + r * 0.5], fill=(40, 38, 40, 120))
        elif style == "wet":
            d.ellipse([x - r, y - r * 0.5, x + r, y + r * 0.5], fill=(40, 70, 120, 110))
        elif style == "dirt":
            d.ellipse([x - r, y - r * 0.5, x + r, y + r * 0.5], fill=(88, 70, 52, 90))
        elif style == "brass":
            d.rectangle([x - r, y - 1, x + r, y + 1], fill=(70, 220, 200, 70))
        else:
            d.ellipse([x - r, y - r * 0.4, x + r, y + r * 0.4], fill=(255, 255, 255, 50))
    # vignette
    vig = Image.new("L", (W, H), 0)
    vd = ImageDraw.Draw(vig)
    vd.ellipse([-W * 0.12, -H * 0.18, W * 1.12, H * 1.18], fill=255)
    vig = vig.filter(ImageFilter.GaussianBlur(W * 0.07))
    dark = Image.new("RGBA", (W, H), shade(th["bg"], 0.45) + (255,))
    im = Image.composite(im, dark, vig.point(lambda v: min(255, int(120 + v * 0.53))))
    return im.resize((ART_W, ART_H), Image.LANCZOS)


# ── props (sortable decor) ─────────────────────────────────────────────────────

def _pal(theme):
    th = THEMES[theme]
    return rigs.Pal(th["tiles"][0], th["accent"], dark=shade(th["bg"], 1.1))


def prop_sprite(kind: str, theme: str, seed: int = 0):
    """A prop PNG (1 px = 1 screen px) and its foot offset (x, y) in that image: (img, (fx, fy))."""
    rnd = random.Random(seed)
    pal = _pal(theme)
    p = Part("p", -60, -150, 60, 25)
    st = THEMES[theme]["style"]
    stone = mix(THEMES[theme]["tiles"][0], (70, 66, 72), 0.55)
    pstone = rigs.Pal(stone, THEMES[theme]["accent"])
    if kind == "pillar":
        shape(p, rrect(-14, -88, 14, 0, 2), pstone)
        shape(p, rrect(-20, -96, 20, -86, 2), pstone, fill=pstone.trim)
        shape(p, rrect(-19, -6, 19, 4, 2), pstone, fill=pstone.trim)
        for x in (-6, 4):
            p.line([(x, -84), (x + 1, -8)], width=0.6)
        rigs.glow(p, 0, -60, 2.6, pal)
    elif kind == "rock":
        pts = rigs.ragged(spikes(0, -14, 14, 22, 8), rnd, 2.5)
        shape(p, spline(pts, steps=2), pstone)
    elif kind == "boulder":
        pts = [(-34, 0), (-30, -26), (-12, -44), (14, -48), (32, -28), (36, 0)]
        shape(p, spline(pts, steps=5), pstone)
        p.line([(-10, -40), (-4, -22), (6, -12)], width=0.8)
    elif kind == "shroom":  # giant glowing mushroom (roots)
        shape(p, rrect(-6, -48, 6, 2, 3), rigs.Pal((210, 196, 170), (170, 110, 255)))
        cap = [(-34, -44), (-26, -70), (0, -82), (26, -70), (34, -44), (0, -36)]
        shape(p, spline(cap, steps=5), rigs.Pal((120, 70, 150), (170, 110, 255)))
        for x, y in ((-14, -62), (10, -68), (22, -54), (-4, -50)):
            rigs.glow(p, x, y, 2.2, rigs.Pal((120, 70, 150), (200, 150, 255)))
    elif kind == "root":  # twisted root arch
        pts = [(-30, 0), (-26, -40), (-8, -70), (14, -60), (26, -30), (32, 0), (22, 0), (16, -28), (8, -48), (-6, -48), (-16, -28), (-20, 0)]
        shape(p, spline(pts, steps=3), rigs.Pal((92, 70, 52), (170, 110, 255)))
        rigs.glow(p, 0, -52, 2.0, pal)
    elif kind == "dead_tree":
        shape(p, spline([(-8, 0), (-5, -50), (-14, -86), (-4, -96), (0, -62), (10, -92), (14, -84), (6, -50), (9, 0)], steps=3), rigs.Pal((78, 66, 62), (255, 120, 50)))
    elif kind == "gear":  # buried cog (city)
        shape(p, spikes(0, -26, 22, 30, 10), rigs.Pal((150, 120, 70), (70, 220, 200)))
        shape(p, ellipse_pts(0, -26, 10, 10), rigs.Pal((70, 60, 50), (70, 220, 200)))
        rigs.glow(p, 0, -26, 3, pal)
    elif kind == "lamp":
        shape(p, rrect(-3, -86, 3, 0, 1.5), rigs.Pal((90, 80, 72), THEMES[theme]["accent"]))
        shape(p, rrect(-9, -104, 9, -84, 4), rigs.Pal(mix(THEMES[theme]["accent"], (60, 50, 40), 0.5), THEMES[theme]["accent"]))
        rigs.glow(p, 0, -94, 5, pal)
    elif kind == "crate":
        shape(p, rrect(-20, -34, 20, 0, 2), rigs.Pal((130, 92, 58), (255, 190, 90)))
        p.line([(-20, -22), (20, -22)], width=0.8)
        p.line([(-20, -11), (20, -11)], width=0.8)
        p.line([(-20, -34), (20, 0)], width=0.7)
    elif kind == "barrel":
        shape(p, spline([(-16, 0), (-19, -22), (-16, -44), (16, -44), (19, -22), (16, 0)], steps=4), rigs.Pal((136, 98, 62), (255, 190, 90)))
        for y in (-34, -10):
            p.line([(-18, y), (18, y)], width=1.0, color=(70, 60, 56, 255))
    elif kind == "tent":
        shape(p, [(-52, 0), (-6, -92), (6, -92), (52, 0)], rigs.Pal((156, 120, 84), (255, 190, 90)))
        shape(p, [(-14, 0), (-4, -54), (4, -54), (14, 0)], rigs.Pal((40, 30, 28), (255, 190, 90)), light=False)
        rigs.glow(p, 0, -22, 4, pal)
    elif kind == "bookshelf":
        shape(p, rrect(-28, -90, 28, 0, 2), rigs.Pal((90, 64, 48), (230, 220, 160)))
        for y in (-70, -46, -22):
            p.line([(-26, y), (26, y)], width=1.0)
            for i in range(8):
                x = -24 + i * 6.2
                p.shape(rrect(x, y - 16 - (i * 3 % 5), x + 5, y - 1, 0.8), (90 + (i * 37) % 120, 70 + (i * 53) % 90, 100 + (i * 29) % 100))
    elif kind == "crystal":
        for dx, h, w in ((-14, 46, 9), (4, 70, 12), (20, 38, 8)):
            shape(p, [(dx - w, 0), (dx - w * 0.4, -h), (dx, -h - 8), (dx + w * 0.5, -h + 4), (dx + w, 0)], rigs.Pal(mix(THEMES[theme]["accent"], (255, 255, 255), 0.25), THEMES[theme]["accent"]))
    elif kind == "statue":
        shape(p, rrect(-20, -16, 20, 0, 2), pstone)
        shape(p, spline([(-12, -16), (-14, -64), (-8, -92), (8, -92), (14, -64), (12, -16)], steps=4), pstone)
        shape(p, ellipse_pts(0, -104, 9, 10), pstone)
        rigs.glow(p, 3, -104, 2.0, pal)
    elif kind == "door":  # boss door / gate: arch with glowing seal
        shape(p, rrect(-34, -112, -22, 0, 2), pstone)
        shape(p, rrect(22, -112, 34, 0, 2), pstone)
        shape(p, spline([(-38, -108), (0, -140), (38, -108), (22, -102), (0, -118), (-22, -102)], steps=5), pstone)
        shape(p, rrect(-22, -108, 22, 0, 1), rigs.Pal((30, 24, 34), THEMES[theme]["accent"]), light=False, shd=False)
        rigs.glow(p, 0, -66, 7, pal)
    elif kind == "stairs":
        for i in range(5):
            shape(p, rrect(-34 + i * 3, -10 - i * 11, 34 - i * 3, -i * 11, 1), pstone, fill=mix(stone, (255, 255, 255), 0.06 * i))
        rigs.glow(p, 0, -64, 4, pal)
    elif kind == "bones":
        for dx, ang in ((-10, -20), (6, 25), (0, 80)):
            p.shape(rrect(dx - 14, -4, dx + 14, 2, 2), (226, 220, 200))
        shape(p, ellipse_pts(12, -9, 7, 6.5), rigs.Pal((226, 220, 200), THEMES[theme]["accent"]))
    elif kind == "banner":
        shape(p, rrect(-2, -100, 2, 0, 1), rigs.Pal((90, 80, 72), THEMES[theme]["accent"]))
        shape(p, [(2, -98), (26, -98), (26, -56), (14, -62), (2, -56)], rigs.Pal(mix(THEMES[theme]["accent"], (60, 30, 40), 0.55), THEMES[theme]["accent"]))
    elif kind == "chest":
        shape(p, rrect(-20, -26, 20, 0, 3), rigs.Pal((120, 84, 54), (255, 200, 80)))
        shape(p, spline([(-20, -26), (-18, -38), (18, -38), (20, -26)], steps=3), rigs.Pal((136, 96, 60), (255, 200, 80)))
        p.shape(rrect(-3, -30, 3, -20, 1), (255, 200, 80))
        rigs.glow(p, 0, -24, 2.0, pal)
    elif kind == "cloud":
        for dx, dy, r in ((-22, -10, 16), (0, -16, 20), (22, -9, 15)):
            p.shape(ellipse_pts(dx, dy, r, r * 0.6), (236, 232, 248))
    elif kind == "pool":  # a flat pool (drawn as prop to be y-sorted under actors)
        p.shape(ellipse_pts(0, -6, 30, 12), mix(THEMES[theme]["tiles"][0], (30, 60, 110), 0.7))
    else:
        raise KeyError(kind)
    sp = p.finish()
    img = sp.image
    k = 1 / 3  # texture pixels -> screen pixels
    img = img.resize((max(1, round(img.width * k)), max(1, round(img.height * k))), Image.LANCZOS)
    return img, (sp.pivot[0] * k, sp.pivot[1] * k)


def prop_t(cell: int, img: Image.Image, foot: tuple[float, float], dy=8.0) -> list[float]:
    """The `t` of a Sprite2D whose foot (pivot) stands on `cell`'s centre (+dy px down)."""
    cx, cy = cell_xy(cell)
    return [1.0, 0.0, 0.0, 1.0, round(cx + img.width / 2 - foot[0], 1), round(cy + dy + img.height / 2 - foot[1], 1)]
