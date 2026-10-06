---
description: Avance la roadmap SuperDofus d'un lot (ou `/suite plan`, `/suite P1.05`)
argument-hint: "[plan] [ID de lot]"
---

Tu reprends le projet SuperDofus là où il s'est arrêté. La roadmap vivante est dans `docs/ROADMAP.md`.

Arguments : `$ARGUMENTS`
- vide : prendre le prochain lot ;
- un ID (ex. `P1.05`) : prendre ce lot ;
- `plan` (éventuellement suivi d'un ID) : s'arrêter après l'étape 2 et présenter le plan détaillé du lot, sans rien coder.

## Étapes

1. **Choisir le lot.**
   - Lancer `python tools/roadmap.py next`.
   - S'il y a un lot `EN COURS`, le reprendre : lire la dernière ligne du Journal pour savoir où il en est.
   - Sinon, prendre le lot `PROCHAIN`, ou celui passé en argument : vérifier que ses dépendances sont faites.
   - Faire `python tools/roadmap.py set <ID> doing`.
   - Afficher le lot avec `python tools/roadmap.py show <ID>`.
2. **Comprendre.**
   - Relire les « Principes » de `docs/ROADMAP.md`, `docs/ARCHITECTURE.md`, la section « Découvertes », `docs/RULES_SOURCES.md` (où trouver une règle, approximations à corriger par ce lot) et les fichiers concernés.
   - Chercher le code réutilisable : `FightRules`, `GameData`, `CriteriaEval`, `Protocol`, le kit d'UI…
   - Identifier les tables Dofus 3 nécessaires. Si une table manque dans `game/content/Content/Data`, trouver le bundle et l'extraire (vérifier l'espace disque avant : `df -h /c`, utiliser `--webp`).
   - Si le lot est trop gros pour une session, le découper en `<ID>a`, `<ID>b`… dans `ROADMAP.md`, avec les mêmes champs, et ne faire que le premier.
   - En mode `plan` : présenter le plan (règles sourcées, fichiers, protocole, tests), puis s'arrêter.
3. **Implémenter, dans cet ordre :**
   1. les règles dans `game/src/sim/` et `game/src/shared/`, avec la source de chaque règle en commentaire (`luaformulas` n°, table.champ, ou un lien). Une approximation est marquée `APPROX` ;
   2. le protocole (`shared/protocol.gd`, commentaire de doc à jour) ;
   3. les tests de scénario via `LocalBackend` (`game/tests/`), et `test_architecture` si de nouvelles classes apparaissent ;
   4. le client : il affiche seulement, via le kit d'UI, avec les vraies textures et polices ;
   5. la doc (`docs/ARCHITECTURE.md`, `CLAUDE.md` si les commandes ou la carte changent).
4. **Vérifier.** Toutes les commandes sont dans `CLAUDE.md`.
   - `godot --headless --path game --import`, puis tous les tests, qui doivent être verts ;
   - une trace `sim_cli` du scénario principal. Tout lot de règles ajoute ou réenregistre un scénario de référence (`sim_cli --record`, voir `docs/RULES_SOURCES.md`) ; un scénario existant qui casse = régression, sauf changement de règle voulu et noté au Journal ;
   - chaque règle cite sa source (`luaformulas <id>`, `table.champ`, lien), sinon `APPROX(<lot>): raison` dans un commentaire ; puis `python tools/rules_sources.py` (registre et index des formules) ;
   - **mode serveur** : toute fonctionnalité doit aussi marcher via le serveur réseau (`NetBackend`). Ajoute au moins un test qui l'exerce via `NetBackend` sur 127.0.0.1 (modèle : les tests réseau de S.01, `test_net*.gd`), vérifie que les nouveaux messages passent le JSON aller-retour (nombres en float : `int()`), que rien ne dépend d'un raccourci local (`LocalBackend.sim`, `user://` côté sim) et que l'état partagé entre joueurs passe par `Persistence` ; si c'est impossible, note-le au Journal comme dette (lot à créer) ;
   - une capture `client_shot`, **relue** avec l'outil Read ;
   - cocher la ligne « Parité » du lot (☑) en étant honnête. Une case non cochée doit être justifiée dans le Journal.
5. **Mettre à jour la roadmap.**
   - Statut : `set <ID> done` si tout est vérifié, sinon laisser `doing`.
   - Ajouter une ligne au **Journal** : date, lot, ce qui est fait, ce qui reste.
   - Ajouter aux **Découvertes** les pièges, les règles trouvées et les `APPROX`.
   - Créer les nouveaux lots découverts, au bon endroit dans leur phase, avec leurs dépendances.
   - Lancer `python tools/roadmap.py check` et `python tools/rules_sources.py --check`, qui doivent passer.
   - Si une info durable a changé (état global du projet), mettre à jour la mémoire `project-client-architecture`.
6. **Rapport à l'utilisateur**, court et en français :
   - le lot réalisé et comment il a été vérifié (tests, capture) ;
   - les approximations ;
   - le prochain lot proposé (`roadmap.py next`).

## Garde-fous
- Aucune règle de jeu dans `client/`, aucun `Node`/fichier/réseau dans `sim/` ou `shared/`.
- **Toute feature doit fonctionner en mode serveur** (test via `NetBackend`, voir l'étape 4) en plus du standalone.
- Le code doit servir tel quel au standalone et au serveur (voir « Standalone vs serveur » dans `docs/ARCHITECTURE.md`).
- Ne jamais commiter `game/content/`. Pas de `print` par frame.
- Scripts Python avec accents : les écrire avec l'outil Write, puis les lancer avec `PYTHONIOENCODING=utf-8`, jamais via un heredoc.
