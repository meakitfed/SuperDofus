---
description: Avance la roadmap SuperDofus d'un lot (ou `/suite plan`, `/suite P1.05`)
argument-hint: "[plan] [ID de lot]"
---

Tu reprends le projet SuperDofus là où il s'est arrêté. La roadmap vivante est dans `docs/ROADMAP.md` (travail restant seulement ; lots faits et vieux Journal : `docs/ROADMAP_ARCHIVE.md`).

Arguments : `$ARGUMENTS`
- vide : prendre le prochain lot ;
- un ID (ex. `P1.05`) : prendre ce lot ;
- `plan` (éventuellement suivi d'un ID) : s'arrêter après l'étape 2 et présenter le plan détaillé du lot, sans rien coder.

## Étapes

1. **Choisir le lot.**
   - Lancer `python tools/roadmap.py next`.
   - S'il y a un lot `EN COURS`, le reprendre : lire les dernières lignes du Journal pour savoir où il en est.
   - Sinon, prendre le lot `PROCHAIN`, ou celui passé en argument : vérifier que ses dépendances sont faites (`roadmap.py show <dép>` marche aussi pour un lot archivé).
   - Faire `python tools/roadmap.py set <ID> doing`.
   - Afficher le lot avec `python tools/roadmap.py show <ID>`.
2. **Comprendre.**
   - Relire les « Principes » de `docs/ROADMAP.md`, la ligne du domaine dans `docs/CARTE.md`, les sections concernées de `docs/ARCHITECTURE.md` et de `docs/RULES_SOURCES.md` (où trouver une règle, approximations à corriger par ce lot), puis les fichiers concernés.
   - Chercher dans `docs/DECOUVERTES.md` (Grep, pas de lecture complète) les mots du lot : pièges déjà rencontrés, règles trouvées.
   - Chercher le code réutilisable : `FightRules`, `GameData`, `CriteriaEval`, `Protocol`, le kit d'UI…
   - Identifier les tables Dofus 3 nécessaires (`docs/data_catalog.md`). Si une table manque dans `game/content/Content/Data`, trouver le bundle et l'extraire (vérifier l'espace disque avant, utiliser `--webp`).
   - Si le lot est trop gros pour une session, le découper en `<ID>a`, `<ID>b`… dans `ROADMAP.md`, avec les mêmes champs, et ne faire que le premier.
   - En mode `plan` : présenter le plan (règles sourcées, fichiers, protocole, tests), puis s'arrêter.
3. **Implémenter, dans cet ordre :**
   1. les règles dans `game/src/sim/` et `game/src/shared/`, avec la source de chaque règle en commentaire (`luaformulas` n°, table.champ, ou un lien). Une approximation est marquée `APPROX` ;
   2. le protocole : les messages d'un domaine vont dans `shared/protocol_<domaine>.gd` (un nouveau fichier s'ajoute à `ProtocolSchema.EXTENSIONS` et ses codes à `Protocol.ERROR_CODES`), commentaire de doc à jour ;
   3. les tests de scénario via `LocalBackend` (`game/tests/`), et `test_architecture` si de nouvelles classes apparaissent ;
   4. le client : il affiche seulement, via le kit d'UI, avec les vraies textures et polices ;
   5. la doc : `docs/ARCHITECTURE.md`, la ligne du domaine dans `docs/CARTE.md`, les nouvelles commandes dans `docs/COMMANDES.md` (`CLAUDE.md` seulement si une règle générale change).
4. **Vérifier.** Commandes : `CLAUDE.md` et `docs/COMMANDES.md`.
   - `godot --headless --path game --import` ;
   - pendant le travail : `TEST_ONLY=<fichiers du domaine>` (sous-chaînes séparées par des virgules) ; la suite complète (> 30 min) **une fois à la fin**, verte, et dont le total de tests ne baisse pas (une erreur de parse dans un fichier de test est silencieuse : vérifier le total). Chercher les échecs avec `Select-String -CaseSensitive "    FAIL"` (PowerShell ignore la casse sinon) ;
   - une trace `sim_cli` du scénario principal. Tout lot de règles ajoute ou réenregistre un scénario de référence (`sim_cli --record`, voir `docs/RULES_SOURCES.md`) ; un scénario existant qui casse = régression, sauf changement de règle voulu et noté au Journal ;
   - chaque règle cite sa source (`luaformulas <id>`, `table.champ`, lien), sinon `APPROX(<lot>): raison` dans un commentaire ; puis `python tools/rules_sources.py` (registre et index des formules) ;
   - **harnais (H)** : tout nouveau sort, effet ou monstre arrive avec ses lignes dans le harnais : une ligne dans le golden (`GOLDEN_UPDATE=1`, diff relu : `tests/golden/spells/classe_<NN>.json`, `tests/golden/monsters/matrix.json` et `ai_*.json`), son contrat (`test_spell_contracts`) et, pour une mecanique multi-tours, un cas dans `tests/spells/spell_cases.gd` ; le garde de couverture (`test_spell_coverage`, `test_monster_matrix`) echoue sinon. Un changement de regle voulu = golden regenere et diff explique au Journal ; `TEST_TIER=fast` (< 5 min) avant le commit, et `TEST_UPDATE_BASELINE=1` si des tests ont ete ajoutes (le total de `tests/baseline.json` ne baisse jamais) ;
   - **mode serveur** : toute fonctionnalité doit aussi marcher via le serveur réseau (`NetBackend`). Ajoute au moins un test qui l'exerce via `NetBackend` sur 127.0.0.1 (modèle : `test_net*.gd` ; pour un sort ou un monstre, `test_matrix_net.gd` rejoue un echantillon en local et par le reseau et compare), vérifie que les nouveaux messages passent le JSON aller-retour (nombres en float : `int()`), que rien ne dépend d'un raccourci local (`LocalBackend.sim`, `user://` côté sim) et que l'état partagé entre joueurs passe par `Persistence` ; si c'est impossible, note-le au Journal comme dette (lot à créer) ;
   - une capture `client_shot`, **relue** avec l'outil Read ;
   - cocher la ligne « Parité » du lot (☑) en étant honnête. Une case non cochée doit être justifiée dans le Journal.
5. **Mettre à jour la roadmap.**
   - Statut : `set <ID> done` si tout est vérifié, sinon laisser `doing`.
   - Ajouter une ligne au **Journal** (tableau, en bas) : date, lot, ce qui est fait, ce qui reste.
   - Ajouter en tête de `docs/DECOUVERTES.md` les pièges, les règles trouvées et les `APPROX`.
   - Créer les nouveaux lots découverts, au bon endroit dans leur phase, avec leurs dépendances.
   - Lancer `python tools/roadmap.py archive` (lots faits et vieux Journal vers l'archive), puis `python tools/roadmap.py check` et `python tools/rules_sources.py --check`, qui doivent passer.
   - Mémoire : seulement si une décision durable de l'utilisateur change (pas d'avancement : la roadmap le porte).
6. **Commiter.** Si tout est vert : commit (message en français, « <ID> <titre> : résumé ») puis push sur `master`. Ne jamais commiter `game/content/`, `serveur.bat` (réglages locaux de l'utilisateur) ni des fichiers sans rapport avec le lot.
7. **Rapport à l'utilisateur**, court et en français :
   - le lot réalisé et comment il a été vérifié (tests, capture) ;
   - les approximations ;
   - le prochain lot proposé (`roadmap.py next`).

## Garde-fous
- Aucune règle de jeu dans `client/`, aucun `Node`/fichier/réseau dans `sim/` ou `shared/`.
- **Toute feature doit fonctionner en mode serveur** (test via `NetBackend`, voir l'étape 4) en plus du standalone.
- Le code doit servir tel quel au standalone et au serveur (voir « Standalone vs serveur » dans `docs/ARCHITECTURE.md`).
- Ne jamais commiter `game/content/`. Pas de `print` par frame.
- Scripts Python avec accents : les écrire avec l'outil Write, puis les lancer avec `PYTHONIOENCODING=utf-8`, jamais via un heredoc.
- Pour enchaîner plusieurs lots sans supervision, l'utilisateur le demande (« enchaîne N lots ») : un workflow lance alors un agent `/suite` par lot, l'un après l'autre (contexte neuf à chaque lot).
