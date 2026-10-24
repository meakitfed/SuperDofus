"""Runs only the tests that your uncommitted changes can break (the daily loop; the whole battery stays for the end).

    python tools/test_changed.py            # changes since HEAD (staged, unstaged, new files)
    python tools/test_changed.py --since origin/master
    python tools/test_changed.py --list     # only print the choice
    python tools/test_changed.py --fast     # also run the heavy fast tier (spells, monsters, scenarios)

Selection:
  * a changed test file runs itself;
  * a changed script runs the tests that name its class or its file, then the tests of the scripts that
    name it (one more level, hubs such as the session or the protocol are not followed);
  * sim/ and data/ changes (the rules) add the fast tier (spell contracts, monster matrix, scenarios);
  * docs / tools only: nothing but the architecture guard;
  * atelier/ (or the Vertebre world, which its tests read) changed: `npm test` in atelier/ runs too.
test_architecture always runs (file sizes, layers: a few seconds).
"""
import os
import re
import subprocess
import sys

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
GAME = os.path.join(ROOT, "game")
GODOT = os.environ.get("GODOT", r"C:\Users\natha\Documents\Godot\Godot_v4.7-stable_win64_console.exe")
HUB = 40  # a script named by more files than this is a hub: following it would select everything
ATELIER = ("atelier/", "game/worlds/vertebre/", "worlds_src/vertebre/gen/validate.py")
RULES = ("game/src/sim/", "game/data/", "game/worlds/", "game/src/shared/")


def git(*args):
    out = subprocess.run(["git", "-C", ROOT, *args], capture_output=True, text=True, encoding="utf-8").stdout
    return [l for l in out.splitlines() if l.strip()]


def changed(since):
    files = set(git("diff", "--name-only", since))
    files |= set(git("ls-files", "--others", "--exclude-standard"))
    return sorted(f.replace("\\", "/") for f in files)


def scripts(sub):
    out = {}
    for base, _, names in os.walk(os.path.join(GAME, sub)):
        for n in names:
            if n.endswith(".gd"):
                p = os.path.join(base, n)
                with open(p, encoding="utf-8", errors="replace") as f:
                    out[os.path.relpath(p, GAME).replace("\\", "/")] = f.read()
    return out


def names_of(path, text):
    base = os.path.basename(path)[:-3]
    m = re.search(r"^class_name\s+(\w+)", text, re.M)
    return {n for n in (base, m.group(1) if m else None) if n}


def refs(name, text):
    return re.search(r"\b%s\b" % re.escape(name), text) is not None or ("/" + name + ".gd") in text


def main():
    args = sys.argv[1:]
    since = args[args.index("--since") + 1] if "--since" in args else "HEAD"
    files = changed(since)
    src = scripts("src")
    tests = scripts("tests")
    tests = {k: v for k, v in tests.items() if os.path.basename(k).startswith("test_") and "/" not in k[len("tests/"):]}
    picked = {"test_architecture"}
    heavy = "--fast" in args
    reason = {}
    for f in files:
        if f.startswith(RULES):
            heavy = True
        if not f.endswith(".gd"):
            continue
        rel = f[len("game/"):] if f.startswith("game/") else f
        if rel.startswith("tests/"):
            if os.path.basename(rel).startswith("test_"):
                picked.add(os.path.basename(rel)[:-3])
                reason[os.path.basename(rel)[:-3]] = rel
            continue
        if rel not in src:
            continue
        level = names_of(rel, src[rel])
        level2 = set()
        for other, text in src.items():
            if other != rel and any(refs(n, text) for n in level):
                level2 |= names_of(other, text)
        users = [o for o in src if o != rel and any(refs(n, src[o]) for n in level)]
        if len(users) > HUB:
            level2 = set()
        for t, text in tests.items():
            tn = os.path.basename(t)[:-3]
            if any(refs(n, text) for n in level) or any(refs(n, text) for n in level2 if len(users) <= HUB):
                picked.add(tn)
                reason.setdefault(tn, rel)
    # the heavy tier already runs these
    names = sorted(picked)
    print("Changed: %d file(s). Selected tests (%d): %s" % (len(files), len(names), ", ".join(names)))
    if heavy:
        print("Rules touched (sim/, data/, shared/): the fast tier runs too.")
    atelier = any(f.startswith(ATELIER) for f in files)
    if atelier:
        print("atelier/ touched: npm test runs too.")
    if "--list" in args:
        return 0
    env = dict(os.environ)
    code = 0
    if atelier:
        code |= subprocess.run("npm test", shell=True, cwd=os.path.join(ROOT, "atelier")).returncode
    env["TEST_ONLY"] = ",".join(names)
    code |= subprocess.run([GODOT, "--headless", "--path", GAME, "-s", "res://tests/run_tests.gd"], env=env).returncode
    if heavy:
        env.pop("TEST_ONLY", None)
        env["TEST_TIER"] = "fast"
        code |= subprocess.run([GODOT, "--headless", "--path", GAME, "-s", "res://tests/run_tests.gd"], env=env).returncode
    return 1 if code else 0


if __name__ == "__main__":
    sys.exit(main())
