"""Icons drawn in code: items (weapons, armour, jewels, resources...), spells and monster portraits.

One symbol library x palettes: an item set only changes the palette, a spell only changes symbol and
element colour. 96x96 PNG, drawn 4x supersampled: dark rounded plate, rarity border, symbol with ink
outline, one shade and one highlight, like the creature art.
"""
from __future__ import annotations

import math

from PIL import Image, ImageDraw, ImageFilter

SIZE = 96
SS = 4
INK = (34, 24, 30, 255)
W = SIZE * SS

ELEMENT = {"earth": (150, 110, 60), "fire": (235, 100, 50), "water": (70, 150, 230), "air": (130, 220, 150),
           "neutral": (200, 195, 210), "ether": (170, 110, 255), "light": (255, 225, 120), "shadow": (110, 80, 150)}
RARITY = {0: (140, 140, 150), 1: (90, 190, 120), 2: (90, 150, 240), 3: (190, 110, 240), 4: (250, 190, 70)}


def _c(c, k):
    return tuple(max(0, min(255, int(v * k))) for v in c[:3])


def _mix(a, b, t):
    return tuple(int(a[i] + (b[i] - a[i]) * t) for i in range(3))


class Canvas:
    def __init__(self):
        self.im = Image.new("RGBA", (W, W), (0, 0, 0, 0))
        self.d = ImageDraw.Draw(self.im)

    @staticmethod
    def P(pts):
        return [(x * SS, y * SS) for x, y in pts]

    def poly(self, pts, fill, line=1.4, shade=True):
        """pts in 0..96 icon units. Fill + ink outline + a darker lower-right half."""
        self.d.polygon(self.P(pts), fill=tuple(fill[:3]) + (255,))
        if shade:
            xs, ys = [p[0] for p in pts], [p[1] for p in pts]
            lay = Image.new("RGBA", (W, W), (0, 0, 0, 0))
            cx, cy = (min(xs) + max(xs)) / 2, (min(ys) + max(ys)) / 2
            ImageDraw.Draw(lay).polygon(self.P([(cx, min(ys) - 2), (max(xs) + 2, min(ys) - 2), (max(xs) + 2, max(ys) + 2), (cx - (max(xs) - min(xs)) * 0.25, max(ys) + 2)]), fill=_c(fill, 0.68) + (255,))
            mask = Image.new("L", (W, W), 0)
            ImageDraw.Draw(mask).polygon(self.P(pts), fill=255)
            a = Image.composite(lay.getchannel("A"), Image.new("L", (W, W), 0), mask)
            lay.putalpha(a)
            self.im.alpha_composite(lay)
            self.d = ImageDraw.Draw(self.im)
        if line:
            self.d.line(self.P(pts + pts[:1]), fill=INK, width=int(line * SS), joint="curve")

    def ellipse(self, cx, cy, rx, ry, fill, line=1.4, shade=True, n=40):
        self.poly([(cx + rx * math.cos(2 * math.pi * i / n), cy + ry * math.sin(2 * math.pi * i / n)) for i in range(n)], fill, line, shade)

    def line(self, pts, width=1.6, color=INK):
        self.d.line(self.P(pts), fill=tuple(color[:3]) + (255,), width=int(width * SS), joint="curve")

    def glow(self, cx, cy, r, color):
        for k, a in ((2.0, 60), (1.45, 130), (1.0, 255)):
            self.d.ellipse([(cx - r * k) * SS, (cy - r * k) * SS, (cx + r * k) * SS, (cy + r * k) * SS], fill=tuple(color[:3]) + (a,))
        self.d.ellipse([(cx - r * 0.4) * SS, (cy - r * 0.4) * SS, (cx + r * 0.4) * SS, (cy + r * 0.4) * SS], fill=(255, 255, 255, 255))

    def finish(self):
        # soft drop shadow under the symbol
        sh = Image.new("RGBA", (W, W), (0, 0, 0, 0))
        sh.paste((0, 0, 0, 110), (3 * SS, 4 * SS), self.im.getchannel("A"))
        sh = sh.filter(ImageFilter.GaussianBlur(2.5 * SS))
        sh.alpha_composite(self.im)
        return sh


def rr(x0, y0, x1, y1, r=3, n=4):
    pts = []
    for cx, cy, a0 in ((x1 - r, y0 + r, -90), (x1 - r, y1 - r, 0), (x0 + r, y1 - r, 90), (x0 + r, y0 + r, 180)):
        for i in range(n + 1):
            a = math.radians(a0 + 90 * i / n)
            pts.append((cx + r * math.cos(a), cy + r * math.sin(a)))
    return pts


def rot(pts, deg, cx=48, cy=48):
    a = math.radians(deg)
    ca, sa = math.cos(a), math.sin(a)
    return [(cx + (x - cx) * ca - (y - cy) * sa, cy + (x - cx) * sa + (y - cy) * ca) for x, y in pts]


def star(cx, cy, r_in, r_out, n, rotd=0.0):
    return [(cx + (r_out if i % 2 == 0 else r_in) * math.cos(math.radians(rotd) + math.pi * i / n),
             cy + (r_out if i % 2 == 0 else r_in) * math.sin(math.radians(rotd) + math.pi * i / n)) for i in range(n * 2)]


METAL = (186, 194, 204)
WOOD = (130, 92, 58)
LEATHER = (150, 100, 70)


# ── symbols: each draws on a Canvas with palette (main, trim, acc) ─────────────────

def sym_sword(c, m, t, a):
    c.poly(rot([(45, 12), (51, 12), (52, 60), (48, 68), (44, 60)], 35), _mix(METAL, m, 0.35))
    c.line(rot([(48, 16), (48, 60)], 35), 1.0, a)
    c.poly(rot([(34, 62), (62, 62), (62, 67), (34, 67)], 35), t)
    c.poly(rot([(45, 67), (51, 67), (51, 82), (45, 82)], 35), WOOD)
    c.ellipse(*rot([(48, 85)], 35)[0], 4.2, 4.2, t)


def sym_dagger(c, m, t, a):
    c.poly(rot([(46, 22), (50, 22), (51, 54), (48, 60), (45, 54)], 30), _mix(METAL, m, 0.3))
    c.poly(rot([(38, 56), (58, 56), (58, 60), (38, 60)], 30), t)
    c.poly(rot([(46, 60), (50, 60), (50, 74), (46, 74)], 30), WOOD)
    c.glow(*rot([(48, 38)], 30)[0], 2.2, a)


def sym_axe(c, m, t, a):
    c.poly(rot([(46, 14), (50, 14), (50, 84), (46, 84)], 30), WOOD)
    c.poly(rot([(50, 18), (70, 12), (76, 28), (70, 44), (50, 40)], 30), _mix(METAL, m, 0.35))
    c.line(rot([(56, 22), (66, 28), (56, 36)], 30)[:3], 1.2, a)


def sym_staff(c, m, t, a):
    c.poly(rot([(46.5, 24), (49.5, 24), (50, 86), (46, 86)], 25), WOOD)
    c.poly(star(*rot([(48, 20)], 25)[0], 4.5, 12, 5, -90), t)
    c.glow(*rot([(48, 20)], 25)[0], 5, a)


def sym_bow(c, m, t, a):
    c.line([(60, 12), (40, 30), (36, 48), (40, 66), (60, 84)], 3.4, WOOD)
    c.line([(60, 12), (60, 84)], 1.0, (235, 235, 235))
    c.poly([(30, 46), (72, 46), (78, 48), (72, 50), (30, 50)], _c(WOOD, 1.2))
    c.poly([(72, 43), (82, 48), (72, 53)], _mix(METAL, m, 0.3))


def sym_hammer(c, m, t, a):
    c.poly(rot([(46, 24), (50, 24), (50, 86), (46, 86)], 25), WOOD)
    c.poly(rot([(28, 12), (68, 12), (68, 34), (28, 34)], 25), _mix(METAL, m, 0.4))
    c.poly(rot([(28, 12), (36, 12), (36, 34), (28, 34)], 25), t)
    c.poly(rot([(60, 12), (68, 12), (68, 34), (60, 34)], 25), t)


def sym_shield(c, m, t, a):
    c.poly([(48, 10), (80, 20), (76, 54), (48, 86), (20, 54), (16, 20)], m)
    c.poly([(48, 18), (70, 26), (67, 50), (48, 74), (29, 50), (26, 26)], _c(m, 1.15))
    c.poly([(46, 18), (50, 18), (50, 74), (46, 74)], t, line=0.8, shade=False)
    c.glow(48, 40, 5, a)


def sym_helm(c, m, t, a):
    c.poly([(20, 60), (22, 34), (36, 18), (60, 18), (74, 34), (76, 60), (66, 66), (60, 56), (36, 56), (30, 66)], m)
    c.poly([(30, 38), (66, 38), (66, 50), (30, 50)], _c(m, 0.35), shade=False)
    c.glow(40, 44, 2.6, a)
    c.glow(56, 44, 2.6, a)
    c.poly([(45, 8), (51, 8), (54, 26), (42, 26)], t)


def sym_hood(c, m, t, a):
    c.poly([(48, 10), (72, 28), (78, 70), (62, 84), (34, 84), (18, 70), (24, 28)], m)
    c.ellipse(48, 52, 15, 19, _c(m, 0.28), shade=False)
    c.glow(42, 50, 2.6, a)
    c.glow(55, 50, 2.6, a)
    c.line([(32, 28), (48, 18), (64, 28)], 1.6, t)


def sym_hat(c, m, t, a):
    c.poly([(10, 60), (30, 54), (46, 12), (66, 54), (86, 60), (66, 70), (30, 70)], m)
    c.poly([(30, 52), (66, 52), (68, 62), (28, 62)], t)
    c.glow(48, 57, 3, a)


def sym_armor(c, m, t, a):
    c.poly([(28, 18), (68, 18), (82, 30), (74, 46), (72, 82), (24, 82), (22, 46), (14, 30)], m)
    c.poly([(36, 18), (60, 18), (54, 34), (42, 34)], _c(m, 0.4), shade=False)
    c.poly([(22, 56), (74, 56), (74, 64), (22, 64)], t)
    c.glow(48, 44, 4, a)


def sym_cloak(c, m, t, a):
    c.poly([(34, 12), (62, 12), (84, 82), (60, 74), (48, 86), (36, 74), (12, 82)], m)
    c.poly([(34, 12), (62, 12), (58, 24), (38, 24)], t)
    c.glow(48, 22, 3, a)


def sym_boots(c, m, t, a):
    c.poly([(26, 14), (50, 14), (52, 54), (82, 66), (84, 80), (24, 80)], m)
    c.poly([(24, 72), (84, 72), (84, 80), (24, 80)], t)
    c.glow(38, 28, 3, a)


def sym_belt(c, m, t, a):
    c.poly(rr(8, 36, 88, 62, 5), m)
    c.poly(rr(36, 32, 60, 66, 4), t)
    c.glow(48, 49, 5, a)
    for x in (16, 22, 70, 76):
        c.ellipse(x, 49, 1.6, 1.6, t, line=0.6, shade=False)


def sym_ring(c, m, t, a):
    c.ellipse(48, 56, 26, 26, t)
    c.ellipse(48, 56, 16, 16, (0, 0, 0), shade=False)
    c.d.ellipse([(48 - 16) * SS, (56 - 16) * SS, (48 + 16) * SS, (56 + 16) * SS], fill=(0, 0, 0, 0))
    c.ellipse(48, 24, 11, 9, m)
    c.glow(48, 24, 4, a)


def sym_amulet(c, m, t, a):
    c.line([(26, 12), (40, 44)], 2.2, t)
    c.line([(70, 12), (56, 44)], 2.2, t)
    c.poly([(48, 38), (64, 54), (48, 84), (32, 54)], m)
    c.glow(48, 58, 5, a)


def sym_potion(c, m, t, a):
    c.poly([(40, 12), (56, 12), (56, 34), (72, 66), (66, 82), (30, 82), (24, 66), (40, 34)], (210, 225, 235), shade=False)
    c.poly([(30, 52), (66, 52), (72, 66), (66, 82), (30, 82), (24, 66)], m)
    c.poly(rr(38, 6, 58, 16, 2), WOOD)
    c.glow(42, 66, 2.4, a)


def sym_scroll(c, m, t, a):
    c.poly(rr(26, 14, 70, 82, 3), (232, 220, 190), shade=True)
    c.ellipse(26, 14, 5, 5, t)
    c.ellipse(70, 82, 5, 5, t)
    for y in (30, 40, 50, 60):
        c.line([(34, y), (62, y)], 1.2, _c(m, 0.7))
    c.glow(48, 70, 3, a)


def sym_key(c, m, t, a):
    c.ellipse(32, 32, 16, 16, t)
    c.ellipse(32, 32, 7, 7, (0, 0, 0), shade=False)
    c.poly([(42, 42), (50, 36), (82, 70), (76, 80), (68, 72), (62, 78), (56, 72), (50, 76), (40, 56)], m)
    c.glow(32, 32, 3, a)


def sym_gem(c, m, t, a):
    c.poly([(30, 22), (66, 22), (82, 42), (48, 84), (14, 42)], m)
    c.poly([(30, 22), (48, 42), (66, 22)], _c(m, 1.3), shade=False)
    c.line([(14, 42), (82, 42)], 1.0)
    c.line([(48, 42), (48, 84)], 1.0)
    c.glow(38, 33, 2, a)


def sym_ore(c, m, t, a):
    c.poly([(20, 70), (26, 38), (44, 22), (66, 30), (78, 52), (70, 76), (40, 82)], _mix((110, 110, 120), m, 0.5))
    c.poly([(40, 36), (52, 34), (56, 50), (44, 52)], t)
    c.glow(62, 56, 3, a)


def sym_herb(c, m, t, a):
    for ang in (-35, 0, 35):
        c.poly(rot([(46, 22), (50, 22), (58, 46), (48, 84), (38, 46)], ang), m)
    c.glow(48, 60, 3, a)


def sym_bone(c, m, t, a):
    c.poly(rot([(28, 40), (24, 32), (32, 24), (38, 32), (62, 56), (68, 52), (76, 60), (68, 68), (60, 64), (34, 40)], -10), (232, 226, 206))
    c.glow(48, 48, 3, a)


def sym_cloth(c, m, t, a):
    c.poly([(16, 26), (50, 20), (82, 30), (76, 70), (44, 80), (18, 68)], m)
    c.line([(22, 36), (46, 32), (72, 40)], 1.2, t)
    c.line([(24, 50), (50, 48), (72, 56)], 1.2, t)
    c.glow(48, 62, 3, a)


def sym_essence(c, m, t, a):
    c.poly([(48, 8), (66, 40), (80, 60), (66, 82), (30, 82), (16, 60), (30, 40)], _mix(m, (255, 255, 255), 0.2))
    c.glow(48, 56, 9, a)


def sym_tome(c, m, t, a):
    c.poly(rr(20, 14, 76, 82, 4), m)
    c.poly(rr(20, 14, 30, 82, 3), _c(m, 0.6))
    c.poly(star(52, 46, 4, 14, 4, 45), t)
    c.glow(52, 46, 4, a)


def sym_orb(c, m, t, a):
    c.ellipse(48, 48, 30, 30, _mix(m, (255, 255, 255), 0.1))
    c.glow(48, 48, 12, a)
    c.line([(26, 70), (70, 70)], 2.2, t)


def sym_fragment(c, m, t, a):
    c.poly([(30, 14), (62, 20), (74, 52), (58, 84), (26, 70), (20, 40)], (230, 220, 200))
    c.line([(30, 34), (60, 38)], 1.0, _c(m, 0.7))
    c.line([(30, 46), (56, 52)], 1.0, _c(m, 0.7))
    c.line([(32, 58), (50, 64)], 1.0, _c(m, 0.7))
    c.glow(62, 28, 3, a)


# ── spell symbols ──────────────────────────────────────────────────────────────

def sym_flame(c, m, t, a):
    c.poly([(48, 8), (66, 36), (80, 54), (70, 80), (48, 88), (26, 80), (16, 54), (32, 40), (38, 24)], m)
    c.poly([(48, 36), (60, 56), (54, 76), (42, 76), (36, 58)], _mix(a, (255, 255, 255), 0.4), shade=False)


def sym_drop(c, m, t, a):
    c.poly([(48, 8), (68, 40), (76, 60), (62, 82), (34, 82), (20, 60), (28, 40)], m)
    c.ellipse(38, 60, 5, 8, _mix(m, (255, 255, 255), 0.5), shade=False, line=0)


def sym_rock(c, m, t, a):
    c.poly([(16, 72), (24, 36), (44, 16), (68, 24), (82, 48), (74, 76), (40, 84)], m)
    c.poly([(40, 30), (56, 28), (62, 46), (46, 50)], _mix(m, (255, 255, 255), 0.3), shade=False)


def sym_wind(c, m, t, a):
    for y, r in ((34, 20), (50, 24), (66, 18)):
        c.line([(18, y)] + [(18 + r + r * 0.9 * math.cos(math.radians(a2)), y - r * 0.55 * math.sin(math.radians(a2))) for a2 in range(200, -90, -20)], 4.5, INK)
        c.line([(18, y)] + [(18 + r + r * 0.9 * math.cos(math.radians(a2)), y - r * 0.55 * math.sin(math.radians(a2))) for a2 in range(200, -90, -20)], 2.4, m)


def sym_burst(c, m, t, a):
    c.poly(star(48, 48, 14, 40, 8, 10), m)
    c.glow(48, 48, 8, a)


def sym_arrow(c, m, t, a):
    c.poly(rot([(44, 8), (52, 8), (52, 62), (62, 62), (48, 88), (34, 62), (44, 62)], 0), m)


def sym_heal(c, m, t, a):
    c.poly([(38, 12), (58, 12), (58, 38), (84, 38), (84, 58), (58, 58), (58, 84), (38, 84), (38, 58), (12, 58), (12, 38), (38, 38)], m)
    c.glow(48, 48, 5, a)


def sym_glyph(c, m, t, a):
    c.ellipse(48, 48, 36, 36, _c(m, 0.5), shade=False)
    c.ellipse(48, 48, 26, 26, m, shade=False)
    c.poly(star(48, 48, 10, 24, 3, -90), t, shade=False)
    c.glow(48, 48, 5, a)


def sym_trap(c, m, t, a):
    c.poly(star(48, 48, 20, 40, 8, 0), t)
    c.ellipse(48, 48, 14, 14, m)
    c.glow(48, 48, 4, a)


def sym_summon(c, m, t, a):
    c.poly([(48, 12), (66, 30), (60, 56), (74, 82), (22, 82), (36, 56), (30, 30)], _c(m, 0.8))
    c.glow(42, 36, 3, a)
    c.glow(55, 36, 3, a)


def sym_eye(c, m, t, a):
    c.poly([(8, 48), (28, 28), (48, 22), (68, 28), (88, 48), (68, 68), (48, 74), (28, 68)], (236, 232, 222))
    c.ellipse(48, 48, 14, 14, m)
    c.ellipse(48, 48, 6, 8, INK[:3], shade=False)


def sym_chain(c, m, t, a):
    for cx, cy, ang in ((34, 34, 40), (62, 62, 40)):
        c.poly(rot([(cx - 14, cy - 8), (cx + 14, cy - 8), (cx + 14, cy + 8), (cx - 14, cy + 8)], ang, cx, cy), m)
    c.poly(rot([(34, 46), (62, 46), (62, 58), (34, 58)], -50, 48, 52), t)


def sym_skull(c, m, t, a):
    c.ellipse(48, 42, 28, 26, (232, 226, 206))
    c.poly(rr(34, 58, 62, 80, 3), (222, 216, 196))
    c.ellipse(38, 44, 6, 7, INK[:3], shade=False)
    c.ellipse(58, 44, 6, 7, INK[:3], shade=False)
    c.glow(38, 44, 2.4, a)
    c.glow(58, 44, 2.4, a)


def sym_wing(c, m, t, a):
    c.poly([(16, 70), (22, 28), (50, 10), (82, 24), (60, 36), (80, 42), (56, 52), (70, 62), (40, 66)], m)


def sym_swap(c, m, t, a):
    c.poly([(14, 34), (54, 34), (54, 20), (82, 42), (54, 64), (54, 50), (14, 50)], m)
    c.poly([(82, 62), (42, 62), (42, 48), (14, 70), (42, 92), (42, 78), (82, 78)], t)


def sym_fist(c, m, t, a):
    c.poly(rr(24, 28, 72, 70, 8), m)
    for x in (30, 42, 54, 66):
        c.line([(x, 30), (x, 46)], 1.3)
    c.poly(rr(20, 66, 70, 84, 4), t)


def sym_dash(c, m, t, a):
    c.poly([(60, 14), (84, 48), (60, 82), (60, 62), (14, 62), (14, 34), (60, 34)], m)


def sym_moon(c, m, t, a):
    c.poly([(60, 10), (46, 20), (38, 40), (42, 62), (58, 78), (74, 78), (54, 66), (50, 44), (58, 26), (74, 16)], m)
    c.glow(66, 34, 2.4, a)


def sym_book(c, m, t, a):
    sym_tome(c, m, t, a)


SYMBOLS = {k[4:]: v for k, v in globals().items() if k.startswith("sym_")}


def plate(rarity=0, pal=ELEMENT["neutral"]):
    """Dark rounded plate with a rarity border and a soft inner gradient."""
    im = Image.new("RGBA", (W, W), (0, 0, 0, 0))
    d = ImageDraw.Draw(im)
    rim = RARITY.get(rarity, RARITY[0])
    d.rounded_rectangle([3 * SS, 3 * SS, W - 3 * SS, W - 3 * SS], radius=14 * SS, fill=rim + (255,))
    d.rounded_rectangle([6 * SS, 6 * SS, W - 6 * SS, W - 6 * SS], radius=12 * SS, fill=(30, 26, 38, 255))
    grad = Image.new("RGBA", (W, W), (0, 0, 0, 0))
    gd = ImageDraw.Draw(grad)
    tint = _mix(pal, (30, 26, 38), 0.8)
    for i in range(W // 2, 0, -8):
        k = i / (W / 2)
        gd.ellipse([W / 2 - i, W * 0.42 - i, W / 2 + i, W * 0.42 + i], fill=tint + (int(60 * (1 - k)),))
    mask = Image.new("L", (W, W), 0)
    ImageDraw.Draw(mask).rounded_rectangle([6 * SS, 6 * SS, W - 6 * SS, W - 6 * SS], radius=12 * SS, fill=255)
    grad.putalpha(Image.composite(grad.getchannel("A"), Image.new("L", (W, W), 0), mask))
    im.alpha_composite(grad)
    return im


def icon(symbol, main, trim=None, acc=None, rarity=0, plate_on=True):
    c = Canvas()
    trim = trim or _c(main, 1.35)
    acc = acc or _mix(main, (255, 255, 255), 0.5)
    SYMBOLS[symbol](c, main, trim, acc)
    base = plate(rarity, main) if plate_on else Image.new("RGBA", (W, W), (0, 0, 0, 0))
    base.alpha_composite(c.finish())
    return base.resize((SIZE, SIZE), Image.LANCZOS)


def portrait(frame_img: Image.Image, size=96) -> Image.Image:
    """Monster portrait: the creature's first idle frame, cropped to its content and fitted in a plate."""
    box = frame_img.getbbox() or (0, 0, 1, 1)
    crop = frame_img.crop(box)
    k = min((size - 14) / crop.width, (size - 14) / crop.height)
    crop = crop.resize((max(1, int(crop.width * k)), max(1, int(crop.height * k))), Image.LANCZOS)
    out = plate(0, (120, 110, 140)).resize((size, size), Image.LANCZOS)
    out.alpha_composite(crop, ((size - crop.width) // 2, (size - crop.height) // 2 + 2))
    return out
