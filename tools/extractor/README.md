# Extracteur de contenu Dofus 3

Convertit les bundles Unity du client en un format neutre, lu par `game/addons/dofus_renderer`. Ce format suit le même layout que d3-ts-renderer.

```
Content/Characters/Bones/<os>/bone.json, skin.json, <i>.png, <anim>.dat
Content/Characters/Bones/families.json      # os répartis sur plusieurs bundles (joueur : 1-static, 1-movement, 1-<classe>-combat…)
Content/Characters/Skins/<id>/skin.json, <i>.png
Content/Animations/Props/<prop>/...
Content/Data/<table>.json                   # {"objectsById": {...}} : bodies, breeds, skin slots, heads, items, monsters, mounts
```

```bash
pip install -r requirements.txt
python extract.py --list bones | head
python extract.py --data --player --all-skins
python extract.py --all --jobs 8           # tout (plusieurs Go, ~30 min)
python extract.py --bones 262 --overwrite  # réextraire un os
python extract.py --tables all            # les 204 tables de données (incrémental, ~200 Mo)
python catalog.py                         # docs/data_catalog.md
python gamedata.py table breeds           # copie légère livrée avec le jeu : game/data/tables/breeds.json
```

Quelques points de fonctionnement :

- **Version Unity.** Elle est lue dans `globalgamemanagers`, car les bundles ne la contiennent pas.
- **Orientation des textures.** Les textures restent orientées comme dans le bundle (retournées verticalement) : les UV des meshes l'attendent ainsi.
- **Noms d'animation.** Les caractères interdits par Windows sont encodés en `%XX` ; `AnimMarche_*1` devient par exemple `AnimMarche_%2A1.dat`. Le loader Godot applique la même règle.
- **Option `--webp` (recommandée).** Elle écrit du WebP lossless, identique au pixel près et environ 40 % plus léger. En PNG, l'extraction complète dépasse 18 Go. `compact.py` convertit en place un contenu déjà extrait en PNG.
