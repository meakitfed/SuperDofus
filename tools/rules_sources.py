"""Keeps the generated parts of docs/RULES_SOURCES.md up to date.

    python tools/rules_sources.py          rewrite the generated sections
    python tools/rules_sources.py --check  exit 1 if they are stale (used by /suite)

Generated sections:
  - the APPROX registry: every `APPROX` comment in game/src and tools/extractor
    (format: `APPROX(<lot>): reason`), i.e. each rule that is not the real one yet;
  - the luaformulas index (official Dofus 3 formulas shipped in the client):
    id, parameters, first comment. Each formula is also written, readable, to
    game/content/Content/Data/luaformulas/<id>.lua (never committed).
"""
from __future__ import annotations

import json
import re
import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
DOC = ROOT / "docs" / "RULES_SOURCES.md"
FORMULAS = ROOT / "game" / "content" / "Content" / "Data" / "luaformulasdataroot.json"
SCAN = [(ROOT / "game" / "src", "*.gd"), (ROOT / "tools" / "extractor", "*.py")]
# in a comment, followed by ":" (strings that merely mention the word do not count)
APPROX = re.compile(r"#.*?\bAPPROX(?:\((?P<lot>[^)]*)\))?:\s*(?P<why>.*)")


def section(text: str, name: str, body: str) -> str:
    start, end = f"<!-- {name}:START -->", f"<!-- {name}:END -->"
    a, b = text.index(start) + len(start), text.index(end)
    return text[:a] + "\n" + body + text[b:]


def approx_registry() -> str:
    rows = []
    for base, pattern in SCAN:
        for path in sorted(base.rglob(pattern)):
            for n, line in enumerate(path.read_text(encoding="utf-8").splitlines(), 1):
                m = APPROX.search(line)
                if not m or "APPROX = re.compile" in line:
                    continue
                rel = path.relative_to(ROOT).as_posix()
                why = m["why"].strip().rstrip(";").replace("|", "\\|") or "(voir le code)"
                rows.append(f"| `{rel}:{n}` | {m['lot'] or '—'} | {why} |")
    head = "| Où | Lot qui corrigera | Approximation |\n|---|---|---|"
    return head + "\n" + "\n".join(rows) + "\n" if rows else "Aucune approximation.\n"


def formulas_index() -> str:
    if not FORMULAS.exists():
        return "_Table absente : lancer `python tools/extractor/extract.py --tables luaformulas`._\n"
    out_dir = FORMULAS.parent / "luaformulas"
    out_dir.mkdir(exist_ok=True)
    rows = ["| Id | Paramètres | Commentaire |", "|---|---|---|"]
    table = json.loads(FORMULAS.read_text(encoding="utf-8"))["objectsById"]
    for fid in sorted(table, key=int):
        code = table[fid].get("formula", "").replace("\r\n", "\n").replace("\r", "\n")
        (out_dir / f"{fid}.lua").write_text(code, encoding="utf-8")
        params = re.search(r"return\s*\{([^}]*)\}", code)
        params_txt = ", ".join(p.strip().strip('"') for p in params[1].split(",")) if params and "function params" in code else ""
        comment = next((l.strip("- ").strip() for l in code.splitlines() if l.strip().startswith("--") and l.strip("- ").strip()), "")
        rows.append(f"| {fid} | {params_txt.replace('|', '/')} | {comment[:90].replace('|', '/')} |")
    return "\n".join(rows) + "\n"


def main() -> None:
    if hasattr(sys.stdout, "reconfigure"):
        sys.stdout.reconfigure(encoding="utf-8")
    text = DOC.read_text(encoding="utf-8")
    new = section(text, "APPROX", approx_registry())
    new = section(new, "FORMULAS", formulas_index())
    if "--check" in sys.argv:
        if new != text:
            print("docs/RULES_SOURCES.md is stale: run python tools/rules_sources.py")
            sys.exit(1)
        print("docs/RULES_SOURCES.md up to date")
        return
    DOC.write_text(new, encoding="utf-8")
    print(f"{DOC}: {new.count('| `')} APPROX rows")


if __name__ == "__main__":
    main()
