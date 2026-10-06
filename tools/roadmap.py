"""Lit et met à jour docs/ROADMAP.md (le plan vivant du projet).

    python tools/roadmap.py status          avancement par phase
    python tools/roadmap.py next            lots en cours, puis le prochain lot faisable
    python tools/roadmap.py show P1.05      détail d'un lot
    python tools/roadmap.py set P1.05 doing statut : todo, doing, done, dropped (ou " ", "~", "x", "-")
    python tools/roadmap.py check           format, IDs uniques, dépendances valides

Un lot est un titre `### [s] ID Titre` suivi de lignes `- Champ : valeur`.
"""
import re
import sys
from pathlib import Path

ROADMAP = Path(__file__).resolve().parent.parent / "docs" / "ROADMAP.md"
HEADING = re.compile(r"^### \[(.)\] ([A-Z]\d*\.\d+[a-z]?) (.+)$")
REQUIRED = ["Dépend", "Règles", "Tests", "Parité"]
ALIASES = {"todo": " ", "_": " ", "": " ", "doing": "~", "done": "x", "dropped": "-"}
STATUSES = {" ": "à faire", "~": "en cours", "x": "fait", "-": "abandonné"}


def parse():
    lines = ROADMAP.read_text(encoding="utf-8").splitlines()
    lots, cur, fence = [], None, False
    for i, line in enumerate(lines):
        if line.startswith("```"):
            fence = not fence
            continue
        if fence:
            continue
        m = HEADING.match(line)
        if m:
            cur = {"status": m[1], "id": m[2], "title": m[3], "line": i, "fields": {}, "body": [line]}
            lots.append(cur)
            continue
        if cur is None:
            continue
        if line.startswith("## ") or line.startswith("### ") or line.strip() == "---":
            cur = None
            continue
        cur["body"].append(line)
        f = re.match(r"^- ([^:]+?) :\s*(.*)$", line)
        if f:
            cur["fields"][f[1].strip()] = f[2].strip()
    for lot in lots:
        dep = lot["fields"].get("Dépend", "—")
        lot["deps"] = [] if dep in ("—", "-", "") else [d.strip() for d in dep.split(",") if d.strip()]
    return lines, lots


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
            print("\n".join(l["body"]).rstrip())
            return
    sys.exit(f"Lot inconnu : {lot_id}")


def cmd_set(lines, lots, lot_id, status):
    status = ALIASES.get(status, status)
    if status not in STATUSES:
        sys.exit(f"Statut invalide : {status!r} (attendu : {', '.join(repr(s) for s in STATUSES)})")
    for l in lots:
        if l["id"] == lot_id:
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
    else:
        sys.exit(__doc__)


if __name__ == "__main__":
    main()
