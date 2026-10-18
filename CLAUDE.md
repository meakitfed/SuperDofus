# SuperDofus — guide pour agents

Ce projet est un client de jeu façon Dofus 3 écrit en Godot 4.7 (GDScript, renderer `gl_compatibility`), avec son serveur. Il affiche les vraies entités Dofus grâce à `game/addons/dofus_renderer`, et le même moteur peut servir plusieurs mondes (et, à terme, un autre jeu : rien de spécifique à Dofus dans le code de session, réseau, comptes, contenu, admin).

**Le client ne parle qu'à une API** (`GameBackend` : `send`, signal `event`, `time_ms`), branchée :
- sur la logique de jeu embarquée (`LocalBackend` → `WorldSim`) : mode **standalone** ;
- sur un **serveur** (`NetBackend`, WebSocket JSON) qui exécute le même `sim/` (`game/src/server/`, `serveur.bat`).

Tout ce qui est « côté serveur » va dans `game/src/sim/`, jamais dans le client. Lire `docs/ARCHITECTURE.md` avant de toucher au gameplay.

## Workflow de session : la roadmap
Le plan (recréer toutes les fonctionnalités de Dofus, par priorité) est dans **`docs/ROADMAP.md`**, découpé en lots d'une session ; il ne garde que le travail restant (lots faits et vieux Journal : `docs/ROADMAP_ARCHIVE.md` ; pièges et règles trouvées : `docs/DECOUVERTES.md`, à chercher avec Grep).
- `/suite` fait avancer d'un lot : choix, implémentation, vérification, mise à jour de la roadmap, commit + push. `/suite plan` présente seulement le plan ; `/suite P1.05` cible un lot.
- `python tools/roadmap.py status | next | show <ID> | set <ID> todo|doing|done|dropped | check | archive`.
- **Toute feature doit marcher aussi en mode serveur** : un test via `NetBackend` (127.0.0.1) accompagne chaque nouvelle mécanique ou message ; sinon dette notée au Journal.

En fin de session, même sans `/suite`, si du travail touche un lot : mettre à jour son statut, le Journal et les Découvertes, puis `roadmap.py archive` et `roadmap.py check`.

## Carte
Le détail par domaine (fichiers, données, mots-clés `client_shot`, tests) est dans **`docs/CARTE.md`** : le lire pour le domaine du lot.
- `game/src/shared/` : logique pure commune à la sim et au client (géométrie 14×20, `IsoGrid`, A*, timing, protocole : `protocol.gd` + une extension `protocol_<domaine>.gd` par domaine, listée dans `ProtocolSchema.EXTENSIONS`). `shared/content_source.gd` est la seule porte vers `content/`, `data/`, `worlds/<id>/`, `mods/`.
- `game/src/sim/` : autoritaire, sans `Node`, déterministe (seed). `WorldSim` n'est qu'un routeur ; les règles sont dans les `world_<domaine>.gd` (base `WorldHandler`) ; combats dans `sim/fight/` ; personnage persistant `sim/character.gd` via `Persistence`. `Clock` donne la date, `DataFiles` lit les données statiques.
- `game/src/api/` : les hôtes (`LocalBackend`, `LocalServer`, `NetBackend`, `FilePersistence`, `SystemClock`). `game/src/server/` : le serveur headless (comptes, cluster de mondes, API de contenu, admin) ; rien d'autre ne le référence.
- `game/src/client/` : nœuds Godot qui affichent les événements ; `ClientSession` route par domaine. Interface : toujours le kit `client/ui/` (`UiWindow`, `UiStyle`, `ItemSlot`, `SpellBar`, `UiTooltips`, `Shortcuts`…), jamais de couleurs ni de raccourcis en dur.
- `game/worlds/<id>/` : données d'un monde (JSON) : `dofus` (les 17 353 maps du client, défaut), `incarnam` (les tests), `test` (généré). `game/data/` : sorts, XP, objets (générés). Scène principale : `scenes/client/launch.tscn` ; `client.tscn` = le client (les outils l'instancient).
- `tools/extractor/` : extraction des tables Dofus 3 (`extract.py --tables all`, `maps.py`, `spells.py`, `gamedata.py`, `ui.py`). **Avant d'utiliser une donnée, consulter `docs/data_catalog.md`**, lire avec `GameData.table("nom")` / `GameData.row("nom", id)`.
- Données serveur absentes du client (positions des PNJ, portes…) : dumps JondoEmu dans `C:\Users\natha\Documents\Dofus3+\datos` (vérifier, noter la source, ne rien republier).

## Règles (vérifiées par `tests/test_architecture.gd`)
1. `shared/` et `sim/` : aucun `Node`, `Input`, rendu, ni référence à `client/` ou `api/`. `src/` ne contient que les couches `shared sim client api server`.
2. `client/` n'utilise jamais une classe de `sim/`. Il passe uniquement par les messages du protocole.
3. Les messages sont des Dictionary JSON-safe. Faire `int()` à la lecture, car les nombres reviennent en float après JSON.
4. Toute nouvelle mécanique a son test de scénario (`tests/`), piloté via `LocalBackend`, plus un test `NetBackend`.
5. Côté client, un événement qui s'anime (un sort, par exemple) est une séquence : `FightView.handle` renvoie `true` et émet `sequence_done` à la fin.
6. Un script ne dépasse pas 800 lignes : découper par domaine avant.
7. **Harnais anti-régression** : tout nouveau sort, effet ou monstre ⇒ une ligne dans le golden (`GOLDEN_UPDATE=1`, relire le diff) + son test (contrat, cas multi-tours ou matrice) ; les gardes de couverture échouent sinon. Détail : `docs/ARCHITECTURE.md` (Harnais), `docs/COMMANDES.md`.

Règles du jeu : **sourcées** (`luaformulas <id>`, `table.champ`, lien) ou marquées `APPROX(<lot>): raison` en commentaire. Scénarios de référence : `game/tests/scenarios/*.jsonl` (`sim_cli --record`). Voir `docs/RULES_SOURCES.md` (enums du client : `docs/client_enums.md` ; code natif décompilé : `tools/client_code`).

## Commandes essentielles
Godot : `C:\Users\natha\Documents\Godot\Godot_v4.7-stable_win64_console.exe`. Tout le reste (captures par mécanique, serveur, export, outils) : **`docs/COMMANDES.md`**.
```bash
godot --headless --path game --import                                   # après tout nouveau class_name
TEST_ONLY=test_trade,test_party godot --headless --path game -s res://tests/run_tests.gd   # itérer sur quelques fichiers
python tools/test_changed.py                                              # AVANT CHAQUE COMMIT : seulement les tests que tes modifs peuvent casser (~1-2 min) ; ajoute le harnais rapide si sim/, data/ ou shared/ ont bougé
TEST_TIER=fast godot --headless --path game -s res://tests/run_tests.gd   # harnais sorts + monstres + scénarios (~2 min), à la main si besoin
godot --headless --path game -s res://tests/run_tests.gd                # tous les tests (> 30 min : une fois, à la fin)
godot --headless --path game -s res://tools/sim_cli.gd -- --world=incarnam --seconds=60 --cmd=500:fight_attack --cmd=1000:fight_ready
godot --headless --path game -s res://tools/sim_cli.gd -- --scenario=res://tests/scenarios/fight_won.jsonl   # rejoue un scénario (--rerecord= après un changement de règle voulu)
godot --path game -s res://tools/client_shot.gd -- --world=incarnam --out=f.png --seconds=12 --cmd=1500:attack --cmd=3000:ready --cmd=7000:win --shot=8500
godot --headless --path game -s res://tools/protocol_doc.gd            # régénère docs/PROTOCOL.md après un changement de SCHEMA
python tools/rules_sources.py                                           # registre des APPROX + index des formules (--check)
godot --headless --path game -s res://src/server/main.gd -- --server --port=7777 --world=incarnam --save-dir=C:/SuperDofus/saves
```

## Pièges connus
- Nouveau message : constante + entrée `SCHEMA` + constructeur dans l'extension du domaine (`shared/protocol_<domaine>.gd`, `protocol.gd` est plein ; un nouveau fichier va dans `ProtocolSchema.EXTENSIONS`), puis régénérer `docs/PROTOCOL.md`. Nouvelle erreur : une constante `E_*` dans `ERROR_CODES` et un texte dans `client/error_texts.gd`. Les règles renvoient des codes, jamais du texte.
- Heredocs bash + Python : les caractères accentués et les antislashs sont corrompus. Écrire les scripts dans un fichier (outil Write) avant de les lancer, avec `PYTHONIOENCODING=utf-8`.
- Un sort lançable est un **grade** (id = 1 000 000 + `spelllevels.id`), pas un `spells.id` : le grimoire, les variantes et la barre parlent en `spells.id`, les combats en grades (`SpellBook.grade_for`).
- Les sorts Pandawa ont des variantes Sobre/Saoul (`cond`) : les conditions se lisent **au moment du lancer**.
- Maps : les ombres utilisent un multiply qui respecte l'alpha (shader dans `DofusMapNode`). Les clip groups Godot ne s'imbriquent pas et dessinent en noir sur un fond transparent.
- Le disque C: est presque plein : extraire le contenu en `--webp` et vérifier l'espace libre avant toute grosse extraction.
- `game/content/` contient les assets Ankama : jamais commités. `serveur.bat` porte les réglages locaux de l'utilisateur : ne pas le commiter sans qu'il le demande.
- Pas de `print` ni de `push_warning` par frame ou par sprite, cela coûte des centaines de ms.
- Sous Windows, `Select-String` ignore la casse : chercher les échecs de tests avec `-CaseSensitive "    FAIL"`.
