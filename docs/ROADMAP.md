# Roadmap SuperDofus : recréer tout Dofus, lot par lot

Ce fichier est le **plan vivant** du projet. Chaque session Claude y prend un lot, le réalise, le vérifie, puis met à jour ce fichier. Le mode d'emploi est la commande `/suite`, décrite dans `.claude/commands/suite.md`.

Il ne garde que le travail restant : les lots faits et l'ancien Journal sont dans `docs/ROADMAP_ARCHIVE.md` (lus par `roadmap.py`), les Découvertes dans `docs/DECOUVERTES.md`.

```bash
python tools/roadmap.py status        # avancement par phase
python tools/roadmap.py next          # prochain lot faisable (dépendances faites)
python tools/roadmap.py show P1.05    # détail d'un lot (aussi archivé)
python tools/roadmap.py set P1.05 doing # statut : todo, doing, done, dropped
python tools/roadmap.py check         # format, IDs uniques, dépendances valides
python tools/roadmap.py archive       # lots faits + vieux Journal -> ROADMAP_ARCHIVE.md (fin de lot)
```

## Principes (à relire avant chaque lot)

1. **Une seule logique de jeu.** Toutes les règles vont dans `game/src/sim/` et `game/src/shared/` : combat, IA, XP, craft, quêtes, HDV, échanges, guildes. Le mode standalone (`LocalBackend`) et le serveur (`game/src/server/`, `NetBackend`) exécutent **le même code**. Le serveur n'ajoute que :
   - le réseau ;
   - les comptes et les sessions ;
   - la base de données ;
   - la sécurité ;
   - l'administration.

   Voir la section « Standalone vs serveur » de `docs/ARCHITECTURE.md`.
2. **Les bonnes règles, et sourcées.** Chaque règle cite sa source dans le code : une formule `luaformulas`, une table de données Dofus 3, ou une documentation communautaire avec le lien. Une approximation est marquée `APPROX` dans le code et listée dans « Découvertes ».
3. **Données réelles d'abord.** On extrait les tables Dofus 3 (`tools/extractor/`) au lieu de recopier des valeurs à la main. Les assets vont dans `game/content/`, qu'on ne commite **jamais**. Tout se fait en `--webp`, en vérifiant l'espace disque avant.
4. **Le client affiche, la sim décide.** Le client ne contient aucune règle : il envoie des commandes et anime des événements. L'UI peut différer de Dofus, mais elle doit permettre **tout** ce que Dofus permet, et être aussi belle. Elle réutilise le kit d'UI (P0.06) et les vraies textures et polices.
5. **Tout est testé en headless.** Chaque mécanique a :
   - un test de scénario via `LocalBackend` (`tests/`) ;
   - une trace `sim_cli` ;
   - une capture `client_shot` relue.
6. **Un lot tient en une session.** Si un lot grossit, on le découpe (P1.05 → P1.05a, P1.05b) plutôt que de le laisser à moitié fait.

## Format d'un lot

```
### [ ] P1.05 Titre
- Dépend : P0.03, P1.02            (ou « — »)
- Données : tables Dofus 3 à extraire ou utiliser
- Règles : ce qu'il faut reproduire exactement (formules, cas limites)
- Commun : ce qui va dans sim/ + shared/  |  Serveur : ce qui sera propre au serveur
- Protocole : commandes et événements
- Client : écrans et interactions
- Tests : scénarios attendus
- Parité : ☑ règles sourcées (sans objet : aucune règle) ☑ tests ☑ sim_cli ☑ capture ☑ doc
```

Statuts : `[ ]` à faire, `[~]` en cours, `[x]` fait, `[-]` abandonné (raison dans le Journal).

---

## H — Harnais anti-régression (priorité 1)

Le code est écrit uniquement par IA : le harnais garantit que **chaque sort et chaque monstre fonctionne** et qu'aucune régression ne passe. Il réutilise l'existant (`tests/test_spell_contracts.gd` : 3 990 grades vérifiés effet par effet dans `SpellArena`, `SpellGaps`, `test_spell_cases.gd`, `TestCase.sub()` + `TEST_CASE=`, scénarios `tests/scenarios/*.jsonl`) et ajoute : un golden par sort, une matrice par monstre, un garde-fou de couverture, des tests paramétrés (un même combat, des attendus différents par sort ou par famille de monstres).

Plan complet : `C:\Users\natha\.claude\plans\re-facto-le-mega-snug-peacock.md` (copie des décisions ci-dessous).

**Ordre d'exécution (les dépendances le font respecter)** : R.04, H.01, P1.18b (1 à 2 : Runification, Estoc Brûlant, fumée du sort entier), H.02, H.03, H.04, H.05, P1.17b, P1.14, H.06. Suite complète (> 30 min) une seule fois, à la fin de H.06.

**Tri de la roadmap (2026-10-17)** :
- *Gardés en tête* : P1.14, P1.17b, P1.18b (cœur du combat, alimentent le harnais), R.04.
- *Clos* : P1.15 (code, tests, scénario et capture déjà faits ; la dépendance sur P1.14 est relâchée, comme pour P3.04a).
- *Bloqué utilisateur* : C.02h (mesure à deux postes via Hamachi), en bas du fichier.
- *Reportés (utiles, pas urgents)* : P2.09 à P2.14, P3.06 à P3.10, P4.x, A1.02b, G.01, P3.02b (ils restent plus bas dans le fichier, après P2.03b / P2.05c).
- *Cosmétique en dernier* : P5.x et R.03.

### [ ] P1.18e Tests des sorts : reste du menage et écarts sans source
- Dépend : P1.18d
- Données : `spells.json`, descriptions FR (`tools/i18n_lookup.py`)
- Règles :
  1. Ménage : migrer vers `SpellArena` (`layout` en paramètre) les `Arena` restants : `test_ai_profiles`, `test_challenges`, `test_formulas` (ne démarre pas le combat), `test_rates`, `test_target_mask`, `test_trigger_codes` (sa méthode `cast` heurte `SpellArena.cast`), `test_zone_decrease`, `test_zone_options`, le `Duel` de `test_fight`
  2. À trancher : Mot Vampirique transfère 2 × 8 % et Détonateur rend 2 PA sur une bombe ; Bambouseraie et Pavois (sous-sort 1077480) : un effet `summon` avec `replaces` + `cond` sur un monstre est traité comme une invocation au centre, pas comme un remplacement des créatures de la zone ; les 29 grades de `SpellGaps` (codes DV / CI / CT / DI sans source, Runes élémentaires 4258-4261 absentes des données, horloge de Synchro)
  3. Compléter les classes 1, 2, 6, 7, 8, 9 à 6 cas si utile
- Commun : `FightEffects` | Serveur : —
- Protocole : —
- Client : —
- Tests : suite complète verte
- Parité : ☐ règles sourcées ☐ tests ☐ sim_cli ☐ capture ☐ doc

### [ ] H.04d Matrice des monstres : les 62 monstres de `MonsterGaps`
- Dépend : H.04c
- Données : `tests/monsters/monster_gaps.gd` (62 monstres qui ne tiennent pas la promesse de leur famille dans les 6 tours du mannequin standard)
- Règles : étudier chaque cause (état ou condition que la partie standard ne pose pas, sort joué en partie, choix d'IA) : source réelle ou `APPROX(H.04d)` documenté ; sortir le monstre de la liste
- Commun : `MonsterGaps`, `FightAi` | Serveur : —
- Tests : `MonsterGaps` vidé, golden de la matrice et `ai_*.json` régénérés, diff relu
- Parité : ☐ règles sourcées ☐ tests ☐ sim_cli ☐ capture ☐ doc

### [ ] H.04e Sorts des monstres : effets `partial` restants
- Dépend : H.04c
- Données : 244 grades `partial` (effets 105, 136, 276, 1133, 1134, 1077, 88, 140, 277, 240-243…) laissés hors de `spells.json` par `spells.py` (`--world …+dofus`) ; 5 666 des 20 596 références de sorts sont encore `spells_absent` dans le golden de la matrice (573 monstres)
- Règles : simuler ces effets (sourcés), puis retirer le filtre de `spells.py`
- Commun : `spells.py` | Serveur : —
- Tests : `spells_absent` à 0 dans le golden ; temps de `TEST_TIER=fast` (matrice ~7 min seule) à ramener sous 5 min
- Parité : ☐ règles sourcées ☐ tests ☐ sim_cli ☐ capture ☐ doc

---

## M — Multijoueur : un serveur sur ta machine, des amis par Hamachi

Plan complet : `docs/PLAN_SERVEUR.md` (validé). Phase presque finie (2026-10-12) : M1, M2 et M3 sont faits, restent C.02h (mesure à deux postes, bloqué utilisateur), A1.02b et G.01 (reportés) ; les lots de contenu ont repris.

Ordre d'exécution (c'est aussi l'ordre du fichier, donc celui de `roadmap.py next`) :
- **M1 « on se voit et on bouge ensemble »** : S.01, P3.01, S.02a, C.01, C.02, C.02b, C.03, X.01.
- **M2 « on joue ensemble »** : P3.02a, P3.03a, P3.03b, P3.04a, P3.04b, S.02b, S.02c, A1.01a, A1.01b.
- **M3 « on peut le laisser tourner »** : S.03, A1.02, S.04, S.05a, S.05b, S.05c, S.06, S.07.
- **G.01** (étude moteur multi-jeux) après M1.

Les lots de cette phase gardent leur identifiant d'origine (S.xx, P3.xx) : `roadmap.py status` les compte donc dans S et P3, pas dans « M ». Les nouveaux lots portent les préfixes C (contenu), X (export), A1 (admin : « A » est pris par les lots Acquis, d'où A1.01 et A1.02)  et G (moteur multi-jeux).

Règles propres à M (en plus des principes ci-dessus) :
1. **Le moteur doit pouvoir servir un autre jeu que Dofus.** Rien de spécifique à Dofus dans le code de session, réseau, comptes, contenu et admin : ni identifiant de classe, ni chemin `dofus`, ni table Dofus. Le nom d'un monde est une donnée (`worlds/<id>/`), le jeu qu'il utilise s'appelle son *module* (`world.json` : `module: "dofus"`, lu mais pas encore exploité : voir G.01).
2. **Le serveur n'ajoute aucune règle** : il héberge `sim/` (principe 1). Le client ne parle qu'au `GameBackend` : `NetBackend` remplace `LocalBackend` sans que le client le sache.
3. **Deux ports TCP, tous deux sur l'interface Hamachi** (choix, note S.01) : jeu en WebSocket JSON (défaut 7777) et contenu / admin en HTTP (défaut 7778 ; l'admin web utilise aussi ce port, avec un jeton admin). Pas de TLS : le tunnel Hamachi chiffre déjà le trafic, et le serveur n'est jamais exposé publiquement.
4. **Contenu : jamais d'URL publique.** Le serveur n'envoie que les fichiers listés dans le manifeste, uniquement avec un jeton de session valide (C.02, S.05). C'est une décision de redistribution qui reste ouverte (`docs/PLAN_SERVEUR.md`, « Droits »).
5. Tout se teste d'abord en local (`NetBackend` sur 127.0.0.1, plusieurs clients scriptés), jamais seulement à la main.
6. Le code réseau est un hôte : il va dans `game/src/server/` (nouveau, comme `api/`) et `game/src/api/net_backend.gd`. `shared/` et `sim/` n'en savent rien ; `client/` ne l'utilise que par `GameBackend`. `tests/test_architecture.gd` est étendu en S.01.

### [ ] P3.02d Chat : alliance
- Dépend : P3.02c, P3.07
- Règles : canal alliance `/a` (aujourd'hui `channel_unavailable` ; le canal guilde `/g` est fait en P3.06a)
- Tests : routage par guilde et alliance (Local + Net)
- Parité : ☐ règles sourcées ☐ tests ☐ sim_cli ☐ capture ☐ doc

### [ ] A1.02b Admin web : debug, mondes et contenu
- Dépend : A1.02a
- Données : —
- Règles :
  - **Debug** : suivre un combat en direct, derniers événements d'un joueur, journal d'erreurs, forcer un respawn.
  - **Mondes et contenu** : reconstruire le paquet de contenu et voir quels clients sont à jour, restauration d'une sauvegarde (copies tournantes de S.03), arrêt programmé ; créer / démarrer / arrêter un monde (lecture seule tant que S.04 n'est pas fait).
  - Fiche d'un joueur : historique de ses commandes d'audit ; actions sur un joueur hors ligne (give, kamas, level) en passant par sa sauvegarde.
- Commun : — | Serveur : `game/src/server/admin/`
- Protocole : — (HTTP JSON : `/admin/...`)
- Client : — (page web)
- Tests : chaque action modifie l'état et laisse une ligne d'audit
- Parité : ☐ règles sourcées ☐ tests ☐ sim_cli ☐ capture ☐ doc

### [ ] G.01 Étude : moteur multi-jeux (sans code)
- Dépend : X.01
- Données : —
- Règles :
  - lister ce qui est **générique** (sessions, comptes, réseau, persistance, contenu par monde, admin, protocole générique) et ce qui est **propre à Dofus** (`sim/` : sorts, effets, géométrie 14×20, critères ; rendu `dofus_renderer`), à partir de ce que M1 a montré (où la frontière a gêné) ;
  - définir l'interface d'un **module de jeu** (règles, rendu, données, messages propres) et le champ `module` d'un paquet de monde ;
  - dire ce qu'il faudrait pour un second jeu minimal (un monde de test sans Dofus) et le coût d'un déplacement de dossiers ;
  - livrable : `docs/MODULES.md` (étude) et, si utile, de nouveaux lots dans cette roadmap.
- Commun : — | Serveur : —
- Protocole : —
- Client : —
- Tests : aucun (étude) ; `roadmap.py check` passe
- Parité : ☐ règles sourcées ☐ tests ☐ sim_cli ☐ capture ☐ doc

---

## U — Interface : audit et refonte (docs/ui/)

Recherches : `docs/ui/AUDIT_UI.md` (défauts mesurés), `docs/ui/DOFUS_UI.md` (ce que fait le vrai client), `docs/ui/ADAPTATIF.md` (échelle, zone de jeu, fenêtres).

### [ ] U.10 Personnages cachés par un décor, écran d'options
- Dépend : U.09
- Règles : un combattant derrière un décor doit rester lisible (silhouette ou contour via le kit, APPROX) ; écran d'options (taille de l'interface, marge, réinitialiser les fenêtres, opacité du chat), flou `MapFrame` proportionnel à l'échelle : `ADAPTATIF.md` 2.3, 2.7, §6.4-5.
- Tests : test_game_area étendu, captures à 4 tailles
- Parité : ☐ tests ☐ capture ☐ doc

## P1 — Boucle de jeu de base (jouer seul, de la création au niveau 50)

---

## P2 — Économie et progression

### [ ] P2.03d Quêtes, reste : départs sans PNJ, sorts sur la barre, formules, dialogues
- Dépend : P2.03c
- Données : `quests` sans `startPosition` (« Mort au rat » 1633 : démarrées par un objet / un niveau / une alerte), `queststeps.dialogId`. Les types d'objectifs 10, 11, 12, 13, 15 n'existent dans aucune quête du monde `dofus` (vérifié : seuls 0-6, 9, 14, 16, 17 y sont) : rien à faire tant qu'ils n'apparaissent pas.
- Règles :
  - démarrage des quêtes sans PNJ de départ (source à trouver : JondoEmu, notifications du client) ;
  - sorts de quête sur la barre (aujourd'hui castables mais hors `spell_bar`) ;
  - formules d'XP et de kamas des récompenses sourcées (aujourd'hui `QuestEngine.XP_SHARE` / `KAMAS_PER_LEVEL`, APPROX) ;
  - dialogues des étapes (serveur) : lire les captures JondoEmu `npc_dialogos_*` si elles existent.
- Commun : `QuestEngine` | Serveur : —
- Protocole : —
- Client : liste des émotes / titres reçus (P4.03)
- Tests : un test par type d'objectif ajouté
- Parité : ☐ règles sourcées ☐ tests ☐ sim_cli ☐ capture ☐ doc

### [-] P2.05d Métiers, partie 1d : sources manquantes
- Dépend : P2.05c
- FERME (2026-10-17) : recherche faite dans JondoEmu `datos` (recursos, interactive_elements, proto, world.zip) et `tools/client_code` : aucune table d'XP de metier, duree, repousse ni bonus. Les APPROX(P2.05) de `shared/jobs.gd` restent documentes ; a rouvrir si une source apparait.
- Données : table d'XP des métiers, durée de récolte, repousse, quantité, ressources bonus : aucune source (ni tables du client, ni JondoEmu `datos` ; le client natif ne fait qu'afficher les paliers que lui envoie le serveur). Icônes de métier (`jobs.iconId`) et curseurs (`skills.cursor`) absents du contenu extrait.
- Règles : ressources bonus (APPROX : aucune) ; remplacer chaque APPROX(P2.05) de `shared/jobs.gd` dès qu'une source apparaît
- Client : icônes de métier, vrais curseurs (extraction `--webp`), ressource masquée par un tronc / une souche si le gfx existe
- Tests : bonus
- Parité : ☐ règles sourcées ☐ tests ☐ sim_cli ☐ capture ☐ doc

### [-] P2.09 Échange entre joueurs
- Dépend : P3.01, P1.05, X.01
- Données : —
- Règles :
  - demande et acceptation ;
  - une double validation qui se réinitialise à chaque modification ;
  - un transfert atomique.
- Commun : `Exchange` | Serveur : transaction en base
- Protocole : `exchange_request`, `exchange_update`, `exchange_ready`, `exchange_done`
- Client : fenêtre d'échange
- Tests : échange réussi ; modification qui annule la validation ; déconnexion en cours d'échange
- Parité : ☐ règles sourcées ☐ tests ☐ sim_cli ☐ capture ☐ doc

### [ ] P2.11 Mode marchand
- Dépend : P2.10a, P3.01, X.01
- Données : —
- Règles : le personnage reste sur la map hors ligne comme marchand ; taxe ; limite par map
- Commun : `MerchantActor` | Serveur : persiste après la déconnexion
- Protocole : `merchant_start`, `merchant_view`, `merchant_buy`
- Client : fenêtre du marchand
- Tests : achat auprès d'un marchand hors ligne
- Parité : ☐ règles sourcées ☐ tests ☐ sim_cli ☐ capture ☐ doc

### [ ] P2.12c Almanax et succès aux clés non suivies
- Dépend : P2.12b
- Données : `almanaxcalendars`, `almanaxcategories`, `almanaxzodiacs` ; les 2055 succès dont les clés ne sont pas suivies (EB montures, Ef / EH challenges, HD captures, Sc…)
- Règles : quête almanax du jour (`dates` "21/09/*", `objectiveId`, bonus) ; événements manquants pour les clés ci-dessus à mesure que leurs mécaniques arrivent (Ef / EH : challenges de P1.15) ; `accountLinked`
- Client : fenêtre almanax (date, bonus, offrande)
- Tests : quête almanax du jour via Local et Net
- Parité : ☐ règles sourcées ☐ tests ☐ sim_cli ☐ capture ☐ doc

### [ ] P2.13 Familiers et montiliers
- Dépend : P1.06, X.01
- Données : `pets` (repas, bonus)
- Règles : nourrir, gain de caractéristiques, bonus max, mort / fantôme de familier (si c'est encore le cas en Dofus 3)
- Commun : `Pet` | Serveur : —
- Protocole : `pet_feed`
- Client : familier qui suit le joueur, fenêtre du familier
- Tests : repas qui donne un bonus, bonus plafonné
- Parité : ☐ règles sourcées ☐ tests ☐ sim_cli ☐ capture ☐ doc

### [ ] P2.14 Montures
- Dépend : P2.13, P4.05, X.01
- Données : `mounts`, `mountbones`, familles
- Règles : monter et descendre, XP partagée, énergie, élevage (enclos, objets d'élevage), reproduction (à sourcer)
- Commun : `Mount`, `Breeding` | Serveur : l'état des enclos
- Protocole : `mount_ride`, `mount_xp_share`, `paddock_*`
- Client : personnage monté, fiche de monture
- Tests : bonus de monture, XP partagée
- Parité : ☐ règles sourcées ☐ tests ☐ sim_cli ☐ capture ☐ doc

---

## P3 — Social et multijoueur

Chaque lot se teste d'abord en standalone, avec **plusieurs clients sur un même `WorldSim`** (bots scriptés), puis via le serveur.

> P3.01 à P3.04 (plusieurs joueurs, chat, groupes, combats à plusieurs) sont dans la phase **M** (jalons M1 et M2).

### [ ] P3.06b Guildes : fenêtre, niveau et XP donnée
- Dépend : P3.06a
- Données : `guildlevelrewards`, `emblemsymbols` (icônes), textes i18n des rangs et droits
- Règles : XP de guilde donnée en pourcentage par chaque membre, niveau de guilde ; droits message / infos / notes / recrutement appliqués ; objet guildalogemme consommé à la création
- Protocole : `guild_xp_rate`, `guild_message`, XP et niveau dans `guild_info`
- Client : fenêtre de guilde (membres, rangs, droits, emblème), onglet /g du chat, création
- Tests : XP donnée, niveau, fenêtre (Local + Net), capture `client_shot` relue
- Parité : ☐ règles sourcées ☐ tests ☐ sim_cli ☐ capture ☐ doc

### [ ] P3.06c Percepteurs
- Dépend : P3.06b, P3.04a
- Données : à étudier (`taxcollector*`)
- Règles : pose d'un percepteur, combat contre lui, butin (lot à détailler)
- Commun : `TaxCollector` via `Persistence` | Serveur : —
- Protocole : `taxcollector_*`
- Client : liste des percepteurs de la guilde
- Tests : pose, attaque, butin (Local + Net)
- Parité : ☐ règles sourcées ☐ tests ☐ sim_cli ☐ capture ☐ doc

### [ ] P3.07 Alliances, prismes, AvA
- Dépend : P3.06b, P3.08
- Données : sous-zones conquérables
- Règles : alliance de guildes, prismes, vulnérabilité, combats AvA
- Commun : `Alliance`, `Conquest` | Serveur : horaires
- Protocole : `alliance_*`, `prism_*`
- Client : fenêtre d'alliance, carte de conquête
- Tests : prise d'une sous-zone
- Parité : ☐ règles sourcées ☐ tests ☐ sim_cli ☐ capture ☐ doc

### [ ] P3.08 Alignement et PvP
- Dépend : P3.04a
- Données : `alignment*` (grades, ordres)
- Règles :
  - Bontarien, Brâkmarien, neutre ;
  - ailes activées ;
  - agression, avec une différence de niveau autorisée ;
  - points d'honneur et grades.
- Commun : `Alignment` | Serveur : —
- Protocole : `align_set`, `pvp_toggle`, `aggress{target}`
- Client : ailes sur le look, fenêtre d'alignement
- Tests : agression valide ou refusée, gain d'honneur
- Parité : ☐ règles sourcées ☐ tests ☐ sim_cli ☐ capture ☐ doc

### [ ] P3.09 Kolizéum
- Dépend : P3.04a
- Données : cartes d'arène
- Règles : file d'attente 3v3, matchmaking par cote, récompenses (kolizetons), pénalité d'abandon
- Commun : `ArenaQueue` (tourne dans la sim, testable avec des bots) | Serveur : matchmaking inter-joueurs
- Protocole : `arena_register`, `arena_found`, `arena_accept`
- Client : fenêtre du Kolizéum
- Tests : 6 bots mis en file, match lancé, cote mise à jour
- Parité : ☐ règles sourcées ☐ tests ☐ sim_cli ☐ capture ☐ doc

---

## P4 — Contenu et monde vivant

### [ ] P4.02 Archimonstres et bestiaire
- Dépend : P1.09
- Données : `monsters` (isArchMonster, correspondance)
- Règles : un archimonstre remplace rarement un monstre du groupe (à sourcer) ; capture ; bestiaire (vus, vaincus)
- Commun : `Bestiary` | Serveur : —
- Protocole : `bestiary`
- Client : fenêtre du bestiaire (fiches, drops, zones)
- Tests : bestiaire mis à jour après un combat
- Parité : ☐ règles sourcées ☐ tests ☐ sim_cli ☐ capture ☐ doc

### [ ] P4.03 Titres, ornements, émotes et attitudes
- Dépend : P2.12b
- Données : `titles`, `ornaments`, `emoticons`
- Règles : débloqués par les succès, les quêtes et la boutique ; un seul actif à la fois
- Commun : `Cosmetics` | Serveur : —
- Protocole : `emote{id}`, `title_set`, `actor_emote`
- Client : roue ou barre d'émotes, titre sous le nom
- Tests : émote diffusée aux autres, titre non débloqué refusé
- Parité : ☐ règles sourcées ☐ tests ☐ sim_cli ☐ capture ☐ doc

### [ ] P4.04 Havre-sac
- Dépend : P1.08
- Données : maps de havre-sac, thèmes
- Règles : entrée et sortie depuis n'importe quelle map extérieure, instance personnelle, invitations
- Commun : `HavenBag` (map instanciée) | Serveur : instances
- Protocole : `havenbag_enter`, `havenbag_exit`
- Client : bouton du havre-sac
- Tests : entrer, puis ressortir sur la map d'origine
- Parité : ☐ règles sourcées ☐ tests ☐ sim_cli ☐ capture ☐ doc

### [ ] P4.05 Maisons et enclos
- Dépend : P2.10a, P3.06b
- Données : `houses`, `paddocks`
- Règles : achat, coffre, code, droits de guilde, enclos publics et privés
- Commun : `Housing` via `Persistence` | Serveur : propriété globale
- Protocole : `house_*`, `paddock_*`
- Client : fenêtres d'achat et de gestion
- Tests : achat, code, accès refusé
- Parité : ☐ règles sourcées ☐ tests ☐ sim_cli ☐ capture ☐ doc

### [ ] P4.06 Événements et contenu saisonnier
- Dépend : P2.03
- Données : quêtes et monstres d'événement
- Règles : activation par date
- Commun : `Events` (`Clock`) | Serveur : calendrier
- Protocole : —
- Client : bannière d'événement
- Tests : un événement actif à une date donnée
- Parité : ☐ règles sourcées ☐ tests ☐ sim_cli ☐ capture ☐ doc

### [ ] P4.07 Extension du monde : Astrub, puis les régions suivantes
- Dépend : P1.07, P1.09
- Données : maps par région (extraction région par région, en vérifiant l'espace disque)
- Règles : le monde est cohérent (voisins, PNJ, monstres, ressources) ; une région à la fois ; les zaapis d'Astrub (limités à leur ville, reportés de P1.08 : pas de zaapi dans Incarnam) ; les zaaps de la région (cellules dans `links.json`)
- Commun : — | Serveur : —
- Protocole : —
- Client : —
- Tests : parcours sans cul-de-sac, monstres présents
- Parité : ☐ règles sourcées ☐ tests ☐ sim_cli ☐ capture ☐ doc
- Note : ce lot est répétable. On le duplique en P4.07a, P4.07b… une région par lot.

---

## P5 — Finition visuelle et sonore

### [ ] P5.01 Sons et musiques
- Dépend : P0.03
- Données : `soundbones`, bundles audio, ambiances des sous-zones
- Règles : musique par sous-zone, sons de sorts, pas, interface, volumes séparés
- Commun : événements sonores déduits des événements existants (aucune règle) | Serveur : —
- Protocole : —
- Client : `client/audio/`
- Tests : un `client_shot` sans erreur audio ; les mappings sont testés
- Parité : ☐ règles sourcées ☐ tests ☐ sim_cli ☐ capture ☐ doc

### [ ] P5.02 Animations de map
- Dépend : A.02
- Données : shaders de map, particules, eau, éléments animés
- Règles : identiques au client d'origine (golden quand c'est possible)
- Commun : — | Serveur : —
- Protocole : —
- Client : `dofus_renderer/map`
- Tests : golden ou capture
- Parité : ☐ règles sourcées ☐ tests ☐ sim_cli ☐ capture ☐ doc

### [ ] P5.03 Fidélité de l'UI
- Dépend : P0.06
- Données : layouts UI Toolkit (décoder les USS `StylePropertyId`)
- Règles : pas besoin d'être identique ; l'objectif est « aussi beau », avec des captures de référence fournies par l'utilisateur
- Commun : — | Serveur : —
- Protocole : —
- Client : thème affiné, animations d'ouverture des fenêtres
- Tests : captures comparées
- Parité : ☐ règles sourcées ☐ tests ☐ sim_cli ☐ capture ☐ doc

### [ ] P5.04 Options et raccourcis
- Dépend : P0.06
- Données : —
- Règles : graphismes, son, interface, raccourcis reconfigurables, tout sauvegardé en local (hors sim)
- Commun : — | Serveur : —
- Protocole : —
- Client : fenêtre d'options
- Tests : les options persistent
- Parité : ☐ règles sourcées ☐ tests ☐ sim_cli ☐ capture ☐ doc

### [ ] P5.05 Attitudes, transitions, confort
- Dépend : P4.03
- Données : animations d'attitude
- Règles : transitions de map en fondu, personnage assis, clic-maintenu pour courir, surbrillance des interactifs
- Commun : — | Serveur : —
- Protocole : —
- Client : animations et effets
- Tests : captures
- Parité : ☐ règles sourcées ☐ tests ☐ sim_cli ☐ capture ☐ doc

### [ ] P5.06 Zoom, accessibilité, performance
- Dépend : P5.03
- Données : —
- Règles : zoom sur la map, échelle d'UI, 60 fps avec 8 joueurs et une map chargée
- Commun : — | Serveur : —
- Protocole : —
- Client : caméra, profilage
- Tests : mesure du temps de frame dans `client_shot`
- Parité : ☐ règles sourcées ☐ tests ☐ sim_cli ☐ capture ☐ doc

---

## R — Refactoring (sans changement de comportement)

### [ ] R.03 Alléger les deux gros scripts du client
- Dépend : —
- Règles : sans objet (aucune règle). `client/fight/fight_view.gd` (796 lignes) et `client/client_session.gd` (702) approchent la limite de 800 (`test_architecture`) : sortir la construction du HUD de `ClientSession._ready` (une quinzaine de nœuds faits à la main) et l'ajout des acteurs / marqueurs (`_add_actor`, `_apply_markers`) ; découper `FightView` par domaine (comme `FightFlow`) avant d'y ajouter quoi que ce soit.
- Client : aucun changement visible.
- Tests : la suite complète, les captures `client_shot` de combat et de map identiques.
- Parité : ☐ règles sourcées (sans objet) ☐ tests ☐ sim_cli ☐ capture ☐ doc

---

## Bloqués (attente de l'utilisateur)

Lots rangés en dernier : `roadmap.py next` ne les propose qu'après tous les autres.

### [ ] C.02h Mesure d'une première connexion sur Hamachi (BLOQUÉ : attend l'utilisateur)
- Note : **bloqué utilisateur** (2026-10-17) : demande deux postes reliés par Hamachi, donc une mesure que seul l'utilisateur peut faire. Le lot est rangé en bas de la roadmap (section « Bloqués »), après tous les autres, pour que `roadmap.py next` ne le propose pas avant eux. Le prendre seulement sur demande.
- Dépend : C.02g
- Données : base `dofus` 344 Mo (zip de base ~175 Mo estimé : ratio 0,51 mesuré en C.02c), une zone de classe 43 à 99 Mo, une zone de départ comprise dans la base
- Règles :
  - sur deux postes reliés par Hamachi : serveur `dofus` avec `--build-packages`, un client vierge (`--content-dir` neuf) ; chronométrer le zip de base, la zone de classe et la première zone hors du départ ;
  - vérifier aussi qu'un `tp` lointain (`/tp`) n'attend pas un nouvel index, et le mode « tout télécharger en arrière-plan » sur la durée (C.02f) ;
  - noter le débit réel et les minutes au Journal ; si > 10 min, réduire la base (pictos d'objets 30 Mo, I18n 26 Mo à la demande) ;
- Commun : — | Serveur : —
- Protocole : —
- Client : —
- Tests : — (mesure)
- Parité : ☐ règles sourcées ☐ tests ☐ sim_cli ☐ capture ☐ doc

---

## Journal

| Date | Lot | Fait | Reste / suite |
|---|---|---|---|

| 2026-10-11 | jouabilité (hors lot) | Descente d'Incarnam : par Maître Anemo (PNJ 4360, Route des âmes 4,-3), comme le vrai jeu (guide de la quête « Destination Astrub ») : « partir explorer le Monde des Douze » → « Insister pour aller à Astrub » → « S'approcher du portail » = téléportation à Astrub (6,-19) 455. Arbres de dialogue écrits à la main (ids de texte du client seulement) dans `tools/extractor/dialogs.json`, écrits dans `worlds/<id>/dialogs.json` par `gamedata.py dialogs <monde>` (aussi à la fin de `npcs`), lus par `JsonWorldSource`. La porte « tonneau » (cellule 174 → Astrub) venait d'une ligne « hand-written » de JondoEmu (supposition de l'auteur des dumps) : écartée dans `jondo.door_routes`, retirée de la map. Fenêtre de dialogue : hauteur réelle du texte et des réponses longues ; le chat passe sous les fenêtres. `test_world` (descente par le dialogue, remontée par le portail d'Astrub), `test_map_ui` (« Incarnam » au survol du portail d'Astrub) | L'ordre des répliques d'Anemo est reconstitué (APPROX(P2.01)) ; la branche « pas fini Incarnam » (748434) n'est pas utilisée. |
| 2026-10-11 | jouabilité (hors lot) | Sorties de maps : `maps.py _neighbour` lisait une ligne `mapscrollactions` comme « pas de sortie » sur les côtés dont `<côté>Exists` = 0, alors que c'est « pas de surcharge : voisin de mapData » ; 1 042 maps du monde `dofus` avaient perdu des côtés (Astrub (8,-18) ne gardait que la gauche). Corrigé, et nouvelle commande `maps.py neighbors <monde>` qui recalcule les voisins d'un monde construit sans réextraire (dofus : 1 042 maps corrigées, incarnam : 0). Audit : depuis Astrub, 5 255 maps atteignables à pied ou par une porte ; le reste du continent (carte 1) = îles (Frigost, Otomaï, Wabbits, Nowel : bateau ou PNJ) et « Mode tactique ». Test `test_world::test_a_scroll_action_row_keeps_the_other_sides` | Passages en bateau / PNJ vers les îles : à faire (données serveur). 1 154 côtés ont un voisin sans case de sortie (falaises, ou à vérifier). |
| 2026-10-11 | jouabilité (hors lot) | Bords de map : dès que la souris passe au-delà des cases d'un côté qui mène à une autre map, flèche de ce côté, quelle que soit la distance le long du bord (`MapHover.edge_exit` : la case de sortie de ce côté la plus proche de la souris) ; un clic y marche puis change de map. Le hors-map n'est plus flouté en permanence : un léger flou (`MapFrame`, fondu) seulement pendant qu'une flèche de sortie s'affiche. Déplacements : au-delà de 3 pas (`MapClick.RUN_CELLS`, chemin depuis la position actuelle) le joueur court, d'un seul clic (cases, PNJ, ressources, portes, bords). `client_shot` : `hoverpast:<côté>[:<0..1>]`. Tests `test_map_ui` | — |
| 2026-10-11 | jouabilité (hors lot) | Mode tactique (touche T) : décor masqué (`DofusMapNode.set_decor_visible`), grille plate (`MapView._draw_tactical` : cases libres, obstacles, vue bloquée, sorties, portes), état gardé d'une map à l'autre et en combat (`ClientSession.set_tactical`). `client_shot` : `tactical`. Test `test_map_ui` | Gabarits officiels `tacticalModeTemplateId` non extraits. |
| 2026-10-11 | P1.18 | Tests de tous les sorts : contrats par type d'effet sur les 3 990 grades (arène neutre, jets forcés, oracle de cibles indépendant), 52 cas multi-tours en données, `SpellGaps` (29 écarts sourcés). Moteur : cibles fixées au lancer (+ invocations du lancer), téléportation sur la case visée (Bond, Pas Chassé, Fulgurance), attirances au plus près d'abord sans dépasser le centre, symétries d'une paire une fois, marques en anneau, `on` / `delay` sur invocations / marques / portails, multiplicateurs sans déclencheur, X<code> = <code>, retours en arrière hors historique, rang 1406 des monstres ; dommages mêlée / distance / sorts, résistances mêlée / distance, dommages critiques et reçus lus. Extracteur : 120, 293, 281, 296, 411, 413, 1075, 275, 1118, 1092 convertis, sorts `noop` ; `FightEffects` découpé (`FightLife`, `FightBuffs`) ; 4 scénarios réenregistrés | Suite : P1.18b (deux cas retirés, fumée du sort entier, audit, plus de cas, ménage) |
| 2026-10-11 | S.06 | Taux du serveur et drops bonus façon Temporis : `WorldRates` (`--xp-rate`, `--drop-rate`, `--kamas-rate`, `--job-xp-rate`, `--bonus-drops`, `--bonus-drop-rate`, `--bonus-drop-range`), partagé par tous les mondes d'un `LocalServer`, réglable aussi en solo (ligne de commande du client, `client_shot`, `sim_cli`). `BonusDrops` : jets à part, après les drops normaux, pools générés par `gamedata.py bonus_drops` (757 monstres liés à 429 panoplies, 1 076 équipements craftables sans panoplie). `welcome.world.rates`, `fight_end.rewards[].bonus_items`, ligne dans le chat, objets bonus encadrés dans la fin de combat, carte « taux » de l'admin web. `test_rates.gd` (6, dont `NetBackend`) | Les taux ne changent qu'au redémarrage (pas de commande GM) ; pas de réglage dans l'écran de lancement solo |
| 2026-10-11 | P4.01 | Donjons génériques (187 donjons de la table `dungeons`), testés sur le Bouftou Royal (id 1) : `shared/dungeon.gd` (règles : niveau, clés, salles, composition), `sim/world_dungeons.gd` (runs par joueur ou groupe, salles = `MapInstance` privées à clé négative, clé consommée à l'entrée, salle suivante quand tous les groupes sont vaincus, boss en dernière salle, défaite / départ / déconnexion), `protocol_dungeon.gd` (`dungeon_enter/leave/room/end`, `map.dungeons` dans `map_enter`), `worlds/<id>/dungeons.json` + clé `bosses` de `monsters.json` (`gamedata.py dungeons <monde>`, à relancer après `maps.py full`), client `DungeonModel` / `DungeonIndicator`. Tests : `test_dungeon*.gd` (traversée complète du Royal en LocalBackend, parcours via NetBackend). APPROX(P4.01) : compositions des groupes (aucune source), niveau du personnage, clés toutes consommées, porte ouverte à la salle vidée. Reste : mécaniques spéciales des boss, `disbanded` jamais envoyé, état de run non persisté, entrée par la porte réelle (bouton du panneau seulement), `world_assets.gd --world=dofus` à relancer pour les looks des boss. |
| 2026-10-11 | combat (hors lot) | Combat qui se fige (solo et reseau, tous les joueurs du combat) : `ClientSession._pump` remettait `_blocked` a vrai apres une sequence finie avant le retour de `_dispatch` (fight_turn a effets legers, fighter_move sans chemin) : plus rien ne le levait, le watchdog ne la voyait pas. Corrige (`_in_dispatch`), `fight_turn` leve `_waiting_reply`, `Fight._next_turn` pose `turn_end` avant les effets de debut de tour, `finish_fight` sans `front()` sur liste vide. Test `test_session_pump.gd` | Non reproduit cote sim : `finish_fight` efface le combat avant les recompenses (une erreur laisse un `fight_id` fantome) et `WorldFights.tick` n'isole pas les erreurs d'un combat. Tests deja rouges : `test_protocol_doc_is_up_to_date`, `test_release::test_check_passes_on_a_good_folder` |
| 2026-10-12 | ménage (hors lot) | Ménage du système et de l'architecture. Méta : `CLAUDE.md` réduit (29 à ~10 Ko) ; la carte par domaine va dans `docs/CARTE.md`, toutes les commandes dans `docs/COMMANDES.md` ; `/suite` mis à jour (Grep des Découvertes, `TEST_ONLY` en cours de route, suite complète une fois, `roadmap.py archive`, commit + push) ; `tools/workflows/chaine.js`, `RAPPORT_NUIT.md`, `REPRISE.md` supprimés ; mémoire réduite aux décisions. Roadmap : `roadmap.py archive` (lots faits + Journal sauf les 15 dernières lignes dans `docs/ROADMAP_ARCHIVE.md`, lus par `show` / `check` / `next`, `set` refusé sur un lot archivé), Découvertes dans `docs/DECOUVERTES.md` ; ROADMAP 395 à 50 Ko, mêmes `status` / `next`. Code : `ProtocolSchema` (`shared/protocol_schema.gd` : `EXTENSIONS`, `all()`, `validate`) remplace 4 listes d'extensions écrites à la main (le fuzz de `test_security` oubliait `ProtocolContacts`) et sort `protocol.gd` de la limite (799 à 765 lignes) ; test `test_every_extension_is_wired` ; démo iso héritée supprimée (`GameEntity`, `EntityView`, `iso_demo`, `benchmark.gd`), `IsoGrid` dans `shared/`, `AnimMap` dans `client/` ; `test_src_only_holds_the_layers` ; `WorldSim.enter_map` délègue à `WorldJobs.on_enter_map` / `WorldTravel.on_enter_map` (même ordre d'événements : 33 scénarios OK) ; `TEST_ONLY` / `TEST_SKIP` acceptent une liste ; `test_protocol_doc_is_up_to_date` ignore les fins de ligne CRLF. Suite complète : 824 tests ; échecs seulement dans des tests instables déjà rouges sur HEAD (`test_accounts`, `test_world_loader` : verts relancés) ; capture `client_shot` relue | R.03 (alléger `client_session.gd` / `fight_view.gd`), R.04 (tests dépendants de l'ordre ou instables) |
| 2026-10-17 | tri (hors lot) | Refonte de la roadmap pour le harnais anti-régression. Nouvelle phase **H** en tête (H.01 socle des tests, H.02 golden des sorts, H.03 audit et garde de couverture, H.04 matrice monstres, H.05 golden de l'IA, H.06 parité serveur et process) avec R.04, P1.18b, P1.17b et P1.14 remontés devant ; P1.18b coupé en P1.18b (Runification, Estoc Brûlant, fumée du sort entier) et P1.18c (ménage, écarts à trancher) pour que la chaîne ne dépende que de la partie utile. P1.15 clos : code, tests, scénario `challenges.jsonl` et capture étaient faits depuis 2026-10-03, seule la dépendance P1.14 (érosion, formules) le gardait `doing` ; dépendance relâchée. C.02h marqué bloqué utilisateur (deux postes Hamachi) et rangé dans une section « Bloqués » en bas, donc ignoré par `next`. Reportés : P2.09 à P2.14, P3.06 à P3.10, P4.x, A1.02b, G.01, P3.02b ; cosmétique en dernier : P5.x, R.03. Aucun lot passé en `dropped` : aucun lot vérifié n'est devenu faux. | Chaîne : R.04, H.01, P1.18b, H.02, H.03, H.04, H.05, P1.17b, P1.14, P1.18c, H.06 |
| 2026-10-17 | R.05 | Cause trouvée : pas la charge ni le seuil, un vrai biais de `NetBackend`. Les 3 pings de départ sont postés derrière le `hello` ; l'hôte construit alors le monde (≈ 300 ms, bloquant) puis répond avec `sim.now` = 0 : rtt 311 ms mesuré, presque tout à l'aller, et l'estimation `offset = server_ms + rtt/2 - now` suppose un trajet symétrique, d'où une erreur de rtt/2 ≈ 155 ms (le médian de 3 échantillons identiques ne corrige rien). Correctif : à la réception de `welcome` (monde construit), `NetBackend` poste 3 pings propres qui reprennent la médiane des 5 derniers échantillons. Seuil de 60 ms inchangé. `TEST_ONLY=test_net` vert 3 fois de suite (13 tests). | Reste : l'horloge n'est juste qu'après un aller-retour de plus à la connexion (le temps d'un `welcome`) ; `time_ms` monotone peut rester figé ≤ 155 ms le temps du rattrapage | Prochain : P1.18c |
| 2026-10-18 | U.06 | Fenêtres d'objets. `client/item_compare.gd` (sans nœud : valeur, totaux, écarts), `UiTooltips.compare_for` + bloc « Comparé à » (`worn_by_slot`, `player_level` : niveau requis en rouge), `ItemSlot.locked` (jeton `UiStyle.VEIL`) et `flash()`, inventaire : recherche, inverser, compteur ; équipement : bonus total ; sorts : filtre Appris ; métiers : prochaine ressource ; `client_shot itemtip:<objet>`. Test `test_item_ui` ; fast vert. | Lot restant renommé U.07 |
| 2026-10-18 | U.07 | Fenêtres de commerce et de société refaites : kit `UiSearch`, `QtyStepper`, `UiRow`, `ConfirmPolicy`, jetons `ROW_*` / `MAP_*` ; boutique (recherche, Max, confirmation d'un gros achat), coffre (recherche, compteurs, boutons de kamas grisés), échange (résumé de ce que Valider engage, cadre doré du joueur prêt), atelier (recettes triées par faisables, ingrédients manquants), forgemagie (jauge de chance, confirmation sous 50 %), zaap (recherche, tri par prix, point de sauvegarde), dialogue (bulle), quêtes (recherche, abandon confirmé), amis (recherche, en ligne d'abord, compte), carte du monde (zoom, coordonnées, légende, nom des lieux), hôtel de vente. `test_commerce_ui` (10), captures relues 4 tailles, fast vert. | Chance de forge non vue en capture à 1280 ; pas de portrait de PNJ ; lot restant renommé U.08 |
| 2026-10-18 | U.11 | Revue finale : galerie de 21 scènes à 3-4 tailles relue image par image ; correctifs (onglets du chat à contour, clé `spell_mod` lisible et effets dédoublonnés, perdants à PV vides dans le résultat, zaap et métiers à hauteur de contenu, icône Amis, titre Défis) ; notes /5 dans `AUDIT_UI.md`. Suite complète lancée. | Grimoire haut à 1920, texte de PV de combat, forge/craft/hôtel de vente/console non recapturés ; U.10 reste à faire |
| 2026-10-18 | U.09 | Couche d'interface sur la map : `MapTip` (infobulle commune, placement sans débord, pastille de nom), infobulle de PNJ, regrossissement des pastilles/bulles selon le zoom, bulle de chat à queue, toasts sous la timeline. `test_map_ui` (+4), fast vert. | Menu contextuel et flèches de sortie inchangés (déjà lisibles) ; captures à 2 tailles seulement ; lot restant renommé U.10 |
| 2026-10-18 | U.08 | Écrans de lancement refaits sur le kit `UiMenu` : lancement (onglets Solo / Serveur, fil des étapes, un bouton primaire, erreur après tentative, options avancées repliées), chargement de monde (lignes, jauge, vitesse, reste), choix et création de personnage (jetons, socle commun, bouton danger), dossier des mondes, bandeau de reconnexion à jauge. `test_menu_ui` (7), `tools/loading_shot.gd`, captures relues 4 tailles, fast vert. | Pas de fond illustré Dofus extrait (symbole de classe en filigrane) ; chargement vu en capture avec une liste simulée, pas avec un vrai serveur ; lot restant renommé U.09 |

## Découvertes

Dans `docs/DECOUVERTES.md` (ajouter en tête ; chercher avec Grep plutôt que tout lire).
| 2026-10-17 | R.04 | Cause du `test_travel` rouge apres `test_quests`/`test_security` : `SpellBook.use_file(fixture)` (etat statique) fuyait vers les tests qui ne le remettent pas (le combat perdu utilisait les sorts de test). Correctif : `run_tests.gd` appelle `_reset_statics()` (SpellBook par defaut, GameData roots + cache) avant chaque suite ; le `_init` du test pose ensuite ce qu'il veut. `TEST_ONLY=test_quests,test_security,test_travel` : 43 tests verts ; `test_accounts`, `test_world_loader`, `test_fight`, `test_characters`, `test_mods` verts | Instabilite a froid de `test_accounts`/`test_world_loader` apres `--import` non reproduite (non corrigee) ; suite complete deux fois verte a faire en fin de chaine |
| 2026-10-17 | H.01 | `run_tests.gd` : echec si un fichier ne se parse pas, si le nombre de tests d'un fichier baisse sous `tests/baseline.json` (98 fichiers, 826 tests ; `TEST_UPDATE_BASELINE=1` pour le reecrire), recapitulatif par fichier (echecs, 5 plus lents), `TEST_TIER=fast` (contrats + cas + scenarios, 16 tests, 50 s). `tools/test_all.ps1` (lots, `-Tier fast`). Gardes testes avec un fichier cassé temporaire (supprime). Reste : `test_all.ps1` en mode complet non lance en entier (> 30 min), a valider a la fin de H.06. | Suivant : P1.18b |
| 2026-10-17 | P1.18b | Runification corrigée (moteur : un état de durée 1 posé puis retiré par le sort lui-même entre dans l'instantané des conditions du lanceur, `FightEffects._unstated_later` : vols des 4 éléments, +30 caractéristiques, états d'élément sur la cible) ; Estoc Brûlant : le moteur suit les données (état 6032 + sous-sort 1079237 + poussée = 4 cases), cas rétabli et pincé, plus un cas d'obstacle. 3 cas dans `spell_cases.gd` (55 cas). Fumée du sort entier : `tests/spells/spell_smoke.gd` + `test_whole_spells` (3 990 grades, normal et critique, invariants PV / PA / PM / cases, 55 s ; mutation vérifiée). `baseline.json` 827 tests. Reste : trancher 2 ou 4 cases d'Estoc Brûlant avec une mesure en jeu | Prochain : H.02 |
| 2026-10-17 | H.02 | Golden des sorts de classe : `tests/spells/spell_golden.gd` + `test_spell_golden.gd`, 1 730 grades (837 sorts, 20 fichiers `tests/golden/spells/classe_<NN>.json`, 2,5 Mo) joués dans `SpellArena` (lanceur 100 partout, jets max) : lancer, un tour complet plus tard, critique, et variante avec les états que les conditions demandent (Sobre/Saoul...) ; instantané en diff (PV, PA/PM, cases, états, buffs, marques, invocations). `GOLDEN_UPDATE=1` ou `-- --update-golden` régénère ; `TEST_CASE=<nom ou (spells.id)>` filtre. Mutation (+5 dégâts) : 2 172 échecs. `baseline.json` 828 tests. Section dans COMMANDES.md | Prochain : H.03 |
| 2026-10-17 | H.03 | Garde de couverture : `tests/spells/spell_coverage.gd` + `test_spell_coverage.gd` (4 tests : chaque grade est jouable par les contrats et, pour une classe, a son golden, sinon il est dans `SpellGaps` ; un écart déclaré doit exister dans les données ; les cas visent une classe qui a des sorts). `tools/spell_audit.gd` écrit `docs/SPELL_AUDIT.md` (par classe : sorts, grades, écarts, cas, effets non atteints, types d'effet sans cas multi-tours). 16 cas multi-tours ajoutés dans `spell_cases.gd` (71 cas) pour les classes les moins couvertes : Sadida (+3), Roublard (+4), Steamer (+2), Éliotrope (+2), Huppermage (+2), Forgelance (+2 ; leurs 2 cas anciens étaient rangés dans la classe 19 qui n'existe pas, corrigé en 20). `baseline.json` 100 fichiers. Reste : les classes à 3 cas (1, 2, 6, 7, 8, 9, 12, 14, 18) n'ont pas reçu leur lot de 4 à 8 ; à reprendre avec P1.18c | Prochain : H.04 |
| 2026-10-17 | H.04 | Matrice monstres : `tests/monsters/{monster_game,monster_matrix,monster_family}.gd` + `test_monster_matrix.gd` (8 tests, une sous-case par monstre : 1 343 entrées = incarnam, dofus, boss ; `TEST_CASE=dofus:4108`). Par monstre : données lues (niveau, PV, PA/PM, résistances, stats, drops, kamas, grades 1..n), sorts présents et complets (`SpellCoverage.missing`), apparition en combat identique aux données (`WorldFights.monster_fighter`), 6 tours contre un mannequin standard (niveau 100, 1 M PV, via `Fight.tick` donc le rythme réel de l'IA, seed 7, dernier grade) sans erreur ni blocage, XP / kamas / drops de `FightRewards` (tous les grades : XP = `FightXp`, kamas dans la fourchette, drops = exactement ceux des données à taux très élevé). Familles = profils d'IA (`MonsterFamily` : passif, corps à corps, tireur, soigneur, invocateur, bombe) avec attendu propre (passif ne blesse pas, soigneur soigne son allié blessé ou frappe...). `tests/golden/monsters/matrix.json` (332 Ko) fige la partie de chacun ; le garde de couverture échoue pour un monstre sans ligne (et une ligne sans monstre). `GOLDEN_UPDATE=1` régénère. Mutation vérifiée : +3 aux dégâts de base fait échouer `test_every_monster_plays`. `TEST_TIER=fast` inclut `test_monster_`. `baseline.json` 101 fichiers, 840 tests. Reste : seuls 133 des 3 424 sorts des monstres de `dofus` sont dans `spells.json` (1 239 monstres jouent sans sort, `spells_absent` du golden) : lot H.04b ; aucun monstre de la donnée n'est une bombe (famille testée par `test_ai_profiles`) ; l'échantillon NetBackend est dans H.06 | Prochain : H.05 |
| 2026-10-17 | H.05 | Golden de l'IA : `tests/ai/{ai_trace,ai_scenes}.gd` + `test_ai_golden.gd` (5 tests). `AiTrace.first_turn` rejoue le combat par `Fight.tick` et écrit les actions du premier tour du monstre en lignes lisibles (déplacement, sort lancé, effets, PA/PM). 16 scènes de profil (`AiScenes` : les situations de `test_ai_profiles` en données, 5 profils) dans `tests/golden/monsters/ai_profiles.json` ; le premier tour des 1 343 monstres (`MonsterGame.setup`, factorisé hors de `play`) rangé par famille dans `ai_{passive,aggressive,cautious,healer,summoner,kamikaze}.json`. Garde : ligne manquante, ligne sans monstre, monstre dans deux familles. `GOLDEN_UPDATE=1` régénère. Mutation vérifiée : départage des cases de `FightAI._act` inversé fait échouer 711 sous-cas. `baseline.json` 102 fichiers. Reste : la parité NetBackend de l'échantillon (H.06) ; 1 239 monstres sans sort (H.04b) donc leur trace n'est que de la marche | Prochain : P1.17b |
| 2026-10-17 | P1.17b | Seizième morceau, le dernier effet inconnu : 1097 CharacterAddIllusionMirror « Crée des illusions » (`spells.py` : `ILLUSION`, kind `illusion` {count = diceNum} ; `Summons.illusions` pose `count` copies du lanceur (look, nom, 1 PV, sans tour ni emplacement d'invocation) sur les cases libres les plus proches, anneau par anneau). `spells.json` régénéré : 23 à 18 grades `partial` ; Roublardise (3 grades) et Goberration (2) sortent de `SpellGaps` (5 écarts de moins). Harnais : contrat `EntityContracts.Illusion` (nombre, lanceur, équipe, look, 1 PV, sans tour), golden `classe_13.json` régénéré et relu (le diff n'ajoute que 3 invocations par grade pour Roublardise, 6 cas), `test_p117b16_illusions`. 74 tests ciblés verts (contrats, golden, couverture, scénarios, matrice, golden IA), `baseline.json` 30 pour `test_audit_effects`. | APPROX(P1.17b) : sens d'après le seul texte i18n (aucune source sur la forme ni la vie des illusions) ; elles apparaissent autour du lanceur au moment de l'effet (après la téléportation 1160 si elle est avant dans la liste). Reste : 18 grades à codes de déclencheur inconnus (DV, CI, CT, DI : pas de source), runes Huppermage, horloge Synchro. Pas de message nouveau (événement `summon` existant), donc pas de test NetBackend. Prochain : P1.14 |
| 2026-10-17 | P1.14 | Exactitude des formules : `tests/test_formulas.gd` (8 tests, tableaux calcules a la main : 20 cas de dommages, 6 de soins, 8 d'erosion, 6 de collision de poussee, derivees `StatFormulas`) fige l'ordre des operations, les arrondis (division entiere / floor de zone) et les plafonds de `FightLife` / `FightDisplace`. Les `APPROX(P1.14)` (erosion, poussee, plaquage, retrait PA / PM) sont documentes avec leur test ; `baseline.json` 854. | Aucune source nouvelle : `luaformulas` n'a aucune formule de combat, les formules restent communautaires `APPROX(P1.14)`. Plafond 50 % de resistance en JCJ : non applique (ni source ni mode JCJ en sim), decision notee aux Decouvertes. Pas de message nouveau, donc pas de test NetBackend. Prochain : P1.18c puis H.06 |
| 2026-10-17 | H.06 | Parité local / réseau : `tests/parity/parity_rig.gd` (`ParityRig` : même combat par `LocalBackend` et par `ServerHost` + `NetBackend` sur 127.0.0.1, empreinte des événements de règles) + `test_matrix_net.gd` (2 tests : un monstre par famille d'IA, 6 familles, avec ses sorts de données, et un sort par classe, 19 classes, lancé par un personnage niveau 100 qui marche vers la cible). Événements identiques au jet de dé près : la graine d'un combat lit l'horloge du monde à l'attaque, donc l'attaque part au même instant des deux côtés (écart réseau mesuré 0) ; limiteur de débit relevé dans le test (S.05 le teste ailleurs). Process : `.claude/commands/suite.md` (étape harnais : golden + test pour tout nouveau sort / effet / monstre, `TEST_TIER=fast`, baseline), `CLAUDE.md` (règle 7), `CARTE.md`, `COMMANDES.md`, `ARCHITECTURE.md` (section Harnais). Dépendance P1.18c relâchée (ménage des anciens `Arena`, sans effet sur le harnais). Suite complète : 856 tests (854 avant H.06), 1 échec, `test_net::test_clock_with_the_real_clock` (écart d'horloge 145 à 175 ms pour 60 ms), qui échoue aussi sur le HEAD d'avant (vérifié par remise à l'état d'avant) : lot R.05. Une seule suite complète lancée, pas deux | Prochain : R.05, P1.18c |
| 2026-10-17 | P1.18c | Lot coupé : seuls les cas multi-tours sont faits (P1.18c). 23 cas ajoutés dans `tests/spells/spell_cases.gd` (94 cas) : Féca 3 (Typhon, Bulle, Égide), Osamodas 4 (Morsure du Serpent, Piqûre Motivante, Toison d'Or, Déplumage), Ecaflip 4 (Neuf Vies, Entrechat, Griffe Joueuse, Kraps), Eniripsa 3 (Mot de Reconstitution, Fontaine de Jouvence, Chapardage), Iop 5 (Pression, Détermination, Endurance, Épée du Jugement, Puissance), Cra 4 (Flèche Harcelante, Œil de Taupe, Balise de Survie, Balise Tactique) ; chaque cas cite ses dés et ses durées dans `source`, jamais une valeur lue sur le moteur. Écarts trouvés, écartés des cas et notés aux Découvertes : effets appliqués deux fois (Mot Déprimant, Mot Stimulant, Balise Tactique), Pavois qui n'invoque qu'un bouclier, retrait de PA esquivable (aléatoire). `TEST_ONLY=test_spell_cases` vert | Reste : P1.18d (classes 12, 14, 18, ménage `Arena` / `Duel`, écarts à trancher) | Prochain : P1.18d |
| 2026-10-17 | H.04b | Sorts des monstres de toutes les zones : `spells.py classes --world incarnam+astrub+dofus` (5 s au lieu de 2 min : plus de lecture des 17 353 maps) charge 2 449 grades de monstres (2 851 references) ; les grades encore `partial` hors Incarnam / Astrub (244, avec leurs parents) restent hors des donnees (`closure()`). Golden regeneres et diff relu : matrice 1 241 monstres passifs a 145 (609 aggressifs, 374 prudents, 118 invocateurs, 91 soigneurs, 6 kamikazes), `ai_*.json` (passif -6 182 lignes, aggressif / prudent / soigneur / invocateur en plus). 13 grades en `SpellGaps` APPROX(H.04c), 62 monstres en `MonsterGaps` (ne blessent pas le mannequin en 6 tours). Temps : la matrice complete dure 7 min ; `TEST_TIER=fast` joue 1 monstre sur 6 (`FAST_STRIDE`) : 2 min 10 au total, contre 9 min sans l'echantillon. Verts : fast, `test_ai_golden`, `test_matrix_net`, `test_architecture` ; la suite complete n'a pas ete relancee. Parite : standalone et reseau passent par les memes donnees (`test_matrix_net` vert). Reste, lot H.04c : 5 666 references `spells_absent` (573 monstres), effets partiels, ecarts | Prochain : H.04c |
| 2026-10-17 | P3.02b | Smileys : `{smiley:ID}` dans le texte (`Chat.smiley_ids`, `smiley_usable` : table `smileys`, `forPlayers`), la sim ne garde que les ids utilisables dans `chat_msg.smileys` (nouveau champ), le client affiche une face. Tests `test_chat.gd` (+1 : smileys Local, et liens / smiley / groupe refuse via NetBackend). Canal groupe, liens d'objets et sourdine GM (`test_admin`, `E_MUTED`) deja la. | Reste coupe en P3.02c : guilde / alliance, infobulle des liens, icones et emotes. APPROX(P3.02b) : face texte a la place de l'image du smiley |
| 2026-10-17 | P2.03b | Recompenses de quete appliquees : `player_stats` porte `emotes` et `titles` (jusque-la tenus mais jamais lus), `Character.known_spells` ajoute les `quest_spells` au grade du niveau (castables en combat). Test `test_quest_rewards.gd` (2 : Local, et Net sur 127.0.0.1 avec schema valide, sauvegarde JSON, pas de doublon d'emote). Types d'objectifs 10-15 absents des donnees du monde dofus : rien a ajouter. Aucun sort dans les recompenses reelles (8 emotes, 4 titres) | Reste coupe en P2.03c : departs sans PNJ, sorts sur la barre, fabrication, formules, dialogues. APPROX(P2.03b) : l'id de `spellsReward` est lu comme un `spells.id` |
| 2026-10-17 | P2.05c | Metiers, suite : XP d'une recolte = `(levelMin / 10) * 2 + 10` (decompile `JobSkillsUI.GetXpForSkillCollect`, remplace `10 + levelMin`), ressource grisee pendant la repousse (`ResourceView`, `self_modulate` : le survol garde `modulate`), curseur de recolte (icone de la ressource), fenetre des metiers (P : `JobsWindow` / `JobsModel`, niveau, jauge d'XP, competences), `client_shot` `element:<id>` / `jobs`. `test_jobs_client.gd` (6, dont `NetBackend`), capture relue | Table d'XP des metiers, duree, repousse, quantite, ressources bonus : toujours APPROX (aucune source), icones de metier et vrais curseurs non extraits : P2.05d |
| 2026-10-17 | P2.09 | Lot clos en doublon : l'echange entre joueurs existe depuis P3.11a/b (WorldTrade, TradeRules, TradeSession, ProtocolTrade trade_*, TradeWindow, tests Local + Net a deux clients dans test_trade.gd et test_trade_client.gd). Double validation reinitialisee a chaque trade_set, transfert atomique (un seul Persistence.commit), deconnexion annule l'echange (on_disconnect). Reverifie : TEST_ONLY=test_trade, 22 tests, 0 failures. Aucun code. | Aucun reste |
| 2026-10-17 | P2.10a | Hotel de vente, partie sim : `MarketRules` (taxe 2 % min 1 a la mise en vente, lots 1/10/100/1000 = `auctionhouses.allowedQuantities`, 14 jours, 50 lots max, filtre `itemtypes.categoryId`), `Marketplace` (lots + prix moyen dans `Persistence` collection `market`), `WorldMarket` (`hdv_*`, un seul `commit` marketplace + personnages), kamas verses hors ligne via `market/proceeds/<monde>/<nom>` encaisses a la connexion (`hdv_sold`), lot expire repris par son vendeur. Tests `test_market.gd` (15 : Local a deux personnages, Net sur 127.0.0.1 avec vente hors ligne). Reste (P2.10b) : fenetre client, acces par element interactif, extraction `auctionhouses`. |
| 2026-10-17 | P2.12a | Succes, partie sim : `Achievements` (regles pures), `AchievementLog` (obtenus + compteurs EM / ES / EI / QF, sauve avec le personnage), `WorldAchievements` (branche sur `WorldQuests.event` : memes evenements que les quetes, plus `quest` a la fin d'une quete). Un objectif est un critere Dofus lu par `CriteriaEval` (nouvelles cles EM ES EI QF OA Ob Oa, parentheses tolerees) ; 725 des 2780 succes dont toutes les cles sont suivies -> `data/achievements.json` (`gamedata.py achievements`). Recompenses = lignes `achievementrewards` dont le critere tient (`Ob!id` = premiere fois), chacune par `QuestEngine.rewards` ; points et chainage (OA / Oa). Monde opt-in `"achievements": true` (mis dans `worlds/dofus/world.json`), donc aucun test existant ne bouge. Protocole `achievement_open` / `achievement_list` / `achievement_unlocked`. Tests `test_achievements.gd` (14 : regles, Local avec un vrai combat, Net 127.0.0.1 avec reconnexion). Reste (P2.12b) : fenetre client, almanax, succes aux cles non suivies. |
| 2026-10-17 | Bilan (etape 10) | Suite complete `tools/test_all.ps1` : 894 tests (= baseline.json, 109 fichiers) en 956 s. Deux lots en echec au premier passage : `test_content_api::test_the_real_incarnam_world_packages` (`worlds/incarnam/_content.json` perime, regenere par `tools/world_assets.gd --world=incarnam`, vert ensuite) et `test_accounts::test_register_then_login_and_play` (5 echecs, vert seul et en lot 0-11 relance : flake WebSocket sous charge). Aucun code modifie. | Fragile : tests WebSocket (accounts, cluster, contacts) sporadiques sur machine chargee ; `_content.json` a regenerer apres un ajout de contenu incarnam ; suite complete ~16 min. |
| 2026-10-17 | P1.18d | Lot coupé (reste en P1.18e). Écarts tranchés dans le moteur : (1) Mot Stimulant / Déprimant, une seule fois : un `unbuff` d'un sous-sort des Mots (`FightBuffs.SHARED_STACK`, « le cumul est partagé ») retire aussi ce que le sort appelant vient de donner dans le même lancer (`Fight.cast_serial`, `cast_chain`, `Buff.cast_serial`), PA rendus compris : PA 8 et puissance -150 ; (2) Pavois : une invocation dont la zone a une taille > 0 (hors `replaces`) invoque sur chaque case libre de la zone, et le `kill` retardé de masque `U` atteint toutes les créatures du lancer, pas seulement celle du centre ; (3) Balise Tactique : conforme aux données (+30 du sort, +30 par ennemi vu de la case ciblée, la ligne de vue exclut les ennemis masqués), cas écrit ; (4) retrait de PA / PM esquivable : règle, pas écart. 22 cas ajoutés dans `spell_cases.gd` (Pandawa 5, Zobal 3, Ouginak 6, correctifs 4, soit 116 cas) ; golden régénérés : `classe_01` (Pavois : 2 boucliers, détruits au tour suivant), `classe_07` (Mots : un seul jeu d'effets). `SpellArena` accepte un `layout` : 11 anciens `Arena` (marks, triggers, summons, bombs, portals, visibility, rollback, telefrag, redirects, carry, audit_effects) en héritent. `test_matrix_net` rejoue Pavois, les Mots et Balise Tactique par le réseau. `TEST_TIER=fast` vert | Reste : P1.18e | Prochain : P1.18e |
| 2026-10-17 | H.04c | Lot coupé (reste en H.04d : 62 monstres de `MonsterGaps`, et H.04e : 244 grades `partial`). Les 13 écarts de `SpellGaps` `APPROX(H.04c)` sont tranchés et la liste n'en garde aucun. (1) `entity_contracts.gd` ne compilait plus depuis P1.18d (un `\n` littéral) : `SpellCheck` non plus, donc `test_spell_contracts` ne vérifiait rien ; corrigé. (2) Contrats : un vol durable n'est plus pris pour un poison (5 grades : Embaumement, Frappe de Corail, Nervure, Boue sirupeuse, Bondage), Drako reflète une fois par porteur, le vol de PM de Macro-Ondes compte le lanceur dans sa zone, les invocations « seul le monstre n le lance » donnent le monstre à l'arène (Bombombre x2, Fruit du Sacrifice). (3) Moteur : `*h` / `*m` / `*j`… (`TargetMask`) = le lanceur est de ce type, Ossuaire (2 grades) agit enfin, APPROX ; retrait de PA / PM esquivable : on ne perd jamais plus de points que détenus (`FightBuffs.resource`, Noyade). Goldens regénérés, diff relu (12 lignes en tout) : sorts classe 6 (Propagation, Lapement : buff -1 au lieu de -2 PM) et 17 (Courant Quadramental : idem, un buff de moins), `ai_aggressive` et `ai_cautious` (3 lignes : un PM ou PA restant de moins), matrice : un `dummy_lost` ; rien d'autre (les tirages d'esquive restent un par point retiré). Tests : `test_target_mask` +2 (lanceur `*m`/`*h`, plafond de l'esquive), `test_matrix_net` +1 (monstres 3153, 3670, 3392, 831 en local et par le réseau) ; `baseline.json` 898. | `test_matrix_net::test_the_p118d_spells_play_the_same_on_both_backends` échouait déjà (3 cas sur 4 : Pavois, Mot Déprimant, Balise Tactique ne sont pas dans les sorts choisis du personnage de niveau 200, `unknown_spell`) ; Mot Stimulant corrigé (grade du niveau), reste à choisir les sorts ou les variantes du personnage. Hors `TEST_TIER=fast`. |
| 2026-10-17 | P2.10b | Hotel de vente, client et acces. Acces : PNJ `npcs` 2900 (Gerant de l'hotel de vente, seul modele du client, non place dans les tables) liste dans `worlds/<id>/market.json` (`WorldSource.is_auctioneer`, `Dialog.with_market` + action `market`, ouverture directe si muet) ; `hdv_open` exige un gerant a cote des que le monde en declare (sinon HDV libre : mondes de test) ; une entree `placed` `approx` peut donner son look au PNJ (le look {11} ne dessine rien). Les vues de lot portent `left` (ms). Client : `MarketModel` (etat, taxe, pages, messages), `MarketWindow` (onglets Acheter : recherche nom + categorie, prix, prix unitaire, ecart au prix moyen, pages ; Vendre : taille de lot, prix, taxe affichee ; Mes lots : reprise, expires), toasts achat / vente, `client_shot` `hdv_seed` / `hdv_tab` / `hdv_sell`. Tests `test_market_client.gd` (10 : modele, acces, dialogue, fenetre sur ClientSession, Net 127.0.0.1) ; captures relues (3 onglets). | APPROX(P2.10b) : categories nommees d'apres l'ordre de l'enum client, texte du bouton litteral, gerant place a la main (map 154010883, `worlds/` non versionne). Reste : audit (S.05) des achats / ventes, lots d'un vendeur d'un autre monde sans push (paye au retour, deja le cas). |
| 2026-10-17 | P2.12b | Succes, client. `AchievementsModel` (lit `data/achievements.json` via `DataFiles`, categories de tete regroupant leurs sous-categories, lignes obtenues d'abord, objectifs coches), `AchievementsWindow` (touche U, ouvre = `achievement_open`, liste de categories x/y, cartes), toast sur `achievement_unlocked`, raccourci `achievements`, commande `client_shot achievements[:<cat>]`. Tests `test_achievements_client.gd` (6 : modele, fenetre, fichier reel, Net 127.0.0.1 avec le modele). Capture relue (monde dofus). Almanax et cles non suivies coupes en P2.12c. Pas de nouvelle regle de sim : aucun scenario sim_cli. |
| 2026-10-17 | P3.10 | Défis (duels). `shared/protocol_duel.gd` (`duel_request / accept / decline`, `duel_requested`, `duel_end`, erreurs `duel_busy`, `no_duel_request`), `sim/world_duel.gd` (défis en attente, 60 s, refus silencieux si ignoré), `WorldFights.start_duel` / `_finish_duel` (combat `Fight.kind = duel`, équipes 0 et 1 de joueurs, placement rouge / bleu de la map, fin sans gain : PV d'avant rendus, pas d'énergie, pas de fantôme, `fight_end` du point de vue de chacun), `Fight.leave` (abandonner un duel = le perdre) et `join_error` (un duel n'est jamais rejoignable). Client : « Défier » du menu d'un joueur, cartes `DuelInvites` / `DuelModel`. `client_shot` : `duel`, `duelaccept`, `mate:duel`, `mate:duelaccept` ; deux captures relues (carte du défi, placement du duel, deux équipes). Tests `test_duel.gd` (8, dont Net 127.0.0.1) et `test_duel_client.gd` (2) : baseline 914 -> 924. Pas de scénario sim_cli (une seule session). | APPROX(P3.10) : délai d'une minute, duel permis sur toute map (le bit 0 de `mapsinformation.m_flags` = défi n'est pas lu). Prochain : voir `roadmap.py next` |
| 2026-10-17 | P3.02c | Chat, partie sans guilde. Smileys : vraies icones (`ui.py smileys` -> `Content/Picto/Smileys`, ajoute aux dossiers de base de `world_assets`, `_content.json` regenere), `client/chat_log.gd` (`ChatLog` : pieces d'une ligne, icones, `[objet]` en meta avec infobulle `UiTooltips.item` au survol). Emotes : `shared/emotes.gd` (`Emotes.usable`), `shared/protocol_emote.gd` (`emote` / `emote_play`, `unknown_emote`), `WorldChat.on_emote` (diffusion a la map, hors combat), client `ActorView.play_emote` + commande `/e <id ou nom>`. Canal d'equipe `/t` : les combattants de l'equipe de l'orateur (duel : deux equipes), onglet Equipe. `tests/test_chat_rich.gd` (10 tests, dont WebSocket), baseline 934, capture relue (icones, bulle sans balises) | APPROX(P3.02c) : emote libre si aucune quete / succes ne la donne, sinon il faut l'avoir gagnee ; les emotes a `criterion` sont refusees (pas evalue) ; animation non verifiee a l'ecran (le look de la capture n'a pas montre d'assise) ; infobulle testee par appel direct (pas de souris en headless). Guilde / alliance : P3.02d (apres P3.06) |
| 2026-10-17 | P2.03c | Fabrication (17) vraiment suivie : `WorldCrafting.on_craft_do` envoie `{kind: "craft", item, qty}` a `WorldQuests.event`, `QuestEngine` compte les crafts de l'objet (plus le contenu du sac, fin de l'APPROX P2.03). Tests : `test_quests` (un objet possede ou un autre objet fabrique ne compte pas), `test_crafting` (Local, et Net sur 127.0.0.1 avec schema valide). | Reste coupe en P2.03d : departs sans PNJ, sorts sur la barre, formules d'XP / kamas, dialogues |
| 2026-10-17 | P2.05d | Recherche de sources metiers (datos, proto, world.zip, code natif decompile) : rien pour l'XP de metier, duree, repousse, quantite, bonus. Lot ferme, APPROX(P2.05) conserves | Icones de metier / curseurs non extraits : a rouvrir si besoin |
| 2026-10-17 | P3.06a | Guildes, première partie : `shared/guild.gd` (rangs `guildranks`, droits `guildrights` appliqués : inviter 6, exclure 13, rangs 26, droits 1), `sim/world_guild.gd` (création avec règle de nom et emblème, invitation 60 s, exclusion, départ, passage de la main, dissolution, tout via `Persistence` : `guilds`, `guild_members`, `guild_names`, relu à chaque commande), `protocol_guild.gd` (`guild_*`), canal `/g` livré (`channel_unavailable` sans guilde). Tests `test_guild.gd` (16 : règles, Local à 2-4 clients, Net 2 comptes). Reste : P3.06b (fenêtre, XP, niveau), P3.06c (percepteurs). |
| 2026-10-17 | bilan (étape 10) | Suite complète via `tools/test_all.ps1` : 949 tests, 0 échec après correctifs, ~1 700 s dont `test_monster_matrix.gd` ~1 200 s (le lot 60-71 paraît figé, il ne l'est pas : ne pas le tuer). Régression trouvée : `test_matrix_net` (3 échecs, depuis H.04c) car le grade de niveau 200 d'un sort à variante n'est connu que si la variante est choisie : `ParityRig.scenario(breed, level, variants)` la passe maintenant ; Balise Tactique retirée du test réseau (cible une case libre, le rig lance sur l'ennemi : couverte par les tests de sorts locaux). Fragile : `test_accounts::test_register_then_login_and_play` a échoué une fois en tête de suite (2e connexion sans réponse), vert ensuite 3 fois. | Rendre `Rig.ask` de `test_accounts` tolérant au démarrage ; piloter Balise Tactique dans `ParityRig` (cible libre). |
| 2026-10-18 | U.01 | Zone de jeu réservée (`GameArea`) : la map, ses cases et ses combattants sont placés hors des bandes (timeline, barre de sorts / de combat + options) et des panneaux (chat, minimap, suivi, défis), exploration comme combat ; chat au-dessus de la bande basse. Captures relues à 1280x720, 1920x1080, 2560x1440, 1280x1024. `test_game_area.gd` (3). Phase U créée, docs/ui/ commités. | Le décor de la map (hors grille) déborde encore sous l'UI, comme dans Dofus ; personnages cachés par un décor : aucune règle Dofus, reporté U.02 |
| 2026-10-18 | U.02 | Échelle d'interface (`UiScale`, stretch 1280x720 canvas_items/expand, choix auto/75-150 %, marge de sécurité) ; `UiWindow` : zone sûre, défilement, redimensionnement, position/taille mémorisées en parts (v2, migration v1), re-clamp au changement d'écran, animation. `test_ui_layout.gd` (7), captures relues 4 tailles, fast vert. | Clics map en vrai avec le stretch non testés à la souris (U.03) ; pas d'écran d'options ; HUD encore positionné par frame ; décor masquant : U.03 |
| 2026-10-18 | U.03 | Langage visuel : jetons `UiStyle` (surfaces, texte AA, typo Lexend hiérarchisée, rayons, durées), boutons primaire / danger, onglets soulignés, jauges, champs, anneau de focus, ombres, survols des cases et transitions (toast, jauge) ; kit appliqué ; `docs/ui/STYLE.md`, `test_ui_style.gd` (7), captures relues 4 tailles, fast vert. | Focus clavier des cases non ajouté (Entrée ouvre la ligne de commande : une case focalisée l'avalerait) ; pas de 9-slice Dofus extrait ; fenêtres métier encore à repasser une à une (U.04+) |
| 2026-10-18 | U.04 | HUD d'exploration refait : `HudLayout` (placement pur, appliqué sur changement de signature), `MapInfo` (lieu, coordonnées, aide en infobulle « ? »), dock bas (jauge d'XP, niveau et vie, barre de sorts, kamas, `HudMenu` aux vraies icônes), chat proportionnel (fond à 4 opacités mémorisé, texte lisible au repos, onglets compacts avec non lus, « Nouveaux messages »), suivi de quêtes repliable. `test_hud.gd` (6), captures relues 1280x720, 1920x1080, 2560x1440, 1280x1024, 1024x576. | HUD de combat encore positionné par frame ; pas d'écran d'options (opacité du chat par bouton) ; icône « amis » absente du contenu (on utilise `social`) ; lot restant renommé U.05 |
| 2026-10-18 | U.05 | HUD de combat refait : `FightLayout` (placement pur, appliqué sur changement de signature), barre aux jetons du kit (jauge de PV, compteurs PA / PM `FightPoints`, chrono, boutons primaire / danger), `TimelineTile` (cadres, coche prêt, vie), infobulles riches de combattant et de sort (raison d'indisponibilité), nombres flottants constants à l'écran et gardés dans la bande libre, résultat de combat aux jetons. `test_fight_hud.gd` (6), captures relues 4 tailles + infobulle + résultat, fast vert. | Pas de capture avec un monstre collé au bas de la map (la garde `keep_in_strip` est testée en pur) ; couleurs de la carte (cases, portée) encore en dur dans `FightView` ; lot restant renommé U.06 |
