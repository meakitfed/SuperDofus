#!/usr/bin/env python3
"""Etape de PUBLICATION du contenu d'un monde (roadmap C.06), sans lancer le jeu.

    python tools/publish_content.py --world incarnam --package-dir D:/packages
    python tools/publish_content.py --world dofus --package-dir D:/packages --copy-files
    python tools/publish_content.py --world incarnam --package-dir D:/packages --static-out D:/cdn

Lance `godot --headless ... --build-packages` (le meme code que le serveur exporte) : hache, zippe
(base + une archive par zone) et publie une version immuable sous <package-dir>/<monde>/versions/<release>/,
puis ecrit le pointeur current.json en dernier. Reprenable : si l'etape est interrompue (Ctrl+C, coupure), la
relancer repart de l'index de hachage et des zips deja ecrits. Le serveur de jeu ne calcule plus rien :
il lit ces paquets au demarrage (`--package-dir` identique) et refuse de demarrer s'ils manquent.

--static-out DIR  assemble de plus l'arborescence servable telle quelle par un hebergement statique :
    DIR/worlds/<monde>/{manifest.json, bundle.json, bundle/part-NNN.zip, zones.json, zones/<z>/manifest.json,
    zones/<z>/pack.zip, files/<hash>} + DIR/worlds.json. Les fichiers par empreinte (`files/`) exigent
    --copy-files (sinon le serveur de jeu les lit directement dans content/, sans duplication des 22 Go).
    Les gros zips sont copies (compter leur taille en espace disque) ; un fichier deja present de meme taille est garde.
"""
import argparse
import json
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
    if args.no_bundle:
        cmd.append("--no-bundle")
    if args.no_zone_packs:
        cmd.append("--no-zone-packs")
    if args.copy_files:
        cmd.append("--copy-files")
    if args.bundle_mb:
        cmd.append("--bundle-mb=%s" % args.bundle_mb)
    if args.keep_versions:
        cmd.append("--keep-versions=%d" % args.keep_versions)
    if args.content_root:
        cmd.append("--content-root=" + args.content_root)
    code = subprocess.call(cmd, cwd=ROOT)
    if code != 0:
        sys.exit("publication en erreur (code %d) : la relancer reprend ou elle s'est arretee" % code)


def copy_if_needed(src: Path, dst: Path) -> None:
    if dst.exists() and dst.stat().st_size == src.stat().st_size:
        return
    dst.parent.mkdir(parents=True, exist_ok=True)
    tmp = dst.with_name(dst.name + ".tmp")
    shutil.copy2(src, tmp)
    os.replace(tmp, dst)


def export_static(args) -> None:
    out = Path(args.static_out)
    listing = []
    for world in args.world:
        wdir = Path(args.package_dir) / world
        cur = json.loads((wdir / "current.json").read_text(encoding="utf-8"))
        vdir = wdir / "versions" / cur["release"]
        release = json.loads((vdir / "release.json").read_text(encoding="utf-8"))
        target = out / "worlds" / world
        for name in release["artifacts"]:
            if name == "blobs.json":
                continue  # ou le serveur de jeu lit chaque fichier : pas pour un hebergement statique
            copy_if_needed(vdir / name, target / name)
        files = wdir / "files"
        if files.is_dir():
            for f in files.iterdir():
                if f.is_file() and not f.name.endswith(".tmp"):
                    copy_if_needed(f, target / "files" / f.name)
        else:
            print("ATTENTION %s : pas de files/ (publier avec --copy-files pour un hebergement statique complet)" % world)
        manifest = json.loads((vdir / "manifest.json").read_text(encoding="utf-8"))
        listing.append({"id": world, "name": manifest["name"], "module": manifest["module"], "version": manifest["version"],
                        "files": len(manifest["files"]), "size": sum(f["size"] for f in manifest["files"])})
        print("statique : %s -> %s (version %s)" % (world, target, manifest["version"][:12]))
    (out / "worlds.json").write_text(json.dumps(listing), encoding="utf-8")


def main() -> None:
    ap = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    ap.add_argument("--world", action="append", required=True, help="monde a publier (repeter ou separer par des virgules)")
    ap.add_argument("--package-dir", required=True, help="dossier des paquets publies (le meme que --package-dir du serveur)")
    ap.add_argument("--content-root", help="dossier contenant worlds/, data/, content/ (defaut : game/)")
    ap.add_argument("--rebuild", action="store_true", help="ignore le cache de hachage")
    ap.add_argument("--no-bundle", action="store_true", help="pas de zip de base")
    ap.add_argument("--no-zone-packs", action="store_true", help="pas de zip par zone")
    ap.add_argument("--copy-files", action="store_true", help="ecrit files/<empreinte> (hebergement statique ; duplique le contenu)")
    ap.add_argument("--bundle-mb", type=int)
    ap.add_argument("--keep-versions", type=int)
    ap.add_argument("--static-out", help="assemble l'arborescence a poser sur un hebergement statique")
    args = ap.parse_args()
    args.world = [w for item in args.world for w in item.split(",") if w]
    free = shutil.disk_usage(Path(args.package_dir).resolve().anchor).free / 1e9
    print("espace libre sur le disque des paquets : %.1f Go" % free)
    publish(args)
    if args.static_out:
        export_static(args)


if __name__ == "__main__":
    main()
