# Atelier de mondes (`atelier/`)

Site local pour créer et éditer un monde (`game/worlds/<id>/`) sans toucher au code Godot, avec une garantie de cohérence. Node ≥ 20, TypeScript. Roadmap : lots **W.01 à W.07** (`docs/ROADMAP.md`).

## État
- **W.01 fait : le harnais** (schémas, validateur, tests).
- **W.02 fait : serveur local + gestion de mondes.** `atelier.bat` (ou `cd atelier && npm run build && npm start`) ouvre http://127.0.0.1:5174 : liste des mondes, création, détail avec panneau Cohérence, renommer, annuler/refaire, relire le dossier, supprimer.
- **W.03 fait : bibliothèque d'images.** Onglet « Images » d'un monde : glisser-déposer de PNG/JPEG/WebP ou d'un ZIP, par catégorie (objets, sorts, monstres, tuiles). Icônes ramenées à 96×96 transparent, tuiles gardées à leur taille. Chaque image est ré-encodée en PNG propre (aucune métadonnée), dédoublonnée par empreinte, numérotée dans la tranche `asset` du monde. Une image utilisée ne peut pas être supprimée ; une image inutilisée donne l'avertissement `W_ASSET_UNUSED`. Les imports ne passent pas par annuler/refaire (fichiers écrits aussitôt).
- **W.04 fait : éditeurs de données.** Fait : textes, objets, panoplies, sorts (onglets « Textes », « Objets », « Sorts »). Sorts : un grade lançable + sa famille ; effets simples (dommages, soin, bouclier, PA, PM), le critique est calculé (+30 %) ; un sort à effets riches reste éditable sur ses réglages, effets verrouillés. Chaque action (`core/editors.ts`, API `/api/worlds/:id/data/<texts|items|sets>`) est une étape d'annulation, passe par un texte i18n (jamais de nom en dur), prend son id dans la tranche du monde, et refuse une suppression qui laisserait une référence cassée (`core/usage.ts` : « utilisé par »). La pastille de cohérence reste visible en édition. Monstres : 1 à 5 grades (stats, résistances, sorts, butin, kamas, agression), squelette copié depuis un autre monde géré (les aperçus sont les planches brutes `0.png`), zones de monstres (clés comptées depuis le haut de la plage `monster`) ; règle `W_MONSTER_NO_ZONE` (56 règles) ; les boss sont en lecture seule. Une zone n'est rattachée à une map que dans l'éditeur de maps (W.05). Classes : nom, rôle, description, squelette, grimoire ordonné (un sort ne sert qu'une classe), classe par défaut ; nouveau type d'id `breed` (plafond de 600 emplacements pour rester sous 2^31). Le contrat Godot couvre un monde rempli avec les éditeurs. Limite : pas encore de symbole ni de portrait de classe (écrans de création du jeu).
- **W.05a fait : éditeur de maps** (onglet « Maps »). Grille 14×40 cliquable (murs, vue bloquée, placement rouge/bleu, porte, renaissance, départ du monde ; glisser pour peindre), nom, coordonnées, extérieur, zone de monstres, voisines (réciproques automatiquement), portes. Une map s'enregistre d'un bloc (une étape d'annulation). L'éditeur refuse ce que le validateur rejetterait aussitôt : porte ou arrivée sur un mur, placement sur un mur, départ bloqué, élément interactif libéré. Créer une map crée son visuel vide ; supprimer une map efface ses fichiers (copie `.bak`, annulation possible) et exige qu'aucun lien, PNJ ou quête n'y mène. Murs = `blocked` et `fight_blocked` écrits ensemble. Le dessin des calques graphiques reste W.07.
- Suite : PNJ, dialogues, boutiques, quêtes (W.05b), workflows (W.06), éditeur de calques de map (W.07). Le clonage de monde (qui exige de remapper tous les ids) n'est pas fait.

## Mondes gérés
- Seuls les mondes du registre sont modifiables : `vertebre` (plages historiques) et ceux créés par l'atelier (`atelier/world_ranges.json`, local, ignoré par git). `dofus`, `incarnam`, `test` sont listés en lecture seule.
- L'atelier ne supprime que les mondes qu'il a créés.
- Chaque monde créé a un emplacement (`core/ranges.ts`) : une tranche de 100 000 ids par type (textes, objets, sorts, monstres, PNJ, quêtes, maps...), tous au-dessus de 1 000 000 000. Les règles `E_ID_RANGE` et `E_ID_COLLISION` les font respecter. Un monde neuf n'a pas de classe propre (`breeds: []`) : le moteur lui offre alors les classes que personne ne réclame.
- Un monde neuf a une map vide (`templates/map_visual_empty.json`, sans image : rien à afficher tant que l'éditeur de calques, W.07, n'existe pas).

## Sécurité du serveur
Écoute 127.0.0.1 seulement, refuse un `Host` étranger (DNS rebinding), exige `x-atelier: 1` et du JSON pour toute écriture (aucun CORS), ne sert jamais de fichier hors de `web/dist`.

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
| `store.test.ts` | plages d'ids disjointes, création valide, collisions, annuler/refaire, suppression protégée, relecture |
| `server.test.ts` | l'API sur une vraie socket, CSRF, Host, accès hors dossier |
| `ui.test.ts` | l'interface dans un vrai navigateur (Playwright) ; `SHOTS_DIR=<dossier>` enregistre une capture par étape |
| `assets.test.ts` | import, ZIP, rejets, doublons, usage, suppression |
| `godot_contract.test.ts` | un monde neuf créé par l'atelier, et un monde relu/réécrit par l'atelier démarre dans `sim_cli` (copie temporaire `game/worlds/atelier_contract`, supprimée ensuite ; ignoré si Godot est absent, `GODOT_EXE` pour le chemin) |

`python tools/test_changed.py` lance `npm test` dès que `atelier/` ou `game/worlds/vertebre/` change.

## Pièges
- `npm install` plante (« edgesOut ») sans `legacy-peer-deps` : déjà dans `atelier/.npmrc`.
- Les messages de `validate.py` sont en anglais, ceux de l'atelier en français : la parité compare les **nombres** de problèmes, pas le texte.
- Les ids doivent être disjoints entre mondes et de `data/` global : `opts.ranges` / `opts.reserved` de `validate()` (alimentés par W.02).
