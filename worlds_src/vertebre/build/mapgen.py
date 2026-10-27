"""Turns a floor layout spec into the three things a map needs:
  - the game map   (worlds/<id>/maps/<n>.json: blocked cells, triggers, groups...)
  - the visual     (Content/Maps/<n>.json: one floor image + sortable props)
  - the PNGs       (Content/Maps/Gfx/<g>.png)

Cells are (col, row): id = row * 14 + col, 14 columns x 40 rows. Only the four diagonal moves are used
for connectivity checks (the strictest): if every anchor is reachable that way, it is reachable.
"""
from __future__ import annotations

import json
import os
import random
import zlib
from collections import deque

from PIL import Image

import tilegen
from tilegen import cell_xy, prop_sprite, prop_t, render_ground, render_void

COLS, ROWS = 14, 40
N = COLS * ROWS


def cid(col, row):
    return row * COLS + col


def pos(c):
    return c % COLS, c // COLS


def neighbors(c):
    col, row = pos(c)
    odd = row % 2
    out = []
    for dr in (-1, 1):
        for dc in ((0, 1) if odd else (-1, 0)):
            cc, rr = col + dc, row + dr
            if 0 <= cc < COLS and 0 <= rr < ROWS:
                out.append(cid(cc, rr))
    return out


def reachable(blocked: set[int], start: int) -> set[int]:
    seen = {start}
    q = deque([start])
    while q:
        c = q.popleft()
        for n in neighbors(c):
            if n not in blocked and n not in seen:
                seen.add(n)
                q.append(n)
    return seen


def ring(c: int, r: int) -> set[int]:
    """Cells within `r` diagonal steps of c."""
    seen, frontier = {c}, {c}
    for _ in range(r):
        frontier = {n for f in frontier for n in neighbors(f)} - seen
        seen |= frontier
    return seen


def variant_of(kind: str, cell: int) -> int:
    """Props that look the same everywhere have one picture; rocks and boulders have two."""
    return cell % 2 if kind in ("rock", "boulder", "bones") else 0


class FloorMap:
    """A map being built: anchors (cells that must stay reachable), obstacles and props."""

    def __init__(self, map_id: int, name: str, theme: str, seed: int, coords=(0, 0)):
        self.id, self.name, self.theme = map_id, name, theme
        self.rnd = random.Random(seed)
        self.seed = seed
        self.coords = list(coords)
        self.blocked: set[int] = set()
        self.void: set[int] = set()
        self.anchors: dict[str, int] = {}
        self.props: list[tuple[str, int]] = []  # (kind, cell) sortable decor, drawn on the cell
        self.npcs: list[dict] = []
        self.triggers: list[dict] = []
        self.groups: list[dict] = []
        self.interactives: list[dict] = []
        self.extra: dict = {}
        self.collect: list[tuple] = []  # (key, prop kind, cell) searchable objects
        self.keep: set[int] = set()  # cells obstacles must stay away from (around NPCs)

    # anchors ---------------------------------------------------------------
    def anchor(self, key: str, col: int, row: int) -> int:
        c = cid(col, row)
        self.anchors[key] = c
        return c

    def _keep_free(self) -> set[int]:
        keep = set(self.keep)
        for c in self.anchors.values():
            keep |= ring(c, 1)
        return keep

    def _connected(self) -> bool:
        cells = list(self.anchors.values())
        if not cells:
            return True
        reach = reachable(self.blocked | self.void, cells[0])
        return all(c in reach for c in cells)

    # obstacles -------------------------------------------------------------
    def clutter(self, kinds: list[str], clusters: int, size=(1, 3), rows=(3, ROWS - 4), margin=1, solid=True):
        """Random obstacle clusters; a cluster that cuts an anchor off is dropped."""
        keep = self._keep_free()
        placed = 0
        tries = 0
        while placed < clusters and tries < clusters * 40:
            tries += 1
            c = cid(self.rnd.randrange(margin, COLS - margin), self.rnd.randrange(*rows))
            cells = {c}
            for _ in range(self.rnd.randint(*size) - 1):
                cells.add(self.rnd.choice(neighbors(self.rnd.choice(list(cells)))))
            if cells & keep or cells & self.blocked or cells & set(c for _, c in self.props):
                continue
            self.blocked |= cells
            if not self._connected():
                self.blocked -= cells
                continue
            kind = self.rnd.choice(kinds)
            for cell in sorted(cells):
                self.props.append((kind, cell))
            placed += 1
        return placed

    def pit(self, cells):
        """Void cells (no floor): cannot be crossed, nothing is drawn on them."""
        cells = set(cells)
        self.void |= cells
        self.blocked |= cells
        if not self._connected():
            self.void -= cells
            self.blocked -= cells
            raise ValueError("pit cuts the map")

    def secret_nook(self, key: str, col: int, row: int, radius=2):
        """An enclosed pocket around (col, row) reachable by one narrow gap on the side facing the map's middle.
        Returns (centre cell, gap cell). The inside stays free (keep) and its reachability is an anchor."""
        c = cid(col, row)
        inner = ring(c, radius - 1)
        wall = ring(c, radius) - inner
        gap = min(wall, key=lambda w: abs(pos(w)[0] - COLS / 2) + abs(pos(w)[1] - ROWS / 2))
        inside = next(n for n in neighbors(c) if gap in neighbors(n))  # the inner cell touching the gap
        self.anchors["pocket_" + key] = inside
        self.keep |= inner | {gap}
        for w in wall - {gap}:
            if w not in self.blocked:
                self.blocked.add(w)
                self.props.append((self.rnd.choice(["rock", "boulder"]), w))
        self.extra["nook_gap_" + key] = gap
        return c, gap

    def place(self, kind: str, col: int, row: int, force=False):
        """A blocking prop on (col, row); refused (None) on an anchor or next to one, unless `force`."""
        c = cid(col, row)
        if not force and (c in self._keep_free() or c in self.blocked):
            return None
        self.props.append((kind, c))
        self.blocked.add(c)
        if not self._connected():
            self.props.pop()
            self.blocked.discard(c)
            return None
        return c

    # export ----------------------------------------------------------------
    def check(self):
        reach = reachable(self.blocked | self.void, next(iter(self.anchors.values())))
        lost = [k for k, c in self.anchors.items() if c not in reach]
        if lost:
            raise ValueError("map %s: unreachable anchors %s" % (self.id, lost))

    def game_json(self, gfx_ids: dict) -> dict:
        d = {"id": self.id, "name": self.name, "coords": self.coords, "visual": self.id, "outdoor": False,
             "blocked": sorted(self.blocked), "fight_blocked": sorted(self.blocked), "los_blocked": sorted(c for c in self.blocked if c in self.void or any(k in ("pillar", "boulder", "tent", "bookshelf", "statue", "crystal") and cc == c for k, cc in self.props)),
             "placement": {"red": [], "blue": []}, "neighbors": {}, "triggers": self.triggers}
        d["los_blocked"] = [c for c in d["los_blocked"] if c not in self.void]  # a pit does not hide what is behind it
        if self.groups:
            d["groups"] = self.groups
        d.update(self.extra_json())
        return d

    def extra_json(self) -> dict:
        return {k: v for k, v in self.extra.items() if not k.startswith("nook_gap_")}

    def visual_json(self, gfx_of: dict, gfx_art: dict) -> dict:
        """gfx_of: (kind, variant) -> gfx id; gfx_art: gfx id -> (img, foot)."""
        theme_bg = tilegen.THEMES[self.theme]["bg"]
        sortable = []
        occupied: dict[int, int] = {}
        for kind, cell in self.props:
            if cell in self.void:
                continue
            variant = variant_of(kind, cell)
            g = gfx_of[(self.theme, kind, variant)]
            img, foot = gfx_art[g]
            o = occupied.get(cell, 0)
            occupied[cell] = o + 1
            sortable.append({"g": g, "c": 0xFF808080 | 0, "t": prop_t(cell, img, foot), "cell": cell, "o": o})
        argb = 0xFF000000 | (theme_bg[0] << 16) | (theme_bg[1] << 8) | theme_bg[2]
        if ("dofus_bg", self.id) in gfx_of:
            background, argb = gfx_of[("dofus_bg", self.id)]
            vg = gfx_of.get(("void", self.id))
            if vg:
                img, _ = gfx_art[vg]
                background.append({"g": vg, "c": 0xFF808080, "t": [1.0, 0.0, 0.0, 1.0, round(img.width / 2 - tilegen.PAD_X, 1), round(img.height / 2 - tilegen.PAD_Y, 1)]})
        else:
            bg_gfx = gfx_of[("ground", self.id)]
            img, _ = gfx_art[bg_gfx]
            background = [{"g": bg_gfx, "c": 0xFF808080, "t": [1.0, 0.0, 0.0, 1.0, round(img.width / 2 - tilegen.PAD_X, 1), round(img.height / 2 - tilegen.PAD_Y, 1)]}]
        cells = [[0, 1, 0, 0, 0, 0, 1, 0, 0, 0, 0] for _ in range(N)]
        return {"id": self.id, "bg": argb, "neighbors": {}, "cell_flags": ["mov", "los", "nonWalkableDuringFight", "nonWalkableDuringRP", "red", "blue", "visible", "floor", "mapChangeData", "farmCell", "havenbagCell"],
                "cells": cells, "layers": {"background": background, "sortable": sortable, "foreground": []}, "animated": []}


class _External:
    """Stand-in for a Dofus gfx (nothing is drawn nor written: the file is copied from game/content by gen/dofus_skin.py)."""

    def __init__(self, size):
        self.width, self.height = size


class GfxBank:
    """Allocates gfx ids (and writes the PNGs once): props per (theme, kind, variant), one ground per map."""

    def __init__(self, first_id=9_000_001):
        self.next = first_id
        self.art: dict[int, tuple] = {}
        self.of: dict[tuple, int] = {}

    def prop(self, theme, kind, variant):
        key = (theme, kind, variant)
        if key not in self.of:
            import dofus_skin
            ext = dofus_skin.prop(theme, kind, variant)
            if ext:  # a real Dofus object: its foot is the bottom centre of the sprite
                self.of[key] = ext[0]
                self.art[ext[0]] = (_External(ext[1]), (ext[1][0] / 2, ext[1][1] - 6))
                return ext[0]
            img, foot = prop_sprite(kind, theme, seed=variant * 31 + zlib.crc32(kind.encode()) % 97)
            self.of[key] = self.next
            self.art[self.next] = (img, foot)
            self.next += 1
        return self.of[key]

    def ground(self, fm: FloorMap):
        import dofus_skin
        ext = dofus_skin.ground(fm.theme, fm.id)
        if ext:  # a real Dofus floor; only the pits (void cells) are still drawn here, over it
            self.of[("dofus_bg", fm.id)] = ext
            if fm.void:
                img = render_void(fm.void, fm.theme)
                self.of[("void", fm.id)] = self.next
                self.art[self.next] = (img, (0, 0))
                self.next += 1
            return
        img = render_ground(fm.void, fm.theme, fm.seed)
        self.of[("ground", fm.id)] = self.next
        self.art[self.next] = (img, (0, 0))
        self.next += 1

    def prepare(self, fm: FloorMap):
        self.ground(fm)
        for kind, cell in fm.props:
            self.prop(fm.theme, kind, variant_of(kind, cell))

    def write(self, folder: str):
        os.makedirs(folder, exist_ok=True)
        for g, (img, _) in self.art.items():
            if isinstance(img, _External):
                continue
            img.save(os.path.join(folder, "%d.png" % g), compress_level=4)


def write_map(fm: FloorMap, bank: GfxBank, world_dir: str, content_dir: str):
    fm.check()
    bank.prepare(fm)
    os.makedirs(os.path.join(world_dir, "maps"), exist_ok=True)
    os.makedirs(os.path.join(content_dir, "Maps"), exist_ok=True)
    with open(os.path.join(world_dir, "maps", "%d.json" % fm.id), "w", encoding="utf-8") as f:
        json.dump(fm.game_json(bank.of), f, ensure_ascii=False, separators=(",", ":"))
    with open(os.path.join(content_dir, "Maps", "%d.json" % fm.id), "w", encoding="utf-8") as f:
        json.dump(fm.visual_json(bank.of, bank.art), f, separators=(",", ":"))
