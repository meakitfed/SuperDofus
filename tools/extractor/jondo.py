"""Server data absent from the Dofus 3 client, read from the JondoEmu emulator dumps
(https://github.com/julianout/JondoEmu, no license: read locally, never republished).
The folder is JONDO_DATOS (default ~/Documents/Dofus3+/datos).

Doors (roadmap P1.07b): an interactive element (the door, stairs, ladder) sits on a
cell of the client map (mapData ... m_interactionId + cellId: client data); where it
leads is server data. Three JondoEmu catalogues give it, most trusted first:
  interactive_teleports_giny_2.68.json       Giny emulator 2.68 skills matched to the
      current elements ("exact-element-match"; "ambiguous" = several rows for one element)
  interactive_teleports_worldgraph_2.73.json  Dofus 2.73 world graph ("reverse-element-approx":
      the arrival cell is the door back, not the exact arrival)
  interactive_teleports_worldgraph_client.json  the Dofus 3 client's world graph
      ("world-graph-map-centre-fallback": arrival at the map centre, left out)
"""
from __future__ import annotations

import json
import os
from pathlib import Path

JONDO_DATOS = Path(os.environ.get("JONDO_DATOS", Path.home() / "Documents" / "Dofus3+" / "datos"))
_FILES = ("interactive_teleports_giny_2.68.json", "interactive_teleports_worldgraph_2.73.json",
          "interactive_teleports_worldgraph_client.json")


def _xy(cell: int) -> tuple[float, float]:
    return (cell % 14) * 2 + (cell // 14) % 2, cell // 14


def _dist(a: int, b: int) -> float:
    (ax, ay), (bx, by) = _xy(a), _xy(b)
    return ((ax - bx) ** 2 + (ay - by) ** 2) ** 0.5


def door_routes() -> dict[tuple[int, int], dict]:
    """(map, element cell) -> {to_map, to_cell, element, criterion, src}, {} without the dumps.
    Per door: the exact Giny row, else the 2.73 world graph, else the ambiguous Giny row
    whose destination has a door back (closest to it), else the client world graph."""
    if not all((JONDO_DATOS / f).exists() for f in _FILES):
        return {}
    giny, wg, client = (json.loads((JONDO_DATOS / f).read_text(encoding="utf-8"))["routes"] for f in _FILES)
    key = lambda r: (int(r["sourceMapId"]), int(r["sourceCellId"]))
    out: dict[tuple[int, int], dict] = {}

    def put(r: dict, src: str) -> None:
        out.setdefault(key(r), {"to_map": int(r["destinationMapId"]), "to_cell": int(r["destinationCellId"]),
                                "element": int(r["elementId"]), "criterion": str(r.get("criterion", "")), "src": src})

    for r in giny:
        if r.get("enabled") and r.get("confidence") == "exact-element-match":
            put(r, "giny-2.68")
    for r in wg:
        if r.get("enabled"):
            put(r, "worldgraph-2.73")
    ambiguous: dict[tuple[int, int], list] = {}
    for r in giny:
        if r.get("confidence") == "ambiguous":
            ambiguous.setdefault(key(r), []).append(r)
    for k, rows in ambiguous.items():
        if k in out:
            continue
        back = []
        for r in rows:
            to = int(r["destinationMapId"])
            doors = [c for (m, c), v in out.items() if m == to and v["to_map"] == k[0]]
            if doors:
                back.append((min(_dist(int(r["destinationCellId"]), c) for c in doors), r))
        if back:
            put(min(back, key=lambda t: t[0])[1], "giny-2.68-resolved")
    for r in client:
        if r.get("enabled") and "centre-fallback" not in str(r.get("confidence", "")):
            put(r, "worldgraph-client")
    return out
