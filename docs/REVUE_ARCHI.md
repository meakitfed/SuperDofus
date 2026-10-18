# Revue d'architecture (2026-10-18)

Synthèse de cinq relectures en lecture seule (sim/fight, client, serveur/API, shared/protocole/sim hors combat, performance/tests). Les gains chiffrés sont mesurés quand c'est dit, sinon estimés. Classement par bénéfice / (coût x risque) ; coût S < M < L, risque faible < moyen. Chaque ligne est un lot de la phase R de `docs/ROADMAP.md`.

## Tableau classé

| Rang | Lot | Titre | Coût | Risque | Bénéfice |
|---|---|---|---|---|---|
| 1 | R.06 | IA : mémoïser zones et occupation dans `_best_cast` | S | faible | Hitchs de ~1 s par tour d'IA (mesuré), test_monster_matrix 920 s, test_ai_golden 185 s. |
| 2 | R.07 | Une seule écriture atomique durable (`AtomicFile`) | S | faible | Perte silencieuse de sauvegarde (disque C: presque plein) : `FilePersistence` et `WorldCluster._save` écrivent sans contrôle. |
| 3 | R.08 | Serveur : contre-pression d'envoi et connexions mortes réapées | S | faible | Désynchronisation silencieuse (`send_text` non vérifié, tampon 4 Mo) et personnages/emplacements gardés par des connexions semi-ouvertes. |
| 4 | R.09 | Test global ERROR_CODES / ErrorTexts / constantes E_* (liste calculée par réflexion) | S | faible | Un code d'erreur sans texte donne un toast vide ; 2 listes tenues à la main. |
| 5 | R.10 | Constantes de règles uniques (TTL d'invitation x4 + 2 copies client, MAX_QTY, XP_BASE, MIN_GROUPS) | S | faible | Divergence silencieuse sim/client. |
| 6 | R.11 | Pompes de tests réseau sans `OS.delay_msec(1)` (helper unique dans `zones_rig.gd`) | S | faible | Probablement -50 à -80 s sur la suite complète (à mesurer). |
| 7 | R.12 | Fabrique de combattant/invocation (`Fighter.setup_points`, `Summons._join`) | S | faible | 5 constructions quasi identiques, ~60 lignes en moins. |
| 8 | R.13 | Renommer `distance` en `chebyshev` / `manhattan` et BFS commun dans `fight_rules.gd` | S | faible | Deux métriques de même nom, 40 sites ; deux BFS copiés. |
| 9 | R.14 | `ServerHost._attach` (login/resume/rôle GM) et `LocalServer.advance` (accumulateur de tick) | S | faible | Logique d'attache dupliquée 2 à 4 fois, tick dupliqué. |
| 10 | R.15 | `HttpServer` : plafond par adresse, échéance dure par requête, getter protégé | S | faible | Slowloris sur 256 emplacements. |
| 11 | R.16 | Kit UI : `UiScroll.rows`, `UiTabs.add_rows_tab`, `UiSearch.bar`, `UiRows.refill` ; `npc_name` typé | S | faible | 17 ScrollContainer copiés, métadonnées de PNJ non typées. |
| 12 | R.17 | Client : classe de base `InviteCards` (duel, échange, groupe) | S | faible | 9 blocs dupliqués, ~150 lignes. |
| 13 | R.18 | Client : `SessionMode` unique et aide recalculée au changement | S | faible | Mode dérivé à 4 endroits, travail par frame. |
| 14 | R.19 | Registre `EffectKinds` : une table de handlers au lieu de 8 listes et de deux `match` | M | faible | Ajouter un effet touche 4 à 6 endroits ; oubli silencieux. |
| 15 | R.20 | `fight.gd` : extraire `FightLobby`, `FightTurns` et `Fight._settle` | M | faible | 762/800 lignes, fin de résolution répétée 4 fois. |
| 16 | R.21 | Client : base `SessionWindow` (shop, bank, market, trade, craft, dialog) et table de construction du HUD | M | faible | -150 à -200 lignes, fermeture unique. |
| 17 | R.22 | Découper `fight_rules.gd` : `FightZones`, `FightMovement`, `FightSight` (façade conservée) | M | faible | 597 lignes, quatre responsabilités. |
| 18 | R.23 | `InviteBook` partagé (trade, duel, party, guild) | M | faible | Machinerie d'invitation copiée 4 fois. |
| 19 | R.24 | Schéma : formes imbriquées (`SHAPES`, `dict:actor`, `array:item`) imprimées dans PROTOCOL.md | M | faible | Seule l'enveloppe des messages est validée. |
| 20 | R.25 | Tests : `TEST_SHARD=i/n` et `tools/run_tests_parallel.py` avec garde de couverture | M | faible | Fast tier 272 s -> ~50 s, suite complète ~32 min -> ~5 min (estimations). |
| 21 | R.26 | `CastContext` et pile `Fight.ctx` (source de lancer imbriquée) ; corrige glyphe + piège | M | moyen | Bug réel : `hit_source`/`aura_tag` remis à zéro par un piège. Test de régression requis. |
| 22 | R.27 | `LifeLoss.lose` : un seul chemin de perte de PV ; corrige invulnérable sur poussée et reflect | M | moyen | Trois formes de l'événement `damage`. Journal + test de régression. |
| 23 | R.28 | Cache snap et cellule -> combattants par lancer (dépend de R.26) | M | faible | Allocations par lancer. |
| 24 | R.29 | Tests : cache partagé des parties de monstres entre matrice et ai_golden | M | moyen | -185 s sur la suite complète. |
| 25 | R.30 | Tests : arène de sort clonée par classe au lieu de reconstruite | M | moyen | 70 % des 152 s de `test_spell_contracts`. |
| 26 | R.31 | Commit multi-documents atomique (journal) dans `ServerPersistence` | M | moyen | Duplication/perte d'objet à l'échange après crash. |
| 27 | R.32 | Autosave étalé (budget par tick, JSON compact) | S | moyen | Gel de ~0,85 s pour 500 joueurs. |
| 28 | R.33 | `WorldAssets` : modes explicites, mémo par carte, JSON invalide signalé, découpe `WorldZoner` | M | moyen | Stats fausses en mode zone, relectures O(profondeur x cartes). |
| 29 | R.34 | Découper `ServerHost` : `ConnectionGuard` et `LoginFlow` | M | moyen | 582 lignes, trois responsabilités. |
| 30 | R.35 | Client : `EventRouter` par domaine pour `ClientSession._dispatch` (+ R.03) | M | moyen | 799/800 lignes. |
| 31 | R.36 | Client : `SessionContext` et `EventQueue` (fin des accès `_s._xxx`) | M | moyen | 28 accès aux champs privés. |
| 32 | R.37 | Table de routage des commandes (politiques dans le SCHEMA) ; d'abord tests de couverture C2S/S2C | M | moyen | Un message sans handler échoue en test, pas en production. |
| 33 | R.38 | Données en dur -> `spells.py` (`stack_group`) et `spell_mod` typés (`SpellMods`) | M | moyen | `SHARED_STACK` casse en silence à une mise à jour de données. |
| 34 | R.39 | IA : consommer `FightEffects.preview_targets` et `FightLife.estimate` (change l'IA, goldens à relire) | M | moyen | L'IA réimplémente ciblage et dégâts. |
| 35 | R.40 | Protocole : SCHEMA source unique, constructeurs minces générés | L | moyen | Triple saisie constante/SCHEMA/constructeur. |
| 36 | R.41 | Client : `FightState` et `FightOverlays` hors de `FightView` | L | moyen | 796/800 lignes. |
| 37 | R.42 | Client : `WindowManager` à la place des statiques de `UiWindow` | M | moyen | État global qui fuit entre tests. |
| 38 | R.43 | Tests : rigs partagés `NetRig` / `LocalRig` | L | faible | 133 blocs de mise en place dupliqués. |

R.03 (alléger `client_session.gd` / `fight_view.gd`) existait déjà ; il est recoupé par R.35, R.36 et R.41.

## Détail des trois premiers

### R.06 IA : mémoïser zones et occupation dans `_best_cast`
- Coût S, risque faible.
- Bénéfice : Hitchs de ~1 s par tour d'IA (mesuré), test_monster_matrix 920 s, test_ai_golden 185 s.
- Travail : `fight_ai.gd` (`_best_cast`, `_score`) : table cellule -> combattant construite une fois par action (remplace `fighter_at`/`hidden`), mémo de `zone_in` par (aire, cellule, from) partagé entre les effets d'un sort, saut des couples (from, cellule) sans combattant dans la zone. Résultat strictement identique.
- Protection : golden `ai_*.json` et `matrix.json` inchangés, `test_ai_golden`, `test_monster_matrix` (TEST_TIER=fast), `test_matrix_net`. Mesure avant/après notée au Journal (pire cas dofus:3373 et dofus:7828).

### R.07 Une seule écriture atomique durable (`AtomicFile`)
- Coût S, risque faible.
- Bénéfice : Perte silencieuse de sauvegarde (disque C: presque plein) : `FilePersistence` et `WorldCluster._save` écrivent sans contrôle.
- Travail : Remonter `_write_atomic` de `ServerPersistence` dans une fonction statique `AtomicFile.write_json(path, data) -> bool` (tmp, flush, relecture, rename vérifié, `failed_writes`, `push_error`) ; utilisée par `FilePersistence._raw_write`, `ServerPersistence` et `WorldCluster._save` (`instances.json`). Exposer `failed_writes` dans `admin.metrics`. Mêmes fichiers produits.
- Protection : `test_server_persistence`, `test_characters`, `test_cluster`, `test_instances`, `test_admin` ; nouveau cas : écriture vers un chemin impossible renvoie false et incrémente `failed_writes` ; ajouter le fichier de test à `baseline.json` s'il est nouveau.

### R.08 Serveur : contre-pression d'envoi et connexions mortes réapées
- Coût S, risque faible.
- Bénéfice : Désynchronisation silencieuse (`send_text` non vérifié, tampon 4 Mo) et personnages/emplacements gardés par des connexions semi-ouvertes.
- Travail : `server_host.gd` : `_send` vérifie le code de `send_text` et `get_current_outbound_buffered_amount()` (seuil 1 Mo), ferme en 4002 et passe par `_drop` (session parquée, reprise possible) ; `_read` ferme en 4000 après `dead_ms` (45 s) sans réception et en 1008 après `login_deadline_ms` (30 s) sans login ; `NetBackend._flush_out` ne vide `_out` qu'après un envoi OK. Valeurs réglables comme `idle_ms`. Comportement nominal inchangé.
- Protection : `test_net`, `test_resume`, `test_accounts`, `test_security` + nouveaux cas NetBackend 127.0.0.1 (client qui ne lit pas, client muet) ; horloge `ticks` injectable.

## Remarques de classement

- R.26 et R.27 corrigent de vrais comportements (source de lancer d'un glyphe écrasée par un piège ; invulnérabilité ignorée sur poussée et reflect) : ils ne sont donc pas à comportement strictement constant, chacun exige une ligne au Journal et un test de régression. Risque moyen, bénéfice élevé : placés juste après les lots sûrs.
- R.39 change volontairement l'IA des monstres : goldens `ai_*.json` à relire une fois.
- R.28 dépend de R.26. R.20 est préférable avant tout lot de combat, `fight.gd` étant à 762/800 lignes ; de même `client_session.gd` (799) et `fight_view.gd` (796) : R.35/R.41 avant le prochain lot qui y touche.
- Ne pas paralléliser les tests réseau ou fichiers sans isoler `user://` et les ports (R.25 : `test_accounts` a échoué lors de deux runs simultanés, cause non vérifiée).

## Chiffres de profilage

Machine à 20 coeurs, plusieurs processus Godot simultanés (temps absolus plutôt pessimistes).

| Mesure | Valeur |
|---|---|
| Taille du code | src 39 409 lignes (shared 6 045, sim 11 401, client 16 771, api 805, server 4 387) ; tests 27 209 (126 fichiers, 1 016 tests) ; tools 3 218 |
| Tier fast | 272 s : `test_spell_contracts` 155,6 s (57 %), `test_monster_matrix` 72,4 s (27 %), `test_spell_golden` 21,1 s, scénarios 2 x 6,4 s |
| Suite complète (estimée ~32 min) | matrice 917-920 s pour 1 343 parties, contrats 152 s, `test_ai_golden` 185,5 s, golden ~21 s, scénarios ~13 s, 85 autres fichiers 539 s (le run s'est arrêté sans récapitulatif) |
| IA | 15 ms par action, 38 ms par tour en moyenne ; pire cas ~1 s par tour (dofus:3373 : 987 ms, dofus:7828 : 1 042 ms) ; `_score` 650 us par appel contre 150 us pour un `zone_in` ; soigneurs 607 ms par partie de 6 tours contre 20 ms pour les passifs ; ~150 combats IA simultanés par coeur en temps réel |
| Arène de sort | `SpellArena.new` 2,19 ms ; 7 197 grades, 22 336 effets, des dizaines de milliers d'arènes ; `test_whole_spells` 37,4 s |
| Sauvegarde | `save_character` 1,7 ms par personnage (200 objets) : 500 joueurs ~0,85 s de gel à chaque autosave |
| Timer Windows | `OS.delay_msec(1)` = 1,97 ms, `delay_usec(100)` = 1,96 ms ; `test_content_zones` 61,7 s, `test_content_api` 24,9 s |
| Fonctions longues | 53 fonctions > 50 lignes, 7 > 80 (`fight_hud.setup` 102, `content_publisher.publish_built` 91, `server_app._ready` 86, `FightEffects._apply_spell` 83, `craft_window.setup_window` 83) |
| Doublons (fenêtres de 8 lignes) | src/client 16 blocs, sim 2, shared 3, server 0 ; tests 133 |

Les gains annoncés (IA 3 à 5x, arène 2 à 3x, sharding) sont des estimations à confirmer après chaque lot.
