#!/usr/bin/env python3
"""Etape de PUBLICATION du contenu d'un monde (roadmap C.07), sans lancer le jeu.

    python tools/publish_content.py --world incarnam --package-dir D:/packages
    python tools/publish_content.py --world dofus,incarnam --package-dir D:/packages --keep-versions 2

Lance `godot --headless ... --build-packages` (le meme code que le serveur exporte) : liste et hache les
fichiers (cache de hachage), ecrit dans des bundles (fichiers immuables nommes par leur empreinte) les contenus
qu'aucun bundle ne contient encore, un manifeste par fragment (la base, chaque zone), l'index de la release,
puis deplace le pointeur du monde dans worlds.json en dernier. Incremental (une modification n'ecrit que les
fichiers modifies) et reprenable (relancer apres une coupure repart de ce qui est ecrit).

Le dossier des paquets EST l'arborescence statique servie : le serveur de jeu la sert telle quelle sur son
port HTTP (`--package-dir` identique), n'importe quel hebergement statique / CDN pourrait la servir aussi
(worlds.json, <monde>/releases/, manifests/, bundles/ ; bundles.json et <monde>/index.json ne sont pas a publier).
"""
import argparse
import os
import shutil
import subprocess
import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent
GAME = ROOT / "game"
GODOT = os.environ.get(
    "GODOT", r"C:\Users\natha\Documents\Godot\Godot_v4.7-stable_win64_console.exe")


def publish(args) -> None:
    cmd = [GODOT, "--headless", "--path", str(GAME), "-s", "res://src/server/main.gd", "--", "--server",
           "--no-auth", "--build-packages", "--world=" + ",".join(args.world),
           "--package-dir=" + str(Path(args.package_dir).resolve())]
    if args.rebuild:
        cmd.append("--rebuild")
    if args.bundle_mb:
        cmd.append("--bundle-mb=%s" % args.bundle_mb)
    if args.keep_versions:
        cmd.append("--keep-versions=%d" % args.keep_versions)
    if args.content_root:
        cmd.append("--content-root=" + args.content_root)
    code = subprocess.call(cmd, cwd=ROOT)
    if code != 0:
        sys.exit("publication en erreur (code %d) : la relancer reprend ou elle s'est arretee" % code)


def main() -> None:
    ap = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    ap.add_argument("--world", action="append", required=True, help="monde a publier (repeter ou separer par des virgules)")
    ap.add_argument("--package-dir", required=True, help="dossier du contenu publie (le meme que --package-dir du serveur)")
    ap.add_argument("--content-root", help="dossier contenant worlds/, data/, content/ (defaut : game/)")
    ap.add_argument("--rebuild", action="store_true", help="ignore le cache de hachage")
    ap.add_argument("--bundle-mb", type=int, help="taille d'un bundle (defaut 32)")
    ap.add_argument("--keep-versions", type=int, help="releases gardees par monde (defaut 3)")
    args = ap.parse_args()
    args.world = [w for item in args.world for w in item.split(",") if w]
    Path(args.package_dir).mkdir(parents=True, exist_ok=True)
    free = shutil.disk_usage(Path(args.package_dir).resolve().anchor).free / 1e9
    print("espace libre sur le disque des paquets : %.1f Go" % free)
    publish(args)


if __name__ == "__main__":
    main()
