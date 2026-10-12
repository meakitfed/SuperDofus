"""Lit et met à jour docs/ROADMAP.md (le plan vivant du projet).

    python tools/roadmap.py status          avancement par phase
    python tools/roadmap.py next            lots en cours, puis le prochain lot faisable
    python tools/roadmap.py show P1.05      détail d'un lot (aussi un lot archivé)
    python tools/roadmap.py set P1.05 doing statut : todo, doing, done, dropped (ou " ", "~", "x", "-")
    python tools/roadmap.py check           format, IDs uniques, dépendances valides (avec l'archive)
    python tools/roadmap.py archive         déplace les lots faits et l'ancien Journal dans ROADMAP_ARCHIVE.md

Un lot est un titre `### [s] ID Titre` suivi de lignes `- Champ : valeur`.
Les lots faits vivent dans docs/ROADMAP_ARCHIVE.md (lecture seule pour `set`) : ROADMAP.md
ne garde que le travail restant, pour rester court à relire.
"""
import re
import sys
from pathlib import Path

DOCS = Path(__file__).resolve().parent.parent / "docs"
ROADMAP = DOCS / "ROADMAP.md"
ARCHIVE = DOCS / "ROADMAP_ARCHIVE.md"
HEADING = re.compile(r"^### \[(.)\] ([A-Z]\d*\.\d+[a-z]?) (.+)$")
REQUIRED = ["Dépend", "Règles", "Tests", "Parité"]
ALIASES = {"todo": " ", "_": " ", "": " ", "doing": "~", "done": "x", "dropped": "-"}
STATUSES = {" ": "à faire", "~": "en cours", "x": "fait", "-": "abandonné"}
JOURNAL = "## Journal"
KEEP_JOURNAL = 15  # lignes du Journal gardées dans ROADMAP.md (`/suite` lit les dernières)
ARCHIVE_HEAD = ("# Roadmap : archive\n\nLots faits et ancien Journal, déplacés de `ROADMAP.md` par "
                "`python tools/roadmap.py archive`. `roadmap.py` les lit (dépendances, `show`, `check`).\n")


def parse_lines(lines, archived):
    lots, cur, fence = [], None, False
    for i, line in enumerate(lines):
        if line.startswith("```"):
            fence = not fence
            continue
        if fence:
            continue
        m = HEADING.match(line)
        if m:
            cur = {"status": m[1], "id": m[2], "title": m[3], "line": i, "end": i + 1, "fields": {},
                   "body": [line], "archived": archived}
            lots.append(cur)
            continue
        if cur is None:
            continue
        if line.startswith("## ") or line.startswith("### ") or line.strip() == "---":
            cur = None
            continue
        cur["body"].append(line)
        cur["end"] = i + 1
        f = re.match(r"^- ([^:]+?) :\s*(.*)$", line)
        if f:
            cur["fields"][f[1].strip()] = f[2].strip()
    for lot in lots:
        dep = lot["fields"].get("Dépend", "—")
        lot["deps"] = [] if dep in ("—", "-", "") else [d.strip() for d in dep.split(",") if d.strip()]
    return lots


def read(path):
    return path.read_text(encoding="utf-8").splitlines() if path.exists() else []


def parse():
    """(lignes de ROADMAP.md, lots de l'archive puis de ROADMAP.md)."""
    lines = read(ROADMAP)
    return lines, parse_lines(read(ARCHIVE), True) + parse_lines(lines, False)


def phase(lot_id):
    return lot_id.split(".")[0]


def cmd_status(lots):
    phases = {}
    for lot in lots:
        phases.setdefault(phase(lot["id"]), []).append(lot["status"])
    total_done = sum(1 for l in lots if l["status"] == "x")
    for p, sts in phases.items():
        done = sts.count("x")
        bar = "#" * done + "~" * sts.count("~") + "." * sts.count(" ")
        print(f"{p:3} {done:2}/{len(sts):<2} [{bar}]")
    print(f"Total : {total_done}/{len(lots)} lots faits")


def ready(lot, by_id):
    return lot["status"] == " " and all(by_id.get(d, {}).get("status") == "x" for d in lot["deps"])


def cmd_next(lots):
    by_id = {l["id"]: l for l in lots}
    doing = [l for l in lots if l["status"] == "~"]
    for l in doing:
        print(f"EN COURS  {l['id']} {l['title']}")
    candidates = [l for l in lots if ready(l, by_id)]
    if not candidates:
        print("Aucun lot faisable : vérifier les dépendances.")
        return
    first = candidates[0]
    print(f"PROCHAIN  {first['id']} {first['title']}")
    others = ", ".join(l["id"] for l in candidates[1:6])
    if others:
        print(f"Aussi faisables : {others}")


def cmd_show(lots, lot_id):
    for l in lots:
        if l["id"] == lot_id:
            print("\n".join(l["body"]).rstrip() + ("\n(archivé : docs/ROADMAP_ARCHIVE.md)" if l["archived"] else ""))
            return
    sys.exit(f"Lot inconnu : {lot_id}")


def cmd_set(lines, lots, lot_id, status):
    status = ALIASES.get(status, status)
    if status not in STATUSES:
        sys.exit(f"Statut invalide : {status!r} (attendu : {', '.join(repr(s) for s in STATUSES)})")
    for l in lots:
        if l["id"] == lot_id:
            if l["archived"]:
                sys.exit(f"{lot_id} est archivé (docs/ROADMAP_ARCHIVE.md) : le remettre dans ROADMAP.md pour le rouvrir")
            lines[l["line"]] = f"### [{status}] {l['id']} {l['title']}"
            ROADMAP.write_text("\n".join(lines) + "\n", encoding="utf-8")
            print(f"{lot_id} → {STATUSES[status]}")
            return
    sys.exit(f"Lot inconnu : {lot_id}")


def cmd_check(lots):
    errors = []
    seen = {}
    for l in lots:
        if l["id"] in seen:
            errors.append(f"ID en double : {l['id']}")
        seen[l["id"]] = l
        for f in REQUIRED:
            if f not in l["fields"]:
                errors.append(f"{l['id']} : champ « {f} » manquant")
        if l["archived"] and l["status"] != "x":
            errors.append(f"{l['id']} archivé mais pas fait")
    for l in lots:
        for d in l["deps"]:
            if d not in seen:
                errors.append(f"{l['id']} : dépendance inconnue {d}")
            elif seen[d]["status"] == "-":
                errors.append(f"{l['id']} : dépend d'un lot abandonné {d}")
        if l["status"] == "x":
            for d in l["deps"]:
                if d in seen and seen[d]["status"] != "x":
                    errors.append(f"{l['id']} fait alors que sa dépendance {d} ne l'est pas")
    # cycles
    state = {}

    def visit(i, stack):
        if state.get(i) == 1:
            errors.append("Cycle : " + " → ".join(stack + [i]))
            return
        if state.get(i) == 2 or i not in seen:
            return
        state[i] = 1
        for d in seen[i]["deps"]:
            visit(d, stack + [i])
        state[i] = 2

    for i in seen:
        visit(i, [])
    for e in errors:
        print("ERREUR", e)
    print(f"{len(lots)} lots, {len(errors)} erreur(s)")
    sys.exit(1 if errors else 0)


def sections(lines):
    """[(titre `## …` ou "", lignes)] dans l'ordre du fichier."""
    out = [["", []]]
    for line in lines:
        if line.startswith("## "):
            out.append([line, []])
        else:
            out[-1][1].append(line)
    return out


def cmd_archive(lines, lots):
    """Déplace les lots faits (sous le titre de leur phase) et le Journal sauf ses dernières lignes."""
    moved = {}  # titre de phase -> blocs
    drop = set()
    current = ""
    titles = {}
    for i, line in enumerate(lines):
        if line.startswith("## "):
            current = line
        titles[i] = current
    for l in lots:
        if l["archived"] or l["status"] != "x":
            continue
        moved.setdefault(titles[l["line"]], []).extend(lines[l["line"]:l["end"]])
        drop.update(range(l["line"], l["end"]))
    kept = [line for i, line in enumerate(lines) if i not in drop]
    # Journal : en-tête du tableau + les KEEP_JOURNAL dernières lignes
    old_rows = []
    secs = sections(kept)
    for sec in secs:
        if sec[0] == JOURNAL:
            body = sec[1]
            rows = [k for k, line in enumerate(body) if line.startswith("| ") and not line.startswith("| Date")]
            old = rows[:-KEEP_JOURNAL] if len(rows) > KEEP_JOURNAL else []
            old_rows = [body[k] for k in old]
            sec[1] = [line for k, line in enumerate(body) if k not in set(old)]
    if not moved and not old_rows:
        print("Rien à archiver.")
        return
    arch = sections(read(ARCHIVE)) if ARCHIVE.exists() else [["", ARCHIVE_HEAD.splitlines()]]
    by_title = {s[0]: s for s in arch}
    for title, block in moved.items():
        if title not in by_title:
            by_title[title] = [title, [""]]
            arch.append(by_title[title])
        sec = by_title[title]
        while sec[1] and sec[1][-1] == "":
            sec[1].pop()
        sec[1].extend([""] + block)
    if old_rows:
        if JOURNAL not in by_title:
            by_title[JOURNAL] = [JOURNAL, ["", "| Date | Lot | Fait | Reste / suite |", "|---|---|---|---|"]]
            arch.append(by_title[JOURNAL])
        sec = by_title[JOURNAL]
        while sec[1] and sec[1][-1] == "":
            sec[1].pop()
        sec[1].extend(old_rows)
    # le Journal de l'archive reste en dernier
    arch.sort(key=lambda s: s[0] == JOURNAL)
    ARCHIVE.write_text(join(arch), encoding="utf-8")
    ROADMAP.write_text(join(secs), encoding="utf-8")
    n = sum(1 for block in moved.values() for line in block if HEADING.match(line))
    print(f"{n} lot(s) et {len(old_rows)} ligne(s) du Journal archivés dans {ARCHIVE.name}")


def join(secs):
    out = []
    for title, body in secs:
        if title:
            if out and out[-1] != "":
                out.append("")
            out.append(title)
        out.extend(body)
    while out and out[-1] == "":
        out.pop()
    return "\n".join(out) + "\n"


def main():
    if hasattr(sys.stdout, "reconfigure"):
        sys.stdout.reconfigure(encoding="utf-8")
    args = sys.argv[1:] or ["status"]
    lines, lots = parse()
    cmd = args[0]
    if cmd == "status":
        cmd_status(lots)
    elif cmd == "next":
        cmd_next(lots)
    elif cmd == "show" and len(args) == 2:
        cmd_show(lots, args[1])
    elif cmd == "set" and len(args) in (2, 3):
        cmd_set(lines, lots, args[1], args[2] if len(args) == 3 else " ")
    elif cmd == "check":
        cmd_check(lots)
    elif cmd == "archive":
        cmd_archive(lines, lots)
    else:
        sys.exit(__doc__)


if __name__ == "__main__":
    main()
