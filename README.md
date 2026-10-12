# SuperDofus — rendu d'entités Dofus 3 dans Godot 4.7

Affiche **n'importe quelle entité Dofus 3** à partir d'une *look string* : personnages de toutes classes avec leurs cosmétiques, familiers, montures avec cavalier, auras, monstres et props de map. Toutes les animations et les 8 directions sont prises en charge, ainsi que la recoloration dynamique, les masques et les blend modes.

C'est un port GDScript natif de [PyDofus/d3-ts-renderer](https://github.com/PyDofus/d3-ts-renderer), architecturé pour un jeu. La lib de rendu est isolée du gameplay.

```
{1|120,2195,4072,4941,3963,5716|1=13418918,2=4077879,...|56|1@0={1420|||90}}
 │  │                            │                         │  └ sous-entités (familier, monture, aura…)
 │  └ skins : corps, tête, équipements        couleurs     └ taille (%)
 └ os (1 = joueur)
```

## Pourquoi ce choix technique

Dofus 3 anime ses entités comme Flash : des **meshes 2D triangulés** échantillonnent des atlas et sont placés chaque frame par une display list. Chaque nœud porte une matrice affine, des couleurs multiplicative et additive, un masque et un blend mode.

Pré-rendre des spritesheets est impossible : il y a des millions de combinaisons de looks, d'animations, de directions et de couleurs. On fait donc comme le client : un **renderer runtime de meshes**. Voici comment il se décline dans Godot.

- **Décodage.** Les `.dat` sont décodés une fois en snapshots par frame, car les deltas s'accumulent depuis la frame 0.
- **Bake paresseux.** Chaque frame est bakée à la demande en quelques meshes, regroupés par texture, blend et masque. Les meshes sont partagés entre toutes les entités de même look.
- **Rendu.** On passe par `RenderingServer`, avec un pool de canvas items. Afficher une frame coûte quelques `canvas_item_add_mesh`.
- **Shader.** Un shader `canvas_item` applique la palette de 16 couleurs (`/127`, comme le jeu). Les couleurs multiplicative et additive transitent par les attributs de vertex `COLOR`, `CUSTOM0` et `CUSTOM1`.
- **Masques.** Les masques stencil deviennent des *clip groups* Godot.
- **Blend modes.** Chaque blend mode Flash a son matériau.

Mesures : **100 entités animées à ~200 FPS (p95 6 ms), 300 à ~130 FPS**, avec le renderer Compatibility sur une RTX 3070 Ti Laptop (mesure faite avec l'ancienne démo iso, retirée depuis).

## Le client de jeu (standalone / serveur)

La lib de rendu sert de base à un **client de jeu façon Dofus** et à son **serveur** :
- **Scène principale** : `scenes/client/launch.tscn` (écran Solo / Serveur), puis le choix du monde et du personnage. Les mondes : `dofus` (les 17 353 maps du client), `incarnam`, `test`.
- **Frontière d'API** : le client ne parle à la logique de jeu qu'à travers `GameBackend`.
  - En **standalone**, la logique (`src/sim/`) tourne dans le client, via `LocalBackend`.
  - En **multijoueur**, un serveur headless (`src/server/`, `serveur.bat`) exécute ce même code ; le client s'y connecte par `NetBackend` (WebSocket JSON). Jouer entre amis : [docs/GUIDE_AMIS.md](docs/GUIDE_AMIS.md) ; export et distribution du contenu : [docs/EXPORT.md](docs/EXPORT.md).
- **Plusieurs mondes** : chaque monde est un `WorldSource`, dans `game/worlds/<id>/`.
- **Avancement** : [docs/ROADMAP.md](docs/ROADMAP.md) (travail restant, par lots ; `python tools/roadmap.py status`).

Détails dans [docs/ARCHITECTURE.md](docs/ARCHITECTURE.md). Le résumé destiné aux agents est dans [CLAUDE.md](CLAUDE.md), les commandes dans [docs/COMMANDES.md](docs/COMMANDES.md).

## Arborescence

```
tools/extractor/        Python + UnityPy : bundles Unity du client -> Content/ neutre
tools/golden/           comparaison pixel à pixel avec d3-ts-renderer (référence)
game/                   projet Godot 4.7 (renderer gl_compatibility)
  addons/dofus_renderer/   LIB VISUELLE autonome, zéro dépendance gameplay
    look/        DofusLook (parse/serialise les look strings), DofusSubEntity
    data/        ContentProvider (FS, extensible pck/CDN), bone/skin, game data (slots, couleurs de classe)
    decode/      DofusAnimClip (.dat)
    anim/        DofusAnimNames (directions, miroirs, anims liées des sous-entités)
    render/      résolveur de look, bake, instance runtime, matériaux/shader
    dofus_content.gd   caches partagés (statique, pas d'autoload)
    dofus_sprite.gd    le Node2D public
  src/shared, src/sim, src/api, src/client, src/server   le jeu (voir docs/ARCHITECTURE.md)
  worlds/        données des mondes (JSON)
  scenes/client/launch.tscn     scène principale (Solo / Serveur)
  scenes/client/client.tscn     le client de jeu
  scenes/tools/look_viewer.tscn  l'outil "skinator"
  tests/          tests unitaires, de scénario et réseau (runner maison, headless)
  tools/          outils headless : sim_cli, client_shot, render_shot… (docs/COMMANDES.md)
```

**Règle d'architecture.** La lib de rendu ne connaît pas le jeu. Côté jeu, la sim émet des événements ; le client (`ActorView`) traduit l'état d'un acteur en animation via une `AnimMap` (par exemple `MOVE` -> `AnimMarche`) et écoute les **labels de l'animation** (`SHOT` marque la frame d'impact d'une attaque ; `Sound(id=…)` et `END` sont aussi exposés).

## Mise en route

1. **Extraire le contenu** depuis le client Dofus 3 installé (détecté dans `%LOCALAPPDATA%\Ankama\Dofus-dofus3`) :
   ```bash
   pip install -r tools/extractor/requirements.txt
   python tools/extractor/extract.py --data --player --all-skins   # joueur + tous les skins
   python tools/extractor/extract.py --all-bones --all-props        # monstres, familiers, montures, props (~quelques Go)
   python tools/extractor/extract.py --bones 1420 2013 --skins 709  # ou à la carte
   ```
   Le contenu va dans `game/content/`. Ce dossier est ignoré par Godot (`.gdignore`) et par git.
   Pour le client de jeu (vraies maps, sorts, noms, UI) :
   ```bash
   python tools/extractor/maps.py index && python tools/extractor/maps.py i18n
   python tools/extractor/maps.py world incarnam --center 154010373 --radius 1
   python tools/extractor/spells.py breed 12 --max 10 --world incarnam
   python tools/extractor/ui.py fonts && python tools/extractor/ui.py textures hud
   ```
2. **Ouvrir `game/` dans Godot 4.7** et lancer le projet : écran de lancement, puis Solo (sim embarquée) ou Serveur (adresse d'un serveur lancé par `serveur.bat`).
3. **Le Look Viewer** (`scenes/tools/look_viewer.tscn`) : on y colle une look string ou on choisit une classe, un monstre ou une monture ; on parcourt les animations et directions, on recolore, on avance frame par frame et on exporte en PNG.

## Utiliser la lib

```gdscript
var s := DofusSprite.new()
add_child(s)
s.look_string = "{1|120,2195,3042||56|1@0={1420|||90}}"
s.play_animation("AnimMarche", DofusAnimNames.Direction.DOWN_LEFT)  # 3 = miroir de 1
s.label_reached.connect(func(label, anim): if label == "SHOT": apply_damage())
s.set_color(3, Color.RED)                           # recolore sans rien reconstruire
s.preload_animations(["AnimMarche", "AnimCourse"])  # décode en tâche de fond
```

- Pour une autre source de contenu (pck, CDN…), appelez `DofusContent.set_provider(mon_provider)` avec votre propre `DofusContentProvider`.
- Le dossier est configurable via `dofus_renderer/content_root` dans les Project Settings.

## Tests et vérifications

```bash
godot --headless --path game -s res://tests/run_tests.gd          # toute la suite (longue ; TEST_ONLY=<fichiers> pour une partie)
godot --path game -s res://tools/render_shot.gd -- --out=x.png --anim=AnimMarche --dir=1 --frames=0,4,8 "{look}" "{look}" "{look}"
python tools/golden/compare.py --ref-repo <clone buildé de d3-ts-renderer>   # diff avec la référence
```

Côté golden test, 8 cas sur 10 sont quasi identiques à la référence (écart moyen de 1 à 3,5 sur 255). Les 2 autres utilisent les blends screen/lighten, voir ci-dessous.

## Limites connues

- **Blend modes.** Screen, lighten, darken et invert sont approximés : Godot 2D n'a pas d'équation MIN/MAX ni de `ONE_MINUS_SRC_COLOR`. Normal, add, subtract et multiply sont exacts.
- **Masques imbriqués.** Les clip groups Godot ne s'imbriquent pas. Le contenu masqué obéit donc au masque le plus interne, alors que le client utilise l'intersection stencil.
- **Masques sur fond transparent.** Sur un fond transparent (portrait UI dans une SubViewport transparente), Godot dessine les clip groups en noir. Utilisez alors `mask_mode = HIDE_MASKED`.
- **Filtres Flash.** Glow, blur et drop shadow sont parsés mais non rendus, comme dans la référence.
- **Chargement synchrone.** Le premier affichage d'un look est synchrone : environ 50 ms par nouvel os, pour le JSON et les textures. Seuls les clips se préchargent en tâche de fond. Un chargement asynchrone des looks est la prochaine étape naturelle.

## Légal

Les assets extraits sont la propriété d'Ankama et ne doivent être ni commités ni redistribués. Le README de d3-ts-renderer interdit d'en faire un clone de *skinator* ou un site payant.

La lib ne dépend d'aucun asset : elle lit un format neutre via `DofusContentProvider`. Un jeu commercialisé devra fournir ses propres assets dans ce format, ou obtenir une licence.
