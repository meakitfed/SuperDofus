"""Shared plumbing of the generators: paths, id ranges, the text registry and the output registry.

Everything the world needs is generated from the spec modules (lore, classes, mobs, items, world) into
game/worlds/vertebre. Ids live in ranges far above the Dofus ones (the overlay only ever adds):
  texts 9 000 000+ · items 9 100 000+ · sets 9 100+ · spell grades 9 200 000+ · class spells (parent) 900 001+
  monsters 910 001+ · npcs 920 001+ · quests 930 001+ · breeds 901..905 · bones 950 001+ · states 960 001+
"""
from __future__ import annotations

import json
import os
import sys

HERE = os.path.dirname(os.path.abspath(__file__))
ROOT = os.path.abspath(os.path.join(HERE, "..", "..", ".."))
BUILD = os.path.join(ROOT, "worlds_src", "vertebre", "build")
SPEC = os.path.join(ROOT, "worlds_src", "vertebre", "spec")
for p in (BUILD, SPEC, HERE):
    if p not in sys.path:
        sys.path.insert(0, p)

WORLD_ID = "vertebre"
OUT = os.path.join(ROOT, "game", "worlds", WORLD_ID)
CONTENT = os.path.join(OUT, "Content")  # layer worlds/<id>: rel paths start with Content/ (Characters, Maps, Picto, I18n...)
DATA = os.path.join(OUT, "data")


class Counter:
    def __init__(self, start):
        self.n = start - 1

    def __call__(self):
        self.n += 1
        return self.n


class Texts:
    """Text registry: every name/description gets an i18n id; written as Content/I18n/extra_fr.json."""

    def __init__(self, start=9_000_000):
        self.next = Counter(start)
        self.by_text: dict[str, int] = {}
        self.by_id: dict[int, str] = {}

    def __call__(self, text: str) -> int:
        if text not in self.by_text:
            i = self.next()
            self.by_text[text] = i
            self.by_id[i] = text
        return self.by_text[text]


T = Texts()
item_id = Counter(9_100_001)
set_id = Counter(9_101)
grade_id = Counter(9_200_001)
spell_id = Counter(900_001)
monster_id = Counter(910_001)
npc_id = Counter(920_001)
quest_id = Counter(930_001)
bone_id = Counter(950_001)
state_id = Counter(960_001)
step_id = Counter(931_001)
objective_id = Counter(932_001)
element_id = Counter(933_001)


class Registry:
    """What the generators produce, written out by build_all."""

    def __init__(self):
        self.items: list[dict] = []
        self.sets: list[dict] = []
        self.spells: list[dict] = []  # castable grades
        self.grades: dict[str, list[int]] = {}  # spells.id -> [grade ids]
        self.classes: dict[str, dict] = {}
        self.summons: dict[str, dict] = {}
        self.tables: dict[str, dict] = {}  # name -> {id: row}
        self.monsters: dict[str, dict] = {}
        self.bosses: dict[str, dict] = {}
        self.subareas: dict[str, dict] = {}
        self.npc_rows: dict[str, dict] = {}
        self.quests: dict[str, dict] = {}
        self.dialogs: dict[str, dict] = {}
        self.shops: dict[str, dict] = {}
        self.bones: dict[str, tuple] = {}  # bone id -> (arch spec) built by the rigs
        self.icons: list[tuple] = []  # (rel path without ext, callable returning a PIL image)
        self.interactives: dict[str, list] = {}
        self.maps: list = []
        self.npc_placed: dict[str, list] = {}

    def table(self, name):
        return self.tables.setdefault(name, {})


R = Registry()


def dump(path, obj, indent=None):
    os.makedirs(os.path.dirname(path), exist_ok=True)
    with open(path, "w", encoding="utf-8") as f:
        json.dump(obj, f, ensure_ascii=False, indent=indent, separators=None if indent else (",", ":"))
