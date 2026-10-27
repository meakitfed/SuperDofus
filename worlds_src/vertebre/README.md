# La Vertèbre : sources du monde

Monde original de SuperDofus (une « tour » brisée par un Effondrement), **sans asset Dofus commité** (les créatures, PNJ, classes et équipements empruntent les sprites Dofus de `game/content`, copiés en local et gitignorés ; voir `spec/dofus_map.py`) : tout ce que le joueur voit
(créatures, icônes, sols, décors) est dessiné par le code de ce dossier, tout ce qu'il lit est écrit dans `spec/lore.py` et
`gen/`. La sortie est `game/worlds/vertebre/` (commitée) ; le guide généré est `docs/MONDE_VERTEBRE.md`.

```bash
python worlds_src/vertebre/gen/build_all.py [--reuse]   # régénère tout (~1 min ; --reuse saute les os inchangés)
python worlds_src/vertebre/gen/validate.py               # intégrité des ids et des assets (0 problème attendu)
godot --headless --path game -s res://tools/vertebre_balance.gd -- --runs=6   # équilibrage : classes contre étages
```

Un seul `build_all.py` à la fois (deux builds simultanés s'écrasent).

## Organisation

| Dossier | Rôle |
|---|---|
| `spec/lore.py` | la bible : chronologie, factions, étages, boss, fragments de mémoire, fins, liste des PNJ |
| `build/rigs.py` | 4 familles de squelettes paramétriques (debout, bête, flottant, serpent) écrites au format « os » du moteur (réutilise `game/mods/joss/build`) |
| `build/icons.py` | ~50 symboles dessinés, palettes par panoplie / élément ; portraits de créatures |
| `build/tilegen.py`, `build/mapgen.py` | sols pré-rendus par thème, objets de décor, génération de maps (obstacles, alcôves secrètes, vides) avec garantie de connexité |
| `gen/common.py` | plages d'ids, registre de textes (`I18n/extra_fr.json`), registre de sortie |
| `gen/spells_lib.py` | constructeurs d'effets et de sorts (3 grades) |
| `gen/classes.py` | les 5 classes et leurs 40 sorts |
| `gen/items.py`, `gen/mobs.py`, `gen/bosses.py` | objets et panoplies, 45 créatures, 5 boss et leurs invocations |
| `gen/story.py` | PNJ, dialogues conditionnels, 16 quêtes |
| `gen/world.py` | les 12 maps, PNJ posés, objets à fouiller, `world.json` |
| `gen/validate.py`, `gen/docs.py` | contrôle d'intégrité, guide du monde |

## Ajouter du contenu

- une créature : une ligne `M(...)` dans `gen/mobs.py` (visuel + rôle par ses sorts, `lambda lv: [...]` avec les motifs `strike`, `bolt`, `aoe`, `mend`, `glyph`, `trap`, `spawn`...) ;
- un objet : `_add(...)` dans `gen/items.py` (une panoplie : une entrée de `SETS`) ;
- une quête ou un dialogue : `gen/story.py` (`quest(...)`, `Tree().node(...)`), avec `criteria` (`Qf=`, `PO=`, `PL>`) ;
- relancer `build_all.py` puis `validate.py` et `TEST_ONLY=test_vertebre_spells,test_vertebre_world,test_vertebre_net`.
