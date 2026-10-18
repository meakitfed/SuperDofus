"""Parametric creature rigs for the Vertebre world, drawn in code (PIL), written as Dofus-format
bones with the joss mod's writer (game/mods/joss/build). Four families cover every creature:

  upright   torso, head, two arms (+weapon), two legs, optional cape / wings / tail   (men, brutes, golems, skeletons)
  beast     long body, head, tail, four legs                                        (wolves, boars, drakes, insects)
  floater   a core with orbiting satellites and trailing wisps, no legs              (eyes, flames, tomes, spirits)
  serpent   a chain of segments following a sine path                               (worms, snakes, roots)

A creature is a `spec` dict (see creatures.py): palette, proportions, head style, extras, attack style.
Style: flat colour + one shade + one highlight, thick dark contour (the joss art primitives), one glowing
accent colour per creature (eyes, runes, core). Only directions 1 and 5 are written, the renderer mirrors them.
"""
from __future__ import annotations

import math
import os
import random
import sys

HERE = os.path.dirname(os.path.abspath(__file__))
sys.path.insert(0, os.path.join(HERE, "..", "..", "..", "game", "mods", "joss", "build"))

from art import INK, INNER, Part, Sprite, ellipse_pts, spline  # noqa: E402
from dofus_bone import Anim, Bone, Node, R, S, T, mul  # noqa: E402

BLEND_ADD = 8


def finish_fast(self: Part) -> Sprite:
    """Part.finish() with the contour dilated after downscaling: the 4x supersampled MaxFilter of the joss art
    module takes seconds per sprite, this one milliseconds, for the same 1.7 unit outline."""
    from PIL import Image, ImageFilter
    from art import OUTER, RES, SS
    img = self.base.copy()
    img.alpha_composite(self.top)
    small = img.resize((max(1, img.width // SS), max(1, img.height // SS)), Image.LANCZOS)
    a = small.getchannel("A").point(lambda v: 255 if v > 8 else 0)
    grown = a.filter(ImageFilter.MaxFilter(int(OUTER * RES) * 2 + 1))
    outline = Image.new("RGBA", small.size, INK)
    outline.putalpha(grown)
    outline.alpha_composite(small)
    box = outline.getchannel("A").getbbox() or (0, 0, 1, 1)
    box = (max(0, box[0] - 1), max(0, box[1] - 1), min(outline.width, box[2] + 1), min(outline.height, box[3] + 1))
    return Sprite(self.name, outline.crop(box), (-self.x0 * RES - box[0], -self.y0 * RES - box[1]))


Part.finish = finish_fast  # every creature, prop and map object of this world uses it


# ── colours ────────────────────────────────────────────────────────────────────

def shade(c, k):
    return tuple(max(0, min(255, int(v * k))) for v in c[:3])


def mix(a, b, t):
    return tuple(int(a[i] + (b[i] - a[i]) * t) for i in range(3))


class Pal:
    def __init__(self, main, acc, trim=None, dark=None):
        self.main = tuple(main)
        self.sh = shade(main, 0.68)
        self.hi = mix(main, (255, 255, 255), 0.28)
        self.acc = tuple(acc)
        self.acc_hi = mix(acc, (255, 255, 255), 0.6)
        self.trim = tuple(trim) if trim else shade(main, 1.35)
        self.trim_sh = shade(self.trim, 0.7)
        self.dark = tuple(dark) if dark else shade(main, 0.38)


def glow(p: Part, x, y, r, pal: Pal):
    """A glowing accent dot: soft halo, saturated disc, white core."""
    p.dot(x, y, r * 1.9, pal.acc + (70,), top=True)
    p.dot(x, y, r * 1.35, pal.acc + (150,), top=True)
    p.dot(x, y, r, pal.acc + (255,), top=True)
    p.dot(x, y, r * 0.45, pal.acc_hi + (255,), top=True)


def shape(p: Part, pts, pal: Pal, fill=None, light=True, shd=True, line=True):
    """A filled shape with a shade crescent (lower right) and a highlight (upper left)."""
    fill = fill or pal.main
    p.shape(pts, fill, line=line)
    xs, ys = [q[0] for q in pts], [q[1] for q in pts]
    x0, x1, y0, y1 = min(xs), max(xs), min(ys), max(ys)
    w, h = x1 - x0, y1 - y0
    if shd:
        p.shade([(x0 + w * 0.55, y0 - 1), (x1 + 2, y0 - 1), (x1 + 2, y1 + 2), (x0 + w * 0.1, y1 + 2)], mix(fill, (0, 0, 0), 0.32))
    if light and w > 5 and h > 5:
        p.shade(ellipse_pts(x0 + w * 0.3, y0 + h * 0.28, w * 0.14, h * 0.12), mix(fill, (255, 255, 255), 0.3))


def rrect(x0, y0, x1, y1, r=2.0, n=4):
    """Rounded rectangle polygon."""
    pts = []
    for cx, cy, a0 in ((x1 - r, y0 + r, -90), (x1 - r, y1 - r, 0), (x0 + r, y1 - r, 90), (x0 + r, y0 + r, 180)):
        for i in range(n + 1):
            a = math.radians(a0 + 90 * i / n)
            pts.append((cx + r * math.cos(a), cy + r * math.sin(a)))
    return pts


def ragged(pts, rnd, amp=1.2):
    return [(x + rnd.uniform(-amp, amp), y + rnd.uniform(-amp, amp)) for x, y in pts]


def spikes(cx, cy, r_in, r_out, n, rot=0.0):
    out = []
    for i in range(n * 2):
        a = rot + math.pi * i / n
        r = r_out if i % 2 == 0 else r_in
        out.append((cx + r * math.cos(a), cy + r * math.sin(a)))
    return out


# ── upright parts ──────────────────────────────────────────────────────────────

def torso_sprite(sp, pal: Pal, rnd) -> Sprite:
    w, H = sp["w"], sp["h"]
    p = Part("torso", -w - 9, -H - 10, w + 9, 12)
    style = sp.get("body", "robe")
    if style in ("robe", "rags"):
        hem = []
        n = 7
        for i in range(n + 1):
            x = w * 1.3 - (2.6 * w * 1.3) * i / n
            hem.append((x, 8 + (3.5 if i % 2 else 0) * (1.6 if style == "rags" else 0.7)))
        top = [(-w * 0.8, -H + 3), (-w * 0.35, -H - 1.5), (w * 0.35, -H - 1.5), (w * 0.85, -H + 3), (w * 1.0, -H * 0.4)]
        pts = top + [(w * 1.1, 0)] + hem + [(-w * 1.1, 0), (-w * 1.0, -H * 0.4)]
        shape(p, spline(pts, steps=3) if style == "robe" else ragged(pts, rnd, 0.9), pal)
        p.line(spline([(0, -H + 1), (0.5, -H * 0.4), (1, 6)], closed=False), width=INNER * 0.8)
        belt = [(-w * 1.05, -H * 0.38), (w * 1.05, -H * 0.38), (w * 1.07, -H * 0.38 + 3.2), (-w * 1.07, -H * 0.38 + 3.2)]
        p.shape(belt, pal.trim)
        p.shape(rrect(-1.5, -H * 0.38 - 0.4, 2.8, -H * 0.38 + 3.6, 1), pal.dark)
    elif style in ("armor", "plate"):
        body = [(-w * 0.85, -H + 2), (w * 0.85, -H + 2), (w * 1.0, -H * 0.4), (w * 0.85, 4), (-w * 0.85, 4), (-w * 1.0, -H * 0.4)]
        shape(p, spline(body, steps=3), pal)
        for sx in (-1, 1):  # pauldrons
            shape(p, ellipse_pts(sx * w * 0.95, -H + 3.5, w * 0.42, w * 0.34), pal, fill=pal.trim)
        p.shape(rrect(-w * 0.95, -H * 0.32, w * 0.95, -H * 0.32 + 4.2, 1.2), pal.dark)
        p.shape(spline([(-w * 0.55, -H + 5), (w * 0.55, -H + 5), (w * 0.4, -H * 0.5), (-w * 0.4, -H * 0.5)], steps=3), pal.trim)
        legs_skirt = [(-w * 0.85, 4), (w * 0.85, 4), (w * 0.7, 11), (0, 8), (-w * 0.7, 11)]
        p.shape(legs_skirt, pal.sh)
    else:  # bare / hulking
        body = [(-w * 0.7, -H), (w * 0.8, -H), (w * 1.15, -H * 0.55), (w * 0.9, 4), (-w * 0.9, 4), (-w * 1.1, -H * 0.55)]
        shape(p, spline(body, steps=4), pal)
        for k in (0.55, 0.3):  # belly lines
            p.line(spline([(-w * 0.5, -H * k), (0, -H * k + 2), (w * 0.5, -H * k)], closed=False), width=INNER * 0.7)
        p.shape(rrect(-w * 0.95, -H * 0.08, w * 0.95, 4.5, 1), pal.dark)
    # rune / core motif in accent colour
    m = sp.get("motif", "core")
    cy = -H * 0.62
    if m == "core":
        glow(p, 1.5, cy, 2.4, pal)
    elif m == "rune":
        p.line([(0, cy - 5), (0, cy + 5)], width=0.9, color=pal.acc + (255,), top=True)
        p.line([(-3.5, cy - 1), (3.5, cy - 1)], width=0.9, color=pal.acc + (255,), top=True)
        p.line([(-2.5, cy + 3), (2.5, cy + 3)], width=0.9, color=pal.acc + (255,), top=True)
    elif m == "cracks":
        for _ in range(3):
            x, y = rnd.uniform(-w * 0.6, w * 0.6), rnd.uniform(-H * 0.9, -H * 0.2)
            pts = [(x, y), (x + rnd.uniform(-3, 3), y + 3), (x + rnd.uniform(-4, 4), y + 6)]
            p.line(pts, width=0.8, color=pal.acc + (255,), top=True)
    return p.finish()


def head_sprite(sp, pal: Pal, rnd, back=False) -> Sprite:
    hs = sp.get("hs", 9)
    style = sp.get("head", "round")
    p = Part("head_b" if back else "head_f", -hs * 2.2, -hs * 3.4, hs * 2.2, 6)
    cx, cy = 0.8, -hs * 1.05
    ex = hs * 0.38  # eyes offset towards the facing side
    if style == "hood":
        hood = spline([(-hs * 1.05, 0), (-hs * 1.1, -hs * 1.2), (-hs * 0.3, -hs * 2.2), (hs * 0.8, -hs * 2.0), (hs * 1.25, -hs * 1.0), (hs * 0.8, 0)], steps=6)
        shape(p, hood, pal)
        if not back:
            face = ellipse_pts(hs * 0.45, -hs * 1.0, hs * 0.62, hs * 0.72)
            p.shape(face, pal.dark)
            glow(p, hs * 0.3, -hs * 1.05, hs * 0.2, pal)
            glow(p, hs * 0.85, -hs * 1.05, hs * 0.2, pal)
    elif style == "skull":
        shape(p, ellipse_pts(cx, cy - 1, hs * 1.0, hs * 1.0), pal, fill=pal.trim)
        jaw = rrect(cx - hs * 0.55, cy + hs * 0.55, cx + hs * 0.75, cy + hs * 1.0, 1)
        p.shape(jaw, pal.trim_sh)
        if not back:
            for dx in (0.05, 0.75):
                p.shape(ellipse_pts(cx + hs * dx, cy - 1, hs * 0.26, hs * 0.3), pal.dark)
                glow(p, cx + hs * dx, cy - 1, hs * 0.15, pal)
            for i in range(4):
                p.line([(cx - hs * 0.3 + i * hs * 0.3, cy + hs * 0.6), (cx - hs * 0.3 + i * hs * 0.3, cy + hs * 1.0)], width=0.5)
    elif style == "helm":
        shape(p, spline([(-hs * 1.0, 0), (-hs * 1.05, -hs * 1.4), (0, -hs * 2.1), (hs * 1.0, -hs * 1.5), (hs * 1.1, 0)], steps=5), pal, fill=pal.trim)
        p.shape([(cx - 1.2, -hs * 2.15), (cx + 1.2, -hs * 2.15), (cx + 2.0, -hs * 3.0), (cx - 2.0, -hs * 3.0)], pal.acc)  # crest
        if not back:
            p.shape(rrect(hs * 0.1, -hs * 1.35, hs * 1.1, -hs * 0.95, 0.8), pal.dark)
            glow(p, hs * 0.65, -hs * 1.15, hs * 0.16, pal)
    elif style == "mask":
        shape(p, ellipse_pts(cx, cy, hs * 0.95, hs * 1.15), pal, fill=mix(pal.trim, (255, 255, 255), 0.4))
        if not back:
            p.line([(cx + hs * 0.2, cy - hs), (cx + hs * 0.2, cy + hs * 0.9)], width=0.8, color=pal.acc + (255,), top=True)
            glow(p, cx + hs * 0.55, cy - hs * 0.15, hs * 0.2, pal)
            p.line(spline([(cx + hs * 0.1, cy + hs * 0.55), (cx + hs * 0.55, cy + hs * 0.65)], closed=False), width=0.7)
    elif style == "cyclops":
        shape(p, ellipse_pts(cx, cy, hs * 1.1, hs * 1.0), pal)
        if not back:
            p.shape(ellipse_pts(cx + hs * 0.35, cy - 0.5, hs * 0.5, hs * 0.5), (240, 236, 224))
            glow(p, cx + hs * 0.45, cy - 0.5, hs * 0.3, pal)
            p.line(spline([(cx - hs * 0.1, cy + hs * 0.65), (cx + hs * 0.4, cy + hs * 0.8), (cx + hs * 0.8, cy + hs * 0.6)], closed=False), width=0.8)
    else:  # round / horned / beastman
        shape(p, ellipse_pts(cx, cy, hs * 1.0, hs * 1.05), pal)
        if style == "horned":
            for sx in (-1, 1):
                horn = spline([(cx + sx * hs * 0.45, cy - hs * 0.85), (cx + sx * hs * 1.2, cy - hs * 1.5),
                               (cx + sx * hs * 1.1, cy - hs * 2.3), (cx + sx * hs * 0.85, cy - hs * 1.5)], steps=6)
                shape(p, horn, pal, fill=pal.trim)
        if not back:
            for dx in (0.15, 0.75):
                glow(p, cx + hs * dx, cy - 0.5, hs * 0.18, pal)
            p.line(spline([(cx + hs * 0.1, cy + hs * 0.55), (cx + hs * 0.45, cy + hs * 0.7), (cx + hs * 0.85, cy + hs * 0.5)], closed=False), width=0.8)
            p.line(spline([(cx + hs * 0.0, cy - hs * 0.45), (cx + hs * 0.35, cy - hs * 0.6)], closed=False), width=0.8)
    return p.finish()


def limb_sprite(name, length, width, kind, pal: Pal, rnd, end="hand") -> Sprite:
    """A limb hanging from its joint (pivot at the top), tapered, ending in a hand / claw / fist / foot."""
    w = width
    p = Part(name, -w * 2.5, -4, w * 3.2 + length * 0.25, length + w * 2.5)
    fill = {"bone": mix(pal.trim, (255, 255, 255), 0.35), "armor": pal.trim, "claw": pal.main, "sleeve": pal.main,
            "fist": pal.main}.get(kind, pal.main)
    tube = [(-w, 0), (w, 0), (w * 0.8, length * 0.55), (w * 0.7, length), (-w * 0.7, length), (-w * 0.8, length * 0.55)]
    shape(p, spline(tube, steps=4), pal, fill=fill)
    if kind == "bone":
        for y in (0.0, 0.55, 1.0):
            p.shape(ellipse_pts(0, length * y, w * 1.25, w * 1.1), fill)
    elif kind == "sleeve":
        p.shape(rrect(-w * 1.1, length * 0.72, w * 1.1, length * 0.9, 0.8), pal.trim)  # cuff
    elif kind == "armor":
        p.shape(rrect(-w * 1.15, length * 0.35, w * 1.15, length * 0.5, 0.8), pal.main)
    if end == "foot":
        shape(p, spline([(-w * 0.8, length - 1), (w * 0.7, length - 1), (w * 2.6, length + w * 0.9), (w * 2.2, length + w * 1.9),
                         (-w * 0.9, length + w * 1.9)], steps=4), pal, fill=pal.dark if kind != "bone" else fill)
    elif kind == "claw":
        for i, ox in enumerate((-0.6, 0.1, 0.8)):
            p.shape(spline([(w * ox - 0.8, length), (w * ox + 0.9, length), (w * ox * 1.6 + 2.2, length + w * 1.9)], closed=True, steps=2), pal.hi)
    elif kind == "fist":
        shape(p, ellipse_pts(0.5, length + w * 0.5, w * 1.5, w * 1.35), pal)
        for i in (-0.5, 0.5):
            p.line([(i * w * 0.9 + 0.5, length), (i * w * 0.9 + 0.5, length + w * 1.4)], width=0.5)
    else:
        shape(p, ellipse_pts(0.5, length + w * 0.5, w * 0.95, w * 1.05), pal, fill=mix(pal.trim, (255, 220, 190), 0.35) if kind == "sleeve" else fill)
    return p.finish()


def weapon_sprite(kind, pal: Pal, size=26) -> Sprite:
    """Held weapon: pivot at the grip, extending DOWN (the way the arm hangs); the pose swings it forward."""
    p = Part("weapon", -size * 0.5, -size * 0.4, size * 0.5, size * 1.55)
    L = size
    if kind == "sword":
        p.shape([(-1.0, -2), (1.0, -2), (1.1, L), (0, L + 4), (-1.1, L)], mix(pal.trim, (255, 255, 255), 0.5))
        p.line([(0, 0), (0, L)], width=0.4, color=pal.acc + (255,), top=True)
        p.shape(rrect(-4, -4, 4, -1.5, 0.8), pal.dark)
    elif kind == "axe":
        p.shape(rrect(-1, -4, 1, L, 0.5), pal.dark)
        blade = spline([(1, L - 2), (L * 0.42, L - 6), (L * 0.46, L + 6), (1, L + 4)], steps=5)
        shape(p, blade, pal, fill=mix(pal.trim, (255, 255, 255), 0.4))
        p.line([(L * 0.2, L - 4), (L * 0.2, L + 3)], width=0.5, color=pal.acc + (255,), top=True)
    elif kind == "staff":
        p.shape(rrect(-1.1, -L * 0.45, 1.1, L * 1.3, 0.6), pal.dark)
        p.shape(spikes(0, L * 1.3 + 3, 1.6, 5.5, 4), pal.trim)
        glow(p, 0, L * 1.3 + 3, 2.6, pal)
    elif kind == "scythe":
        p.shape(rrect(-1, -L * 0.4, 1, L * 1.25, 0.6), pal.dark)
        blade = spline([(0, L * 1.25), (L * 0.55, L * 1.2), (L * 0.75, L * 1.55), (L * 0.3, L * 1.4), (0, L * 1.33)], steps=5)
        shape(p, blade, pal, fill=mix(pal.trim, (255, 255, 255), 0.45))
    elif kind == "shield":
        shape(p, ellipse_pts(0, L * 0.3, L * 0.38, L * 0.46), pal, fill=pal.trim)
        glow(p, 0, L * 0.3, 2.4, pal)
        p.line(ellipse_pts(0, L * 0.3, L * 0.3, L * 0.38), width=0.6, color=pal.dark + (255,))
    elif kind == "orb":
        glow(p, 0, 2, 4.5, pal)
    elif kind == "bow":
        p.line(spline([(-1, -L * 0.7), (L * 0.35, L * 0.4), (-1, L * 1.5)], closed=False), width=1.6, color=pal.dark + (255,))
        p.line([(-1, -L * 0.7), (-1, L * 1.5)], width=0.35, color=(230, 230, 230, 255))
    elif kind == "dagger":
        p.shape([(-0.9, -1), (0.9, -1), (0.9, L * 0.5), (0, L * 0.6)], mix(pal.trim, (255, 255, 255), 0.5))
        p.shape(rrect(-2.5, -2.6, 2.5, -0.8, 0.5), pal.dark)
    else:  # mace / club
        p.shape(rrect(-1.1, -4, 1.1, L * 0.9, 0.6), pal.dark)
        shape(p, spikes(0, L, 4.5, 8, 7), pal, fill=pal.trim)
    return p.finish()


def cape_sprite(sp, pal: Pal, rnd) -> Sprite:
    w, H = sp["w"], sp["h"]
    p = Part("cape", -w * 1.8, -H - 4, w * 1.8, H * 1.1)
    pts = [(-w * 0.7, -H), (w * 0.7, -H), (w * 1.4, -H * 0.2)]
    for i in range(6):
        pts.append((w * 1.4 - 2.8 * w * i / 5, H * 0.75 + (3.5 if i % 2 else 0)))
    pts.append((-w * 1.4, -H * 0.2))
    shape(p, pts, pal, fill=shade(pal.main, 0.8))
    return p.finish()


def wings_sprite(sp, pal: Pal, kind="bat") -> Sprite:
    w, H = sp["w"], sp["h"]
    sz = sp.get("wing", H * 1.1)
    p = Part("wings", -sz * 1.6, -sz * 1.3, sz * 0.4, sz * 0.5)
    if kind == "feather":
        for i in range(5):
            a = -0.2 - i * 0.28
            tip = (-sz * 1.2 * math.cos(a * 0.8 + 0.4), -sz * math.sin(0.5 + i * 0.25) * 1.1)
            shape(p, spline([(0, 0), (tip[0] * 0.5, tip[1] * 0.5 - 3), tip, (tip[0] * 0.6, tip[1] * 0.6 + 4)], steps=4), pal, fill=mix(pal.trim, pal.main, i / 5))
    else:  # bat / membrane
        fingers = [(-sz * 1.3, -sz * 0.9), (-sz * 1.4, -sz * 0.35), (-sz * 1.0, sz * 0.1), (-sz * 0.4, sz * 0.15)]
        pts = [(0, 0), (-sz * 0.3, -sz * 0.9)] + fingers
        shape(p, spline(pts, steps=3), pal, fill=shade(pal.main, 0.85))
        for f in fingers[:-1]:
            p.line([(0, 0), f], width=0.9, color=pal.dark + (255,))
    return p.finish()


def tail_sprite(sp, pal: Pal, length=22, kind="tail") -> Sprite:
    p = Part("tail", -length * 1.2, -length * 0.5, 6, length * 0.9)
    pts = [(0, -2.5), (-length * 0.5, -length * 0.1), (-length * 1.0, -length * 0.35), (-length * 1.0, -length * 0.15), (-length * 0.5, length * 0.15), (0, 2.5)]
    shape(p, spline(pts, steps=5), pal)
    if kind == "spiked":
        p.shape(spikes(-length * 1.0, -length * 0.25, 2.5, 6.5, 5), pal.trim)
    return p.finish()


def shadow_sprite(r=15) -> Sprite:
    """A soft ground shadow: no ink contour, so it is built directly (Part.finish would outline it)."""
    from PIL import Image, ImageDraw, ImageFilter
    from art import RES
    w, h = int(r * 2 * RES) + 8, int(r * 0.8 * RES) + 8
    img = Image.new("RGBA", (w, h), (0, 0, 0, 0))
    ImageDraw.Draw(img).ellipse((4, 4, w - 4, h - 4), fill=(10, 6, 14, 110))
    img = img.filter(ImageFilter.GaussianBlur(1.5))
    return Sprite("shadow", img, (w / 2, h / 2))


# ── poses and animation plumbing ───────────────────────────────────────────────

REST = dict(px=0.0, bob=0.0, torso=0.0, breath=1.0, head=0.0, sh_n=6.0, el_n=8.0, sh_f=-4.0, el_f=6.0,
            hip_n=0.0, hip_f=0.0, fall=0.0, drop=0.0, alpha=1.0, flap=0.0, sway=0.0)


def pose(**kw):
    p = dict(REST)
    p.update(kw)
    return p


def _ease(t):
    return t * t * (3 - 2 * t)


def keyed(keys, count):
    out = []
    for fr in range(count):
        for (f0, p0), (f1, p1) in zip(keys, keys[1:]):
            if f0 <= fr <= f1:
                t = _ease((fr - f0) / max(1, f1 - f0))
                out.append({k: p0[k] + (p1[k] - p0[k]) * t for k in p0})
                break
        else:
            out.append(dict(keys[-1][1]))
    return out


def mirror(nodes, view):
    """View 5 is the view-1 skeleton mirrored (the back head sprite is swapped by the caller)."""
    if view == 1:
        return nodes
    m = S(-1, 1)
    return [Node(n.sprite, mul(m, n.m), n.mul, n.blend) for n in nodes]


def upright_pose_set(sp, clip):
    """List of poses (and labels) for a clip of the upright family."""
    style = sp.get("attack", "slash")
    big = sp.get("heavy", False)
    if clip == "idle":
        n = 40
        return [pose(breath=1 + 0.02 * math.sin(2 * math.pi * t / n), bob=-0.5 * math.sin(2 * math.pi * t / n),
                     head=2 * math.sin(2 * math.pi * t / n + 1), sh_n=6 + 3 * math.sin(2 * math.pi * t / n + 0.5),
                     sh_f=-4 + 2 * math.sin(2 * math.pi * t / n + 1), sway=math.sin(2 * math.pi * t / n)) for t in range(n)], {}
    if clip in ("walk", "run"):
        n, amp, lean = (22, 20.0, -4.0) if clip == "walk" else (14, 30.0, -12.0)
        if big:
            amp *= 0.7
        out = []
        for t in range(n):
            ph = 2 * math.pi * t / n
            s = math.sin(ph)
            out.append(pose(hip_n=amp * s, hip_f=-amp * s, bob=-1.6 * abs(math.cos(ph)), torso=lean + math.cos(2 * ph),
                            sh_n=6 - 16 * s, sh_f=-2 + 14 * s, el_n=14, el_f=12, sway=s))
        return out, {}
    if clip == "attack":
        if style == "cast":
            up = pose(bob=1, torso=8, head=-8, sh_n=150, el_n=-10, sh_f=140, el_f=-10, flap=1)
            peak = pose(bob=2, torso=14, head=-12, sh_n=175, el_n=-5, sh_f=165, el_f=-5, flap=1)
            keys = [(0, pose()), (6, pose(torso=-8, sh_n=-30, sh_f=-30)), (12, up), (15, peak), (17, peak), (23, pose())]
            return keyed(keys, 24), {15: ["SHOT"]}
        if style == "slam":
            raise_ = pose(bob=1, torso=18, head=10, sh_n=185, el_n=20, sh_f=178, el_f=20, hip_n=-6, hip_f=8)
            hit_ = pose(bob=-3, torso=-24, head=-14, sh_n=40, el_n=5, sh_f=34, el_f=5, hip_n=12, hip_f=-8)
            keys = [(0, pose()), (9, raise_), (12, raise_), (15, hit_), (18, hit_), (27, pose())]
            return keyed(keys, 28), {15: ["SHOT"]}
        wind = pose(bob=0.5, torso=14, head=8, sh_n=-75, el_n=-30, sh_f=-30, el_f=10, hip_n=-6, hip_f=8)
        swing = pose(bob=-2.5, torso=-22, head=-12, sh_n=125, el_n=8, sh_f=40, el_f=10, hip_n=14, hip_f=-8, px=2)
        keys = [(0, pose()), (7, wind), (10, wind), (13, swing), (16, swing), (24, pose())]
        return keyed(keys, 25), {13: ["SHOT"]}
    if clip == "hit":
        return [pose(px=-3.5 * e, torso=14 * e, head=14 * e, sh_n=6 + 35 * e, sh_f=-4 + 30 * e, hip_n=-5 * e, hip_f=6 * e)
                for e in (t / 3 if t < 3 else math.exp(-(t - 3) / 3.0) for t in range(13))], {}
    # death
    stagger = pose(px=-3, torso=12, head=16, sh_n=60, el_n=30, sh_f=50, el_f=30, hip_n=-8, hip_f=10)
    tip = pose(px=-4, torso=8, head=18, sh_n=110, el_n=20, sh_f=95, el_f=20, hip_n=20, hip_f=30, fall=30, drop=8)
    down = pose(px=-4, torso=4, head=8, sh_n=150, el_n=10, sh_f=140, el_f=10, hip_n=30, hip_f=24, fall=82, drop=sp["leg"] * 0.65)
    keys = [(0, pose()), (5, stagger), (12, tip), (19, down), (22, dict(down, fall=77)), (25, down), (30, down), (40, dict(down, alpha=0))]
    return keyed(keys, 41), {}


def upright_nodes(sp, view, p, parts):
    f = 1
    H, L, w = sp["h"], sp["leg"], sp["w"]
    al = p["alpha"]
    c = (1, 1, 1, al)
    dark = (0.78, 0.76, 0.8, al)
    pelvis = mul(T(p["px"], L + p["bob"] - p["drop"]), R(f * p["fall"]))
    torso = mul(pelvis, mul(R(f * p["torso"]), S(1, p["breath"])))
    neck = mul(torso, T(1.0, H))
    head = mul(neck, R(f * p["head"]))
    arm_len, fore_len = parts["arm_len"], parts["fore_len"]

    def arm(x, y, sh, el):
        up = mul(torso, mul(T(x, y), R(f * sh)))
        lo = mul(up, mul(T(0, -arm_len), R(f * el)))
        hand = mul(lo, T(0, -fore_len))
        return up, lo, hand

    up_n, lo_n, hand_n = arm(-w * 0.72, H - 4, p["sh_n"], p["el_n"])
    up_f, lo_f, hand_f = arm(w * 0.74, H - 3, p["sh_f"], p["el_f"])
    leg_n = mul(pelvis, mul(T(-w * 0.35, 0), R(f * p["hip_n"])))
    leg_f = mul(pelvis, mul(T(w * 0.4, 1), R(f * p["hip_f"])))
    nodes = [Node("shadow", mul(T(p["px"] * 0.3, 0), S(1 - 0.25 * min(1, abs(p["fall"]) / 80), 1)), (1, 1, 1, al))]
    if "wings" in parts:
        nodes.append(Node("wings", mul(torso, mul(T(-w * 0.3, H - 6), R(f * (8 + 18 * math.sin(p["flap"] * 1.0 + p["sway"] * 0.8))))), c))
    if "tail" in parts:
        nodes.append(Node("tail", mul(pelvis, mul(T(-w * 0.8, 4), R(f * (8 + 6 * p["sway"])))), c))
    if "cape" in parts:
        nodes.append(Node("cape", mul(torso, mul(T(-w * 0.35, H - 2), R(f * (-3 - 5 * p["sway"] - abs(p["px"]))))), (0.9, 0.9, 0.9, al)))
    if parts.get("far_weapon"):
        nodes += [Node("arm_up", up_f, dark), Node("arm_lo", lo_f, dark), Node("far_weapon", hand_f, dark)]
    else:
        nodes += [Node("arm_up", up_f, dark), Node("arm_lo", lo_f, dark)]
    nodes += [Node("leg", leg_f, dark), Node("leg", leg_n, c), Node("torso", torso, c),
              Node("head_b" if view == 5 else "head_f", head, c), Node("arm_up", up_n, c), Node("arm_lo", lo_n, c)]
    if "weapon" in parts:
        nodes.append(Node("weapon", hand_n, c))
    return mirror(nodes, view)


# ── upright bone ───────────────────────────────────────────────────────────────

def build_upright(name, sp) -> Bone:
    rnd = random.Random(sp.get("seed", name))
    pal = sp["pal"]
    aw = sp.get("arm_w", 3.0)
    arm_len = sp.get("arm", 15.0)
    fore_len = sp.get("fore", 14.0)
    sprites = {
        "shadow": shadow_sprite(sp["w"] * 1.5 + 4),
        "torso": torso_sprite(sp, pal, rnd),
        "head_f": head_sprite(sp, pal, rnd),
        "head_b": head_sprite(sp, pal, rnd, back=True),
        "arm_up": limb_sprite("arm_up", arm_len, aw, sp.get("limbs", "sleeve"), pal, rnd),
        "arm_lo": limb_sprite("arm_lo", fore_len, aw * 0.9, sp.get("limbs", "sleeve"), pal, rnd, end="hand"),
        "leg": limb_sprite("leg", sp["leg"], sp.get("leg_w", 3.3), "bone" if sp.get("limbs") == "bone" else "armor" if sp.get("limbs") == "armor" else "leg", pal, rnd, end="foot"),
    }
    parts = {"arm_len": arm_len, "fore_len": fore_len}
    if sp.get("weapon"):
        sprites["weapon"] = weapon_sprite(sp["weapon"], pal, sp.get("wsize", 26))
        parts["weapon"] = True
    if sp.get("off"):
        sprites["far_weapon"] = weapon_sprite(sp["off"], pal, sp.get("wsize", 26))
        parts["far_weapon"] = True
    if "cape" in sp.get("extras", []):
        sprites["cape"] = cape_sprite(sp, pal, rnd)
        parts["cape"] = True
    if "wings" in sp.get("extras", []) or "feather" in sp.get("extras", []):
        sprites["wings"] = wings_sprite(sp, pal, "feather" if "feather" in sp["extras"] else "bat")
        parts["wings"] = True
    if "tail" in sp.get("extras", []):
        sprites["tail"] = tail_sprite(sp, pal, sp["w"] * 2.2, "spiked" if sp.get("spiked") else "tail")
        parts["tail"] = True
    bone = Bone(str(name), sprites)
    for base, clip in (("AnimStatique", "idle"), ("AnimMarche", "walk"), ("AnimCourse", "run"),
                       ("AnimAttaque0", "attack"), ("AnimHit", "hit"), ("AnimMort", "death")):
        poses, labels = upright_pose_set(sp, clip)
        if clip == "attack" and "flap" not in poses[0]:
            pass
        for view in (1, 5):
            bone.anims.append(Anim("%s_%d" % (base, view), [upright_nodes(sp, view, q, parts) for q in poses], dict(labels)))
    return bone


# ── beast (quadruped) ──────────────────────────────────────────────────────────

def beast_sprites(sp, pal: Pal, rnd):
    bl, bh, hs, ll = sp["body_len"], sp["body_h"], sp.get("hs", 9), sp["leg"]
    sprites = {"shadow": shadow_sprite(bl * 0.8 + 6)}
    p = Part("body", -bl - 8, -bh - 12, bl + 8, bh * 0.6 + 6)
    pts = [(-bl, -bh * 0.1), (-bl * 0.7, -bh * 0.9), (0, -bh * 1.05), (bl * 0.7, -bh * 0.95), (bl * 1.0, -bh * 0.3),
           (bl * 0.6, bh * 0.4), (0, bh * 0.45), (-bl * 0.7, bh * 0.35)]
    shape(p, spline(pts, steps=5), pal)
    if "spikes" in sp.get("extras", []):
        for i in range(5):
            x = -bl * 0.6 + i * bl * 0.3
            p.shape([(x - 2.2, -bh * 0.95), (x, -bh * 1.65 + (i % 2) * 2), (x + 2.2, -bh * 1.0)], pal.trim)
    if "mane" in sp.get("extras", []):
        p.shape(ragged(spikes(bl * 0.55, -bh * 0.75, bh * 0.5, bh * 0.95, 7), rnd, 0.6), pal.trim_sh)
    for i in range(3):
        p.line(spline([(-bl * 0.2 + i * 6, -bh * 0.95), (-bl * 0.18 + i * 6, -bh * 0.35)], closed=False), width=INNER * 0.7)
    if sp.get("motif", "core") == "core":
        glow(p, -bl * 0.1, -bh * 0.35, 2.2, pal)
    sprites["body"] = p.finish()
    h = Part("head", -hs * 2.2, -hs * 1.8, hs * 2.6, hs * 1.6)
    style = sp.get("head", "wolf")
    skull = [(-hs * 0.9, -hs * 0.6), (0, -hs * 1.1), (hs * 1.0, -hs * 0.65), (hs * 1.9, -hs * 0.1), (hs * 1.9, hs * 0.45), (hs * 0.9, hs * 0.75), (-hs * 0.6, hs * 0.8)]
    shape(h, spline(skull, steps=5), pal)
    if style in ("wolf", "boar"):
        for sx in (0.0, 0.7):
            h.shape([(hs * (0.1 + sx) - 2, -hs * 0.9), (hs * (0.25 + sx), -hs * 1.8), (hs * (0.55 + sx), -hs * 0.85)], pal.sh)
    if style == "ram":
        for sx in (-1, 1):
            shape(h, spline([(hs * 0.1, -hs * 0.9), (-hs * 0.6, -hs * 1.5), (-hs * 0.9, -hs * 0.2), (-hs * 0.2, -hs * 0.2)], steps=5), pal, fill=pal.trim)
    if style == "boar":
        h.shape([(hs * 1.5, hs * 0.3), (hs * 1.95, -hs * 0.35), (hs * 1.65, hs * 0.5)], (236, 230, 214))
    if style == "bug":
        for k in (0.2, 0.6):
            h.shape(ellipse_pts(hs * k, -hs * 0.3, hs * 0.32, hs * 0.4), pal.dark)
    glow(h, hs * 0.85, -hs * 0.3, hs * 0.2, pal)
    h.line(spline([(hs * 1.2, hs * 0.45), (hs * 1.7, hs * 0.5)], closed=False), width=0.8)
    for i in range(3):  # fangs
        h.shape([(hs * (1.0 + i * 0.25), hs * 0.5), (hs * (1.1 + i * 0.25), hs * 0.85), (hs * (1.2 + i * 0.25), hs * 0.5)], (240, 236, 224), width=0.4)
    sprites["head"] = h.finish()
    sprites["leg"] = limb_sprite("leg", ll, 3.4, "claw" if sp.get("claws", True) else "leg", pal, rnd, end="foot")
    sprites["tail"] = tail_sprite(sp, pal, sp.get("tail", 24), "spiked" if "spikes" in sp.get("extras", []) else "tail")
    return sprites


def beast_poses(sp, clip):
    if clip == "idle":
        n = 40
        return [dict(bob=-0.6 * math.sin(2 * math.pi * t / n), head=3 * math.sin(2 * math.pi * t / n + 1), tail=8 * math.sin(2 * math.pi * t / n),
                     g=0.0, lunge=0.0, fall=0.0, drop=0.0, alpha=1.0, amp=0.0) for t in range(n)], {}
    if clip in ("walk", "run"):
        n, amp = (20, 22) if clip == "walk" else (12, 36)
        return [dict(bob=-1.4 * abs(math.cos(2 * math.pi * t / n)), head=2 * math.sin(4 * math.pi * t / n), tail=10 * math.sin(2 * math.pi * t / n),
                     g=2 * math.pi * t / n, lunge=0.0, fall=0.0, drop=0.0, alpha=1.0, amp=amp) for t in range(n)], {}
    if clip == "attack":
        out = []
        for t in range(22):
            k = math.sin(math.pi * min(1, max(0, (t - 4) / 12)))
            out.append(dict(bob=-1.5 * k, head=-25 * k + (10 if t < 5 else 0), tail=12 * k, g=0.0, lunge=7 * k, fall=0.0, drop=0.0, alpha=1.0, amp=0.0))
        return out, {10: ["SHOT"]}
    if clip == "hit":
        return [dict(bob=0.0, head=-18 * e, tail=15 * e, g=0.0, lunge=-3.5 * e, fall=0.0, drop=0.0, alpha=1.0, amp=0.0)
                for e in (t / 3 if t < 3 else math.exp(-(t - 3) / 3.0) for t in range(13))], {}
    keys = [(0, dict(bob=0, head=0, tail=0, g=0.0, lunge=0, fall=0, drop=0, alpha=1.0, amp=0.0)),
            (8, dict(bob=0, head=-15, tail=10, g=0.0, lunge=-3, fall=-14, drop=3, alpha=1.0, amp=0.0)),
            (16, dict(bob=0, head=-38, tail=-10, g=0.0, lunge=-5, fall=-8, drop=sp["leg"] * 0.8, alpha=1.0, amp=0.0)),
            (26, dict(bob=0, head=-38, tail=-10, g=0.0, lunge=-5, fall=-8, drop=sp["leg"] * 0.8, alpha=1.0, amp=0.0)),
            (36, dict(bob=0, head=-38, tail=-10, g=0.0, lunge=-5, fall=-8, drop=sp["leg"] * 0.8, alpha=0.0, amp=0.0))]
    out = []
    for fr in range(37):
        for (f0, p0), (f1, p1) in zip(keys, keys[1:]):
            if f0 <= fr <= f1:
                t = _ease((fr - f0) / max(1, f1 - f0))
                out.append({k: p0[k] + (p1[k] - p0[k]) * t for k in p0})
                break
    return out, {}


def beast_nodes(sp, view, q):
    bl, bh, ll = sp["body_len"], sp["body_h"], sp["leg"]
    al = q["alpha"]
    c, dark = (1, 1, 1, al), (0.76, 0.74, 0.78, al)
    base = mul(T(q["lunge"], ll + bh * 0.2 + q["bob"] - q["drop"]), R(q["fall"]))
    legs = []
    for ox, ph, col in ((-bl * 0.55, 0.0, dark), (bl * 0.6, math.pi, dark), (-bl * 0.4, math.pi, c), (bl * 0.75, 0.0, c)):
        ang = q["amp"] * math.sin(q["g"] + ph)
        legs.append((col, mul(base, mul(T(ox, -bh * 0.1), R(ang)))))
    nodes = [Node("shadow", mul(T(q["lunge"] * 0.5, 0), S(1, 1)), c), Node("tail", mul(base, mul(T(-bl * 0.95, bh * 0.1), R(q["tail"] - 10))), c)]
    nodes += [Node("leg", m, col) for col, m in legs[:2]]
    nodes.append(Node("body", base, c))
    nodes += [Node("leg", m, col) for col, m in legs[2:]]
    nodes.append(Node("head", mul(base, mul(T(bl * 0.95, bh * 0.45), R(q["head"]))), c))
    return mirror(nodes, view)


def build_beast(name, sp) -> Bone:
    rnd = random.Random(sp.get("seed", name))
    bone = Bone(str(name), beast_sprites(sp, sp["pal"], rnd))
    for base, clip in (("AnimStatique", "idle"), ("AnimMarche", "walk"), ("AnimCourse", "run"),
                       ("AnimAttaque0", "attack"), ("AnimHit", "hit"), ("AnimMort", "death")):
        poses, labels = beast_poses(sp, clip)
        for view in (1, 5):
            bone.anims.append(Anim("%s_%d" % (base, view), [beast_nodes(sp, view, q) for q in poses], dict(labels)))
    return bone


# ── floater ────────────────────────────────────────────────────────────────────

def floater_sprites(sp, pal: Pal, rnd):
    r = sp.get("r", 13)
    kind = sp.get("core", "eye")
    sprites = {"shadow": shadow_sprite(r * 1.1)}
    p = Part("core", -r * 1.8, -r * 1.8, r * 1.8, r * 1.8)
    if kind == "flame":
        pts = [(0, -r * 1.5), (r * 0.5, -r * 0.7), (r * 1.0, 0), (r * 0.6, r * 0.9), (0, r * 1.1), (-r * 0.6, r * 0.9), (-r * 1.0, 0), (-r * 0.5, -r * 0.7)]
        shape(p, spline(pts, steps=5), pal, fill=pal.acc)
        shape(p, spline([(0, -r * 0.8), (r * 0.4, 0), (0, r * 0.7), (-r * 0.4, 0)], steps=5), pal, fill=pal.acc_hi, shd=False)
    elif kind == "tome":
        p.shape(rrect(-r * 0.9, -r * 0.7, r * 0.9, r * 0.7, 2), pal.dark)
        shape(p, rrect(-r * 0.8, -r * 0.6, r * 0.8, r * 0.6, 1.5), pal, fill=pal.main)
        p.line([(0, -r * 0.6), (0, r * 0.6)], width=1.0)
        glow(p, 0, 0, r * 0.28, pal)
        for k in (-1, 1):
            p.line([(k * r * 0.2, -r * 0.4), (k * r * 0.6, -r * 0.4)], width=0.6, color=pal.trim + (255,))
    elif kind == "crystal":
        shape(p, [(0, -r * 1.5), (r * 0.7, -r * 0.4), (r * 0.5, r * 0.9), (0, r * 1.2), (-r * 0.5, r * 0.9), (-r * 0.7, -r * 0.4)], pal, fill=pal.trim)
        p.line([(0, -r * 1.5), (0, r * 1.2)], width=0.6)
        glow(p, 0, 0, r * 0.3, pal)
    elif kind == "ghost":
        pts = [(-r * 0.9, r * 0.5), (-r * 1.0, -r * 0.6), (0, -r * 1.3), (r * 1.0, -r * 0.6), (r * 0.9, r * 0.5)]
        for i in range(5):
            pts.append((r * 0.9 - r * 1.8 * i / 4, r * 1.3 + (r * 0.35 if i % 2 else 0)))
        shape(p, spline(pts, steps=3), pal, fill=mix(pal.main, (255, 255, 255), 0.25))
        for dx in (-0.35, 0.35):
            p.shape(ellipse_pts(dx * r + 1, -r * 0.35, r * 0.2, r * 0.3), pal.dark)
            glow(p, dx * r + 1, -r * 0.35, r * 0.1, pal)
        p.shape(ellipse_pts(1, r * 0.2, r * 0.15, r * 0.22), pal.dark)
    elif kind == "jelly":
        pts = [(-r, r * 0.3), (-r * 1.05, -r * 0.5), (0, -r * 1.2), (r * 1.05, -r * 0.5), (r, r * 0.3)]
        for i in range(6):
            pts.append((r - r * 2 * i / 5, r * 0.5 + (r * 0.3 if i % 2 else 0)))
        shape(p, spline(pts, steps=3), pal, fill=mix(pal.main, pal.acc, 0.25))
        glow(p, 0, -r * 0.2, r * 0.3, pal)
    else:  # eye
        shape(p, ellipse_pts(0, 0, r, r), pal, fill=(236, 230, 218))
        for a in range(7):
            ang = a * 0.9
            p.line([(math.cos(ang) * r * 0.5, math.sin(ang) * r * 0.5), (math.cos(ang) * r * 0.95, math.sin(ang) * r * 0.95)], width=0.5, color=(190, 70, 70, 255))
        p.shape(ellipse_pts(r * 0.3, 0, r * 0.52, r * 0.52), pal.acc)
        p.shape(ellipse_pts(r * 0.38, 0, r * 0.2, r * 0.38), pal.dark)
        p.dot(r * 0.25, -r * 0.2, r * 0.1, (255, 255, 255, 255), top=True)
        for sx in (-1, 1):  # tentacle-ish fins
            p.shape(spline([(sx * r * 0.8, r * 0.3), (sx * r * 1.6, r * 0.2), (sx * r * 1.3, r * 0.9)], steps=4), pal.trim)
    sprites["core"] = p.finish()
    sat = Part("sat", -5, -7, 5, 7)
    sat.shape(spikes(0, 0, 1.7, 5.5, 3, rot=1.57), pal.trim)
    glow(sat, 0, 0, 1.3, pal)
    sprites["sat"] = sat.finish()
    wisp = Part("wisp", -4, -10, 4, 10)
    shape(wisp, spline([(0, -9), (3.5, -2), (0, 9), (-3.5, -2)], steps=4), pal, fill=mix(pal.main, pal.acc, 0.4), shd=False)
    sprites["wisp"] = wisp.finish()
    return sprites


def floater_frames(sp, view, clip):
    r = sp.get("r", 13)
    hover = sp.get("hover", 22)
    nsat = sp.get("sats", 3)
    nw = sp.get("wisps", 2)
    count = {"idle": 40, "walk": 24, "run": 14, "attack": 22, "hit": 12, "death": 30}[clip]
    frames, labels = [], {}
    for t in range(count):
        u = t / count
        ph = 2 * math.pi * u
        spin = ph * (1 if clip != "run" else 2)
        bob = 3 * math.sin(ph)
        px = lunge = 0.0
        sc, al, tilt = 1.0, 1.0, 0.0
        flash = 0.0
        if clip == "attack":
            k = math.sin(math.pi * min(1, max(0, (t - 4) / 12)))
            lunge, sc, flash = 14 * k, 1 + 0.3 * k, k
            spin = ph * 3
            labels = {10: ["SHOT"]}
        elif clip == "hit":
            e = t / 3 if t < 3 else math.exp(-(t - 3) / 3.0)
            px, tilt = -5 * e, -20 * e
        elif clip == "death":
            sc, al = max(0.05, 1 - u * 1.1), max(0.0, 1 - u * 1.2)
            spin = ph * 5
        base = mul(T(px + lunge, hover + bob), mul(R(tilt), S(sc)))
        c = (1, 1, 1, al)
        nodes = [Node("shadow", mul(T(px + lunge, 0), S(max(0.3, 1 - bob * 0.04) * sc)), (1, 1, 1, al * 0.9))]
        for i in range(nw):
            wm = mul(base, mul(T(-r * 0.9 - i * 6, -r * 0.7 - i * 4 + 2 * math.sin(spin + i)), R(70 + 20 * math.sin(ph + i))))
            nodes.append(Node("wisp", wm, (1, 1, 1, al * 0.8), BLEND_ADD if sp.get("core") in ("flame", "ghost") else 0))
        nodes.append(Node("core", base, (1 + flash * 0.3, 1 + flash * 0.3, 1 + flash * 0.3, al)))
        for i in range(nsat):
            a = spin + 2 * math.pi * i / nsat
            rad = r * 1.6
            nodes.append(Node("sat", mul(base, mul(T(rad * math.cos(a), rad * 0.45 * math.sin(a) + 2), R(math.degrees(a) * 0.5))), c))
        frames.append(mirror(nodes, view))
    return frames, labels


def build_floater(name, sp) -> Bone:
    rnd = random.Random(sp.get("seed", name))
    bone = Bone(str(name), floater_sprites(sp, sp["pal"], rnd))
    for base, clip in (("AnimStatique", "idle"), ("AnimMarche", "walk"), ("AnimCourse", "run"),
                       ("AnimAttaque0", "attack"), ("AnimHit", "hit"), ("AnimMort", "death")):
        for view in (1, 5):
            frames, labels = floater_frames(sp, view, clip)
            bone.anims.append(Anim("%s_%d" % (base, view), frames, dict(labels)))
    return bone


# ── serpent ────────────────────────────────────────────────────────────────────

def serpent_sprites(sp, pal: Pal, rnd):
    w = sp.get("w", 6.5)
    sprites = {"shadow": shadow_sprite(sp.get("segs", 7) * w * 0.9)}
    head = Part("head", -w * 2.5, -w * 2.2, w * 3, w * 2)
    shape(head, spline([(-w * 1.1, -w * 0.9), (w * 0.5, -w * 1.3), (w * 2.3, -w * 0.3), (w * 2.4, w * 0.5), (w * 0.4, w * 1.1), (-w * 1.1, w * 0.9)], steps=5), pal)
    glow(head, w * 1.0, -w * 0.4, w * 0.27, pal)
    head.line(spline([(w * 1.5, w * 0.45), (w * 2.3, w * 0.35)], closed=False), width=0.8)
    if "horn" in sp.get("extras", []):
        head.shape([(w * 0.1, -w * 1.2), (-w * 0.5, -w * 2.1), (w * 0.8, -w * 1.25)], pal.trim)
    sprites["head"] = head.finish()
    seg = Part("seg", -w * 1.8, -w * 1.8, w * 1.8, w * 1.8)
    shape(seg, ellipse_pts(0, 0, w * 1.15, w * 1.15), pal)
    seg.line(spline([(-w * 0.5, -w * 0.9), (-w * 0.2, 0), (-w * 0.5, w * 0.9)], closed=False), width=0.6)
    if sp.get("motif", "core") == "core":
        glow(seg, 0, 0, w * 0.2, pal)
    sprites["seg"] = seg.finish()
    tl = Part("tip", -w * 2, -w, w, w)
    shape(tl, [(w * 0.5, -w * 0.8), (-w * 2.0, 0), (w * 0.5, w * 0.8)], pal)
    sprites["tip"] = tl.finish()
    return sprites


def serpent_frames(sp, view, clip):
    segs, w = sp.get("segs", 7), sp.get("w", 6.5)
    count = {"idle": 40, "walk": 24, "run": 14, "attack": 22, "hit": 12, "death": 30}[clip]
    frames, labels = [], {}
    for t in range(count):
        u = t / count
        ph = 2 * math.pi * u * (2 if clip == "run" else 1)
        amp, lift, al, rear = 5.0, 0.0, 1.0, 0.0
        px = 0.0
        if clip == "attack":
            k = math.sin(math.pi * min(1, max(0, (t - 4) / 12)))
            rear, px = 14 * k, 12 * k
            labels = {10: ["SHOT"]}
        elif clip == "hit":
            e = t / 3 if t < 3 else math.exp(-(t - 3) / 3.0)
            px, amp = -5 * e, 5 + 5 * e
        elif clip == "death":
            amp, al = 5 + 6 * u, max(0.0, 1.5 - u * 1.5)
            lift = -3 * u
        nodes = [Node("shadow", mul(T(px * 0.5 - segs * w * 0.6, 0), S(1.0, 1)), (1, 1, 1, al * 0.9))]
        pts = []
        for i in range(segs + 1):  # head is index 0 on the right, the tail trails to the left
            x = px - i * w * 1.55
            y = w * 1.2 + amp * math.sin(ph - i * 0.9) * min(1.0, i * 0.35) + rear * max(0, 1 - i * 0.35) + lift * i
            pts.append((x, y))
        for i in range(segs, 0, -1):
            x, y = pts[i]
            sc = 1.0 - (i / (segs + 1)) * 0.55
            if i == segs:
                nodes.append(Node("tip", mul(T(x, y), S(sc + 0.2)), (1, 1, 1, al)))
            else:
                nodes.append(Node("seg", mul(T(x, y), S(sc)), (1, 1, 1, al)))
        hx, hy = pts[0]
        nxt = pts[1]
        ang = math.degrees(math.atan2(hy - nxt[1], hx - nxt[0]))
        nodes.append(Node("head", mul(T(hx, hy), R(ang * 0.8 + (rear * 0.9))), (1, 1, 1, al)))
        frames.append(mirror(nodes, view))
    return frames, labels


def build_serpent(name, sp) -> Bone:
    rnd = random.Random(sp.get("seed", name))
    bone = Bone(str(name), serpent_sprites(sp, sp["pal"], rnd))
    for base, clip in (("AnimStatique", "idle"), ("AnimMarche", "walk"), ("AnimCourse", "run"),
                       ("AnimAttaque0", "attack"), ("AnimHit", "hit"), ("AnimMort", "death")):
        for view in (1, 5):
            frames, labels = serpent_frames(sp, view, clip)
            bone.anims.append(Anim("%s_%d" % (base, view), frames, dict(labels)))
    return bone


BUILDERS = {"upright": build_upright, "beast": build_beast, "floater": build_floater, "serpent": build_serpent}


_MEMO: dict = {}


def build(name, sp) -> Bone:
    """Memoised: the portrait of a creature and its bone file come from the same build."""
    key = (str(name), repr(sorted(sp.items(), key=lambda kv: kv[0])))
    if key not in _MEMO:
        _MEMO[key] = BUILDERS[sp["arch"]](name, sp)
    return _MEMO[key]
