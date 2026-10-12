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

## M — Multijoueur : un serveur sur ta machine, des amis par Hamachi

Plan complet : `docs/PLAN_SERVEUR.md` (validé). Phase presque finie (2026-10-12) : M1, M2 et M3 sont faits, restent C.02h (mesure à deux postes), A1.02b et G.01 ; les lots de contenu ont repris.

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

### [ ] C.02h Mesure d'une première connexion sur Hamachi
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

### [~] P3.02b Chat : groupe, guilde, alliance, liens d'objets, smileys
- Dépend : P3.02a, P3.03a
- Données : `smileys`, `smileypacks`, émotes
- Règles :
  - canaux groupe (`/p`, avec P3.03), guilde (`/g`) et alliance (`/a`) (`channel_unavailable` tant que leurs lots n'existent pas) ;
  - liens d'objets (`[objet]` cliquable avec infobulle) ;
  - smileys et emotes ;
  - mise en sourdine par un GM (`mute`, par nom, via la console A1.01) ;
  - ignorés (P3.05a, fait : `WorldChat` les filtre déjà) ; chat visible pendant un combat côté client ; canal d'équipe quand les combats auront plusieurs joueurs (P3.04).
- Commun : `Chat` | Serveur : modération
- Protocole : `chat_send` / `chat_msg` existants (champ `links` à ajouter)
- Client : onglets groupe / guilde, liens et smileys dans le texte
- Tests : routage par groupe et par guilde, lien d'objet valide, sourdine
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

## P1 — Boucle de jeu de base (jouer seul, de la création au niveau 50)

### [~] P1.14 Combat, partie 5 : exactitude des formules
- Dépend : P1.13b
- Données : `luaformulas`, `spellstates` (flags : invulnérable, pesanteur, enraciné…)
- Règles :
  - érosion (10 % de base) ;
  - dommages de poussée et de critique ;
  - résistances plafonnées à 50 % en JCJ ;
  - % de dommages finaux et soins reçus ;
  - états standards appliqués via leurs flags ;
  - arrondis exacts.
- Commun : `FightEffects` complet, sans `APPROX` restant | Serveur : —
- Protocole : `fighter.erosion`
- Client : PV érodés affichés sur la barre
- Tests : tableau de cas calculés à la main et sourcés
- Parité : ☐ règles sourcées ☐ tests ☐ sim_cli ☐ capture ☐ doc

### [~] P1.15 Combat, partie 6 : challenges, fuite, options de combat, timer
- Dépend : P1.14
- Données : `challenges` (si présente), sinon liste sourcée
- Règles :
  - 1 à 2 challenges par combat, avec un bonus d'XP et de drop ;
  - fuite / abandon ;
  - options : verrouiller, groupe seul, bloquer les spectateurs, demander de l'aide ;
  - timer de tour réel (30 s + reste), fin de tour automatique.
- Commun : `FightChallenges`, `Fight.options` | Serveur : —
- Protocole : `challenge_list`, `challenge_update`, `fight_option`
- Client : bandeau des challenges, boutons d'option, chrono visuel du tour
- Tests : challenge réussi puis bonus appliqué ; challenge raté ; timeout de tour
- Parité : ☑ règles sourcées (APPROX bonus et nombre) ☑ tests ☑ sim_cli (scénario challenges.jsonl) ☑ capture ☑ doc

---

## P2 — Économie et progression

### [~] P1.17b Sorts « partial » restants : classes et autres zones
- Dépend : P1.17
- Données : 662 grades de classe encore `partial`, surtout les effets 1045, 2935, 1160, 335, 2822, 2792, 1026, 1036, 776, 414, 285, 115 (`spells.json` : liste `partial`) ; les monstres des autres sous-zones (`--world dofus` : 2 851 grades de sorts, 70 seulement chargés)
- Règles : lire chaque effet (texte i18n `effects.descriptionId`, enums du client), l'ajouter à `spells.py` et à `FightEffects` avec son test, par ordre de fréquence
- Commun : `FightEffects`, `spells.py` | Serveur : —
- Protocole : —
- Client : —
- Tests : chaque effet ajouté a son test
- Parité : ☐ règles sourcées ☐ tests ☐ sim_cli ☐ capture ☐ doc

### [ ] P1.18b Tests des sorts : suite (fumée, audit, cas, ménage)
- Dépend : P1.18
- Données : `spells.json`, descriptions FR (`tools/i18n_lookup.py`)
- Règles : par ordre de priorité
  1. Deux cas retirés à corriger dans le moteur : Runification (Huppermage : la rune se déclenche mais pas le vol par élément ni les +30 caractéristiques), Estoc Brûlant (Forgelance : poussée « depuis le lanceur » en cône, mauvaise case d'arrivée) ; le Forgelance n'a encore aucun cas
  2. Fumée du sort entier : chaque grade complet (normal et critique) lancé d'un bloc, pour les interactions entre effets que les contrats isolés ne voient pas
  3. `tools/spell_audit.gd` → `docs/SPELL_AUDIT.md` (par classe et par sort, liste des effets jamais testés : c'est ainsi que Bond / Pas Chassé ont failli passer) et `tools/spell_descriptions.py` (description ↔ effets des données)
  4. Plus de cas : 4 à 8 par classe (≈ 3 aujourd'hui) et des mécaniques de monstres
  5. Ménage : migrer les `Arena` / `Duel` dupliqués des anciens tests vers `SpellArena` ; `ARCHITECTURE.md`, `CLAUDE.md`
  6. À trancher : Mot Vampirique transfère 2 × 8 % et Détonateur rend 2 PA sur une bombe (données suivies, descriptions ambiguës) ; les 29 grades de `SpellGaps` (codes DV / CI / CT / DI sans source, illusions 1097, Runes élémentaires 4258-4261 absentes des données, horloge de Synchro)
- Commun : `FightEffects`, `FightLife`, `FightBuffs`, `FightDisplace` | Serveur : —
- Protocole : —
- Client : —
- Tests : `test_spell_cases.gd` (les deux cas rétablis), fumée dans `test_spell_contracts.gd`, suite complète verte
- Parité : ☐ règles sourcées ☐ tests ☐ sim_cli ☐ capture ☐ doc

### [ ] P2.03b Quêtes, complément : ce que P2.03 laisse
- Dépend : P2.03, P2.05a, X.01
- Données : `questobjectives` types 10 (escorter), 11 (défi joueur), 12 (âmes), 13 (éliminer), 15 (Krosmaster), `quests` sans `startPosition` (« Mort au rat » 1633 : démarrées par un objet / un niveau / une alerte), `queststeps.dialogId`, `queststeprewards` (émotes, titres, sorts, métiers)
- Règles :
  - démarrage des quêtes sans PNJ de départ (source à trouver : JondoEmu, notifications du client) ;
  - récompenses d'émotes, de titres et de sorts réellement appliquées (la liste `Character.emotes` / `titles` / `quest_spells` est tenue, rien ne la lit) ;
  - fabrication (17) vraiment suivie une fois les métiers faits (P2.05) ;
  - formules d'XP et de kamas des récompenses sourcées (aujourd'hui `QuestEngine.XP_SHARE` / `KAMAS_PER_LEVEL`, APPROX) ;
  - dialogues des étapes (serveur) : lire les captures JondoEmu `npc_dialogos_*` si elles existent.
- Commun : `QuestEngine` | Serveur : —
- Protocole : —
- Client : —
- Tests : un test par type d'objectif ajouté
- Parité : ☐ règles sourcées ☐ tests ☐ sim_cli ☐ capture ☐ doc

### [ ] P2.05c Métiers, partie 1c : ressources bonus, retours visuels, fenêtre des métiers
- Dépend : P2.05b, X.01
- Données : `jobs` (icônes), `skills.cursor` (curseur de récolte), ressources bonus, table d'XP des métiers, XP par récolte, durée, repousse (aucune source trouvée : ni les tables du client, ni JondoEmu `datos`)
- Règles : ressources bonus (APPROX : aucune pour l'instant) ; sources réelles de la table d'XP des métiers, de l'XP par récolte, de la durée et de la repousse si on en trouve
- Protocole : `jobs` complets à la connexion si besoin
- Client : ressource grisée / masquée pendant la repousse (hook dans `DofusMapNode`), curseur de récolte au survol, fenêtre des métiers (niveaux, barre d'XP, compétences)
- Tests : bonus, état de la ressource côté client
- Parité : ☐ règles sourcées ☐ tests ☐ sim_cli ☐ capture ☐ doc

### [ ] P2.09 Échange entre joueurs
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

### [ ] P2.10 Hôtel de vente (HDV)
- Dépend : P2.08, P0.02, X.01
- Données : HDV par catégorie de type d'objet (interactifs)
- Règles :
  - mise en vente par lots de 1, 10 ou 100 ;
  - taxe de mise en vente (à sourcer) ;
  - durée de mise en vente ;
  - prix moyen ;
  - le kama arrive à la vente, même hors ligne ;
  - un nombre maximum d'objets en vente.
- Commun : `Marketplace` via `Persistence` | Serveur : HDV global et concurrent
- Protocole : `hdv_open`, `hdv_search`, `hdv_buy`, `hdv_sell`, `hdv_cancel`
- Client : fenêtre d'HDV (recherche, filtres, prix)
- Tests : vendre puis acheter entre deux personnages ; taxe ; expiration
- Parité : ☐ règles sourcées ☐ tests ☐ sim_cli ☐ capture ☐ doc

### [ ] P2.11 Mode marchand
- Dépend : P2.10, P3.01, X.01
- Données : —
- Règles : le personnage reste sur la map hors ligne comme marchand ; taxe ; limite par map
- Commun : `MerchantActor` | Serveur : persiste après la déconnexion
- Protocole : `merchant_start`, `merchant_view`, `merchant_buy`
- Client : fenêtre du marchand
- Tests : achat auprès d'un marchand hors ligne
- Parité : ☐ règles sourcées ☐ tests ☐ sim_cli ☐ capture ☐ doc

### [ ] P2.12 Succès et almanax
- Dépend : P2.03, X.01
- Données : `achievements`, `achievementobjectives`, `achievementrewards`, almanax
- Règles : objectifs suivis par événement ; récompenses ; points de succès ; quête almanax du jour
- Commun : `Achievements` (réutilise `QuestEngine`) | Serveur : —
- Protocole : `achievement_unlocked`, `achievement_list`
- Client : fenêtre des succès, notification
- Tests : succès débloqué par un combat
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

### [ ] P3.06 Guildes
- Dépend : P3.02a, P0.02
- Données : emblèmes (guildemblems…)
- Règles :
  - création (guildalogemme), rangs et droits ;
  - XP de guilde donnée en pourcentage ;
  - niveau de guilde ;
  - percepteurs et leurs combats (lot à découper le moment venu).
- Commun : `Guild` via `Persistence` | Serveur : concurrence
- Protocole : `guild_*`
- Client : fenêtre de guilde (membres, rangs, emblème)
- Tests : création, invitation, droits, XP donnée
- Parité : ☐ règles sourcées ☐ tests ☐ sim_cli ☐ capture ☐ doc

### [ ] P3.07 Alliances, prismes, AvA
- Dépend : P3.06, P3.08
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

### [ ] P3.10 Défis (duels)
- Dépend : P3.01, P1.15
- Données : —
- Règles : défi accepté, combat sans perte d'énergie ni gain
- Commun : `Fight.kind = duel` | Serveur : —
- Protocole : `duel_request`, `duel_accept`
- Client : menu contextuel « Défier »
- Tests : duel sans gain et sans perte
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
- Dépend : P2.12
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
- Dépend : P2.10, P3.06
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

### [ ] R.04 Tests qui dépendent de l'ordre
- Dépend : —
- Règles : sans objet. `test_travel::test_save_point_at_a_zaap_for_recall_and_defeat` passe seul mais échoue quand `test_quests` ou `test_security` tournent avant (le combat perdu ne finit pas : « expected lose, got "" ») : un état statique partagé fuit d'un test à l'autre. Le trouver et l'isoler. Aussi instables (2026-10-12, déjà rouges sur `7ac1017`) : `test_accounts` et `test_world_loader` échouent au premier lancement après un `--import` (démarrage à froid : hachage du login dans un thread, délais trop courts ?) puis passent ; les échecs WebSocket « sporadiques » notés en C.06/C.07.
- Tests : `TEST_ONLY=test_quests,test_travel` vert ; suite complète verte deux fois de suite.
- Parité : ☐ règles sourcées (sans objet) ☐ tests ☐ sim_cli ☐ capture ☐ doc

---

## Journal

| Date | Lot | Fait | Reste / suite |
|---|---|---|---|

| 2026-10-06 | S.04b | Instances d'un meme contenu. `WorldSource.instance(id, name)` (memes donnees, `info.id` = instance, `info.content`), `LocalServer.instances` + `source_of`, `WorldCluster.create` / `remove` / `restore` / `content_of` / `sync_content`, `instances.json` du dossier de sauvegarde rouvert par `ServerApp`, actions admin `world_create{id, content, name?}` / `world_remove{id}` (auditees), `servers[].content`, `welcome.world` / `characters.world` portent `content` (`WorldSim.world_summary`), `ContentApi.instances` (liste l'instance sous son id avec `content`, sert le paquet du contenu meme si seul l'instance est ouverte), `WorldLoader.content_of` (cache et manifeste par contenu), `ClientSession.content_id`. `tests/test_instances.gd` (4 tests via vrais WebSockets : personnages separes, listes, API de contenu, creation / suppression, redemarrage) + 1 test de `WorldLoader`. 750 tests, 0 echec apres correction de `test_architecture` (client_session a 800 lignes pile). | APPROX(S.04b) : supprimer une instance garde ses personnages sauvegardes ; pas de formulaire de creation dans la page admin (action HTTP seulement) ni de choix d'instance dedie dans l'ecran de chargement (elle y est une ligne comme un monde). Pas de capture. `P1.17b` : les 14 grades restants n'ont aucune source (declencheurs CI, DV, TR<n>, EC, PMD... sans sens connu), laisse `doing`. Prochain : C.02h (mesure a deux postes) ou S.05c |
| 2026-10-06 | S.05c | Securite, dernier morceau. Hachage dans un thread : `server/auth/auth_job.gd` (`AuthJob`, `WorkerThreadPool`), `ServerHost._login` lit les identifiants sur le fil principal, lance le job, `_finish_jobs` (appele par `poll`) termine le login ; les tentatives d'une connexion pendant un hachage sont mises en file (8 au plus), `AccountStore.register_precheck` / `credentials` / `register(..., prepared)`, `AuthService.login_checked`. Debit par session : seau `Conn.costly` pour `chat_send` et `admin_cmd` (`error{rate_limited}`, sans coupure). Sanction automatique : `server/security/address_penalties.gd` (`AddressPenalties`, `ServerHost.penalties`) : une adresse coupee 3 fois en 10 min (debit, mauvais mots de passe) est refusee 10 min a l'`accept`. `WorldContacts.cached_book` (2 s de temps sim, invalide par `_save`) pour le filtre des ignores ; les invitations de groupe / d'echange d'un ignore etaient deja filtrees (P3.05b). `test_security.gd` : 4 tests (le tick ne bloque pas pendant 0,4 s de hachage, debit par session, `AddressPenalties`, bannissement par l'hote via vrais WebSockets), `test_contacts.gd` : 1. 755 tests, 0 echec. | APPROX(S.05c) : 10 puis 2 / s pour les commandes couteuses, 3 coupures / 10 min = 10 min de ban, cache de 2 s (un changement fait par un autre monde est vu apres au plus 2 s), argon2 : aucune extension Godot disponible, SHA-256 itere garde (APPROX(S.02a)). Dette : pas d'audit de l'HDV (n'existe pas), le bannissement d'adresse est en memoire (perdu au redemarrage), pas de commande GM pour le lever (`penalties.clear`). Lot done. `P1.17b` reste `doing` (14 grades sans source), `P1.15` attend P1.14 |
| 2026-10-06 | C.06a-d | Publication du contenu façon launcher. Le serveur ne hache plus au démarrage : `server/content_publisher.gd` (`ContentPublisher.publish` : `WorldPackage.build` avec points de reprise atomiques de l'index toutes les 5 s et progression, `WorldBundle.build(into=)` reprenable par `progress.json`, un zip par zone `zones/<z>/pack.zip` reprenable, `release.json` = tampon des tailles, `current.json` écrit en dernier, versions inachevées supprimées, élagage `--keep-versions`) ; `server/published_package.gd` (`PublishedPackage.load_package` : lecture des JSON, existence et taille de chaque artefact, `blobs.json` = empreinte -> fichier, aucun hachage ; `verify`). `ServerApp` : `--build-packages` publie et quitte, `http-port` charge les paquets publiés et refuse de démarrer s'ils manquent (message : lancer l'étape de build), `--build-on-start` = ancien comportement, `--no-zone-packs`, `--copy-files`, `--keep-versions` ; `ServerCheck` dit publié / non publié. `ContentApi` : `GET /worlds/<id>/zones/<zone>/pack.zip` (jeton, Range, 404 / 409) ; `ContentClient.install_zone_pack` (une requête, empreinte du manifeste puis de chaque entrée, repli fichier par fichier). `tools/publish_content.py` (publication sans le jeu, `--static-out` assemble l'arborescence servable en statique), `build_release.py --publish`, `serveur-lancer.bat` (`PACKAGES`, `publier`, publie seul au premier démarrage) ; `docs/EXPORT.md` « Publication du contenu », `ARCHITECTURE.md`, `CLAUDE.md`. `tests/test_content_publish.gd` (8 tests : version et pointeur, serveur qui lit sans hacher, build interrompu puis repris, élagage, vrai serveur HTTP 127.0.0.1 avec zone en une requête, sans zip / zip abîmé, `files/<hash>`, mise en page = API) ; `test_release.gd` adapté. **Mesures (incarnam, 19 880 fichiers, 1,9 Go)** : avant, premier démarrage = 280 s (hachage + zip de 981 Mo en 50 parties), puis ~12 s à chaque démarrage (cache de hachage + parcours) ; après, publication 279 s la première fois, 2 à 12 s si rien n'a changé, et **démarrage du serveur : lecture des paquets 165 ms, processus complet 2,6 s** (écoute comprise). | Le monde `dofus` n'a pas été recalculé (disque, 22 Go) : les zones sont testées sur la fixture `zx` seulement ; la publication complète de `dofus` (17 k maps, 533 zones, zips de zones) reste à mesurer. `--copy-files` duplique le contenu (non essayé sur `dofus`). L'ancien dossier `user://packages/<monde>/bundle/` (988 Mo ici) n'est plus lu : à supprimer à la main. Le client ne lit pas encore un contenu depuis une autre URL que le serveur de jeu (hébergement statique : format prêt, pas de client). Suite de tests : sporadiquement des tests WebSocket de cluster / contacts / reprise échouent sur cette machine chargée (aussi avec `TEST_SKIP=test_content_publish`, toujours verts seuls). |
| 2026-10-09 | C.02f | Télécharger tout le monde en arrière-plan. `ZoneGate` : `background` (option du joueur), `set_background`, `pause_background`, `background_line()` ; quand rien n'est demandé il installe une à une toutes les zones de l'index (ordre des ids), et une zone attendue par le joueur coupe celle en cours (`cancel_requested`, les octets déjà au cache servent à la reprise) puis passe devant ; un échec de fond ne montre rien (réessai après `retry_s`). `LaunchScreen` : case « Télécharger tout le monde en arrière-plan » (mémorisée dans `launch.cfg` `[content] background`), ligne de progression en bas à gauche. Correctif en passant : `_save_memory` recréait `launch.cfg` et effaçait le dossier des mondes (C.04), il relit le fichier d'abord. `tests/test_zone_background.gd` : 5 tests (défaut éteint, toutes les zones, la zone demandée d'abord, pause, fil de téléchargement) sur un vrai serveur HTTP en 127.0.0.1 ; capture de l'écran de lancement relue | APPROX(C.02f) : pas de bouton de pause dans l'interface (l'API existe), pas de pause automatique en combat ; la reprise d'une zone coupée repose sur le cache, pas sur un test de coupure en plein fil (timing non déterministe) ; le `tp` lointain avec un vrai serveur `dofus` n'est pas vérifié (C.02h). Prochain : C.02h (deux postes) ou P3.02b |
| 2026-10-10 | C.07 | Distribution du contenu façon launcher, en remplacement des zips de base / zips de zone / `blobs.json` / `/files/<hash>` / thread de préparation. Publication hors du serveur : `server/content_publisher.gd` (réécrit : `publish` = `WorldPackage.build` puis `publish_built` : contenus absents de tout bundle lus 64 à la fois sur le pool et revérifiés, `server/bundle_writer.gd` (bundles ~32 Mo nommés par leur SHA-256, `bundles.json`), un manifeste gzip par fragment, index de release nommé par son hash, pointeur `worlds.json` en dernier (`server/content_store.gd`), historique, `gc` (releases au-delà de `keep`, manifestes et bundles orphelins, anciens `versions/` `bundle/` `files/`)) ; format pur `shared/content_release.gd` (`plan_ranges`, validation). Serveur : `ContentApi` = fichiers statiques (`/worlds`, `/worlds/<id>/releases/`, `/manifests/`, `/bundles/` avec `Range`), tout sur le thread HTTP (joueurs passés par `sync_state`), monde ouvert non publié `unpublished` ; `ServerApp` sans thread de préparation ni `--build-on-start` / `--sync-packages` / `--copy-files` / `--no-bundle` / `--no-zone-packs` ; `WorldCluster` sans `package_builder`. Client : `content_client.gd` (réécrit : `plan_install` / `install` / `update` / `install_zone` / `repair`, état `_install/state.json`, journal de reprise, adoption des anciens caches), `client/range_downloader.gd` (remplace `BlobDownloader`), `WorldLoader` (liste = une requête, `measure` derrière, `repair`), `WorldLoadScreen` (« Vérifier », « ≤ »), `ZoneStreamer` (index = release locale). Supprimés : `world_bundle.gd`, `published_package.gd`, `content_bundle.gd`, `blob_downloader.gd`, `test_content_bundle.gd`. Tests : `test_content_publish.gd`, `test_content_ranges.gd` (nouveaux), `test_content_api.gd`, `test_content_zones.gd`, `test_world_loader.gd` réécrits en partie ; suite complète 773 tests verts (échecs isolés de WebSocket relancés seuls). **Mesures (cette machine)** : publication incarnam 33 s la première fois (279 s avant), 2,9 s sans changement ; dofus 271 s pour 8,4 Go et 110 147 contenus (29 min avant) ; dossier publié 11 Go pour les deux mondes (13 Go d'ancien format supprimés) ; serveur `--world=incarnam,dofus` : mondes ouverts en 265 à 473 ms, **aucune lecture du contenu**, port ouvert 1,6 à 5 s après le lancement du processus ; liste des mondes 21 ms, release 20 à 30 ms ; incarnam neuf : plan 310 ms, **premier octet 4 ms**, 1,9 Go en 22,8 s (82 Mo/s, 165 s avant) ; à jour : 0 fichier, aucun fichier lu ; dofus base 370 Mo en 14,4 s, 40 zones (1,5 Go) en 44 s. | Le client ne lit le contenu que depuis le serveur de jeu (format prêt pour un CDN, sans client). Le monde `test` garde son ancien dossier dans `packages/` (jamais republié). Pas de capture de l'écran des mondes dans ce lot. |
| 2026-10-11 | jouabilité (hors lot) | Détails pour jouer. (1) Double-clic = courir (Maj aussi) : `client/map_click.gd` (`MapClick` : clics de la map sortis de `client_session.gd`, `press` / `click` / `try_pending`). (2) Profondeur : les visuels des maps étaient 1,5 rang (64,5 px) trop haut par rapport à la grille (chaque élément animé tombait 64,5 px au-dessus de sa cellule, la porte de la grange des Champs au-dessus de sa cellule 274) : `DofusMapNode.GRID_SHIFT_Y` (les 17 353 maps extraites restent valables) ; le blé ne passe plus devant le personnage. (3) Hors-map flouté et assombri : `client/map_frame.gd` (`BackBufferCopy` + shader, masque d'une texel par cellule iso). (4) Curseur flèche sur une sortie, main sur ce qui s'utilise : `client/map_cursor.gd`. (5) Survol : `client/map_hover.gd` (sprites de l'élément éclairés, `DofusMapNode.elements_at(cell, gfx)`, case cerclée de blanc, infobulle : ressource + verbe + métier + niveau, « Repousse bientôt », porte → nom de la destination : « Astrub » sur la Route des âmes 174) ; Tab maintenu (`Shortcuts` `highlight`) = tous les éléments, portes et sorties. Les déclencheurs portent `to_name_id` / `to_area_name_id` (`WorldSource.get_map`). (6) La map tient au-dessus de la barre de sorts (`PlayerHud.reserved_bottom`, `band_changed`) ; le chat s'estompe au repos ; fenêtres ouvertes sur les côtés. Outils `client_shot` : `hoverat:<cell>`, `highlight`. Nouveau `tests/test_map_ui.gd` (double-clic, cibles et infobulles, Astrub, noms des portes via NetBackend, masque, visuels sur les cellules) | Pas de surbrillance en contour (shader) : éclaircissement + pulsation. Curseurs Dofus d'origine non extraits (flèches dessinées). |
| 2026-10-11 | jouabilité (hors lot) | Descente d'Incarnam : par Maître Anemo (PNJ 4360, Route des âmes 4,-3), comme le vrai jeu (guide de la quête « Destination Astrub ») : « partir explorer le Monde des Douze » → « Insister pour aller à Astrub » → « S'approcher du portail » = téléportation à Astrub (6,-19) 455. Arbres de dialogue écrits à la main (ids de texte du client seulement) dans `tools/extractor/dialogs.json`, écrits dans `worlds/<id>/dialogs.json` par `gamedata.py dialogs <monde>` (aussi à la fin de `npcs`), lus par `JsonWorldSource`. La porte « tonneau » (cellule 174 → Astrub) venait d'une ligne « hand-written » de JondoEmu (supposition de l'auteur des dumps) : écartée dans `jondo.door_routes`, retirée de la map. Fenêtre de dialogue : hauteur réelle du texte et des réponses longues ; le chat passe sous les fenêtres. `test_world` (descente par le dialogue, remontée par le portail d'Astrub), `test_map_ui` (« Incarnam » au survol du portail d'Astrub) | L'ordre des répliques d'Anemo est reconstitué (APPROX(P2.01)) ; la branche « pas fini Incarnam » (748434) n'est pas utilisée. |
| 2026-10-11 | jouabilité (hors lot) | Sorties de maps : `maps.py _neighbour` lisait une ligne `mapscrollactions` comme « pas de sortie » sur les côtés dont `<côté>Exists` = 0, alors que c'est « pas de surcharge : voisin de mapData » ; 1 042 maps du monde `dofus` avaient perdu des côtés (Astrub (8,-18) ne gardait que la gauche). Corrigé, et nouvelle commande `maps.py neighbors <monde>` qui recalcule les voisins d'un monde construit sans réextraire (dofus : 1 042 maps corrigées, incarnam : 0). Audit : depuis Astrub, 5 255 maps atteignables à pied ou par une porte ; le reste du continent (carte 1) = îles (Frigost, Otomaï, Wabbits, Nowel : bateau ou PNJ) et « Mode tactique ». Test `test_world::test_a_scroll_action_row_keeps_the_other_sides` | Passages en bateau / PNJ vers les îles : à faire (données serveur). 1 154 côtés ont un voisin sans case de sortie (falaises, ou à vérifier). |
| 2026-10-11 | jouabilité (hors lot) | Bords de map : dès que la souris passe au-delà des cases d'un côté qui mène à une autre map, flèche de ce côté, quelle que soit la distance le long du bord (`MapHover.edge_exit` : la case de sortie de ce côté la plus proche de la souris) ; un clic y marche puis change de map. Le hors-map n'est plus flouté en permanence : un léger flou (`MapFrame`, fondu) seulement pendant qu'une flèche de sortie s'affiche. Déplacements : au-delà de 3 pas (`MapClick.RUN_CELLS`, chemin depuis la position actuelle) le joueur court, d'un seul clic (cases, PNJ, ressources, portes, bords). `client_shot` : `hoverpast:<côté>[:<0..1>]`. Tests `test_map_ui` | — |
| 2026-10-11 | jouabilité (hors lot) | Mode tactique (touche T) : décor masqué (`DofusMapNode.set_decor_visible`), grille plate (`MapView._draw_tactical` : cases libres, obstacles, vue bloquée, sorties, portes), état gardé d'une map à l'autre et en combat (`ClientSession.set_tactical`). `client_shot` : `tactical`. Test `test_map_ui` | Gabarits officiels `tacticalModeTemplateId` non extraits. |
| 2026-10-11 | P1.18 | Tests de tous les sorts : contrats par type d'effet sur les 3 990 grades (arène neutre, jets forcés, oracle de cibles indépendant), 52 cas multi-tours en données, `SpellGaps` (29 écarts sourcés). Moteur : cibles fixées au lancer (+ invocations du lancer), téléportation sur la case visée (Bond, Pas Chassé, Fulgurance), attirances au plus près d'abord sans dépasser le centre, symétries d'une paire une fois, marques en anneau, `on` / `delay` sur invocations / marques / portails, multiplicateurs sans déclencheur, X<code> = <code>, retours en arrière hors historique, rang 1406 des monstres ; dommages mêlée / distance / sorts, résistances mêlée / distance, dommages critiques et reçus lus. Extracteur : 120, 293, 281, 296, 411, 413, 1075, 275, 1118, 1092 convertis, sorts `noop` ; `FightEffects` découpé (`FightLife`, `FightBuffs`) ; 4 scénarios réenregistrés | Suite : P1.18b (deux cas retirés, fumée du sort entier, audit, plus de cas, ménage) |
| 2026-10-11 | S.06 | Taux du serveur et drops bonus façon Temporis : `WorldRates` (`--xp-rate`, `--drop-rate`, `--kamas-rate`, `--job-xp-rate`, `--bonus-drops`, `--bonus-drop-rate`, `--bonus-drop-range`), partagé par tous les mondes d'un `LocalServer`, réglable aussi en solo (ligne de commande du client, `client_shot`, `sim_cli`). `BonusDrops` : jets à part, après les drops normaux, pools générés par `gamedata.py bonus_drops` (757 monstres liés à 429 panoplies, 1 076 équipements craftables sans panoplie). `welcome.world.rates`, `fight_end.rewards[].bonus_items`, ligne dans le chat, objets bonus encadrés dans la fin de combat, carte « taux » de l'admin web. `test_rates.gd` (6, dont `NetBackend`) | Les taux ne changent qu'au redémarrage (pas de commande GM) ; pas de réglage dans l'écran de lancement solo |
| 2026-10-11 | P4.01 | Donjons génériques (187 donjons de la table `dungeons`), testés sur le Bouftou Royal (id 1) : `shared/dungeon.gd` (règles : niveau, clés, salles, composition), `sim/world_dungeons.gd` (runs par joueur ou groupe, salles = `MapInstance` privées à clé négative, clé consommée à l'entrée, salle suivante quand tous les groupes sont vaincus, boss en dernière salle, défaite / départ / déconnexion), `protocol_dungeon.gd` (`dungeon_enter/leave/room/end`, `map.dungeons` dans `map_enter`), `worlds/<id>/dungeons.json` + clé `bosses` de `monsters.json` (`gamedata.py dungeons <monde>`, à relancer après `maps.py full`), client `DungeonModel` / `DungeonIndicator`. Tests : `test_dungeon*.gd` (traversée complète du Royal en LocalBackend, parcours via NetBackend). APPROX(P4.01) : compositions des groupes (aucune source), niveau du personnage, clés toutes consommées, porte ouverte à la salle vidée. Reste : mécaniques spéciales des boss, `disbanded` jamais envoyé, état de run non persisté, entrée par la porte réelle (bouton du panneau seulement), `world_assets.gd --world=dofus` à relancer pour les looks des boss. |
| 2026-10-11 | combat (hors lot) | Combat qui se fige (solo et reseau, tous les joueurs du combat) : `ClientSession._pump` remettait `_blocked` a vrai apres une sequence finie avant le retour de `_dispatch` (fight_turn a effets legers, fighter_move sans chemin) : plus rien ne le levait, le watchdog ne la voyait pas. Corrige (`_in_dispatch`), `fight_turn` leve `_waiting_reply`, `Fight._next_turn` pose `turn_end` avant les effets de debut de tour, `finish_fight` sans `front()` sur liste vide. Test `test_session_pump.gd` | Non reproduit cote sim : `finish_fight` efface le combat avant les recompenses (une erreur laisse un `fight_id` fantome) et `WorldFights.tick` n'isole pas les erreurs d'un combat. Tests deja rouges : `test_protocol_doc_is_up_to_date`, `test_release::test_check_passes_on_a_good_folder` |
| 2026-10-12 | ménage (hors lot) | Ménage du système et de l'architecture. Méta : `CLAUDE.md` réduit (29 à ~10 Ko) ; la carte par domaine va dans `docs/CARTE.md`, toutes les commandes dans `docs/COMMANDES.md` ; `/suite` mis à jour (Grep des Découvertes, `TEST_ONLY` en cours de route, suite complète une fois, `roadmap.py archive`, commit + push) ; `tools/workflows/chaine.js`, `RAPPORT_NUIT.md`, `REPRISE.md` supprimés ; mémoire réduite aux décisions. Roadmap : `roadmap.py archive` (lots faits + Journal sauf les 15 dernières lignes dans `docs/ROADMAP_ARCHIVE.md`, lus par `show` / `check` / `next`, `set` refusé sur un lot archivé), Découvertes dans `docs/DECOUVERTES.md` ; ROADMAP 395 à 50 Ko, mêmes `status` / `next`. Code : `ProtocolSchema` (`shared/protocol_schema.gd` : `EXTENSIONS`, `all()`, `validate`) remplace 4 listes d'extensions écrites à la main (le fuzz de `test_security` oubliait `ProtocolContacts`) et sort `protocol.gd` de la limite (799 à 765 lignes) ; test `test_every_extension_is_wired` ; démo iso héritée supprimée (`GameEntity`, `EntityView`, `iso_demo`, `benchmark.gd`), `IsoGrid` dans `shared/`, `AnimMap` dans `client/` ; `test_src_only_holds_the_layers` ; `WorldSim.enter_map` délègue à `WorldJobs.on_enter_map` / `WorldTravel.on_enter_map` (même ordre d'événements : 33 scénarios OK) ; `TEST_ONLY` / `TEST_SKIP` acceptent une liste ; `test_protocol_doc_is_up_to_date` ignore les fins de ligne CRLF. Suite complète : 824 tests ; échecs seulement dans des tests instables déjà rouges sur HEAD (`test_accounts`, `test_world_loader` : verts relancés) ; capture `client_shot` relue | R.03 (alléger `client_session.gd` / `fight_view.gd`), R.04 (tests dépendants de l'ordre ou instables) |

## Découvertes

Dans `docs/DECOUVERTES.md` (ajouter en tête ; chercher avec Grep plutôt que tout lire).
