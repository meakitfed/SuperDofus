#!/usr/bin/env python3
"""Construit la distribution de SuperDofus (roadmap X.01) : dist/client/ et dist/server/.

    python tools/build_release.py                      # client + serveur, mondes incarnam et test
    python tools/build_release.py --worlds dofus --content link
    python tools/build_release.py --only client --zip   # + dist/SuperDofus-client.zip pour les amis
    python tools/build_release.py --smoke               # lance le serveur exporte (--check) apres le build
    python tools/build_release.py --publish             # + PUBLIE le contenu des mondes avec le serveur exporte (C.07)

Prerequis : les modeles d'export de Godot 4.7 (Editeur > Gerer les modeles d'export) et de la place
sur C: (verifie ici : le build ecrit ~210 Mo, 2 x 105 Mo). Les presets sont dans game/export_presets.cfg :
  Client   exe unique, SANS content/, data/, worlds/, mods/ (le contenu se telecharge du serveur)
  Serveur  exe + console (headless), le PCK ne contient pas les assets
Le serveur lit les dossiers worlds/, data/, content/, mods/ a cote de l'exe (voir ServerApp) : `--content link`
(defaut) y met une jonction vers game/content (22 Go : jamais copie), les autres dossiers sont copies
(ou lies avec `--link-all`). override.cfg ouvre scenes/server/server.tscn : un serveur exporte ignore `-s`.
"""
import argparse
import os
import shutil
import subprocess
import sys
import zipfile
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent
GAME = ROOT / "game"
DIST = ROOT / "dist"
RELEASE = Path(__file__).resolve().parent / "release"
GODOT = os.environ.get(
    "GODOT", r"C:\Users\natha\Documents\Godot\Godot_v4.7-stable_win64_console.exe")
TEMPLATES = Path(os.environ.get("APPDATA", "")) / "Godot" / "export_templates" / "4.7.stable"
MIN_FREE_GB = 2.0
SERVER_OVERRIDE = '[application]\n\nrun/main_scene="res://scenes/server/server.tscn"\n'


def free_gb(path: Path) -> float:
    return shutil.disk_usage(path).free / 1e9


def run(cmd: list[str], **kw) -> subprocess.CompletedProcess:
    return subprocess.run(cmd, text=True, encoding="utf-8", errors="replace",
                          capture_output=True, **kw)


def export(preset: str) -> None:
    res = run([GODOT, "--headless", "--path", str(GAME), "--export-release", preset])
    text = res.stdout + res.stderr
    errors = [l for l in text.splitlines() if "ERROR" in l and "savepack" not in l and "Stockage" not in l]
    if res.returncode != 0 or errors:
        sys.exit("export %s a echoue :\n%s" % (preset, "\n".join(errors) or text[-2000:]))


def link_or_copy(src: Path, dst: Path, link: bool) -> None:
    if dst.exists() or dst.is_symlink():
        if os.path.isdir(dst) and not os.path.islink(dst) and not _is_junction(dst):
            shutil.rmtree(dst)
        elif _is_junction(dst):
            os.rmdir(dst)
        else:
            dst.unlink()
    if link:
        if os.name == "nt":
            res = run(["cmd", "/c", "mklink", "/J", str(dst), str(src)])
            if res.returncode != 0:
                sys.exit("jonction impossible : " + res.stdout + res.stderr)
        else:
            dst.symlink_to(src, target_is_directory=True)
    else:
        shutil.copytree(src, dst, ignore=_ignore)


_IGNORE = shutil.ignore_patterns(".gdignore", "_*", "*.import", "*.uid")


def _ignore(directory, names):
    """Fichiers de travail ignores, sauf _content.json (C.02b : les assets du monde, lus par le serveur)."""
    skipped = set(_IGNORE(directory, names))
    skipped.discard("_content.json")
    return skipped


def _is_junction(p: Path) -> bool:
    return getattr(os.path, "isjunction", lambda _p: False)(p)


def dir_size(p: Path) -> int:
    return sum(f.stat().st_size for f in p.rglob("*") if f.is_file())


def build_client(zip_it: bool) -> None:
    out = DIST / "client"
    out.mkdir(parents=True, exist_ok=True)
    export("Client")
    shutil.copy2(DIST / "LISEZMOI.txt", out / "LISEZMOI.txt")
    size = dir_size(out)
    print("client : %s (%.1f Mo)" % (out, size / 1e6))
    if zip_it:
        z = DIST / "SuperDofus-client.zip"
        with zipfile.ZipFile(z, "w", zipfile.ZIP_DEFLATED) as zf:
            for f in out.iterdir():
                zf.write(f, f.name)
        print("zip    : %s (%.1f Mo)" % (z, z.stat().st_size / 1e6))


def build_server(worlds: list[str], content: str, link_all: bool) -> None:
    out = DIST / "server"
    out.mkdir(parents=True, exist_ok=True)
    export("Serveur")
    (out / "override.cfg").write_text(SERVER_OVERRIDE, encoding="utf-8", newline="\n")
    (out / "worlds").mkdir(exist_ok=True)
    (out / "packages").mkdir(exist_ok=True)  # C.07 : le contenu publie (bundles, manifestes, releases), servi par le serveur
    for w in worlds:
        src = GAME / "worlds" / w
        if not (src / "world.json").exists():
            sys.exit("monde inconnu : " + w)
        link_or_copy(src, out / "worlds" / w, link_all)
    link_or_copy(GAME / "data", out / "data", link_all)
    if (GAME / "mods").exists():
        link_or_copy(GAME / "mods", out / "mods", link_all)
    if content == "link":
        link_or_copy(GAME / "content", out / "content", True)
    elif content == "copy":
        sys.exit("copier content/ (22 Go) est refuse : utiliser --content link")
    shutil.copy2(RELEASE / "serveur-lancer.bat", DIST / "serveur-lancer.bat")
    (DIST / "serveur-lancer.bat").write_text(
        (DIST / "serveur-lancer.bat").read_text(encoding="utf-8").replace("@WORLDS@", ",".join(worlds)),
        encoding="utf-8", newline="\r\n")
    print("serveur : %s (mondes %s, content %s)" % (out, ",".join(worlds), content))


def smoke() -> None:
    exe = DIST / "server" / "SuperDofusServeur.console.exe"
    res = run([str(exe), "--headless", "--", "--check", "--port=0", "--save-dir=" + str(DIST / "server" / "saves"),
               "--package-dir=" + str(DIST / "server" / "packages"),
               "--world=" + ",".join(WORLDS_USED)], cwd=DIST / "server", timeout=120)
    lines = [l for l in res.stdout.splitlines() if l.startswith("check:")]
    print("\n".join(lines))
    if res.returncode != 0:
        sys.exit("le serveur exporte signale un probleme (code %d)" % res.returncode)


def publish() -> None:
    """C.06 : l'etape de build du contenu, avec le serveur exporte (reprenable : relancer si interrompue)."""
    exe = DIST / "server" / "SuperDofusServeur.console.exe"
    res = run([str(exe), "--headless", "--", "--build-packages", "--no-auth",
               "--package-dir=" + str(DIST / "server" / "packages"),
               "--world=" + ",".join(WORLDS_USED)], cwd=DIST / "server")
    print(os.linesep.join(l for l in res.stdout.splitlines() if l.startswith("publish:") and "bundling" not in l))
    if res.returncode != 0:
        sys.exit("la publication du contenu a echoue :" + os.linesep + (res.stderr or res.stdout)[-1500:])


WORLDS_USED: list[str] = []


def main() -> None:
    ap = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    ap.add_argument("--only", choices=["client", "server"], help="un seul des deux")
    ap.add_argument("--worlds", default="incarnam,test", help="mondes du serveur (liste separee par des virgules)")
    ap.add_argument("--content", choices=["link", "none", "copy"], default="link")
    ap.add_argument("--link-all", action="store_true", help="worlds/ et data/ en jonction au lieu de copies")
    ap.add_argument("--zip", action="store_true", help="zip du client pour les amis")
    ap.add_argument("--smoke", action="store_true", help="lance `--check` du serveur exporte")
    ap.add_argument("--publish", action="store_true", help="publie le contenu des mondes (serveur exporte, --build-packages)")
    args = ap.parse_args()
    free = free_gb(ROOT)
    print("espace libre : %.1f Go" % free)
    if free < MIN_FREE_GB:
        sys.exit("moins de %.0f Go libres : liberer de la place avant le build" % MIN_FREE_GB)
    if not (TEMPLATES / "windows_release_x86_64.exe").exists():
        sys.exit("modeles d'export 4.7 absents : %s" % TEMPLATES)
    DIST.mkdir(exist_ok=True)
    shutil.copy2(RELEASE / "LISEZMOI.txt", DIST / "LISEZMOI.txt")
    res = run([GODOT, "--headless", "--path", str(GAME), "--import"])
    if res.returncode != 0:
        sys.exit("import Godot en erreur :\n" + res.stderr[-1500:])
    worlds = [w for w in args.worlds.split(",") if w]
    WORLDS_USED.extend(worlds)
    if args.only != "server":
        build_client(args.zip)
    if args.only != "client":
        build_server(worlds, args.content, args.link_all)
        if args.publish:
            publish()
        if args.smoke:
            smoke()


if __name__ == "__main__":
    main()
