# Atelier de mondes (`atelier/`)

Site local pour créer et éditer un monde (`game/worlds/<id>/`) sans toucher au code Godot, avec une garantie de cohérence. Node ≥ 20, TypeScript. Roadmap : lots **W.01 à W.07** (`docs/ROADMAP.md`).

## État
- **W.01 fait : le harnais.** Pas encore d'interface : le socle sur lequel elle se construira.
- Suite : serveur local + gestion de mondes (W.02), assets (W.03), éditeurs (W.04, W.05), workflows (W.06), éditeur de calques de map (W.07).

## Disposition
- `atelier/core/` : TypeScript pur.
  - `schemas.ts` : un schéma par fichier d'un monde (strict sur ce que le moteur lit, `passthrough` sur le reste).
  - `io.ts` : `loadWorld`, `saveWorld` (atomique : `.tmp` puis renommage, ancienne version en `.bak`), `serializeWorld`. **Le modèle est le JSON brut** : l'ordre des clés et les champs inconnus survivent à un aller-retour.
  - `validate.ts` + `rules_content.ts` / `rules_maps.ts` / `rules_story.ts` : les règles. `RULES` est la liste unique ; un `Problem` porte un code stable, un message français et une référence (`ref`) pour que l'interface mène à l'élément fautif.
  - `grid.ts` : grille 14 × 40 = 560 cellules, voisinage en diagonale (le plus strict).
  - `cli.ts` : `cd atelier && npm run validate -- ../game/worlds/<id>` (code de sortie 1 s'il y a des erreurs ; les avertissements `W_*` n'échouent pas).
- `atelier/tests/` : voir ci-dessous.

## Ajouter une règle
1. L'écrire dans le fichier de règles du domaine : `{ code: "E_…", severity, doc, run }`. Préfixe `E_` (erreur) ou `W_` (avertissement), imposé par le test.
2. Ajouter sa mutation dans `tests/rules.test.ts` (`MUTATIONS`) : partir du mini-monde, casser **une** chose. La mutation ne doit déclencher que cette règle (sauf `also` justifié). La garde de couverture échoue sinon.
3. Si la règle a un équivalent dans `worlds_src/vertebre/gen/validate.py`, ajouter une casse dans `tests/vertebre.test.ts` (parité des verdicts).

## Le harnais (`cd atelier && npm test`)
| Test | Ce qu'il garantit |
|---|---|
| `rules.test.ts` | chaque règle se déclenche sur sa mutation et sur elle seule ; le mini-monde est valide ; garde de couverture ; préfixe vs sévérité |
| `vertebre.test.ts` | La Vertèbre est relue sans perte, jugée cohérente (0 problème), et le validateur dit comme `validate.py` sur 7 casses (nécessite Python + Pillow) |
| `io.test.ts` | aller-retour disque, sauvegarde idempotente, échec en cours d'écriture sans effet, fichiers cassés signalés sans plantage |
| `godot_contract.test.ts` | un monde relu/réécrit par l'atelier démarre dans `sim_cli` (copie temporaire `game/worlds/atelier_contract`, supprimée ensuite ; ignoré si Godot est absent, `GODOT_EXE` pour le chemin) |

`python tools/test_changed.py` lance `npm test` dès que `atelier/` ou `game/worlds/vertebre/` change.

## Pièges
- `npm install` plante (« edgesOut ») sans `legacy-peer-deps` : déjà dans `atelier/.npmrc`.
- Les messages de `validate.py` sont en anglais, ceux de l'atelier en français : la parité compare les **nombres** de problèmes, pas le texte.
- Les ids doivent être disjoints entre mondes et de `data/` global : `opts.ranges` / `opts.reserved` de `validate()` (alimentés par W.02).
