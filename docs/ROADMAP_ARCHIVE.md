# Roadmap : archive

Lots faits et ancien Journal, déplacés de `ROADMAP.md` par `python tools/roadmap.py archive`. `roadmap.py` les lit (dépendances, `show`, `check`).

## A — Acquis (déjà fait avant la roadmap)

### [x] A.01 Rendu des entités Dofus 3
- Dépend : —
- Données : bundles d'entités (os, animations, skins), extraits par `tools/extractor/extract.py`
- Règles : rendu identique au client d'origine, vérifié par le golden d3-ts-renderer
- Commun : — | Serveur : —
- Protocole : —
- Client : `game/addons/dofus_renderer`
- Tests : golden `tools/golden/compare.py`
- Parité : ☑ règles sourcées ☑ tests ☑ sim_cli ☑ capture ☑ doc

### [x] A.02 Exploration : maps réelles, déplacement, changement de map, groupes de monstres
- Dépend : A.01
- Données : maps Incarnam 3×3, i18n, `worlds/incarnam`, `worlds/test`
- Règles : géométrie 14×20, A*, timing Dofus des pas, cellules de bord, groupes errants
- Commun : `WorldSim`, `MapInstance`, `MonsterGroupAI`, `shared/map_*`, `Movement` | Serveur : —
- Protocole : `hello`, `move`, `change_map`, `welcome`, `map_enter`, `actor_*`
- Client : `ClientSession`, `MapView`, `ActorView`, `GroupView`
- Tests : `tests/test_sim.gd`
- Parité : ☑ règles sourcées ☑ tests ☑ sim_cli ☑ capture ☑ doc

### [x] A.03 Combat complet v1 : placement, initiative, effets, IA, gains
- Dépend : A.02
- Données : sorts Pandawa et sorts des monstres d'Incarnam (`data/spells.json`), membres des groupes (grades, stats, drops), `experience.json`, `items.json`
- Règles :
  - dégâts, soins, vol de vie ;
  - poussée avec collision ;
  - PA/PM avec esquive ;
  - buffs, états, boucliers, poisons ;
  - tacle, critiques, cooldowns ;
  - formules XP et prospection (`luaformulas` 99/100/106).
- Commun : `sim/fight/*`, `FightRules`, `SpellBook` | Serveur : —
- Protocole : `fight_*`, `spell_cast`, `fight_end{rewards}`
- Client : `FightView`, `FightHud`, `FightResultWindow`, `SpellFx`
- Tests : `tests/test_fight.gd`
- Parité : ☑ règles sourcées ☑ tests ☑ sim_cli ☑ capture ☑ doc

### [x] A.04 Personnage persistant v1
- Dépend : A.03
- Données : table d'XP
- Règles :
  - niveau, XP, kamas, capital (+5 par niveau), inventaire simple ;
  - régénération de 1 PV/s ;
  - après une défaite : retour au point de départ avec 1 PV.
- Commun : `Character`, `CharacterStore` (devenu `Persistence` en P0.02) | Serveur : persistance en base de données (S.03)
- Protocole : `player_stats`, `boost_stat`
- Client : `PlayerHud`, `InventoryPanel`
- Tests : `test_fight.gd` (sauvegarde, régénération, boost)
- Parité : ☑ règles sourcées ☑ tests ☑ sim_cli ☑ capture ☑ doc

## P0 — Fondations

### [x] P0.01 Outillage de la roadmap
- Dépend : —
- Données : —
- Règles : un lot = une session ; statut, journal et découvertes tenus à jour
- Commun : — | Serveur : —
- Protocole : —
- Client : —
- Tests : `python tools/roadmap.py check`
- Parité : ☑ règles sourcées ☑ tests ☑ sim_cli ☑ capture ☑ doc

### [x] P0.02 Frontière standalone / serveur
- Dépend : P0.01
- Données : —
- Règles :
  - la sim ne connaît ni le réseau ni la base de données. Elle reçoit des interfaces injectées :
    - `Persistence` : comptes, personnages, banque, et plus tard HDV, guildes, maisons. Des documents JSON par collection, avec `commit` pour les écritures groupées. Les appels sont synchrones (décision de P0.02, voir Découvertes) ;
    - `Clock` ;
    - un RNG seedé ;
  - la notion de session (`session_id` → joueur) est séparée de la notion de personnage.
- Commun : `sim/persistence.gd`, `sim/clock.gd`, `shared/data_files.gd`, `WorldSim(source, seed, persistence, clock)`, `connect_player(nom, look, compte)` ; hôte `api/local_server.gd`, `api/file_persistence.gd`, `api/system_clock.gd` | Serveur : `DbPersistence` (S.03)
- Protocole : inchangé
- Client : —
- Tests :
  - `test_architecture` interdit `FileAccess`, `DirAccess`, `HTTP`, `WebSocket`, `Time`, `OS` et le RNG global dans `sim/` et `shared/` ;
  - `tests/test_hosting.gd` : deux sessions sur un même monde, reconnexion qui termine l'ancienne session, personnage retrouvé par un nouveau serveur, documents `Persistence`, `FilePersistence` avec lecture des anciennes sauvegardes.
- Parité : ☑ règles sourcées ☑ tests ☑ sim_cli ☑ capture ☑ doc

### [x] P0.03 Pipeline de données générique
- Dépend : P0.01
- Données :
  - lister **tous** les `*dataroot` des bundles, dont ceux qui manquent aujourd'hui : quests, npcs, jobs, recipes, skills, interactives, itemsets, achievements, titles, emotes, dungeons, alignment… ;
  - les exporter en JSON dans `game/content/Content/Data`.
- Règles : l'extraction est idempotente et incrémentale, avec un contrôle de l'espace disque
- Commun :
  - `GameData` devient un loader générique et paresseux : `GameData.table("items")`, `GameData.get("items", id)` ;
  - les tables dérivées légères, nécessaires au jeu, sont écrites dans `game/data/`.
  - Serveur : charge les mêmes fichiers.
- Protocole : —
- Client : —
- Tests : le loader sur des fixtures ; une clé absente ne fait pas planter (`tests/test_game_data.gd`)
- Parité : ☑ règles sourcées ☑ tests ☑ sim_cli ☑ capture (sans objet : aucun changement client) ☑ doc
- Livrable annexe : `docs/data_catalog.md`, qui indique pour chaque table ses champs utiles et les lots qui s'en servent.

### [x] P0.04 Protocole robuste
- Dépend : P0.01
- Données : —
- Règles :
  - version de protocole dans `hello` et `welcome` ;
  - enveloppe `{t, seq}` ;
  - `error{code, msg, cmd}` avec des codes typés ;
  - une table des messages qui liste le nom, les champs et le sens.
- Commun : `Protocol` avec des constructeurs pour chaque message et `Protocol.validate(msg)` | Serveur : il rejette les messages invalides avant la sim
- Protocole : tous les messages
- Client : erreurs affichées proprement (toast)
- Tests : aller-retour JSON sur chaque constructeur ; `validate` rejette les champs manquants (`tests/test_protocol.gd`, 7 tests, dont un combat entier sans aucun événement hors schéma et `docs/PROTOCOL.md` à jour)
- Parité : ☑ règles sourcées ☑ tests ☑ sim_cli ☑ capture ☑ doc

### [x] P0.05 Harnais de parité et de non-régression
- Dépend : P0.04
- Données : —
- Règles :
  - un scénario est un fichier `tests/scenarios/*.jsonl` : une seed, des commandes horodatées, et les événements attendus (sous-ensemble des champs) ;
  - `sim_cli` peut enregistrer un scénario.
- Commun : `tests/test_scenarios.gd` rejoue tous les scénarios | Serveur : S.07 rejoue les mêmes scénarios via le réseau
- Protocole : —
- Client : —
- Tests : 3 scénarios de départ : exploration, combat gagné, combat perdu (`tests/test_scenarios.gd` : rejeu, déterminisme, détection d'écart, correspondance partielle)
- Parité : ☑ règles sourcées ☑ tests ☑ sim_cli ☑ capture (sans objet : aucun changement client) ☑ doc
- Livrable annexe : `docs/RULES_SOURCES.md`. Il explique comment trouver une règle (`luaformulas`, tables, champs `criteria`, sources communautaires), et contient le registre des `APPROX`.

### [x] P0.06 Kit d'UI
- Dépend : P0.01
- Données : textures d'UI Dofus 3 (`tools/extractor/ui.py`) : cadres, boutons, onglets, barres, emplacements d'objets
- Règles :
  - fenêtres déplaçables, fermables avec Échap, et qui gardent leur position ;
  - raccourcis clavier centralisés ;
  - infobulles riches : objet, sort, monstre.
- Commun : — | Serveur : —
- Protocole : —
- Client :
  - `client/ui/` avec `UiWindow`, `UiTabs`, `ItemSlot`, `ItemTooltip`, `SpellTooltip`, `ProgressBar`, `Toast`, `ContextMenu` et `Shortcuts` ;
  - migration de `InventoryPanel` et `FightResultWindow` sur ce kit.
- Tests : `client_shot` d'une page de démo du kit (`tools/ui_demo.gd`), captures du client réel (fenêtres C/I, survol d'un groupe, fin de combat), test sim (membres publics des groupes)
- Parité : ☑ règles sourcées ☑ tests ☑ sim_cli ☑ capture ☑ doc

## M — Multijoueur : un serveur sur ta machine, des amis par Hamachi

### [x] S.01 Serveur headless et NetBackend
- Dépend : P0.02, P0.04
- Données : —
- Règles :
  - `server/main.gd` (Godot headless, `--server`) héberge un `LocalServer` (donc un `WorldSim` par monde) et accepte des connexions WebSocket JSON ; une connexion = un `LocalBackend`-équivalent côté serveur (`connect_player`), mêmes messages que `Protocol` (P0.04, une trame texte = un message) ;
  - transport et hôte réunis dans `server/server_host.gd` (`ServerHost` : `TCPServer` + `WebSocketPeer` (accept_stream), liste des connexions, tick de la sim à chaque `poll`, aucune règle) ; `main.gd` ne fait que lire les arguments et appeler `poll` ;
  - `api/net_backend.gd` : `NetBackend` implémente `GameBackend` (`send`, signal `event`, `time_ms`) sur un `WebSocketPeer` client ; les erreurs réseau (connexion refusée, coupure) deviennent un événement d'erreur du protocole, jamais une exception ;
  - horloge : `ping{t0}` / `pong{t0, server_ms}` (`t` est déjà le type du message), `time_ms` du client = horloge du serveur estimée (décalage au meilleur aller-retour, médiane de 5 mesures, relancé toutes les 10 s) ;
  - arguments : `--server --port=7777 --world=<id>[,<id>] --save-dir=<dossier>` ; arrêt propre (sauvegarde des personnages) sur SIGINT / fermeture ;
  - décision : le contenu HTTP est servi par C.02 sur un second port (`--http-port`, défaut port + 1) car une même socket ne peut pas être lue d'abord comme HTTP puis passée à `WebSocketPeer`.
- Commun : aucune règle nouvelle, le serveur ne fait qu'héberger `sim/` | Serveur : `game/src/server/main.gd`, `server_host.gd`, `game/src/api/net_backend.gd`
- Protocole : `ping` / `pong` (schéma, constructeurs, `docs/PROTOCOL.md` régénéré), code d'erreur de transport ; le reste est identique
- Client : écran de lancement « Solo / Serveur (adresse:port) » (le choix du monde et du personnage restent ceux de P1.01) ; l'adresse est mémorisée dans `user://` ; message clair si le serveur est injoignable
- Tests : un test lance le serveur dans le même processus (boucle sur 127.0.0.1, port libre) et vérifie qu'un `NetBackend` joue une exploration (`hello`, `move`, `change_map`) ; l'horloge converge ; une coupure donne une erreur ; `test_architecture` interdit à `sim/`, `shared/` et `client/` de référencer `server/` ; test de non-régression : la suite complète passe sans réseau
- Parité : ☑ règles sourcées (aucune règle : hôte seulement) ☑ tests ☑ sim_cli ☑ capture ☑ doc

### [x] P3.01 Plusieurs joueurs sur une map
- Dépend : P0.02, S.01
- Données : —
- Règles :
  - visibilité par map ;
  - déplacements diffusés ;
  - arrivée et départ ;
  - collisions (les joueurs se traversent, comme dans Dofus).
- Commun : `WorldSim` multi-session, diffusion par map | Serveur : une session par connexion
- Protocole : existant (`actor_*`) ; l'apparence d'un autre joueur (look, nom, classe, niveau) passe dans `actor_add`
- Client : autres joueurs rendus (look, nom), infobulle et menu contextuel sur un joueur
- Tests : 2 clients sur la même map voient les déplacements l'un de l'autre (d'abord deux `LocalBackend` sur un `LocalServer`, puis deux `NetBackend`) ; arrivée et départ à un changement de map ; un joueur en combat n'est plus sur la map
- Parité : ☑ règles sourcées (Dofus : les joueurs se traversent, fiche publique = nom, look, classe, niveau ; rien de sourcé en formule) ☑ tests ☑ sim_cli (trace ci-dessous, un seul joueur : `sim_cli` ne pilote pas deux sessions, S.07) ☑ capture ☑ doc

### [x] S.02a Comptes minimaux
- Dépend : S.01, P1.01
- Données : —
- Règles :
  - création de compte (login unique, mot de passe) puis `login` ; un jeton de session aléatoire (32 octets) est renvoyé et exigé ensuite, y compris par l'API de contenu (C.02) ;
  - mot de passe jamais en clair : sel aléatoire + SHA-256 itéré (APPROX(S.02a) : Godot n'a ni argon2 ni bcrypt sans GDExtension ; 100 000 itérations, comparaison en temps constant ; à remplacer en S.05 si une extension est disponible) ;
  - une seule connexion par compte (la seconde est refusée : `E_ALREADY_CONNECTED`) ;
  - un compte possède ses personnages (`CharacterRoster` existant, clé = compte) ;
  - comptes stockés par `Persistence` (`accounts/<login>`), jamais de logique propre à un jeu dans `server/auth/` ;
  - rôles : `player` (défaut) et `gm` (donné à la main dans le fichier de comptes ou par A1.01).
- Commun : la sim reçoit un `session → compte → personnage` déjà authentifié | Serveur : `game/src/server/auth/`
- Protocole : `register`, `login`, `login_ok{token, role}`, `login_error{code}` ; le `hello{world}` n'est accepté qu'après un `login_ok` en mode serveur (le mode standalone reste sans compte)
- Client : écran de connexion réel (adresse, login, mot de passe, créer un compte), puis choix du monde
- Tests : création puis connexion ; mauvais mot de passe refusé ; double connexion refusée ; jeton invalide refusé ; le mot de passe n'apparaît jamais dans un fichier ni un journal
- Parité : ☑ règles sourcées (rien de Dofus : APPROX(S.02a) pour le hachage) ☑ tests (`test_accounts.gd`, 10) ☐ sim_cli (sans objet : `sim_cli` n'a pas de comptes, S.07 rejouera les scénarios via `NetBackend`) ☑ capture (`launch_shot` : écran de connexion, refus lisible) ☑ doc

### [x] C.01 ContentSource
- Dépend : P0.03
- Données : inventaire de tout ce que le client lit dans `res://` (`content/`, `data/`, `worlds/`) : `grep` des `res://` et des `load` / `FileAccess` du client, de `GameData`, de `DataFiles` et de `addons/dofus_renderer`
- Règles :
  - une couche unique `ContentSource` : `read_text`, `read_bytes`, `exists`, `load_texture` / `load_resource`, `list_dir`, avec deux racines : `res://` (dev, solo) ou le cache `user://worlds/<id>/` ;
  - aucun chemin `res://content/`, `res://data/` ou `res://worlds/` en dur dans le client ni dans le moteur : tout passe par `ContentSource` (vérifié par `test_architecture`) ;
  - `DataFiles` (seule lecture de fichiers de la sim) lit via `ContentSource`, donc le serveur et le client lisent les mêmes octets ;
  - les ressources non importables à l'exécution (le cache contient des PNG / WebP / JSON bruts, pas des `.import`) sont chargées par `Image.load_from_file` ; le rendu `dofus_renderer` accepte une source de contenu injectée (interface minimale, l'addon reste autonome) ;
  - le monde actif est une donnée : `ContentSource.use_world(id)` ; tant qu'aucun cache n'existe, repli sur `res://` (standalone inchangé, aucun test existant ne bouge).
- Commun : `ContentSource` dans `shared/` (interface) | Serveur : lit les mêmes fichiers pour construire les paquets (C.02)
- Protocole : —
- Client : aucun changement visible ; toutes les lectures de fichiers passent par la couche
- Tests : lecture identique depuis `res://` et depuis un cache de test ; fichier manquant = erreur claire ; test d'architecture : aucun `res://content`, `res://data` ni `res://worlds` hors de la couche ; les 448+ tests existants passent inchangés ; capture client identique avant / après
- Parité : ☐ règles sourcées ☐ tests ☐ sim_cli ☐ capture ☐ doc

### [x] C.02 Paquets de monde et API de contenu
- Dépend : C.01, S.01, S.02a
- Données : manifeste, format versionné ; liste des fichiers d'un monde = `worlds/<id>/*`, les tables de `game/data` qu'il référence, les assets de `game/content/` qu'il utilise (sélection par monde, `world.json` : `content: [globs]`) ; **`game/content/` pèse 22 Go** : le paquet ne contient QUE les assets réellement utilisés par le monde (déduits des maps, entités, sorts, interface du monde, pas un copier-coller du dossier), construit dans un dossier configurable (le disque C: est à 98 %)
- Règles :
  - **paquet de monde** : `manifest.json` = `{format: 1, world, module, version, files: [{path, hash, size}]}` ; `hash` = SHA-256 du contenu ; `version` = hash de la liste triée des (chemin, hash) ; `module` est lu dans `world.json` (générique, voir G.01) ;
  - outil serveur `tools/world_package.gd` (et `--build-packages` du serveur) : construit le manifeste d'un monde depuis `game/` et `game/content/`, stocké dans `user://packages/<id>/` ; reconstruit seulement si un fichier a changé (cache par date et taille) ; vérifie `df -h /c` avant d'écrire (disque presque plein : une seule copie, liens par hash) ;
  - API HTTP (second port, jeton de session exigé dans `Authorization: Bearer`) : `GET /worlds` (liste : id, nom, version), `GET /worlds/<id>/manifest.json`, `GET /worlds/<id>/files/<hash>` (octets, en-têtes `Content-Length`, `ETag` = hash, `Range` pour reprendre un téléchargement) ; tout le reste = 404 ;
  - liste blanche : seul un hash présent dans le manifeste du monde est servi (aucun chemin fourni par le client n'est ouvert sur le disque) ;
  - décisions : serveur HTTP écrit à la main sur `TCPServer` (HTTP/1.1, `Connection: close`, un fichier à la fois, lecture par blocs de 1 Mo) ; pas de compression (images déjà WebP).
- Commun : `ContentManifest` pur (construction, comparaison, vérification de hash) dans `shared/` | Serveur : `game/src/server/content_api.gd`, `http_server.gd`
- Protocole : — (HTTP, hors du protocole de jeu)
- Client : `ContentClient` (sans écran) : `list_worlds`, `fetch_manifest`, `diff(manifest, cache)`, `download(missing)` avec reprise et vérification de hash, écriture atomique dans le cache (`.part` puis renommage)
- Tests : manifeste stable (même contenu = même version) et sensible à un octet ; `diff` ne demande que le manquant ; hash faux = fichier rejeté ; reprise via `Range` ; 401 sans jeton ; 404 pour un hash hors manifeste et pour `..` ; deux clients simultanés
- Parité : ☑ règles sourcées (rien de Dofus : format et HTTP propres au moteur) ☑ tests (`test_content_api.gd`, 21) ☐ sim_cli (sans objet : pas de règle de jeu) ☐ capture (sans objet : pas d'écran avant C.03 ; vérifié en processus séparés, voir Journal) ☑ doc
- Reste : la sélection AUTOMATIQUE des assets d'un monde (voir C.02b) ; en attendant `world.json` `content: [globs]`.

### [x] C.02b Sélection des assets d'un monde
- Dépend : C.02
- Données : ce que lit le client pour afficher un monde : maps (`maps/<id>.json` : décors, fonds), entités (monstres, PNJ, classes), sorts (icônes, animations), interface, polices, `I18n`, `Data`
- Règles :
  - outil `tools/world_assets.gd` (`WorldAssets`, `server/world_assets.gd`) qui calcule la liste de globs d'un monde depuis ses maps, `monsters.json`, `npcs.json`, `shops.json`, `quests.json`, les recettes, les invocations, les corps et visages jouables et les objets qu'il référence, plus un socle d'interface commun, et l'écrit dans `worlds/<id>/_content.json` (lu par `WorldPackage`, hors du manifeste) ;
  - mesure : taille du paquet par monde (`GET /worlds` donne `size`), objectif Incarnam << 22 Go : **1,87 Go** ; le client affiche Incarnam depuis le cache seul (voir Journal) ;
  - vérification : `ContentSource.trace_*`, `client_shot --trace=`, `world_assets --check-trace=` : 3113 chemins lus par 5 sessions, 0 hors paquet ; client exporté, cache téléchargé, aucun `res://content`.
- Commun : — | Serveur : l'outil
- Protocole : —
- Client : aucun (`ContentSource` : trace optionnelle)
- Tests : `test_world_assets.gd` (3) : un monde minuscule, les globs couvrent tout ce que le rendu lit et rien d'autre, le paquet ne contient que cela, un client qui s'authentifie par WebSocket (127.0.0.1) et télécharge par HTTP lit tout depuis son cache
- Parité : ☑ règles sourcées (rien de Dofus dans le code : formats de `worlds/` et `data/`) ☑ tests ☐ sim_cli (sans objet : aucune règle de jeu) ☐ capture (sans objet : le client n'a pas changé, vérifié par la trace des chemins lus) ☑ doc
- Reste : télécharger plus vite (C.02c : ~25 fichiers/s, 20 000 fichiers = 13 min) ; limiter les skins d'objets au niveau du monde.

### [x] C.03 Écran de chargement client
- Dépend : C.02, S.02a
- Données : —
- Règles :
  - après le login, le client demande la liste des mondes, l'utilisateur en choisit un, le client compare le manifeste à son cache `user://worlds/<id>/` et ne télécharge que ce qui manque ou a changé ;
  - le chargement du monde (`ContentSource.use_world`) n'a lieu qu'une fois le cache complet et vérifié ;
  - « Mettre à jour » quand le manifeste d'un monde change (comparaison de `version` à chaque connexion) ; fichiers devenus inutiles supprimés après une mise à jour réussie ;
  - échec réseau en cours de route : le cache reste cohérent, on reprend là où on s'est arrêté ; espace disque insuffisant = message avant de commencer (taille totale du manifeste).
- Commun : — | Serveur : —
- Protocole : — (HTTP via `ContentClient`)
- Client : écran de choix du monde (nom, version, taille à télécharger), barre de progression (fichiers et octets, vitesse), bouton « Annuler » / « Réessayer », cache réutilisé au lancement suivant sans retélécharger (vérification des hash paresseuse : taille d'abord, hash complet après une coupure)
- Tests : modèle d'écran sans Node piloté par un serveur local (premier lancement = tout, deuxième = rien, un fichier changé = un fichier) ; coupure puis reprise ; capture relue (liste des mondes, barre de progression)
- Parité : ☑ règles sourcées (rien de Dofus : cache et HTTP du moteur) ☑ tests (`test_world_loader.gd`, 9) ☐ sim_cli (sans objet : pas de règle de jeu) ☑ capture (liste, progression, relues) ☑ doc
- Reste : les assets d'un monde (C.02b) : tant que `world.json` n'a pas de `content`, le cache d'Incarnam ne contient que les données et le client n'a pas d'images.

### [x] C.04 Dossier de contenu configurable
- Dépend : C.03, X.01
- Données : — (réglage du joueur : `user://launch.cfg`, section `[content]`, clé `folder`)
- Règles :
  - le client choisit où sont stockés les mondes téléchargés : n'importe quel dossier, n'importe quel disque (`D:/Jeux/SuperDofus`, avec espaces), mémorisé ; priorité : option `--content-dir=<dossier>` (aussi mémorisée), dossier mémorisé, sinon l'ancien `user://worlds` ;
  - `ContentSource.set_cache_base` / `cache_base()` : le dossier de base de tous les caches (`use_world` et `cache_dir_for` le suivent quand on ne leur en passe pas un) ; `WorldLoader.cache_base` le suit par défaut ;
  - `ContentFolder` (modèle sans Node) : `resolve`, `remember`, `apply`, `validate` (absolu, créable, écriture testée, espace libre) ; avant un téléchargement `WorldLoader.install` vérifie déjà l'espace (taille du manifeste + 5 %), et explique un dossier inaccessible (disque absent) ou plein en disant de changer de dossier ;
  - migration de l'ancien cache : si `user://worlds` contient des mondes (dossier avec `manifest.json`) et que le joueur choisit un autre dossier, l'écran propose de les **déplacer** (renommage si même disque, sinon copie puis suppression, espace vérifié ; un monde déjà présent dans la destination est gardé, l'ancien reste) ; **réutiliser** = garder l'ancien dossier comme dossier de contenu (c'est le choix par défaut proposé).
- Commun : `ContentSource` (base configurable) | Serveur : —
- Protocole : — (réglage local, hors du protocole de jeu)
- Client : `ContentFolderScreen` (au premier lancement sans option en ligne de commande, puis bouton « Changer… » de l'écran de lancement qui affiche le dossier courant) : chemin, « Parcourir… » (sélecteur natif), espace libre, proposition de déplacer l'ancien cache
- Tests : `test_content_folder.gd` (7) : ordre de résolution et conservation des autres mémoires du fichier ; validation (relatif, sous un fichier, espaces, espace libre réel) ; migration (déplacé, déjà présent gardé, même dossier) ; un client qui s'authentifie par WebSocket (127.0.0.1) télécharge dans un dossier au choix, le lit depuis là, le déplace ailleurs et le retrouve complet sans retélécharger, un dossier inécrivable est expliqué
- Parité : ☑ règles sourcées (rien de Dofus : réglage du moteur) ☑ tests ☐ sim_cli (sans objet : aucune règle de jeu) ☑ capture (`tools/folder_shot.gd`, relue) ☑ doc
- Reste : la copie entre disques n'a pas de barre de progression (écran figé pendant un gros déplacement) ; pas de test automatique du chemin copie (le renommage ne passe jamais par là sur un seul disque).

### [x] C.05 Paquet zip de base par monde
- Dépend : C.02b, C.03, C.04
- Données : le manifeste d'un monde (C.02) ; Incarnam = 19 880 fichiers, 1 881 Mo
- Règles :
  - le serveur construit pour chaque monde un **zip de base** (`server/world_bundle.gd`, `WorldBundle`) : un seul exemplaire de chaque contenu distinct du manifeste (entrée nommée par son SHA-256 : pas de chemin dans l'archive, rien à échapper), découpé en parties `part-NNN.zip` d'environ 256 Mo de fichiers (`--bundle-mb`, `--no-bundle` pour s'en passer) ; les formats déjà compressés (webp, png, jpg, ogg, mp3, dds) sont stockés tels quels, le reste est compressé (deflate) ;
  - le découpage est **déduit du manifeste** (`shared/content_bundle.gd`, `ContentBundle.plan`, pur) : serveur et client calculent les mêmes parties, l'index (`bundle.json` : `{format, world, version, max_source, parts: [{name, size, hash}]}`) ne porte que la taille et l'empreinte de chaque zip, et le client sait quelle partie contient quoi sans liste de hash ; `validate` refuse un index d'une autre version ou qui ne colle pas au manifeste ;
  - stockage `<package-dir>/<id>/bundle/<version>/` ; reconstruit seulement quand la version du manifeste change (les anciennes versions sont supprimées) ; construit au démarrage du serveur ou par `--build-packages` ;
  - API de contenu : `GET /worlds/<id>/bundle.json` et `GET /worlds/<id>/bundle/<part>` (jeton obligatoire, `Range` pour reprendre, `ETag` = empreinte ; seuls les noms de l'index sont servis, 409 si le zip a changé sur disque depuis la construction, 404 pour un monde sans zip) ;
  - client (`ContentClient.install_bundle`) : ne prend que les parties qui contiennent un contenu manquant, et seulement si elles pèsent moins de 90 % des fichiers qu'elles remplacent (`BUNDLE_GAIN`) : une première installation passe par le zip, une mise à jour par fichier (diff) ; chaque partie est téléchargée dans `<dossier du monde>/_bundle/` (`.part` repris par `Range` après une coupure), son empreinte est comparée à l'index (**un zip abîmé est refusé et supprimé**), puis décompressée par `ZIPReader` : chaque fichier est vérifié contre le manifeste (taille + SHA-256) avant d'être écrit (`.part` puis renommage), la partie est supprimée, l'état de reprise (`progress.json`) est sauvegardé ; après une coupure en pleine décompression, ce qui est installé n'est pas réécrit ;
  - un zip inutilisable (abîmé, absent, d'une autre version) ne bloque jamais : `WorldLoader.install` retombe sur le téléchargement fichier par fichier (`fallback`) ; une coupure réseau ou une annulation s'arrête et reprendra là ;
  - écran de chargement : deux phases, « Archive n / N » (octets du zip) puis « Décompression, archive n / N », puis éventuellement « Fichier » pour le reste ; vitesse et temps restant par phase (`WorldLoader.eta`, `WorldLoadScreen.format_duration`).
- Commun : `ContentBundle` (pur) | Serveur : `world_bundle.gd`, route dans `content_api.gd`
- Protocole : — (HTTP, hors du protocole de jeu)
- Client : `ContentClient.install_bundle`, `WorldLoader` (phases, `use_bundle`, `bundle_min_bytes`), `WorldLoadScreen` (texte de progression)
- Tests : `test_content_bundle.gd` (7) : partition déterministe et index validé ; zips construits (une entrée par contenu, compressés, réutilisés, anciennes versions supprimées) ; route (401, Range 206, nom hors index, `..`, monde sans zip) ; client connecté par WebSocket 127.0.0.1 : installation par le zip puis mise à jour d'un seul fichier par fichier ; coupure dans le zip (reprise par Range) puis dans la décompression ; zip abîmé refusé puis monde complet par fichiers ; phases et temps restant du chargeur
- Parité : ☑ règles sourcées (rien de Dofus : format et HTTP du moteur) ☑ tests ☐ sim_cli (sans objet : aucune règle de jeu) ☐ capture (sans objet : seul le texte de progression change, couvert par un test) ☑ doc
- Reste : voir Journal (mesure Incarnam) ; le zip n'est pas servi par morceaux plus petits que `--bundle-mb` ; pas de barre de progression de la construction côté serveur (quelques secondes pour Incarnam).

### [x] C.02c Monde dofus pour le client léger : base légère et zones à la demande
- Dépend : C.02b, C.03, C.04, C.05
- Données : le monde `dofus` (17 353 maps, `world.json`) ; `game/content/` (22 Go) ; tailles mesurées par `tools/world_assets.gd --world=dofus --zones --dry` (voir Journal)
- Règles :
  - **stratégie** (décidée au vu des mesures) : le client ne télécharge pas les 17 353 maps. Paquet de **base** = interface, polices, textes, pictos, personnages jouables, boutiques / quêtes / recettes et la **zone de départ** ; chaque autre **zone** (une sous-zone : champ `subarea` des maps de la sim, `world.json` `zone_key`) se télécharge quand le joueur s'en approche (sa map et celles qui y mènent). Le serveur sert depuis `game/content` sans copie (blobs par hash, comme C.02) ;
  - `server_only` (`world.json`) : les fichiers que seule la sim lit (`worlds/dofus/maps/*`, 17 353 fichiers) ne vont jamais dans le paquet d'un client ;
  - `WorldAssets.compute_zoned` : base + une liste par zone (maps, textures, accessoires, monstres de la sous-zone, PNJ de ses maps, skins des butins), un fichier partagé est listé dans chaque zone qui l'utilise (le client le prend une fois) ; `_content.json` : `globs` = base, `zones` ;
  - `WorldPackage` : un manifeste par zone et l'index `ContentZones` (versions, tailles, maps) ; routes `zones.json` et `zones/<zone>/manifest.json` ; `GET /worlds` donne `zones` et `zones_size` ;
  - `ContentClient.install_zone` (reprise, hash, rien de redemandé de ce que le cache a déjà) et `ZoneStreamer` (modèle sans écran : `ensure(map)`, `prefetch(voisines)`).
- Commun : `ContentZones` (pur, `shared/`) | Serveur : `world_assets.gd`, `world_package.gd`, `content_api.gd`
- Protocole : — (HTTP, hors du protocole de jeu)
- Client : `ZoneStreamer` (sans écran) ; le branchement sur le changement de map et l'indicateur de chargement sont C.02d
- Tests : `test_content_zones.gd` : découpage d'un monde de test par zone (base, zone de départ, fichier partagé, monstre, PNJ, `server_only`), manifestes et index (versions stables, une zone change seule), routes (401, 404 hors zone, monde sans zones), un client qui s'authentifie par WebSocket (127.0.0.1) télécharge la base puis une zone à la demande, puis son voisin sans retélécharger le fichier partagé, nouvelle session = seulement le manifeste, un fichier modifié = ce fichier seul, serveur injoignable = erreur propre
- Parité : ☑ règles sourcées (rien de Dofus dans le code réseau / contenu : `zone_key` est un réglage du monde) ☑ tests ☐ sim_cli (sans objet) ☐ capture (sans objet : pas d'écran avant C.02d) ☑ doc
- Reste : C.02d (branchement sur le jeu : sans lui, la base seule s'affiche), C.02e (base encore trop lourde : 1,8 Go).

### [x] C.02d Zones à la demande branchées sur le jeu
- Dépend : C.02c
- Données : —
- Règles :
  - le client connaît `zones.json` dès l'entrée dans le monde ; à chaque `map_enter` il appelle `ZoneStreamer.ensure` (zone de la map, **bloquant** avec indicateur « Chargement de la zone… ») puis `prefetch` des zones des maps voisines (sorties de la map, dans un thread, en arrière-plan) ;
  - un téléchargement qui échoue n'empêche pas de jouer les maps déjà installées : message, nouvel essai à la map suivante ;
  - une map dont la zone n'est pas installée ne s'ouvre pas (jamais d'écran noir) ; un `tp` lointain (console GM) passe par `ensure`, avec barre de progression ;
  - (l'option « tout télécharger » et le zip par zone sont passés dans C.02f)
- Commun : — | Serveur : —
- Protocole : — (HTTP)
- Client : `ZoneGate` (nœud : file de zones, fil de téléchargement, retenue du `map_enter`), `ZoneIndicator`, `SessionLink`, `LaunchScreen`
- Tests : `test_content_zones.gd` : la map est retenue puis montrée, préchargement des voisines, échec puis reprise, sans index, retenue par `SessionLink`, vrai fil ; capture relue (`tools/zone_shot.gd`)
- Parité : ☑ règles sourcées (rien de Dofus) ☑ tests ☑ sim_cli (sans objet) ☑ capture ☑ doc

### [x] C.02e Base plus légère : classes à la demande et grosses zones coupées
- Dépend : C.02c
- Données : mesures de C.02c (base 1 761 Mo, dont l'essentiel = les squelettes de combat des 19 classes ; zone `0` = 1 993 maps, 577 Mo ; zone `10` = 158 maps, 397 Mo)
- Règles :
  - les squelettes (`Characters/Bones/1-<classe>-*`) de la seule classe jouée (et des autres classes vues en jeu) se téléchargent comme une zone (« zone de classe ») ; la base ne garde que l'interface et un squelette de repli : objectif base < 400 Mo ;
  - les zones trop grosses (> 150 Mo) sont coupées par blocs de maps voisines (coordonnées de monde `coords`), ou par `area` pour les maps sans sous-zone (zone `0`) ;
  - mesure : première connexion d'un ami (base zippée) en minutes sur Hamachi, notée au Journal.
- Commun : `WorldAssets` | Serveur : paquet
- Protocole : —
- Client : `ZoneStreamer` (zone de classe au choix du personnage)
- Tests : une classe absente de la base : sélection du personnage, zone de classe installée par `NetBackend` (127.0.0.1) ; une grosse zone coupée en blocs, chaque map dans un seul bloc
- Parité : ☑ règles sourcées (rien de Dofus : familles de bundles, `breed` des tables, `zone_key`) ☑ tests ☐ sim_cli (sans objet) ☐ capture (sans objet : pas d'écran nouveau, l'aperçu de création attend sa classe) ☑ doc
- Reste : base à 506 Mo (objectif 400 Mo non atteint) : voir C.02g.

### [x] C.02g Base sous 400 Mo : skins d'équipement et monstres de la zone 10
- Dépend : C.02e
- Données : mesure C.02e (`world_assets.gd --world=dofus --zones` : base 506 Mo dont 162 Mo de skins d'objets que le monde distribue, 30 Mo de pictos d'objets, 26 Mo de textes ; zone `10-1` = 430 Mo pour 39 maps, la coupe ne l'allège pas : les monstres de la sous-zone pèsent dans chaque bloc)
- Règles :
  - les skins d'objets quittent la base : zone `equipment` (ou par type d'objet) demandée quand un joueur qui les porte est vu (`actor_look`) ou quand l'inventaire s'ouvre ;
  - les monstres d'une grosse sous-zone se rangent dans une zone à part (`<zone>-m`), que chaque bloc de la sous-zone demande ;
  - mesure : première connexion d'un ami (zip de base + une classe) en minutes sur Hamachi, notée au Journal.
- Commun : `WorldAssets` | Serveur : paquet
- Protocole : —
- Client : `ZoneGate` (zone d'équipement)
- Tests : un skin d'objet hors de la base : installé par `NetBackend` avant d'être porté
- Fait (voir Journal) : zone `equipment` (170 Mo), zones requises `<zone>-m` (monstres) et `<zone>-c<n>` (communs), recoupe d'une moitié qui reste lourde ; base `dofus` 506 à **344 Mo**, plus gros bloc jouable 148 Mo.
- Reste : mesure de connexion d'un ami sur Hamachi (aucun second poste : estimation au Journal), voir C.02h.
- Parité : ☑ règles sourcées (rien de Dofus : `zone_key`, `requires`) ☑ tests ☐ sim_cli (sans objet) ☐ capture (sans objet : pas d'écran nouveau) ☑ doc

### [x] C.02f Zones : tout télécharger en arrière-plan et zip par zone
- Dépend : C.02d
- Données : mesure des requêtes par zone (C.02c : ~25 fichiers/s)
- Règles :
  - ~~option de joueur « Télécharger tout le monde en arrière-plan » (toutes les zones, reprise, pause)~~ : fait (`ZoneGate.background`, case de `LaunchScreen`, ligne « Téléchargement du monde : n / N zones ») ;
  - ~~zip par zone~~ : fait dans C.06c (`zones/<z>/pack.zip`) ;
  - un `tp` lointain n'attend pas un nouvel index : à vérifier avec un vrai serveur `dofus` (reporté à C.02h).
- Commun : — | Serveur : route `zones/<z>/bundle` éventuelle
- Protocole : — (HTTP)
- Client : réglage dans `LaunchScreen` / fenêtre d'options, file basse priorité de `ZoneGate`
- Tests : la file de fond ne retarde pas une zone demandée ; reprise après coupure
- Parité : ☐ règles sourcées (rien à sourcer : réseau) ☑ tests ☐ sim_cli (aucune règle de sim) ☑ capture ☑ doc

### [x] C.06a Publication du contenu : étape de build reprenable, versions immuables
- Dépend : C.05, C.02c
- Données : mesures du premier démarrage (Incarnam : 19 880 fichiers hachés + zip de 981 Mo = 280 s ; `dofus` : plusieurs Go, 17 k maps, 533 zones) ; le démarrage reparcourait tout, l'index n'était écrit qu'à la fin
- Règles :
  - **le serveur de jeu ne calcule plus le contenu** : une étape explicite (`--build-packages`, `tools/publish_content.py`, `build_release.py --publish`) le hache, le zippe et le **publie** (`server/content_publisher.gd`, `ContentPublisher`) ; le même code tourne dans le serveur exporté, sans lancer le jeu ;
  - **reprenable** : l'index de hachage (`<paquets>/<monde>/index.json`) est écrit par points de reprise atomiques (toutes les 5 s) pendant le hachage ; chaque partie du zip de base est notée dans `progress.json` dès qu'elle est écrite ; chaque zip de zone aussi (`zones/progress.json`, version de la zone + taille). Une interruption (Ctrl+C, coupure) perd au plus le fichier en cours ; un fichier partagé par deux zones n'est haché qu'une fois par passage ; progression imprimée (`publish: <monde>: N files seen`, `bundle part i/n`, `zone packs i/n`) ;
  - **version immuable, publiée atomiquement** : `<paquets>/<monde>/versions/<release>/` (`release` = empreinte de la version de base, de celle des zones et des options : un dossier n'est jamais modifié une fois publié), le tampon `release.json` (taille de chaque artefact) est écrit après les artefacts, puis le pointeur `current.json` en dernier ; les versions inachevées (sans tampon) sont supprimées, les plus anciennes élaguées (`--keep-versions`, défaut 3) ; republier les mêmes fichiers ne fait rien (`unchanged`) ;
  - rien du contenu n'est copié (22 Go) : `blobs.json` dit où le serveur lit chaque empreinte (chemin relatif à `--content-root`) ; `--copy-files` écrit `files/<empreinte>` (C.06d).
- Commun : — | Serveur : `content_publisher.gd`, `published_package.gd`, `world_package.gd` (points de reprise, `opts`), `world_bundle.gd` (`into`, reprise, `pack`)
- Protocole : — (HTTP, hors du protocole de jeu)
- Client : —
- Tests : `test_content_publish.gd` : version écrite avec tampon et pointeur, republication sans rien refaire, build interrompu (`abort_after`) : pas de pointeur, index sauvegardé, reprise qui ne rehache pas ; nouvelle version sans toucher l'ancienne, élagage
- Parité : ☑ règles sourcées (rien de Dofus : format et publication du moteur) ☑ tests ☐ sim_cli (sans objet) ☐ capture (sans objet) ☑ doc

### [x] C.06b Démarrage rapide du serveur : il lit les paquets publiés
- Dépend : C.06a
- Règles :
  - au démarrage le serveur ne hache ni ne parcourt rien : `PublishedPackage.load_package` lit `current.json`, le tampon, le manifeste, `blobs.json`, l'index de zones et les manifestes de zone, et vérifie **seulement l'existence et la taille** de chaque artefact (zips de base et de zones compris) ;
  - un paquet absent, coupé ou abîmé : le serveur refuse de démarrer avec un message qui dit de lancer l'étape de build (`--build-packages`) ; `--check` le dit aussi (FAIL avec `--http-port`, WARN sinon) ;
  - `--build-on-start` garde l'ancien comportement (publier ce qui manque ou a changé, puis démarrer) : tests et premier essai ; un monde ouvert par un admin (S.04) est chargé depuis les paquets publiés ;
  - un fichier de contenu modifié depuis la publication est refusé à la requête (409), comme avant : republier.
- Commun : — | Serveur : `server_app.gd` (`_publish`, `_load_packages`), `server_check.gd`
- Protocole : —
- Client : —
- Tests : `test_release.gd` (`--check`), `test_content_publish.gd` (le serveur lit sans hacher, paquet jamais publié / zip de taille différente refusés avec le message), tous les tests de contenu et de serveur inchangés
- Parité : ☑ règles sourcées (sans objet) ☑ tests ☐ sim_cli (sans objet) ☐ capture (sans objet) ☑ doc

### [x] C.06c Un zip par zone
- Dépend : C.06a, C.02d
- Règles :
  - la publication construit pour chaque zone un petit zip `zones/<zone>/pack.zip` (entrées nommées par empreinte, comme le zip de base ; au plus `ContentPublisher.PACK_MAX_ENTRIES` contenus, sinon fichier par fichier) et note `pack: {size, hash}` dans le manifeste de la zone (un manifeste ordinaire reste valide : la version ne change pas) ;
  - route `GET /worlds/<id>/zones/<zone>/pack.zip` (jeton, `Range`, ETag = empreinte, liste blanche = zips publiés, 409 si changé, 404 sinon) ;
  - `ContentClient.install_zone` : si le manifeste annonce un zip et que le cache manque d'au moins `ZONE_PACK_MIN_FILES` contenus (ou de la moitié du poids), une seule requête (reprise après coupure, empreinte vérifiée), chaque entrée vérifiée contre le manifeste avant d'être écrite, le zip supprimé ; **repli fichier par fichier** pour tout ce que le zip n'a pas donné (zip absent, abîmé, 404) ;
  - ferme la partie « zip par zone » de C.02f (l'option « tout télécharger » reste à faire).
- Commun : — | Serveur : `content_api.gd`, `content_publisher.gd`
- Protocole : — (HTTP)
- Client : `ContentClient.install_zone_pack`
- Tests : `test_content_publish.gd` : un client connecté par WebSocket 127.0.0.1 installe une zone avec une requête (vrai serveur HTTP), route (401, 404, 206), monde publié sans zips, zip abîmé de même taille ignoré
- Parité : ☑ règles sourcées (sans objet) ☑ tests ☐ sim_cli (sans objet) ☐ capture (sans objet) ☑ doc

### [x] C.06d Contenu publié servable en statique, export
- Dépend : C.06a, C.06b, C.06c, X.01
- Règles :
  - le dossier d'une version a **la forme de l'API** (`manifest.json`, `bundle.json`, `bundle/part-NNN.zip`, `zones.json`, `zones/<z>/manifest.json`, `zones/<z>/pack.zip`, `files/<empreinte>`) : le poser tel quel sous `/worlds/<id>/` d'un hébergement statique suffit (le test compare les fichiers publiés à ce que l'API sert) ; `--copy-files` écrit `files/<empreinte>` (partagé entre versions, duplique le contenu : à décider monde par monde) ;
  - `tools/publish_content.py` : lance la publication sans le jeu, `--static-out` assemble l'arborescence + `worlds.json` ;
  - `build_release.py --publish`, `serveur-lancer.bat` (`PACKAGES`, `publier`, publie seul le premier démarrage), `--check` ; documenté dans `docs/EXPORT.md` (« Publication du contenu »).
- Commun : — | Serveur : —
- Protocole : —
- Client : —
- Tests : `test_content_publish.gd` (`files/<hash>`, mise en page = API) ; mesures dans le Journal
- Parité : ☑ règles sourcées (sans objet) ☑ tests ☐ sim_cli (sans objet) ☐ capture (sans objet) ☑ doc
- Reste : l'accès public sans jeton (hébergement statique) est une décision de sécurité (le serveur de jeu exige toujours le jeton de session : « jamais d'URL publique ») ; le client ne sait pas encore lire un contenu depuis une autre URL que le serveur de jeu.

### [x] C.07 Distribution du contenu façon launcher (bundles, manifestes, plages d'octets)
- Dépend : C.06a, C.02c, C.03
- Règles :
  - la méthode des launchers (RMAN de Riot, Cytrus d'Ankama, dépôts Steam) remplace les zips de base, zips de zone, `blobs.json`, `/files/<hash>` et le thread de préparation : publication **hors du serveur** en fichiers immuables nommés par leur empreinte (`shared/content_release.gd`) : `bundles/` (~32 Mo, chaque contenu écrit une fois dans tout le dossier), `manifests/` (un par fragment : base, zones ; `[chemin, empreinte, taille, bundle, offset]`), `<monde>/releases/<id>.json`, pointeurs `worlds.json` écrits en dernier ;
  - publication incrémentale (seuls les contenus nouveaux sont écrits) et reprenable, élagage des releases (`--keep-versions`) avec ce que plus rien n'utilise ; anciens `versions/`, `bundle/`, `files/` supprimés à la première publication ;
  - le serveur de jeu ne lit **rien** du contenu au démarrage : `ContentApi` sert le dossier en statique sur le thread HTTP (`/worlds` compris), un monde ouvert non publié est `unpublished` ;
  - client : liste = une requête comparée à `_install/state.json` (aucun manifeste, aucun `stat`, aucun hachage), taille exacte des mises à jour mesurée derrière (`WorldLoader.measure`), installation par plages `Range` regroupées (`ContentRelease.plan_ranges`, 8 connexions, `client/range_downloader.gd`), reprise par journal, vérification complète seulement sur demande (« Vérifier »), ancien cache adopté sans retéléchargement ; une zone = un fragment, l'index des zones est la release gardée avec la base.
- Commun : `shared/content_release.gd` (pur) | Serveur : `content_publisher.gd`, `bundle_writer.gd`, `content_store.gd`, `content_api.gd`
- Protocole : API HTTP de contenu (docs/EXPORT.md « Distribution du contenu »)
- Client : `content_client.gd`, `range_downloader.gd`, `world_loader.gd`, `world_load_screen.gd` (« Vérifier », « ≤ » avant mesure), `zone_streamer.gd`
- Tests : `test_content_publish.gd`, `test_content_ranges.gd`, `test_content_api.gd`, `test_content_zones.gd`, `test_world_loader.gd`, `test_zone_background.gd` (vrai serveur HTTP 127.0.0.1, jeton d'un login WebSocket)
- Parité : ☑ règles sourcées (sans objet) ☑ tests ☐ sim_cli (sans objet) ☐ capture ☑ doc

### [x] X.01 Export : client léger et serveur headless
- Dépend : C.03, S.01
- Données : —
- Règles :
  - `export_presets.cfg` : preset **Client** (Windows, sans `content/`, sans `data/`, sans `worlds/` ; scènes, scripts, addon et polices) et preset **Serveur** (headless, sans l'interface) ; le client pèse quelques dizaines de Mo ;
  - script `tools/build_release.py` (modèles d'export Godot requis, vérifie `df -h /c`) : produit `dist/client/` et `dist/server/` (exe + dossier `content/`, `data/`, `worlds/` à côté du serveur, lus par le serveur pour ses paquets : le PCK ne contient pas les assets) ;
  - `dist/serveur-lancer.bat` (port, mondes, dossier de sauvegarde) et `dist/LISEZMOI.txt` pour les amis : installer Hamachi, rejoindre le réseau, lancer le client, saisir `adresse:port` ;
  - le client exporté ne démarre jamais en solo sans contenu : l'écran de lancement explique qu'il faut un serveur (le solo reste disponible depuis le projet) ;
  - `--check` du serveur : vérifie ports libres, dossiers, paquets construits, puis quitte (utile avant d'inviter les amis).
- Commun : — | Serveur : `tools/build_release.py`, presets
- Protocole : —
- Client : écran de lancement adapté au client exporté (pas de solo, adresse mémorisée)
- Tests : le serveur exporté démarre et répond `GET /worlds` ; un client exporté se connecte, télécharge un petit monde de test (`worlds/test`) et affiche la map ; taille du client mesurée et notée
- Parité : ☑ règles sourcées (sans objet : pas de règle de jeu) ☑ tests ☐ sim_cli (sans objet) ☑ capture ☑ doc

### [x] P3.02a Chat : canaux ouverts, privé, commandes, anti-flood
- Dépend : P3.01
- Données : `chatchannels` (raccourcis `/s /b /r /w`, noms i18n)
- Règles :
  - canaux général (map ; en combat, les combattants), commerce, recrutement (tout le monde), privé, équipe (le combat) ;
  - anti-flood (APPROX : pas de constante dans les données) ; commandes (`/w`, `/b`, `/r`…) analysées par la sim ;
  - journal des 200 derniers messages (modération, console A1.01).
- Commun : `Chat` | Serveur : `WorldChat`, journal
- Protocole : `chat_send{channel, text, to?}`, `chat_msg{channel, from, from_id, text, at, to?}` ; erreurs `chat_flood`, `channel_unavailable`, `player_offline`
- Client : `ChatPanel` à onglets (Entrée), `ChatBubble` au-dessus du personnage
- Tests : `tests/test_chat.gd` (routage par canal, anti-flood, message privé à un joueur hors ligne, combat, journal, et le même flux par deux `NetBackend` sur 127.0.0.1)
- Parité : ☑ règles sourcées (raccourcis et noms = `chatchannels` ; flood, longueur 256 : APPROX(P3.02a)) ☑ tests ☑ sim_cli (sans objet : une session ne parle à personne) ☑ capture ☑ doc

### [x] P3.03a Groupes : invitations, chef, suivi, position des membres
- Dépend : P3.01
- Données : — (APPROX(P3.03a) : 8 joueurs et 60 s d'invitation sont les valeurs du jeu, absentes des tables)
- Règles :
  - 8 joueurs max ; invitation (une minute), acceptation, refus ; chef (le premier de la liste), exclusion, passage du commandement ;
  - quitter : le suivant devient chef, un groupe d'un seul membre se dissout ; se déconnecter quitte le groupe ;
  - suivre un membre : quand il change de carte hors combat, on l'y rejoint ;
  - position des membres (carte, coordonnées, case, PV, en combat) renvoyée dans `party_update` ;
  - bonus d'XP : `FightXp.GROUP_BONUS` est déjà lu par `FightRewards` (nombre de joueurs du combat) ; il jouera à plusieurs en P3.04.
- Commun : `Party`, `ProtocolParty` | Serveur : `WorldParty`
- Protocole : `party_invite`, `party_accept`, `party_decline`, `party_leave`, `party_kick`, `party_leader`, `party_follow` ; `party_invited`, `party_update`, `party_left`, `party_declined` ; erreurs `party_full`, `already_in_party`, `not_in_party`, `not_party_leader`, `no_invitation`
- Client : voir P3.03b
- Tests : `tests/test_party.gd` (règles de `Party`, invitation, refus, expiration, départ, exclusion, commandement, 8 joueurs, déconnexion, position, suivi, bonus d'XP de 2 joueurs, et le même flux par deux `NetBackend` sur 127.0.0.1)
- Parité : ☑ règles sourcées (bonus = luaformulas 99 ; reste APPROX(P3.03a)) ☑ tests ☑ sim_cli (sans objet : `sim_cli` ne pilote qu'une session, S.07) ☐ capture (P3.03b : pas de client dans ce morceau) ☑ doc

### [x] P3.03b Groupes : cadre du groupe et marqueurs sur la carte
- Dépend : P3.03a
- Données : portraits (`ui.py`), `ErrorTexts`
- Règles : aucune (le client affiche `party_update`)
- Commun : — | Serveur : —
- Protocole : existant (P3.03a)
- Client : `PartyFrame` (portraits, barre de PV, chef, bouton quitter / exclure / suivre dans le menu d'un membre), invitation reçue (accepter / refuser), entrée « Inviter dans le groupe » dans le menu contextuel d'un joueur (`other_players.gd`), marqueur du membre sur la map ou flèche vers la sortie ; `client_session.gd` est à 796 lignes : router par un fichier à part (`_on_party_event`)
- Tests : routage des événements, rendu du cadre sans erreur ; `/p` du chat (P3.02b)
- Parité : ☑ règles sourcées (aucune règle : le client affiche) ☑ tests (`tests/test_party_client.gd`, 5 tests dont le flux par deux `NetBackend`) ☑ sim_cli (sans objet, client) ☑ capture relue ☑ doc

### [x] P3.04a Rejoindre un combat et mode spectateur : règles, protocole, serveur
- Dépend : P3.03a
- Note : P1.15 (minuteur, options, fuite) est fait et vérifié, il reste `doing` derrière P1.14 : dépendance relâchée
- Données : — (APPROX(P3.04) : 8 combattants par équipe, valeur du jeu absente des tables)
- Règles :
  - rejoindre pendant le placement, équipe des joueurs seulement, 8 par équipe, une case de placement libre ; options `locked` / `party_only` (membre du groupe du chef) lues par `Fight.join_error` ;
  - le combat est un acteur de la map (`FightActor`, les épées) : équipes, phase, options ; renvoyé quand ils changent, retiré à la fin ; présent dans `map_enter` ;
  - spectateurs : hors de la map, reçoivent tous les événements (vue « sans équipe » : rien d'invisible), ne peuvent que quitter (`fight_leave`) ou parler ; option `secret` ;
  - fuite avec d'autres joueurs encore dedans : seul le fuyard quitte (`fighter_left`, retour sur la map, sans gain), le combat continue ; une déconnexion fait pareil (le dernier joueur dehors termine le combat) ;
  - XP et butin partagés : `FightRewards` compte les joueurs du combat (bonus de groupe luaformulas 99, PP pour les kamas et le butin), hors fuyards.
- Commun : `Fight.join`, `Fight.spectate`, `Fight.team_size`, `Fighter.left` | Serveur : `WorldFightWatch`, `FightActor`
- Protocole : `fight_join{fight, team}`, `fight_spectate{fight}` ; `fight_watch`, `fighter_joined`, `fighter_left`, `actor_add{kind: fight}` ; erreurs `no_fight`, `fight_full`, `fight_started`, `bad_team`, `spectating` (`ProtocolWatch`)
- Client : voir P3.04b
- Tests : `tests/test_fight_join.gd` (swords, rejoindre, refus, 8 par équipe, spectateur, fuite, déconnexion, gains partagés, bonus de groupe, schéma, et le flux par trois `NetBackend` sur 127.0.0.1)
- Parité : ☑ règles sourcées (bonus = luaformulas 99 ; reste APPROX(P3.04)) ☑ tests ☑ sim_cli (sans objet : `sim_cli` ne pilote qu'une session, S.07) ☐ capture (P3.04b : pas de client dans ce morceau) ☑ doc

### [x] P3.04b Combats à plusieurs : client (épées, rejoindre, spectateur)
- Dépend : P3.04a, P3.03b
- Données : textures des épées (`ui.py` si besoin), `ErrorTexts`
- Règles : aucune (le client affiche)
- Commun : — | Serveur : —
- Protocole : existant (P3.04a)
- Client : épées sur la map (`actor_add{kind: fight}` : `teams` arrive en float après JSON, `int()`), clic = menu « Rejoindre » (placement, équipe 0) / « Regarder » ; `fighter_joined` / `fighter_left` dans `FightView` ; `fight_watch` ouvre le combat en lecture seule (pas de barre de sorts, bouton « Quitter » = `fight_leave`) ; `fight_end` vide (spectateur, fuyard, `rewards: []`, `result: ""` quand il quitte) sans fenêtre de gains ; chat d'équipe ; `client_session.gd` est à 796 lignes : router par un fichier à part
- Tests : routage des événements, rendu des épées sans erreur
- Parité : ☑ règles sourcées (aucune règle : le client affiche) ☑ tests ☑ sim_cli (sans objet : `sim_cli` ne pilote qu'une session, S.07) ☑ capture ☑ doc

### [x] S.02b Comptes complets : reconnexion (serveur et sim ; le client est S.02c)
- Dépend : S.02a, P3.04a
- Données : —
- Règles :
  - reconnexion en combat : le combat attend N secondes (APPROX(S.02b) : 60 s, à régler) le joueur déconnecté, qui passe son tour puis est pris par l'IA si le délai est dépassé ;
  - reconnexion avec le même jeton tant qu'il est valide : l'état courant (map, combat) est renvoyé ;
  - la double connexion remplace l'ancienne si le jeton est valide (au lieu de refuser) après un délai d'inactivité ;
  - expiration des jetons, déconnexion propre.
- Commun : la sim gère « joueur absent » dans le combat (`WorldResume`, `Fight.set_absent`) | Serveur : `game/src/server/auth/`, `ServerHost`
- Protocole : `resume{token}`, `resume_ok{token, role, login, state}` (`shared/protocol_resume.gd`), code `bad_token`
- Client : voir S.02c
- Tests : `tests/test_resume.gd` (15) : coupure en plein combat puis retour dans le délai ; coupure plus longue = IA ; jeton expiré refusé ; déconnexion propre ; double connexion
- Parité : ☑ règles sourcées (rien de Dofus : APPROX(S.02b) pour les délais) ☑ tests ☐ sim_cli (sans objet : pas de réseau dans `sim_cli`) ☐ capture (sans objet : aucun écran, le bandeau est S.02c) ☑ doc

### [x] S.02c Reconnexion automatique du client
- Dépend : S.02b
- Données : —
- Règles : aucune (le serveur est S.02b)
- Commun : —
- Client : `NetBackend` : après une coupure (`state == "closed"` avec `failure`, jamais après `close()`), il se reconnecte seul (délais 1, 2, 4, 8 s, puis toutes les 8 s) et envoie `resume{token}` ; bandeau « Reconnexion… » (kit UI) pendant l'attente, retiré à `resume_ok` ; sur `bad_token` : retour à l'écran de connexion avec le message ; sur `resume_ok` : `ClientSession` repart de l'état reçu (welcome, map ou combat) comme à une connexion neuve ; `client_session.gd` est à 799 lignes : router par un fichier à part
- Tests : coupure puis retour via `NetBackend` (le client se rétablit seul, l'état est rejoué), jeton expiré = retour à la connexion
- Parité : ☑ règles sourcées (rien de Dofus : APPROX(S.02c) pour les délais) ☑ tests ☐ sim_cli (sans objet : pas de réseau dans `sim_cli`) ☑ capture (`tools/banner_shot.gd`) ☑ doc

### [x] A1.01a Admin : console GM, sanctions et audit
- Dépend : S.02a, S.01
- Données : — (APPROX(A1.01) : outil de maître du jeu, aucune règle Dofus ; mute par défaut 10 min, plafond une semaine)
- Règles :
  - commandes GM en jeu (`admin_cmd`, rôle `gm` vérifié par la sim, hors combat) : `tp`, `give <objet> [qté] [joueur]`, `kamas <n> [joueur]`, `level <n> [joueur]`, `heal [joueur]` (PV, énergie, un fantôme ressuscite), `say <texte>` (annonce à tout le monde), `who`, `kick`, `ban <joueur> [raison]`, `unban`, `mute <joueur> [minutes]`, `unmute`, `reload` (tables `GameData`) ;
  - bannissement et sourdine par **compte** (`Sanctions`, dans le document du compte : valable dans tous les mondes et après un redémarrage) ; un compte banni est refusé au `login` / `resume` (`login_error banned`, après vérification du mot de passe) et au `hello` / choix de personnage ; un muet ne parle plus sur aucun canal (`muted`, `msg` = secondes restantes) ;
  - kick / ban d'un joueur connecté : dernier événement `error kicked` / `banned`, la session se ferme, le serveur coupe la socket après 300 ms de grâce (le client lit la raison), rien n'est gardé pour une reprise ;
  - toutes les commandes (acceptées ou refusées, même sans le rôle) sont journalisées : `WorldAdmin.audit_log` (200 dernières, mémoire) et `audit_sink` → fichier d'audit du serveur (`--audit-log=<fichier>`, défaut `<save-dir>/admin_audit.jsonl`, une ligne JSON {at, world, account, name, cmd, args, ok, code}).
- Commun : `ProtocolAdmin`, `Sanctions` | Serveur : `WorldAdmin` (sim), `server/admin/audit_log.gd`, `ServerHost` (coupe les kickés), `AuthService` (ban)
- Protocole : `admin_cmd` (étendu), `admin_result{cmd, args}`, `announce{from, text}` ; erreurs `banned`, `muted`, `kicked`
- Client : `/give`, `/level`… dans la boîte de chat (Entrée) : résultat en vert, annonces en doré dans l'onglet Général, `/help` liste les commandes ; la virgule n'est un séparateur que pour `/tp`
- Tests : `tests/test_admin.gd` (rôle refusé et audit, give / kamas / level / heal, say / who / inconnues / reload, mute, kick et ban, `Sanctions`, et le flux complet par `NetBackend` sur 127.0.0.1 avec comptes : kick coupe la vraie socket, ban refusé au login, fichier d'audit)
- Parité : ☑ règles sourcées (outil GM : APPROX(A1.01)) ☑ tests ☑ sim_cli (`admin:<cmd>:<args>`) ☑ capture ☑ doc

### [x] A1.01b Admin : métriques en JSON
- Dépend : A1.01a
- Données : —
- Règles : `GET /admin/metrics` sur le port HTTP (jeton admin, distinct du jeton de session des joueurs) : joueurs connectés, maps actives, combats en cours, durée de tick (moyenne, max sur une fenêtre), mémoire (`OS.get_static_memory_usage`), version, uptime ; mêmes chiffres lisibles par un test via `NetBackend`.
- Commun : — | Serveur : `game/src/server/admin/metrics.gd` (mesure du tick dans `ServerHost.poll`), route dans `HttpServer` / `ContentApi`
- Protocole : — (HTTP)
- Client : —
- Tests : métriques cohérentes avec 2 clients (joueurs = 2, maps actives, combat en cours), jeton refusé sans jeton admin, JSON valide
- Parité : ☑ règles sourcées ☑ tests ☐ sim_cli ☐ capture ☑ doc (sim_cli et capture sans objet : HTTP, aucune règle de jeu ni client)

### [x] S.03 Persistance fiable
- Dépend : S.01, P0.02
- Données : —
- Règles :
  - `FilePersistence` côté serveur dans `--save-dir`, écritures atomiques (fichier temporaire puis renommage) ;
  - sauvegardes périodiques (toutes les N minutes et à la déconnexion) et copies tournantes (les 10 dernières) ;
  - restauration depuis une copie ;
  - SQLite plus tard si le besoin apparaît (HDV, échanges transactionnels) : l'interface `Persistence` ne change pas.
- Commun : — | Serveur : `game/src/server/persistence/`
- Protocole : —
- Client : —
- Tests : les tests de `Persistence` rejoués sur la persistance serveur ; kill du processus en pleine écriture = fichier précédent intact ; restauration
- Parité : ☑ règles sourcées (rien de Dofus : APPROX(S.03) pour les durées) ☑ tests ☐ sim_cli (sans objet : pas de règle de jeu) ☐ capture (sans objet : pas de client) ☑ doc

### [x] A1.02a Admin web : tableau de bord, comptes, actions, audit
- Dépend : A1.01b, C.02
- Données : — (APPROX(A1.02) : outil de maître du jeu, aucune règle Dofus)
- Règles : page statique `/admin` (publique, demande le jeton) + JSON sous `/admin/*` (jeton admin) ; toutes les actions sont journalisées (A1.01).
  - **Vue d'ensemble** : joueurs connectés (liste), maps actives, combats en cours (liste), durée de tick, mémoire, version, uptime, nombre de comptes (`GET /admin/overview`).
  - **Comptes et personnages** : recherche (compte ou nom de personnage), fiche de compte (rôle, création, dernière connexion et adresse, ban / muet, coffre, personnages) et fiche de personnage (document vivant s'il est connecté, sauvegarde sinon : niveau, classe, position, kamas, inventaire, quêtes, métiers).
  - **Actions** (`POST /admin/action`) : téléporter (map ou coordonnées), donner objet / kamas / niveau, soigner / ressusciter, kick, ban / unban, muet / voix, réinitialiser un mot de passe, message à tous, sauvegarde manuelle, rechargement des tables.
  - **Audit** : les 200 dernières lignes du fichier d'audit, les plus récentes d'abord ; chaque action (acceptée ou refusée) laisse une ligne `web-admin`.
- Commun : — | Serveur : `server/admin/admin_views.gd`, `admin_actions.gd`, `admin_api.gd` (routes), `web/index.html`, `WorldAdmin.run_web`, `AccountStore.set_password` / `note_seen`, `HttpServer` (corps de requête)
- Protocole : — (HTTP JSON : `/admin/...`)
- Client : — (page web)
- Tests : `tests/test_admin_web.gd` (401 sans jeton, page publique, corps trop gros, vue d'ensemble avec deux clients `NetBackend` sur 127.0.0.1, la fiche d'un personnage correspond à la sauvegarde, chaque action modifie l'état et laisse une ligne d'audit)
- Parité : ☑ règles sourcées (outil GM : APPROX(A1.02)) ☑ tests ☐ sim_cli (sans objet : HTTP) ☐ capture (voir Journal) ☑ doc

### [x] S.04a Plusieurs mondes sur un serveur : liste, ouverture et arrêt depuis l'admin
- Dépend : S.01, C.02, A1.01b
- Données : —
- Règles :
  - chaque monde ouvert = son `WorldSim` (événements, personnages, maps), son paquet de contenu (C.02) et ses sauvegardes (Persistence clé par monde), derrière le même port ; le hôte route une session vers le monde de son `hello` ;
  - `WorldCluster` : liste (ouverts, et avec `all` les mondes démarrables), `start(id)`, `stop(id)` : les joueurs du monde sont sauvegardés et reçoivent `error{world_closed}`, le monde sort des listes, de l'API de contenu et ne se rouvre pas par un `hello` ;
  - transfert de personnage entre mondes : hors périmètre (G.01).
- Commun : `shared/protocol_cluster.gd` | Serveur : `game/src/server/cluster/world_cluster.gd`, admin `world_start` / `world_stop` / `GET /admin/worlds` (page : section Mondes)
- Protocole : `server_list` -> `servers{worlds:[{id,name,module,players,version}]}`, `error{world_closed}`
- Client : l'écran de chargement (C.03) affiche le nombre de joueurs de chaque monde (`/worlds` porte `players`)
- Tests : `tests/test_cluster.gd` (2 mondes en parallèle sans fuite d'événements, `server_list`, arrêt / redémarrage par l'admin, audit, liste vide, contenu)
- Parité : ☑ règles sourcées ☑ tests ☐ sim_cli ☐ capture ☑ doc (sim_cli : sans objet, rien côté règles ; capture non faite : seule une ligne de texte change dans l'écran de chargement)

### [x] S.04b Instances d'un même contenu (un monde par groupe d'amis)
- Dépend : S.04a
- Données : —
- Règles :
  - créer une instance `amis` du contenu `incarnam` : id d'instance différent de l'id de contenu (`world.json` id = contenu, sauvegardes et listes par instance), chaque instance son dossier de sauvegarde ;
  - l'admin crée / supprime une instance (`world_create{id, content}`), persistée dans un fichier `instances.json` du dossier de sauvegarde, rouverte au démarrage ;
  - `welcome.world` et `servers` portent `content` pour que le client lise le paquet du bon contenu ;
  - sous réserve : `Mods.read_all`, `world_id()` et `ContentSource` supposent id = dossier.
- Commun : — | Serveur : `server/cluster/`
- Protocole : `servers[].content`
- Client : choix de l'instance dans l'écran de chargement
- Tests : deux instances du même contenu, personnages séparés, redémarrage du serveur
- Parité : ☑ règles sourcées (aucune règle de jeu) ☑ tests ☐ sim_cli (pas de règle de sim) ☐ capture (écran de chargement inchangé : l'instance est une ligne de plus) ☑ doc

### [x] S.05a Sécurité : débit, trames, adresses, chemins, fuzz
- Dépend : S.02a, C.02
- Données : —
- Règles :
  - limitation de débit par connexion (seau à jetons : rafale de 60 messages puis 30 par seconde) : `error{rate_limited}` au premier refus, coupure (1008) après 20 refus d'affilée ; au plus 16 connexions par adresse ; 30 tentatives de `login` / `register` / `resume` par adresse puis une toutes les 2 s (`login_error{too_many_attempts}` sans calculer de hachage) ; trame de plus de 64 Ko refusée (coupure 1009) ;
  - accès contenu : liste blanche par hachage du manifeste, jeton obligatoire, aucun chemin libre (déjà C.02, testé avec des chemins hostiles) ;
  - un fuzz de toutes les commandes du protocole ne fait jamais planter la sim ni l'hôte.
- Commun : `shared/protocol_security.gd` | Serveur : `game/src/server/security/rate_limiter.gd`, `ServerHost`
- Protocole : `error{code:rate_limited}`
- Client : message « Trop de requêtes : ralentissez » (`ErrorTexts`)
- Tests : `tests/test_security.gd` (11 : seau, inondation coupée, client normal jamais limité, rafale courte récupérée, trame trop grande, plafond par adresse, tentatives de connexion, vrai client `NetBackend`, chemins du contenu, fuzz des commandes en 6 parties dont 3 en combat, déchets sur le fil)
- Parité : ☑ règles sourcées (APPROX(S.05) : valeurs sans source) ☑ tests ☐ sim_cli (sans objet : réseau) ☐ capture (sans objet : une ligne de texte) ☑ doc

### [x] S.05b Sécurité : audit des échanges, fuite d'information
- Dépend : S.05a
- Données : —
- Règles :
  - journaux d'audit des échanges : déjà écrits par P3.11a (`WorldTrade._record` -> `audit_sink` -> fichier d'audit, visible dans l'admin web) ; vérifiés ici de bout en bout dans le fichier ; l'HDV n'existe pas encore (son audit viendra avec son lot) ;
  - pas de fuite d'information : les instantanés d'un combat (`fight_start` de la reprise S.02b, `fight_start` d'un joueur qui rejoint, `watch` d'un spectateur) passent par `FightVisibility.view` comme les événements en direct : la case d'un invisible n'est plus envoyée à l'autre camp ni aux spectateurs ; hors combat aucun état invisible n'existe (un joueur en combat ou spectateur est retiré de la map, `PUBLIC_KEYS` reste la liste blanche de `actor_add`).
- Commun : — | Serveur : — (sim : `world_resume.gd`, `world_fight_watch.gd`)
- Protocole : —
- Client : —
- Tests : `tests/test_security_audit.gd` (3 : deux trades de deux clients WebSocket dans le fichier d'audit sans secret, reprise sans la case d'un ennemi invisible, spectateur sans les cases des invisibles)
- Parité : ☑ règles sourcées (sans objet : sécurité) ☑ tests ☐ sim_cli (sans objet) ☐ capture (sans objet) ☑ doc

### [x] S.05c Sécurité : mots de passe, débit par session, sanction automatique
- Dépend : S.05b
- Données : —
- Règles :
  - mots de passe : revoir APPROX(S.02a) (argon2 si une extension existe) et déplacer le hachage dans un thread (il bloque le tick ~0,1 s) ;
  - débit : limiter aussi par session les commandes coûteuses (chat, admin) ; sanction automatique (ban temporaire) d'une adresse qui se fait couper plusieurs fois ;
  - audit : un cache de `WorldContacts.book_of` (relu à chaque appel) ; invitations de groupe / d'échange d'un ignoré à filtrer ; l'audit de l'HDV quand il existera.
- Commun : — | Serveur : `game/src/server/security/`
- Protocole : —
- Client : —
- Tests : le hachage ne bloque pas le tick ; une adresse coupée plusieurs fois est bannie un moment
- Parité : ☑ règles sourcées (APPROX(S.05c) : valeurs sans source) ☑ tests ☐ sim_cli (sans objet : réseau) ☐ capture (sans objet) ☑ doc

### [x] S.06 Taux du serveur et drops bonus (façon Temporis)
- Dépend : S.01, P1.09
- Données : `recipes`, `itemsets`, `items`, `monsters.drops` → `game/data/bonus_drops.json` (`python tools/extractor/gamedata.py bonus_drops dofus`, puis `items dofus` pour que tous les objets du pool soient connus). `monsters.temporisDrops` et `items.dropTemporisMonsterIds` existent mais sont vides (0 / 5 135, 0 / 21 748) : APPROX(S.06), voir Découvertes.
- Règles :
  - facteurs génériques, réglés au lancement : `--xp-rate` (XP de combat, après `FightXp.player_xp`), `--drop-rate` (chance des drops normaux), `--kamas-rate` (kamas de fin de combat), `--job-xp-rate` (récolte et craft ; pas les potions d'XP de métier). Défaut 1 : mêmes jets, mêmes gains, scénarios inchangés ;
  - drops bonus (`--bonus-drops`), un système à part : pour chaque joueur et chaque monstre tué, `--bonus-drop-rate` (défaut 3 %) × prospection / 100 d'obtenir un équipement (sans facteur de drop, sans étoiles, sans challenge), tiré après les drops normaux ; une fois sur deux dans les panoplies liées aux monstres tués (s'il y en a), sinon parmi les équipements craftables sans panoplie de niveau ± `--bonus-drop-range` (défaut 15) autour du monstre le plus haut du groupe.
- Commun : `sim/world_rates.gd` (`WorldRates`), `sim/fight/bonus_drops.gd` (`BonusDrops`), `FightRewards`, `WorldJobs`, `WorldCrafting` | Serveur : options de `ServerApp` (ligne au démarrage, `--check` refuse un taux invalide), `LocalServer.rates` (tous les mondes et instances), tableau de bord de l'admin web
- Protocole : `welcome.world.rates` (seulement si les taux ne sont pas ceux par défaut), `fight_end.rewards[].bonus_items`
- Client : ligne « Taux du serveur » dans le chat à l'arrivée ; objets bonus encadrés à part dans la fenêtre de fin de combat ; en solo les mêmes options sur la ligne de commande (`LocalBackend.cmdline_rates`, aussi `client_shot` et `sim_cli`)
- Tests : `tests/test_rates.gd` (6 : options, facteurs XP / kamas / drop, bonus à part des drops normaux, données Larve → panoplie de la Larve et Bouftou → panoplie Bouftou, de bout en bout en solo `LocalBackend` et sur un serveur `NetBackend` 127.0.0.1)
- Parité : ☑ règles sourcées (APPROX(S.06) : réglages de serveur, lien panoplie ↔ monstre par les recettes) ☑ tests ☑ sim_cli ☑ capture ☑ doc

### [x] S.07 Parité standalone / serveur
- Dépend : S.01, P0.05, P3.01
- Données : —
- Règles : tous les scénarios JSONL donnent les mêmes événements via `LocalBackend` et via `NetBackend` (à l'horloge près)
- Commun : — | Serveur : —
- Protocole : —
- Client : —
- Tests : `test_scenarios` exécuté sur les deux backends ; un scénario à deux joueurs
- Parité : ☑ règles sourcées (aucune règle : un harnais de test) ☑ tests ☐ sim_cli (pas d'option `--server` : dette mineure) ☐ capture (rien à afficher) ☑ doc

### [x] P3.02b Chat : groupe, liens d'objets, smileys, sourdine (fait ; guilde / alliance / infobulle / emotes : P3.02c)
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

### [x] P3.02c Chat : infobulle des liens, icones de smileys, emotes, canal d'equipe
- Dépend : P3.02b
- Règles : infobulle au survol d'un `[objet]` ; icone des smileys (`smileys.gfxId`) au lieu de la face texte ; emotes (`emoticons`) ; canal d'équipe `/t` (les combattants de son équipe)
- Tests : emotes, canal d'équipe, pièces d'une ligne, infobulle (Local + Net), capture
- Parité : ☐ règles sourcées ☐ tests ☐ sim_cli ☐ capture ☐ doc

## P1 — Boucle de jeu de base (jouer seul, de la création au niveau 50)

### [x] P1.01 Connexion et choix du personnage
- Dépend : P0.02, P0.06
- Données : —
- Règles :
  - un compte possède N personnages par serveur ;
  - noms uniques par monde, validés par les règles de nom de Dofus (lettres, un tiret, longueur) ;
  - suppression d'un personnage.
- Commun :
  - `Account` et `CharacterList` via `Persistence` ;
  - commandes `list_characters`, `create_character`, `delete_character`, `select_character`.
  - Serveur : l'authentification réelle (S.02).
- Protocole : `characters{list}`, `character_created`, `error{code:name_taken}`
- Client : écran de connexion (standalone : compte local automatique), puis liste des personnages
- Tests : création, doublon de nom, suppression, sélection, puis `welcome` (`tests/test_characters.gd`, scénario `tests/scenarios/characters.jsonl`)
- Parité : ☑ règles sourcées ☑ tests ☑ sim_cli ☑ capture ☑ doc

### [x] P1.02 Création de personnage : toutes les classes
- Dépend : P1.01, P0.03
- Données : `breeds` (18 classes, looks par sexe, couleurs par défaut), `heads`, `skinslotsrules`
- Règles : classe, sexe, tête, 5 couleurs, construction de la chaîne de look exacte de Dofus
- Commun : `Character.breed`, `Character.look`, et `LookBuilder` dans `shared/` | Serveur : —
- Protocole : `create_character{name, breed, sex, head, colors}`
- Client : écran de création avec un aperçu animé (le renderer) et les palettes de couleurs
- Tests : looks générés identiques au format Dofus ; chaque classe produit un look valide (`tests/test_characters.gd`, scénario `characters.jsonl`)
- Parité : ☑ règles sourcées ☑ tests ☑ sim_cli ☑ capture ☑ doc

### [x] P1.03 Sorts de toutes les classes
- Dépend : P1.02
- Données : `spells`, `spelllevels`, `spellvariants` et `spellscripts` pour les 18 classes (`spells.py breed --all`)
- Règles :
  - le niveau requis de chaque sort et de chaque niveau de sort ;
  - les variantes Dofus 3 (choix de l'un des deux sorts) ;
  - les sorts communs.
- Commun : `SpellBook.known_ids(breed, level, choices)`, commande `choose_variant`, ouvrir `CharacterRoster.PLAYABLE_BREEDS` à toutes les classes (l'écran de création les montre déjà) | Serveur : —
- Protocole : `spell_variant{spell}`, champ `spells` de `player_stats`
- Client : fenêtre des sorts (grimoire), barre de sorts personnalisable par glisser-déposer
- Tests : sorts débloqués au bon niveau pour 3 classes ; changement de variante ; la barre persiste (`tests/test_spells.gd`, scénario `spells.jsonl`)
- Parité : ☑ règles sourcées ☑ tests ☑ sim_cli ☑ capture ☑ doc
- Note : les effets non encore supportés sont marqués `partial`. Voir P1.11 à P1.14.

### [x] P1.04 Caractéristiques Dofus 3
- Dépend : P1.02
- Données : `breeds` (coûts du capital par palier, s'ils existent encore en Dofus 3), `luaformulas`
- Règles :
  - le coût du capital selon la classe et le palier (à sourcer : la table fait foi) ;
  - PV = 50 + 5 × niveau + vitalité ;
  - PA 6 → 7 au niveau 100, PM 3 ;
  - initiative, prospection, pods ;
  - la réinitialisation (restat) ;
  - les stats dérivées : tacle, fuite, esquive PA/PM, retrait.
- Commun : `Character.derived_stats()`, source unique réutilisée par `Fighter` | Serveur : —
- Protocole : `boost_stat{stat, points}`, `reset_stats`
- Client : fenêtre de caractéristiques complète (base, bonus, total, infobulles de formule)
- Tests : coûts par palier, restat, stats dérivées identiques hors combat et en combat (`tests/test_characteristics.gd`, scénario `characteristics.jsonl`)
- Parité : ☑ règles sourcées ☑ tests ☑ sim_cli ☑ capture ☑ doc

### [x] P1.05 Objets, partie 1 : jets, inventaire, pods, consommables
- Dépend : P0.03, P0.06
- Données : `items` (possibleEffects, criteria, weight, usable), `itemtypes`, `effects`
- Règles :
  - un objet est une instance avec un UID et des jets tirés entre min et max à sa création (drop, craft) ;
  - les objets identiques se regroupent en piles ;
  - pods max et surcharge (au-delà, on ne peut plus bouger) ;
  - utilisation des consommables : soin, pain, potion de rappel, parchemins de caractéristiques.
- Commun : `ItemInstance`, `Inventory`, `ItemEffects.roll()` | Serveur : UIDs globaux (via `Persistence`)
- Protocole : `inventory{items}`, `item_added`, `item_removed`, `use_item{uid}`, `destroy_item`
- Client : inventaire à onglets (équipement, consommables, ressources, quête), tri, barre de pods, infobulle d'objet
- Tests : jets déterministes par seed, piles, surcharge, soin par potion, rappel vers le point de sauvegarde (`tests/test_items.gd`, scénario `items.jsonl`)
- Parité : ☑ règles sourcées ☑ tests ☑ sim_cli ☑ capture ☑ doc

### [x] P1.06 Objets, partie 2 : équipement, conditions, panoplies, apparence
- Dépend : P1.05, P1.04
- Données : `items` (criteria, appearanceId), `itemsets`, `itemtypes` (slots)
- Règles :
  - les slots : amulette, 2 anneaux, ceinture, bottes, coiffe, cape, arme, bouclier, familier, 6 dofus/trophées ;
  - un seul exemplaire de chaque dofus ou trophée ;
  - les conditions (`criteria`) : niveau, caractéristiques, classe… ;
  - les bonus de panoplie selon le nombre d'objets portés ;
  - les armes : un coup d'arme utilise les effets de l'arme et ses propres règles de critique ;
  - les objets portés changent le look (coiffe, cape, bouclier, familier).
- Commun : `Equipment`, `CriteriaEval` (moteur générique de `criteria`, réutilisé par les quêtes et les PNJ) | Serveur : —
- Protocole : `equip{uid, slot}`, `unequip{slot}`, `actor_look{id, look}`
- Client : fenêtre d'équipement avec le personnage au centre, glisser-déposer, bonus de panoplie dans l'infobulle
- Tests : conditions refusées, bonus de panoplie, stats de combat avec équipement, arme au corps à corps (`tests/test_equipment.gd`, scénario `equipment.jsonl`) ; le look passe dans P1.06b
- Parité : ☑ règles sourcées ☑ tests ☑ sim_cli ☑ capture ☑ doc

### [x] P1.06b Apparence des objets portés
- Dépend : P1.06
- Données : **absentes du client Dofus 3** : `items.appearanceId` ne sert qu'aux familiers, montures et objets d'apparat (1 049 objets) ; les skins des coiffes, capes et boucliers sont envoyés par le serveur officiel. Il faut une source (liste communautaire objet → skin, ou relevé sur un serveur de test) avant de coder. **Source trouvée (P1.10)** : `equipment_skins.json` de JondoEmu (`Documents/Dofus3+/datos`) : `skins` objet → skin (286 mesurés sur captures + `_inferred` par comparaison d'images, 100 % sur les cas de contrôle ; ignorer `_inferred_needs_review`), `mounts`, `pets`
- Règles : coiffe, cape, bouclier, familier (sous-entité `1@0=`) ajoutent leur skin au look ; objets d'apparat (`appearances`) ; masquage par `skinslotsrules`
- Commun : `LookBuilder.with_equipment(look, worn)` | Serveur : —
- Protocole : `actor_look{id, look}`
- Client : le personnage change d'apparence sur la map, en combat et dans la fenêtre d'équipement
- Tests : look mis à jour à l'équipement et au retrait (`tests/test_equipment.gd`, scénario `look.jsonl`)
- Parité : ☑ règles sourcées ☑ tests ☑ sim_cli ☑ capture ☑ doc

### [x] P1.07 Monde, partie 1 : tout Incarnam, transitions réelles
- Dépend : P0.03
- Données : `mapscoordinates`, `mapsinformation` (voisins réels, cellules de sortie), `subareas`, `areas`, maps d'Incarnam complètes
- Règles :
  - les voisins réels de chaque map, y compris les maps sans voisin ;
  - les sorties par cellule (portes, escaliers) ;
  - les maps intérieures ;
  - les cellules de changement interdites.
- Commun : `WorldSource` enrichi (triggers, sorties), commande `use_trigger` | Serveur : —
- Protocole : `map_enter{subarea, coords}`
- Client : nom de la sous-zone et coordonnées affichés, transition de map
- Tests : parcourir tout Incarnam sans cul-de-sac ; une porte mène à un intérieur (`tests/test_world.gd`, scénario `world.jsonl`)
- Parité : ☑ règles sourcées ☑ tests ☑ sim_cli ☑ capture ☑ doc

### [x] P1.07b Intérieurs d'Incarnam
- Dépend : P1.07
- Données : maps `mapsinformation.worldMap = -1` des sous-zones d'Incarnam (≈ 40 : Mine 778, Crypte de Kardorim 447, maisons de 442 / 443 / 444 / 445 / 449 / 450) aux coordonnées de leur map extérieure ; Temple Céleste (446, `worldMap` 41, relié par `mapscrollactions`)
- Règles : chaque intérieur a une entrée et une sortie (APPROX : cellules relevées sur capture, les destinations sont des données serveur) ; les maps à plusieurs salles (Mine, Crypte) reliées entre elles
- Commun : `links.json` complété | Serveur : —
- Protocole : —
- Client : —
- Tests : `test_every_map_is_reachable_without_dead_end` couvre les nouveaux intérieurs, `test_the_mine_rooms_are_linked_by_doors`, scénario `doors.jsonl`
- Parité : ☑ règles sourcées ☑ tests ☑ sim_cli ☑ capture ☑ doc

### [x] P1.08 Monde, partie 2 : carte, zaaps, point de sauvegarde
- Dépend : P1.07
- Données : `worldmaps`, `superareas`, positions des zaaps (interactifs)
- Règles :
  - un zaap s'enregistre à la première visite ;
  - un voyage coûte des kamas selon la distance (formule à sourcer) ;
  - le zaap sert de point de sauvegarde ;
  - le zaapi est limité à sa ville.
- Commun : `Travel`, `Character.known_zaaps`, `Character.save_point` | Serveur : —
- Protocole : `zaap_list`, `zaap_travel{map}`, `set_save_point`
- Client : carte du monde zoomable (vraies textures), minimap, fenêtre de zaap
- Tests : voyage payant, zaap inconnu refusé, défaite qui ramène au point de sauvegarde (`tests/test_travel.gd`, scénario `zaap.jsonl`) ; zaapis : pas dans Incarnam, voir P4.07
- Parité : ☑ règles sourcées ☑ tests ☑ sim_cli ☑ capture ☑ doc

### [x] P1.09 Spawn des monstres par sous-zone
- Dépend : P1.07
- Données : `subareas` (monsters, niveau), `monsters` (grades, isBoss, isMiniBoss, canPlay)
- Règles :
  - groupes générés selon la sous-zone (taille, grades) ;
  - respawn après un combat ;
  - étoiles de bonus qui montent avec le temps (bonus d'XP et de drop, à sourcer) ;
  - groupes agressifs (distance d'aggro, alignement) ;
  - aucun spawn sur les maps sans monstres.
- Commun : `MonsterSpawner` dans `sim/` | Serveur : l'état des spawns est persistant
- Protocole : `actor_add{stars}`
- Client : étoiles sur le groupe, infobulle de groupe (monstres, niveaux, XP estimée)
- Tests : composition conforme à la sous-zone, respawn, agression déclenchant un combat (`tests/test_spawn.gd` ; scénarios `fight_won` / `fight_lost` réenregistrés sur des groupes composés)
- Parité : ☑ règles sourcées ☑ tests ☑ sim_cli ☑ capture ☑ doc

### [x] P1.10 Énergie, mort, fantôme, phénix
- Dépend : P1.08
- Données : `luaformulas` (perte d'énergie, si présente)
- Règles :
  - une défaite fait perdre de l'énergie (formule à sourcer) ;
  - à 0 énergie : tombe, puis fantôme (vitesse, impossible de combattre) ;
  - résurrection au phénix ;
  - l'énergie se régénère.
- Commun : `Character.energy`, états `ghost` et `tomb` | Serveur : —
- Protocole : `player_stats{energy, state}`, `actor_look` (fantôme)
- Client : barre d'énergie, rendu fantôme, phénix sur la carte
- Tests : défaite à 0 énergie, puis fantôme, puis phénix, puis retour à la normale (`tests/test_energy.gd` ; `fight_lost` réenregistré avec la perte d'énergie)
- Parité : ☑ règles sourcées ☑ tests ☑ sim_cli ☑ capture ☑ doc

### [x] P1.11 Combat, partie 2 : invocations
- Dépend : P1.03
- Données : effets 181, 180 (double), 185 (invocation statique), 405… ; monstres invocables
- Règles :
  - nombre d'invocations max (caractéristique) ;
  - l'invocation joue après son invocateur ;
  - elle meurt quand son invocateur meurt ;
  - les invocations statiques ;
  - pas d'XP ni de drop pour une invocation.
- Commun : `FightEffects.summon`, `Fighter.summoner`, IA d'invocation | Serveur : —
- Protocole : `fighter_add{fighter}` dans les effets
- Client : invocation qui apparaît, affichée dans la timeline sous son invocateur
- Tests : limite d'invocations, ordre de jeu, mort en chaîne (`tests/test_summons.gd`, scénario `summons.jsonl`)
- Parité : ☑ règles sourcées ☑ tests ☑ sim_cli ☑ capture ☑ doc

### [x] P1.12 Combat, partie 3 : porter et lancer
- Dépend : P1.11
- Données : effets 50 (porter), 51 (lancer), 52… ; états porteur et porté
- Règles :
  - le porté se déplace avec le porteur ;
  - lancer dans une zone ;
  - interactions avec la pesanteur, l'enracinement et la stabilisation ;
  - le porté est libéré si le porteur meurt.
- Commun : `FightEffects.carry` et `throw` | Serveur : —
- Protocole : effets `carry` et `throw`
- Client : animations porter et lancer du Pandawa
- Tests : porter, marcher, lancer ; stabilisé non portable ; mort du porteur
- Parité : ☑ règles sourcées ☑ tests ☑ sim_cli ☑ capture ☑ doc

### [x] P1.13a Combat, partie 4a : pièges et glyphes
- Dépend : P1.11
- Données : effets 400 (piège), 401 / 402 (glyphes de début / fin de tour), 2018 (dissipe les glyphes) ; `diceNum` / `diceSide` = sous-sort et grade, `value` = couleur, zone = cellules
- Règles :
  - un piège se déclenche quand une entité entre dans sa zone (la marche s'arrête), son sort part de son centre ;
  - un glyphe frappe qui commence (401) ou finit (402) son tour dedans ;
  - durée comptée sur les tours du poseur, marques retirées à sa mort.
- Commun : `FightMarks` | Serveur : —
- Protocole : effets `mark_add`, `mark_remove` ; `fighter_move.triggered`
- Client : cellules des marques dans leur vraie couleur, pièges visibles seulement par leur équipe
- Tests : piège déclenché, glyphe en début et en fin de tour, expiration, mort du poseur, dissipation
- Parité : ☑ règles sourcées ☑ tests ☑ sim_cli ☑ capture ☑ doc

### [x] P1.13b Combat, partie 4b : déclencheurs, sous-sorts, glyphes-auras
- Dépend : P1.13a
- Données : `triggers` et `effectTriggerDuration` des effets, `delay`, sous-sorts 792 / 1017 / 1019 / 1160 / 2160 / 2794 / 2795 / 2960, glyphe-aura 1091, 1163 / 1159, 1109, 141, 406, `spelllevels.maxStack`, `monsters.grades.startingSpellId`
- Règles :
  - un effet déclenché devient un buff « trigger » sur sa cible, qui se déclenche sur ses codes (TB, TE, D…, DBE, DBA, DM, DR, H, X) ;
  - un effet à retardement (`delay`) arrive après autant de tours du lanceur ;
  - un sous-sort est lancé sur la case de la cible (792 : par la cible) ;
  - un glyphe-aura donne ses effets à qui est dedans, et les retire à la sortie ;
  - dommages subis x% (1163), soins reçus x% (1159) ; une invocation lance son sort de départ.
- Commun : `FightTriggers` | Serveur : —
- Protocole : buffs `trigger` / `delay` (`on`, `effect`), marque `aura` ; les effets déclenchés partent dans les événements existants
- Client : texte des buffs déclenchés et à retardement dans l'infobulle du combattant
- Tests : multiplicateur et maxStack, poison de fin de tour, déclencheur sur coup ennemi, chaîne bornée, aura, sort de départ, retardement
- Parité : ☑ règles sourcées ☑ tests ☑ sim_cli ☑ capture ☑ doc

### [x] P1.13c Combat, partie 4c : invisibilité
- Dépend : P1.13a
- Données : effets 150 (« Rend la cible invisible » → spellstates 250 « Invisible »), 202 (« Dévoile les entités invisibles »)
- Règles : position cachée pour l'autre équipe (et son IA), on peut toujours viser la case ; révélé par 202 ou à la fin de l'état (effet `reveal` avec sa case) ; un sort lancé montre d'où (APPROX)
- Commun : `FightVisibility` | Serveur : événements filtrés par destinataire (`WorldSim._fight_emit` : chaque joueur reçoit la vue de son équipe)
- Protocole : `fighter_move.path` vide, `cell` -1, `spell_cast.from`, effet `reveal` ; pièges de l'autre équipe non envoyés
- Client : invisible translucide pour son équipe, absent pour l'autre ; « ? » là où un invisible lance un sort
- Tests : marche cachée, cellule cachée, IA aveugle, révélation par sort et en fin d'état, `from`, pièges non envoyés
- Parité : ☑ règles sourcées ☑ tests ☑ sim_cli ☑ capture ☑ doc

### [x] P1.13d Combat, partie 4d : runes et bombes
- Dépend : P1.13b
- Données : effets 2022 / 2023 (runes), 1009 (déclenche une bombe), tables `spellbombs` (explosion, réaction en chaîne, instantané, mur) et `spellbombwalls` (sort, couleur, alignement, 1 à 7 cases), filtres de masque `F` / `f` (monstres, mesurés par JondoEmu), `p` / `P` (APPROX)
- Règles : rune = marque déclenchée seulement par 2023 (sur la cible), une par case ; bombe : 1009 → réaction en chaîne puis explosion (tue la bombe), une bombe morte (Poudre) → sort instantané ; murs entre deux bombes alignées du même type ; conditions de cible lues au lancer ; `maxStack` sur les buffs de caractéristique ; 1171 / 1172 / 2971 / 1027 (dommages et soins finaux, combo), 753 / 754 / 1040 / 320
- Commun : `FightMarks` (runes, murs), `Summons.detonate` | Serveur : —
- Protocole : `mark_add` kinds `rune` / `wall`, effet `explode`
- Client : runes et murs dessinés comme les marques, « Boum ! », textes des nouvelles caractéristiques ; client_shot `at`, `wall`, `detonate`
- Tests : `test_bombs.gd` (rune déclenchée, durée, explosion, chaîne, bombes alliées épargnées, mur posé et retiré, dommages finaux)
- Parité : ☑ règles sourcées ☑ tests ☑ sim_cli ☑ capture ☑ doc

### [x] P1.13f Combat, partie 4f : portails (Eliotrope)
- Dépend : P1.13d
- Données : effets 1181 (pose un portail : +#3 % dommages = value, +#1 % par case = diceNum, diceSide = le spelllevels.id de « Téléportail »), 1182 (Téléportail), 1183 (désactive un portail, forme A = tous), lettres de masque `R` / `r` (sort projeté ou non), déclencheurs `PT` / `CPT` (traversée), états 3737 « Portail » / 3738 « Errance » (sorts 24955 / 24956)
- Règles : réseau des portails actifs d'un lanceur (au plus proche non visité, sortie = le dernier), traversée en marchant dedans ou par 1182, sort projeté sur un de ses portails (atterrit sur la sortie, depuis le portail d'avant, bonus par case), 1183 désactive pour `duration` tours, ennemis qui ne marchent pas dans un portail au premier tour ; APPROX pour tout ce qui n'est pas dans les données
- Commun : `FightMarks` (portal, network, crossing, cross, projection, unportal), `Fight.cast` (projection, `cast_from`, `fight_round`) | Serveur : —
- Protocole : `mark_add` kind `portal` (active, bonus, per_cell), effets `projected` {path, bonus} et `portal` {mark, active}, `move` how `portal`
- Client : portails bleus (grisés si désactivés), marques dessinées au-dessus des cases de portée, « Portail +N % », traversée en fondu, un portail à soi est une cible valable ; client_shot `on`, `project`
- Tests : `test_portals.gd` (données, réseau et bonus, traversée en marchant, premier tour, sort projeté avec poussée R, Neutral, Interruption, Exil, 4 portails au plus, PT)
- Parité : ☑ règles sourcées ☑ tests ☑ sim_cli ☑ capture ☑ doc

### [x] P1.11b Combat : caractéristiques des invocations (`characRatios`)
- Dépend : P1.11
- Données : `monsters.grades.bonusCharacteristics` ; `monsters.characRatios` et `characteristics.scaleFormulaId` (luaformulas 4 / 5 / 3 / 12) vérifiés : c'est la mise à l'échelle des monstres, pas des invocations
- Règles : PV = grade + bonus × (niveau + 10) / 20 (mesure JondoEmu, inchangé) ; autres caractéristiques = grade + caractéristique de l'invocateur × bonus / 100 (APPROX : parts 50 / 75 / 100 lues dans les données)
- Commun : `Summons.create` | Serveur : —
- Protocole : —
- Client : —
- Tests : `test_summons.gd` (Tofu à deux niveaux : 50 % de l'agilité et des dommages Air, rien hors de son élément ; bombe à 100 %)
- Parité : ☑ règles sourcées ☑ tests ☑ sim_cli ☑ capture ☑ doc

### [x] P1.13e Combat, partie 4e : formes de zone, redirections de dommages, CCMPARR
- Dépend : P1.13b
- Données : enums du client (`docs/client_enums.md`, `tools/client_enums/client_enums.cs` : assemblys Cpp2IL de MelonLoader) : `Metadata.Enums.SpellZoneShape` (les 27 lettres de zone nommées), `Metadata.Effect.ActionId` (les noms des 1 000 effets), la liste des codes de déclencheurs ; effets 786 `CharacterHealAttackers`, 765 `CharacterSacrify`, 1061 `CharacterShareDamages`, 1165 `FightAddGlyphCastingSpellImmediate` ; déclencheur `CCMPARR` (capture JondoEmu)
- Règles : formes `A` (toute la carte), `l` (ligne depuis le lanceur, param2 = longueur), `V` (cône), `U` (demi-cercle), `F` (fourche), `-` / `/` (lignes diagonales), `+` / `#` (croix diagonale, sans centre), `W`, `I` ; `T` reste la ligne perpendiculaire (le client dit PerpendicularLine, pas une croix) ; interception (765 : celui qui est sur la case ciblée, sinon le lanceur), partage (1061 : réparti entre les porteurs), soin des attaquants (786 : #% des dommages), glyphe immédiat (1165), `CCMPARR` une fois par PM utilisé en marchant ; APPROX : la géométrie des formes nommées (le code est natif), le détail des redirections
- Commun : `FightRules.zone`, `FightTriggers` (codes, interceptor, sharers, contexte du coup), `FightEffects.damage` (renvoie tous les coups), `FightMarks` (`glyph_now`), `Fight.move` (CCMPARR) | Serveur : —
- Protocole : mark kind `glyph_now`
- Client : infobulles des nouveaux effets ; `ScenarioBot` `--bot=fight:<spells.id>`
- Tests : `test_zones.gd` (formes), `test_redirects.gd` (786, 765, Sac Animé, 1061, 1165, CCMPARR)
- Parité : ☑ règles sourcées ☑ tests ☑ sim_cli ☑ capture ☑ doc

### [x] P1.13g Combat, partie 4g : formes de zone lues dans le code natif du client
- Dépend : P1.13e
- Données : `zoneDescr` (`shape`, `param1`, `param2`, `isStopAtTarget`) ; code natif `GameAssembly.dll` (adresses des méthodes dans les assemblys Cpp2IL, décompilation Ghidra : `tools/client_code`)
- Règles : fabrique `gru.blgy` (lettre → classe), classes `SpellZoneShape*Behavior` (cases), direction `og.ovk` (exacte ou aucune), coordonnées `oh.owg` / `oh.owh` ; `N` et `;` sans géométrie dans le client
- Commun : `FightRules.zone`, `FightRules.dir8`, `spells.py zone_of`, `Equipment.zone` | Serveur : —
- Protocole : —
- Client : aperçu de zone (même `FightRules.zone`), `client_shot aim`
- Tests : `test_zones.gd` (une forme par test), scénario `zones.jsonl`
- Parité : ☑ règles sourcées ☑ tests ☑ sim_cli ☑ capture ☑ doc

### [x] P1.13h Combat, partie 4h : masques de cible lus dans le client
- Dépend : P1.13g
- Données : lettres de masque inconnues (`c`, `j` / `J`, `U`, `m` / `M`, `l` / `L`, `T`, `b<n>` / `B<n>`, `h`, `d`, `D`, `H`, `i`, `I`, `O`, `o`, `s`, `x`, `V<n>` / `v<n>`, `PB` / `pb`…, lues « tous » en APPROX) ; `p` / `P` / `R` / `r` à confirmer
- Règles : trouver dans le code natif le filtre des masques (l'aperçu des cibles du client : `tools/client_code find` / `xref` autour de `Core.Features.Fight.Spells`, des classes `grs` / `grr`, ou de `EffectInstanceData`), le lire lettre par lettre ; sinon rester APPROX
- Commun : `spells.py convert_effect` (`target`, `cond`), `FightEffects.targets` | Serveur : —
- Protocole : —
- Client : —
- Tests : un test par lettre sourcée, scénario réenregistré si les cibles changent
- Parité : ☑ règles sourcées ☑ tests ☑ sim_cli ☐ capture (rien d'affiché : les masques ne changent que qui est touché) ☑ doc

### [x] P1.13i Combat, partie 4i : codes de déclencheurs lus dans le client
- Dépend : P1.13h
- Données : `Core.Features.Fight.Spells.Triggers` (bits des codes, analyseur `grr.blfl`, `EON<n>` / `EK:<masque>` : `Triggers.blgb` / `blfz`), l'aperçu de combat du client (classe `gzp` : quel événement allume quel code)
- Règles : coups subis (`D`, élément, `DBA` / `DBE`, `DM` / `DR`, `DS`, `DT` / `DG`, `PD`), ce que fait le porteur (`CD…`, `CH`, `CS`, `CC`, `K` / `KWS`, `EK:<masque>`), déplacements (`M`, `P`, `MA`), `APA` / `MPA` / `R` / `LPU`, états (`EON<n>` / `EOFF<n>`, `ION` / `IOFF`) ; les autres codes laissent le sort `partial`
- Commun : `FightTriggers` (`event`, `dealer_codes`, `state_changed`, `died`), `Fight.hit_source`, `Fighter.last_hit_by`, `spells.py TRIGGERS` / `known_trigger` | Serveur : —
- Protocole : —
- Client : textes des nouveaux codes dans l'infobulle des buffs déclenchés
- Tests : `test_trigger_codes.gd` (un test par famille de codes), scénario `attraction.jsonl`
- Parité : ☑ règles sourcées ☑ tests ☑ sim_cli ☑ capture ☑ doc

### [x] P1.13j Combat, partie 4j : baisse des dommages en zone
- Dépend : P1.13g
- Données : `zoneDescr.damageDecreaseStepPercent`, `maxDamageDecreaseApplyCount` (10 % et 4 fois sur presque tous les effets) ; armes : `itemtypes.rawZone` (« X1,0,10,1 » : les deux derniers nombres)
- Règles : code natif : `gru.blgz` (classe de distance par forme : `grz` Manhattan, `gsc` Manhattan / 2, `gse` plus grand écart, `gsa` / `gsb` le long de la direction, `gsd` 0 ; décalage `param2` pour C / Q / X / l / +, `param1` pour O), `grt.blgw` / `grz.blil` (min(100, min(distance − décalage, max) × pas), si `param1` < 51), `hs.nfg` (`param1` ≥ 1, forme autre que P) ; application : `HitContext.bmuv` → `gzm.bmyw` (× (100 − %) / 100), `gzm.bmyv` (sur les dommages côté lanceur, `ra.fay` arrondi à l'inférieur, avant la cible), exclusions `gzj.bmws` / `gzj.bmvt`
- Commun : `FightRules.efficiency`, `FightEffects` (`ZONE_DECREASE`, `damage` / `heal`), `spells.py zone_of`, `Equipment.zone` | Serveur : —
- Protocole : —
- Client : aperçu des dommages en zone (plus tard, avec l'aperçu des dommages)
- Tests : `test_zone_decrease.gd` (une zone de dommages à 0, 1, 2, 3, 5 cases du centre, formes, ordre avec les résistances, soins) ; `bombs` et `zones` réenregistrés
- Parité : ☑ règles sourcées ☑ tests ☑ sim_cli ☑ capture ☑ doc

### [x] P1.13l Combat, partie 4l : options de zone
- Dépend : P1.13j
- Données : `zoneDescr.onlyAffectIfInSightLine` (256 effets, cercles), `forcedDirection` (L, /, R : 240 effets), `includeCarried` (1 sur les points, 0 ailleurs), `cellIds` (forme `;`, sorts de monstres)
- Règles : code natif : offsets de `SpellZoneDescr` (Cpp2IL : `isStopAtTarget` 0xD, `forcedDirection` 0xE, `includeCarried` 0xF, `onlyAffectIfInSightLine` 0x10) ; `gru.blhb` les passe à `gru.blha`, qui les range dans la zone `grt` (0x20 et 0x19 ; `forcedDirection` n'est pas transmis) ; `gtb.blnr` → `gtb.blnw` (ligne de vue depuis le centre), `gtz.nhs` (porté, état 8 : `gvr.bmcs` → `gui.bluz(8)`), classe `grx` (forme `;`)
- Commun : `FightRules.zone`, `FightEffects.targets` | Serveur : —
- Protocole : —
- Client : aperçu de zone (mêmes cases)
- Tests : une zone en ligne de vue, un porté inclus (la direction forcée est passée à P1.13k : aucun lecteur dans le client)
- Parité : ☑ règles sourcées ☑ tests ☑ sim_cli ☑ capture ☑ doc

### [x] P1.13k Combat, partie 4k : lettres de masque T / W / U, « statique », repli de K
- Dépend : P1.13i
- Données : code natif du client : `gtz.blqe` (T → `gvs.bmdh`, W → `gvs.bmdi`, U → `gvs.bmdp`, K), `gyn.bmqg`, la liste d'événements par combattant de l'aperçu (`FightState.bmjp` : événements de déplacement `gzw`, d'invocation `haa`) ; les références de type du code natif (`usage` : emplacement de métadonnées → type, IL2CPP v39)
- Règles : T / W = déplacé pendant ce lancer (vers une case que `pointMov` accepte : `ezl` emplacement 18 = `enq.babz` → `enq.babg`) ; U = invoqué pendant ce lancer ; K = porté par le lanceur, ou lancé par lui pendant ce lancer (`gzw.throwerEntityId`) ; statique = `monsters.canPlay` faux
- Commun : `Fight.cast_log` / `log_cast`, `FightEffects.apply_spell` (le plus externe ouvre la liste), `TargetMask` | Serveur : —
- Protocole : —
- Client : —
- Tests : `test_target_mask.gd` (T / W / U / K par la liste, un vrai lancer qui pousse, Frappe de Xélor : Téléfrag seulement si la cible a bougé, créatures statiques) ; scénario `double.jsonl`
- Parité : ☑ règles sourcées ☑ tests ☑ sim_cli ☑ capture ☑ doc

### [x] P1.13m Combat, partie 4m : codes de déclencheurs restants
- Dépend : P1.13k
- Données : codes que le client ne connaît pas (`XD`, `XPD`, `XDM`…, `TP`, `DTB` / `DTE`, `DV`, `CCMPARR` / `CMPARR`) : le serveur seul les lit, à sourcer par captures ou JondoEmu ; codes que l'aperçu n'évalue pas ou pas encore lus (`CI`, `CT`, `DIS`, `MS`, `PO`, `CAPA` / `CMPA`, `CAPAS` / `CMPAS`, `DI`, `DCCBA` / `DCCBE`, `PMD` / `PPD`, `V` / `VA` / `VE` / `VM`, `PST` / `PDT`) ; le filtre de `M` (ensemble de genres de déplacement, `gzp.bmzy`, champ `dragType` de `gzw`) ; les types des emplacements de métadonnées (outil de P1.13k) aident à lire `gzp`
- Règles : sourcer chaque code ou laisser le sort `partial`
- Commun : `FightTriggers`, `spells.py known_trigger` | Serveur : —
- Protocole : —
- Client : textes des nouveaux codes dans l'infobulle des buffs déclenchés
- Tests : `test_trigger_codes.gd` (6 nouveaux : échange / PO, vol de PA / PM, désenvoûtement, arme et critique, vie, invisibilité donnée), scénario `steal.jsonl`
- Parité : ☑ règles sourcées ☑ tests ☑ sim_cli ☑ capture ☑ doc

### [x] P1.13n Combat, partie 4n : Téléfrag (téléportation sur une case occupée)
- Dépend : P1.13k
- Données : code natif du client : `hai.bnca` / `dht` / `hbl` / `mwk` (aperçu des téléportations : case d'arrivée, `ezl` emplacement 18, occupant `FightState.bmhh`, échange permis `gvr.st` dans les deux sens, événement de déplacement de l'occupant avec `swappedEntityId`, `isTelefrag` si le type lu à `+0x18 +0x14` vaut 5) ; états 244 / 251 (Téléfrag) posés par le sous-sort 13265 ; Xélor
- Règles : une téléportation vers une case occupée échange les deux combattants au lieu d'échouer (aujourd'hui `FightEffects.teleport` refuse une case prise) ; ce que le serveur exige de plus pour T (« Peut générer un Téléfrag »)
- Commun : `FightEffects.teleport` / `_swap` / `can_swap`, `TargetMask` (T = téléfragué), `Fighter.can_switch*`, `spells.py` (`effect` des déplacements, `switch` des invocations), `maps.py` (`switch` des monstres) | Serveur : —
- Protocole : effet `move` : `swapped`, `telefrag`
- Client : — (l'échange s'anime comme `swap`) ; `client_shot mirror:<sort>`
- Tests : `test_telefrag.gd` (échange, occupant d'abord, Téléfrag du seul Xélor, stabilisé / porteur, enraciné selon l'effet, `canSwitchPos` et 4 forcé, Frappe de Xélor complète) ; `test_target_mask.gd` (T / W) ; scénario `telefrag.jsonl`
- Parité : ☑ règles sourcées ☑ tests ☑ sim_cli ☑ capture ☑ doc

### [x] P1.13o Combat, partie 4o : renvoi de dommages (107 / 220)
- Dépend : P1.13k
- Données : 107 CharacterLifeLostReflector et 220 CharacterReflectorUnboosted (145 + 60 grades de sorts de monstres hors d'Incarnam, toujours sur `D`, `diceNum` = dommages renvoyés, montant fixe)
- Règles : `APPROX(P1.13o)` : aucune formule trouvée (luaformulas, enums du client, JondoEmu) ; l'attaquant reçoit `diceNum` (+ la stat `reflect` du porteur pour 107), sans résistances, sans déclencher d'autre effet
- Commun : `FightEffects` (`reflect`), `spells.py REFLECTS` | Serveur : —
- Protocole : —
- Client : infobulle « Renvoie N dommages à l'attaquant »
- Tests : `test_reflect.gd` (renvoi, stat de 107, 220 non boosté, pas de renvoi sur ses propres coups)
- Parité : ☐ règles sourcées ☑ tests ☑ sim_cli ☐ capture ☑ doc

### [x] P1.13r Combat, partie 4r : renvoi de sort, direction forcée
- Dépend : P1.13o
- Données : 106 CharacterSpellReflector (34 grades, sorts de monstres hors d'Incarnam : déclencheurs `APA|D`, `diceSide` 6, `value` 25-80 : sens des champs non établi) ; zones (P1.13l) : `forcedDirection` (L, /, R : 244 effets de monstres, aucun lecteur dans le client), le fournisseur de `grw.blhz` (interface appelée avec (case, origine, true)) et celui de `grw.blia` / `blic` / `grx` (case valable ?), `includeCarried` pour les marques (glyphes, auras : `MarkedCellsService` non lu)
- Règles : sourcer chaque règle (code natif : `tools/client_code`) ou rester APPROX
- Commun : `FightEffects`, `FightRules.zone`, `FightMarks` | Serveur : —
- Protocole : —
- Client : —
- Tests : un test par règle sourcée
- Parité : ☐ règles sourcées (106 = APPROX, `forcedDirection` sans lecteur) ☑ tests ☐ sim_cli (aucun sort concerné dans Incarnam) ☐ capture ☐ doc (ARCHITECTURE inchangé, PROTOCOL régénéré)

### [x] P1.13s Combat, partie 4s : fournisseurs de zone et `includeCarried` des marques
- Dépend : P1.13r
- Données : le fournisseur de `grw.blhz` (interface appelée avec (case, origine, true)) et celui de `grw.blia` / `blic` / `grx` (case valable ?), `includeCarried` pour les marques (glyphes, auras : `MarkedCellsService` non lu)
- Règles : sourcer chaque règle (code natif : `tools/client_code`) ou rester APPROX
- Commun : `FightRules.zone`, `FightMarks` | Serveur : —
- Protocole : —
- Client : —
- Tests : un test par règle sourcée
- Parité : ☐ règles sourcées ☐ tests ☐ sim_cli ☐ capture ☐ doc

### [x] P1.13p Combat, partie 4p : codes de déclencheurs du serveur
- Dépend : P1.13m
- Données : codes que le client ne connaît pas (`XD`, `XPD`, `XDM`, `XDTB` : toujours à côté de `D` / `PD` / `DM` / `TB` ; `CPD`) ou que son aperçu n'allume jamais (`CI`, `CT`, `TP`, `DTB`, `DTE`, `DV`, `CMPARR`, `CAPAS` / `CMPAS`, `CMPDEP`, `CAP`, `TR`, `Y`, `iQ`, `il`) ; `DI` (drapeau de combattant `gyp`+0x38 non identifié), `PMD` (`hs.nes`), `PST` / `PDT` (`FightState`+0x38 dans [0, 560)) ; érosion (`VM` / `VE`) ; 13 sorts de classe concernés (Berserk, Ataraxie, Pénitence, Massacre, Distillation, Laisse Spirituelle, Faille, Férocité, Holmgang, Stratagème, Ronces Agressives, Toupet, Maladresse d'Arme…)
- Règles : à sourcer par captures de combat (JondoEmu : messages du serveur) ; sinon le sort reste `partial`
- Commun : `FightTriggers`, `spells.py known_trigger` | Serveur : —
- Protocole : —
- Client : textes des codes dans l'infobulle
- Tests : un test par code sourcé
- Parité : ☐ règles sourcées (APPROX : sens déduits des descriptions) ☑ tests ☐ sim_cli ☐ capture ☑ doc
- Fait (2026-10-03) : XD, XPD, XDM, XDTB, TP, CPD, CMPAS, CAPAS, DTB, DTE. Restent : DV, CI, CT, CMPARR, CMPDEP, CAP, TR, Y, iQ, il, DI, PMD, PST / PDT (sans source : ils demandent des captures serveur ou le code natif).

### [x] P1.13q Combat, partie 4q : retours en arrière et téléportations restantes
- Dépend : P1.13n
- Données : effets non extraits qui passent par la même règle d'échange (`hai.*`, `FightEffects.can_swap`) : 1106 FightTeleswapMirrorImpactPoint (77 grades : symétrie par rapport au point d'impact), 1100 FightRollbackPreviousPosition (49 : position précédente, Xélor surtout), 1099 FightRollbackTurnBeginPosition (9 : Rembobinage, Tarot d'Ecaflip), 1023 CharacterExchangePlacesForce (9 : échange sans `gvr.st`), 784 CharacterTeleportToFightStartPos ; `hai.bnca` : pour 1099 / 1100 la case d'arrivée vient de `hai.bnbz` (historique des positions, à lire) ; `hai.hbl` saute `gvr.st` pour un effet (0x50, à identifier)
- Règles : garder par combattant sa position de début de tour et la précédente (le déplacement le plus récent) ; les Téléfrags de ces retours (texte i18n « Les Téléfrags » : téléportation à la position précédente / de début de tour)
- Commun : `FightEffects.teleport`, `Fighter` (positions), `spells.py MOVES` | Serveur : —
- Protocole : —
- Client : —
- Tests : Rembobinage sur une case reprise par un autre : échange et Téléfrag ; symétrie par rapport au point d'impact
- Parité : ☐ règles sourcées (1106 : APPROX) ☑ tests ☑ sim_cli ☐ capture (rien de nouveau à voir : `move` `teleport` existant) ☑ doc

### [x] P1.16 IA des monstres par profil
- Dépend : P1.11, P1.13b
- Données : `monsters` (champs de comportement, s'il y en a)
- Règles :
  - profils agressif, prudent (fuit à faibles PV), soigneur, invocateur, kamikaze ;
  - utiliser les états, boosts, poussées et retraits ;
  - rester déterministe et rapide (budget en ms par décision).
- Commun : `FightAI` avec un profil et un score par effet, partagé avec les invocations | Serveur : même code
- Protocole : —
- Client : —
- Tests : chaque profil fait le bon choix sur un combat scripté ; le temps de décision reste sous le budget
- Parité : ☐ règles sourcées (APPROX(P1.16)) ☑ tests ☑ sim_cli ☐ capture (client inchangé) ☑ doc
Pièges, règles trouvées, approximations et lots à créer :

- **Profils d'IA (P1.16)** : la table `monsters` n'a aucun champ de comportement (seulement `aggressive*`) : `APPROX(P1.16)`, le profil se lit dans les sorts (`FightAI.profile`, caché dans `Fighter.ai_profile`) : kamikaze (un sort qui tue son lanceur), invocateur, soigneur, prudent (que des sorts à distance), agressif. Prudent / soigneur / invocateur fuient sous 30 % de PV (`FLEE_PCT`) et lancent depuis leur case ; le soigneur va vers un allié blessé. Pondérations (soin x2, invocation 25, dommages du soigneur x0,5) : réglage, pas une donnée.

### [x] P1.17 Tous les sorts d'une zone : audit « partial »
- Dépend : P1.12, P1.13d
- Données : tous les sorts des monstres et des classes (`spells.py --report`)
- Règles : plus aucun sort `partial` pour Incarnam et Astrub ; un rapport liste les effets non gérés restants
- Commun : `FightEffects`, nouveaux effets | Serveur : —
- Protocole : —
- Client : —
- Tests : chaque effet ajouté a son test ; le rapport d'extraction est vide pour la zone
- Parité : ☐ règles sourcées (1071 / 1132 : APPROX, texte i18n seul) ☑ tests ☐ sim_cli (pas de scénario : aucun monstre d'Incarnam concerné) ☐ capture ☑ doc

### [x] P1.15 Combat, partie 6 : challenges, fuite, options de combat, timer
- Dépend : —
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

## P2 — Économie et progression

### [x] P1.18 Tests de tous les sorts : contrats par effet, cas multi-tours
- Dépend : P1.17
- Données : les 3 990 grades de `spells.json` (classes et monstres) ; descriptions FR (`description_id`)
- Règles : un contrat par type d'effet (`tests/spells/*_contracts.gd`) rejoue chaque effet seul dans une arène neutre (`SpellArena`), jets forcés au min puis au max ; cibles attendues calculées hors moteur (`TargetOracle`) ; cas multi-tours en données (`SpellCases`) ; écarts sourcés (`SpellGaps`)
- Commun : `FightLife` / `FightBuffs` (découpe de `FightEffects`), `spells.py` | Serveur : —
- Protocole : —
- Client : —
- Tests : `test_spell_contracts.gd`, `test_spell_cases.gd` (52 cas) ; `TEST_CASE=<id|nom>`
- Parité : ☑ règles sourcées ☑ tests ☐ sim_cli ☐ capture ☐ doc

### [x] P2.01 PNJ et dialogues
- Dépend : P1.07, P1.06
- Données : `npcs`, `npcmessages`, `npcactions`, positions des PNJ sur les maps
- Règles : dialogue en arbre, réponses conditionnées (`criteria`), actions (ouvrir une boutique, une quête, téléporter)
- Commun : `Dialog`, `NpcActor` | Serveur : —
- Protocole : `npc_talk{npc}`, `dialog{text, replies}`, `dialog_reply{id}`, `dialog_close`
- Client : PNJ affichés avec leur look, fenêtre de dialogue Dofus
- Tests : dialogue complet, réponse cachée par une condition
- Parité : ☐ règles sourcées (APPROX : arbre) ☑ tests ☐ sim_cli (pas de règle de combat) ☑ capture ☑ doc

### [x] P2.02 Marchands PNJ
- Dépend : P2.01, P1.05
- Données : listes de vente des PNJ
- Règles : prix d'achat, revente à un prix réduit (à sourcer), kamas insuffisants, pods
- Commun : `NpcShop` | Serveur : —
- Protocole : `shop_open`, `shop_buy`, `shop_sell`
- Client : fenêtre de boutique
- Tests : achat, vente, refus faute de kamas, refus pour surcharge
- Parité : ☑ règles sourcées (rachat et pods en APPROX) ☑ tests ☑ sim_cli ☑ capture ☑ doc

### [x] P2.03 Quêtes, partie 1
- Dépend : P2.01
- Données : `quests`, `queststeps`, `questobjectives`, `questobjectivetypes`
- Règles :
  - étapes et objectifs : parler, tuer X, ramener Y, aller sur une map, vaincre en combat ;
  - récompenses : XP, kamas, objets, sorts, émotes ;
  - les quêtes d'Incarnam jouables de bout en bout.
- Commun : `QuestLog`, `QuestEngine` (qui écoute les événements de la sim) | Serveur : —
- Protocole : `quest_start`, `quest_update`, `quest_complete`, `quest_list`
- Client : journal de quêtes, suivi à l'écran, notifications
- Tests : une quête d'Incarnam complète en scénario
- Parité : ☑ règles sourcées (APPROX : formules de récompense, ordre des objectifs, dialogues, fabrication) ☑ tests ☑ sim_cli ☑ capture ☑ doc

### [x] P2.04a Quêtes, partie 2a : règles, abandon, marqueurs (sim)
- Dépend : P2.03, P1.08
- Données : `quests.repeatType` (déjà extrait : `repeat`)
- Règles : conditions d'accès (critères = chaînes `Qf=`), quêtes répétables et leur délai (jour réel de `Clock`), abandon, marqueurs de la map calculés par la sim
- Commun : `QuestEngine.can_start` / `markers`, `QuestLog.finished_day` / `abandon` | Serveur : —
- Protocole : `quest_abandon`, `map_markers`
- Client : bouton « Abandonner » du journal
- Tests : chaîne de quêtes, répétable bloquée pendant le délai, abandon, marqueurs
- Parité : ☑ règles sourcées (APPROX : sens de `repeatType`, délai) ☑ tests ☑ sim_cli ☑ capture ☑ doc

### [x] P2.04b Quêtes, partie 2b : marqueurs affichés
- Dépend : P2.04a
- Données : `map_markers` (déjà envoyé)
- Règles : —
- Commun : — | Serveur : —
- Protocole : —
- Client : points d'exclamation au-dessus des PNJ qui proposent une quête, marqueur d'objectif sur la carte du monde et la minimap (fait : `ClientSession._apply_markers`)
- Tests : une capture
- Parité : ☑ règles sourcées (aucune règle : affichage) ☑ tests (423 tests verts, `test_map_markers_show_offers_and_goals` couvre les données) ☑ sim_cli (scénario `quest_abandon` existant) ☑ capture ☑ doc

### [x] P2.05a Métiers, partie 1a : récolte (règles, protocole, clic)
- Dépend : P1.07, P1.05
- Données : `skills` / `jobs` (tables légères), éléments interactifs des maps (JondoEmu `interactive_elements.json` + `recursos_*.json` : `gamedata.py interactives <monde>` → `worlds/<id>/interactives.json`)
- Règles : niveau de métier requis (`skills.levelMin`), durée, quantité selon le niveau, repousse, XP de métier (APPROX, voir Découvertes)
- Commun : `shared/Jobs`, `sim/JobLog`, `sim/InteractiveState` (par map, partagé par les joueurs de la map) | Serveur : même code
- Protocole : `interactive_use{element, skill}`, `interactive_start`, `interactive_end`, `interactive_state`, `job_xp` ; `player_stats.jobs`
- Client : clic sur la ressource (marche à côté puis récolte), animation `useAnimation`, toast d'XP de métier
- Tests : `test_jobs.gd` (9), scénario `harvest.jsonl`
- Parité : ☑ règles sourcées (APPROX marqués) ☑ tests ☑ sim_cli ☑ capture ☑ doc

### [x] P2.05b Métiers, partie 1b : règles (critère PJ, effet 614, apprentissage)
- Dépend : P2.05a
- Données : `queststeprewards.jobsReward` (liste d'ids de métiers : `quests.json` champ `jobs`), effet d'objet 614 (parchemins de métier)
- Règles : critère `PJ<op><métier>,<niveau>` dans `CriteriaEval` (niveau du métier, `Character.criteria_values().jobs`) ; effet 614 = `[614, 0, métier, XP]` (`ItemEffects.JOB_XP`, `use_item` donne l'XP et `job_xp`) ; `jobsReward` enseigne le métier (`JobLog.learn`) ; pods : une récolte n'est jamais refusée faute de place (comme tout gain, `give_item`)
- Commun : `CriteriaEval`, `ItemEffects`, `JobLog`, `QuestEngine.rewards` | Serveur : —
- Protocole : aucun changement (`job_xp` réutilisé ; `rewards.jobs` dans `quest_complete`)
- Tests : `test_jobs.gd` (PJ, parchemin, jobsReward)
- Parité : ☑ règles sourcées (APPROX marqués) ☑ tests ☐ sim_cli (rien de nouveau à rejouer) ☐ capture (aucun client) ☑ doc

### [x] P2.06a Métiers, partie 2a : craft (règles, protocole)
- Dépend : P2.05a
- Données : `recipes` (copie légère), `skills.parentJobId`
- Règles : cases selon le niveau (APPROX), le craft crée des instances aux jets aléatoires, craft en série, XP de craft (APPROX), grimoire des recettes (celles qui tiennent dans les cases)
- Commun : `Crafting` | Serveur : `WorldCrafting`
- Protocole : `craft_open`, `craft_set`, `craft_do{count}`, `craft_close`, `craft_state`, `craft_done`
- Tests : `test_crafting.gd` (8), scénario `craft.jsonl`
- Parité : ☑ règles sourcées (APPROX marqués) ☑ tests ☑ sim_cli ☐ capture (aucun client : P2.06b) ☑ doc

### [x] P2.06b Métiers, partie 2b : fenêtre d'atelier et grimoire des recettes
- Dépend : P2.06a
- Règles : aucune (affichage seulement ; règles de P2.06a)
- Client : fenêtre d'atelier (cases d'ingrédients posées depuis le sac, résultat, quantité, bouton Fabriquer) et grimoire des recettes (kit `client/ui/`), ouverte par une compétence de craft ; `ClientSession` envoie `craft_open` / `craft_set` / `craft_do`
- Tests : `test_craft_client.gd` (4 : `CraftModel` pilote par `LocalBackend`) ; capture `client_shot --cmd=craft:20 --cmd=craft_recipe:44` relue
- Parité : ☑ règles sourcées (aucune règle ajoutée) ☑ tests ☐ sim_cli (aucune règle, `craft.jsonl` de P2.06a reste la référence) ☑ capture ☑ doc
- APPROX(P2.06b) : aucun atelier sur les maps (donnée serveur absente) : la touche J (`Shortcuts` « workshop ») ouvre le dernier atelier (Forger au départ) et la liste déroulante change de compétence ; cliquer un élément interactif dont la compétence est un craft ouvre aussi la fenêtre.

### [x] P2.07a Forgemagie, partie 1 : règles et protocole
- Dépend : P2.06a
- Données : runes = objets de type 78 (195, `gamedata.py items` les garde tous : effet de la caractéristique + quantité en `diceNum`), maximum d'un objet = ses dés ; AUCUNE formule de forgemagie dans `luaformulas` ni les tables (vérifié) : tout le modèle est APPROX
- Règles : `Smithmagic` (poids par unité, chance selon le maximum, critique / réussite / neutre / échec, puits rempli par les échecs, overmax payé par le puits, exotiques, PA / PM / Portée à +1 maximum)
- Commun : `Smithmagic` | Serveur : `WorldSmithmagic` (`sim/`)
- Protocole : `fm_apply{uid, rune}` -> `fm_result{uid, rune, outcome, item, lost}`, `item_added` / `item_removed` ; erreurs `fm_item`, `fm_rune`, `fm_reserve` ; `reserve` (centièmes de poids) sur l'instance d'objet (jamais empilée avec un objet sans puits, suit l'objet à l'équipement et au coffre)
- Tests : `test_smithmagic.gd` (9 : runes lues dans les données, chance, overmax et puits, distribution déterministe par graine, mouvements de poids de chaque issue, `fm_apply` par `LocalBackend`, pile qui donne un objet, objet porté refusé) ; scénario `smithmagic.jsonl`
- Parité : ☐ règles sourcées (aucune source : APPROX(P2.07)) ☑ tests ☑ sim_cli ☐ capture (lot b) ☑ doc
- APPROX(P2.07) : poids par unité (Dofus 2 : Vitalité 0,2, Force 1, Sagesse 3, PA 100, PM 90, Portée 51, Critique 10, Dommages 20, Soins 20…), chance = 100 - 70 x nouvelle valeur / maximum (au moins 30 %), critique = chance / 10, le reste après la réussite se partage entre neutre et échec, la perte d'une réussite ou d'un échec est tirée sur les autres caractéristiques au hasard (au moins une unité), l'overmax est une réussite sûre qui consomme le poids de la rune du puits ; pas de rune de signature, de chasse ni de caractéristiques négatives ; objet porté refusé ; le puits démarre à 0 (le vrai puits dépend du niveau et des jets, donnée serveur absente).

### [x] P2.07b Forgemagie, partie 2 : fenêtre cliente
- Dépend : P2.07a
- Règles : aucune (affichage seulement ; règles de P2.07a)
- Client : fenêtre de forgemagie (sac : équipement et runes, aperçu `Smithmagic.preview` : chance, critique, overmax refusé, puits), historique des résultats (`fm_result`), touche et ouverture via l'atelier de forgemagage (`skills.isForgemagus`) ; `client_session.gd` est à la limite de 800 lignes : extraire un domaine d'abord
- Tests : modèle de fenêtre sans Node piloté par `LocalBackend`, capture relue
- Parité : ☑ règles sourcées (aucune règle côté client) ☑ tests (`test_smithmagic_client`) ☐ sim_cli (sans objet) ☑ capture (fenêtre K relue) ☑ doc

### [x] P2.08 Banque et coffres
- Dépend : P1.05, P0.02
- Données : PNJ banquier
- Règles : banque partagée au niveau du compte, coût d'accès (à sourcer), dépôt et retrait de kamas
- Commun : `Bank` via `Persistence` (niveau compte) | Serveur : transactions
- Protocole : `bank_open`, `bank_move`
- Client : fenêtre à deux grilles, inventaire et banque
- Tests : un objet déposé par un personnage est visible par un autre personnage du même compte
- Parité : ☑ règles sourcées (texte du banquier i18n 913012 ; coût APPROX) ☑ tests ☑ sim_cli ☑ capture ☑ doc

### [x] P2.03b Quêtes, complément : récompenses d'émotes, de titres et de sorts appliquées
- Dépend : P2.03, P2.05a, X.01
- Règles : émotes, titres et sorts de récompense réellement appliqués (voir Fait)
- Commun : `Character`, `WorldQuests` | Serveur : —
- Protocole : `player_stats` porte `emotes` et `titles`
- Client : —
- Tests : `test_quest_rewards` (Local + Net)
- Fait : `Character.emotes` / `titles` envoyés dans `player_stats` ; `quest_spells` castables en combat (`known_spells`, grade du niveau) ; test Local + Net (`test_quest_rewards`).
- Parité : ☑ règles sourcées ☑ tests ☐ sim_cli ☐ capture ☑ doc

### [x] P2.05c Métiers, partie 1c : XP par récolte, retours visuels, fenêtre des métiers
- Dépend : P2.05b, X.01
- Règles : XP par récolte sourcée (code natif) ; reste APPROX : table d'XP, durée, repousse, quantité, ressources bonus (P2.05d)
- Protocole : — (`player_stats.jobs` portait déjà les métiers)
- Client : ressource grisée, curseur de récolte, fenêtre des métiers
- Fait : XP d'une récolte = `(levelMin / 10) * 2 + 10` (code natif `JobSkillsUI.GetXpForSkillCollect`), ressource grisée pendant la repousse (`ResourceView`, `self_modulate`), curseur de récolte (`MapCursor.kind_for_skill`), fenêtre des métiers (touche P : `JobsWindow` / `JobsModel`), commandes `client_shot` `element:<id>` et `jobs`
- Tests : `test_jobs_client.gd` (formule, grisage, curseur, modèle, `NetBackend`)
- Parité : ☑ règles sourcées ☑ tests ☑ sim_cli ☑ capture ☑ doc

### [x] P2.10a Hôtel de vente : règles, protocole, sim (fait)
- Dépend : P2.08, P0.02, X.01
- Données : `auctionhouses` (quantités), `itemtypes.categoryId`
- Règles : taxe, lots 1/10/100/1000, durée, prix moyen, kamas versés hors ligne, plafond de lots (APPROX(P2.10) notés dans `market_rules.gd`)
- Tests : `test_market.gd` (Local à deux personnages, Net, vente hors ligne, expiration)
- Fait : `shared/market_rules.gd` (taxe 2 %, lots 1/10/100/1000, durée 14 j, 50 lots max : APPROX), `shared/protocol_market.gd` (`hdv_open/search/sell/buy/cancel/close`), `sim/marketplace.gd` (lots + prix moyen via `Persistence`), `sim/world_market.gd` (kamas de la vente versés hors ligne via le document `proceeds`), `tests/test_market.gd` (Local + Net).
- Parité : ☑ règles sourcées (APPROX notés) ☑ tests ☐ sim_cli (pas de scénario : HDV hors combat) ☐ capture (P2.10b) ☑ doc

### [x] P2.12a Succès : objectifs, récompenses, points
- Dépend : P2.03, X.01
- Données : `achievements`, `achievementobjectives`, `achievementrewards`, `achievementcategories` -> `game/data/achievements.json` (`gamedata.py achievements`, non commité : donnée dérivée)
- Règles : objectif = critère Dofus lu par `CriteriaEval` (PL, Qf / QF, EM, ES, EI, OA / Ob / Oa, PO) ; compteurs d'événements dans `AchievementLog` ; récompenses = lignes de `achievementrewards` par `QuestEngine.rewards` ; points ; chaînage (OA, Oa) ; monde opt-in `"achievements": true`
- Commun : `Achievements`, `AchievementLog`, `WorldAchievements` | Serveur : —
- Protocole : `achievement_open`, `achievement_list`, `achievement_unlocked` (`ProtocolAchievement`)
- Tests : `test_achievements.gd` (Local avec combat réel, Net sur 127.0.0.1)
- Parité : ☑ règles sourcées ☑ tests ☐ sim_cli ☐ capture ☑ doc

### [x] P2.10b Hôtel de vente : client et accès
- Dépend : P2.10a
- Règles : l'accès est libre partout (APPROX de P2.10a) : le limiter à un élément interactif / PNJ d'hôtel de vente (`auctionhouses.typeId`, positions à trouver) ; tables `auctionhouses` à extraire (catégories des 7 hôtels) ; lots de vendeur connecté dans un autre monde du cluster payés à son retour (pas de push) ; remplacer les APPROX de `market_rules.gd` si une source apparaît
- Client : fenêtre d'HDV (`UiWindow`) : recherche (nom, catégorie), liste des lots (prix, prix unitaire, prix moyen), achat, mise en vente (lot 1/10/100/1000, prix, taxe affichée), mes lots (reprise, expirés), message de vente ; `client_shot` ; audit (`S.05`) des achats / ventes
- Tests : modèle client, capture
- Parité : ☑ règles sourcées (APPROX(P2.10b) notés) ☑ tests ☐ sim_cli (aucune règle de combat touchée, pas de nouveau scénario) ☑ capture ☑ doc

### [x] P2.12b Succès : client
- Dépend : P2.12a
- Données : `data/achievements.json` (P2.12a)
- Règles : aucune nouvelle (client seul, les règles sont celles de P2.12a)
- Client : fenêtre des succès (U : catégories, points, objectifs), notification `achievement_unlocked`, lecture de `data/achievements.json` côté client
- Tests : modèle, fenêtre, Net 127.0.0.1
- Parité : ☑ règles sourcées ☑ tests ☐ sim_cli ☑ capture ☑ doc

### [x] P2.03c Quêtes : fabrication suivie
- Dépend : P2.03b, P2.06a
- Règles : objectif 17 compté par le craft (événement `craft` de `WorldCrafting.on_craft_do`), plus par le contenu du sac.
- Tests : `test_crafting.gd` (Local + Net), `test_quests.gd`
- Parité : ☑ règles sourcées ☑ tests ☐ sim_cli ☐ capture ☐ doc

## P3 — Social et multijoueur

### [x] P3.05a Amis, ennemis, ignorés : règles, protocole, serveur
- Dépend : P3.02a
- Données : — (APPROX(P3.05) : 100 entrées par liste, un joueur sur une seule liste à la fois, ajout d'un ami immédiat et à sens unique ; pas de table extraite)
- Règles : listes au niveau du compte (entrées = compte + nom de personnage), notification de connexion et de déconnexion aux amis connectés, ignorés non entendus sur tous les canaux (y compris le privé, sans prévenir l'expéditeur)
- Commun : `Contacts` (`shared/contacts.gd`) | Serveur : `WorldContacts` (`sim/world_contacts.gd`), stockage dans le document de compte via `Persistence` (clé `contacts`)
- Protocole : `shared/protocol_contacts.gd` : `contacts_get`, `contact_add{kind, name}`, `contact_remove{kind, name}` ; `contacts{friends, enemies, ignored}`, `contact_status{kind, name, online, playing, level}` ; erreurs `bad_contact_kind`, `contact_self`, `contact_exists`, `contact_full`, `contact_unknown`
- Tests : `tests/test_contacts.gd` (règles pures, ajout / retrait, ami hors ligne retrouvé dans les sauvegardes, listes retrouvées à la session suivante, notices, ignoré sans message reçu, ignoré par compte, et le même flux par deux comptes `NetBackend` sur 127.0.0.1)
- Parité : ☑ règles sourcées (APPROX(P3.05), pas de donnée) ☑ tests ☐ sim_cli (sans objet) ☐ capture (P3.05b) ☑ doc

### [x] P3.05b Amis : fenêtre du client
- Dépend : P3.05a
- Règles : —
- Client : fenêtre des amis (kit `client/ui/`, raccourci dans `Shortcuts`) : trois onglets amis / ennemis / ignorés, pastille en ligne, ajout par nom, retrait, clic droit « chuchoter » ; toast sur `contact_status` ; `ClientSession` route `contacts` et `contact_status` ; commandes de chat `/friend`, `/ignore` à envisager ; `client_shot` : `friends`, `friend_add:<nom>`
- Tests : routage des événements, rendu de la fenêtre sans erreur, capture relue
- Parité : ☑ tests (`test_contacts_client.gd`, dont un flux `NetBackend`) ☑ capture (`client_shot --mate=Bob --cmd=…:friend_add:Bob --cmd=…:friends`, relue) ☑ doc

### [x] P3.11a Échange entre joueurs : règles, protocole, serveur
- Dépend : P3.01, P3.02a
- Données : — (aucune règle d'échange dans les tables du client ni dans `luaformulas` : APPROX(P3.11), voir Découvertes)
- Règles : invitation d'échange à un joueur de la même map (hors combat, hors fantôme, aucune fenêtre ouverte, pas deux échanges à la fois), fenêtre commune (objets et kamas de chacun, poids du sac vérifié), validation des deux côtés, toute modification annule les validations, annulation par l'un ou l'autre (déplacement, autre action, combat, déconnexion), transfert atomique à la double validation (sac plein = refus sans perte), journal d'audit de chaque échange ouvert
- Commun : `TradeRules` (`shared/trade_rules.gd`) | Serveur : `sim/world_trade.gd` (`WorldTrade`), `sim/trade_session.gd`
- Protocole : `trade_invite`, `trade_accept`, `trade_decline`, `trade_set` (objets, kamas), `trade_ready`, `trade_cancel` ; `trade_invited`, `trade_open`, `trade_update`, `trade_end` ; extension `ProtocolTrade` (`shared/protocol_trade.gd`) ; erreurs `trade_busy`, `not_in_trade`, `no_trade_invitation`
- Client : voir P3.11b
- Tests : `tests/test_trade.gd` (règles pures, schéma, échange complet, validations annulées par un changement, annulation, invitations refusée / expirée, un seul échange, autre map, fantôme, offre refusée, sac plein, déplacement / action / combat / déconnexion, sink d'audit, et le flux par deux `NetBackend` sur 127.0.0.1) ; `tools/essai_serveur.gd` (+ `tools/essai_trade.gd`) : la sonde « échange » est devenue un vrai scénario
- Parité : ☑ règles sourcées (APPROX(P3.11) noté : aucune source) ☑ tests ☑ sim_cli (sans objet : `sim_cli` ne pilote qu'une session, S.07) ☐ capture (P3.11b : pas de client dans ce morceau) ☑ doc

### [x] P3.11b Échange entre joueurs : client (fenêtre, menu d'un joueur)
- Dépend : P3.11a
- Données : —
- Règles : aucune (le client affiche seulement)
- Protocole : celui de P3.11a (`trade_*`), rien de nouveau
- Client : fenêtre d'échange (kit `client/ui` : `UiWindow`, `ItemSlot`), mes objets et mes kamas à gauche, ceux de l'autre à droite, boutons Valider / Annuler, état « validé » de chaque côté ; entrée « Échanger » dans le menu d'un joueur (`client/other_players.gd`) ; invitation reçue en notification (accepter / refuser, comme `PartyFrame`) ; textes des fins (`trade_end.reason`) ; `client_shot` : `trade:<joueur>`, `mate:trade...`
- Tests : modèle de la fenêtre (sans nœud, comme `craft_model`), flux avec de vraies `ClientSession` sur `LocalBackend` (invitation, offre, validation, fin)
- Parité : ☑ règles sourcées (aucune règle côté client) ☑ tests ☑ sim_cli (sans objet : une seule session) ☑ capture ☑ doc

### [x] P3.10 Défis (duels)
- Dépend : P3.01, P1.15
- Données : —
- Règles : défi accepté (une minute pour répondre, même map, hors combat, aucun des deux occupé), combat sans perte d'énergie ni gain : ni XP, ni kamas, ni butin, ni mort (les PV d'avant reviennent) ; abandonner ou se déconnecter = perdre, sans pénalité ; personne ne peut rejoindre un duel, on peut le regarder
- Commun : `Fight.kind = duel` (équipe 0 = le provocateur, équipe 1 = le provoqué, tous deux des joueurs) | Serveur : —
- Protocole : `duel_request`, `duel_accept`, `duel_decline` ; `duel_requested`, `duel_end` (extension `protocol_duel.gd`, erreurs `duel_busy`, `no_duel_request`)
- Client : menu contextuel « Défier », carte Accepter / Refuser sous le groupe (`DuelInvites`, `DuelModel`)
- Tests : `test_duel.gd` (8 : messages, duel de deux équipes, rien gagné ni perdu, abandon, déconnexion, refus / expiration, occupés, et le même flux par deux `NetBackend`), `test_duel_client.gd` (2)
- Parité : ☑ règles sourcées (APPROX : délai d'une minute, duel permis sur toute map, voir Découvertes) ☑ tests ☑ sim_cli (non applicable : `sim_cli` ne pilote qu'une session, S.07 ; le flux est couvert par les tests à deux clients) ☑ capture ☑ doc

### [x] P3.06a Guildes : création, rangs, droits, invitation, canal /g
- Dépend : P3.02a, P0.02
- Règles : création (nom `namingrules` guilde, emblème `emblemsymbols` / `emblembackgrounds`), rangs `guildranks`, droits `guildrights`, invitation, exclusion, passage de la main, dissolution, canal `/g`
- Commun : `Guild` (shared), `WorldGuild` via `Persistence` (`guilds`, `guild_members`, `guild_names`) | Serveur : concurrence = dette S.03
- Protocole : `guild_*` (`protocol_guild.gd`)
- Tests : `tests/test_guild.gd` (règles pures, Local à plusieurs clients, Net sur 127.0.0.1)
- Parité : ☑ règles sourcées ☑ tests ☐ sim_cli (sans objet : aucune règle de combat) ☐ capture (client en P3.06b) ☑ doc

## P4 — Contenu et monde vivant

### [x] P4.01 Donjons
- Dépend : P1.09, P1.16
- Données : `dungeons`, salles (maps), clés (items), boss
- Règles :
  - entrée avec une clé ;
  - enchaînement des salles (le groupe de chaque salle doit être vaincu) ;
  - sortie ;
  - IA et mécaniques spécifiques des boss ;
  - premier donjon : Incarnam ou Astrub.
- Commun : `Dungeon` | Serveur : une instance par groupe si besoin
- Protocole : `map_enter{dungeon, room}`
- Client : indicateur de salle
- Tests : donjon traversé en scénario
- Parité : ☐ règles sourcées ☐ tests ☐ sim_cli ☐ capture ☐ doc

## R — Refactoring (sans changement de comportement)

### [x] R.01 Refactoring de l'architecture
- Dépend : P2.08
- Données : —
- Règles : aucune nouvelle règle ; les scénarios de référence restent identiques (aucun `--rerecord`), le nombre de tests ne baisse pas
- Commun : `sim/world_sim.gd` réduit à un routeur (connexion, tick, drain, `_handle`) + gestionnaires par domaine dans `sim/` (`WorldItems`, `WorldTravel`, `WorldNpcs`, `WorldQuests`, `WorldJobs`, `WorldDeath`, `WorldFights`) | Serveur : —
- Protocole : —
- Client : `ClientSession` : une seule « action en attente » (`PendingAction`) à la place des `_pending_*` ; plus grosses fonctions découpées (`FightRules.zone`, `FightEffects._apply`, `FightView._apply_effects`, `ClientSession._dispatch`)
- Tests : `test_architecture.gd` : taille d'un fichier <= 800 lignes (exceptions justifiées)
- Parité : ☑ règles sourcées (inchangées) ☑ tests ☑ sim_cli ☑ capture ☑ doc

### [x] R.05 Test d'horloge réelle de `test_net` instable
- Dépend : —
- Règles : sans objet. `test_net::test_clock_with_the_real_clock` échoue sur cette machine, même sur le HEAD d'avant H.06 (écart client / sim de 145 à 175 ms pour un seuil de 60 ms, mesure à l'horloge réelle dans un seul processus) : trouver si l'écart vient de la durée d'un tour de boucle (`host.poll` lent) ou d'une vraie dérive de `NetBackend`, puis corriger ou fixer un seuil justifié.
- Tests : `TEST_ONLY=test_net.gd` vert trois fois de suite.
- Parité : ☐ règles sourcées (sans objet) ☐ tests ☐ sim_cli ☐ capture ☐ doc

## H — Harnais anti-régression (priorité 1)

### [x] R.04 Tests qui dépendent de l'ordre
- Dépend : —
- Règles : sans objet. `test_travel::test_save_point_at_a_zaap_for_recall_and_defeat` passe seul mais échoue quand `test_quests` ou `test_security` tournent avant (le combat perdu ne finit pas : « expected lose, got "" ») : un état statique partagé fuit d'un test à l'autre. Le trouver et l'isoler. Aussi instables (2026-10-12, déjà rouges sur `7ac1017`) : `test_accounts` et `test_world_loader` échouent au premier lancement après un `--import` (démarrage à froid : hachage du login dans un thread, délais trop courts ?) puis passent ; les échecs WebSocket « sporadiques » notés en C.06/C.07.
- Tests : `TEST_ONLY=test_quests,test_travel` vert ; suite complète verte deux fois de suite.
- Parité : ☐ règles sourcées (sans objet) ☐ tests ☐ sim_cli ☐ capture ☐ doc

### [x] H.01 Socle du harnais : garde des tests, niveaux fast / full
- Dépend : R.04
- Données : `game/tests/run_tests.gd`, `tools/`
- Règles :
  - `run_tests.gd` échoue si un fichier de test ne se parse pas (aujourd'hui l'erreur est silencieuse) ou si le total de tests baisse sous `tests/baseline.json` (mis à jour volontairement) ;
  - rapport récapitulatif en fin de run (par fichier : tests, échecs, durée) ;
  - niveaux `TEST_TIER=fast|full` : `fast` = contrats de sorts + cas multi-tours + scénarios, en moins de 5 min ; `full` = tout ;
  - `tools/test_all.ps1` découpe la suite complète en lots (un processus Godot par lot) pour éviter la fuite d'état et les délais de plus de 30 min d'un seul bloc.
- Commun : — | Serveur : —
- Protocole : —
- Client : —
- Tests : un fichier de test volontairement cassé fait échouer le run ; `TEST_TIER=fast` vert en moins de 5 min
- Parité : ☑ règles sourcées (sans objet) ☑ tests (fichier cassé volontairement : echec ; baseline relevee : echec ; fast vert en 50 s) ☐ sim_cli (sans objet) ☐ capture (sans objet) ☑ doc

### [x] P1.18b Tests des sorts : cas retirés et fumée du sort entier
- Dépend : P1.18, H.01
- Données : `spells.json`
- Règles : (le reste de l'ancien lot est dans P1.18c)
  1. Deux cas retirés à corriger dans le moteur : Runification (Huppermage : la rune se déclenche mais pas le vol par élément ni les +30 caractéristiques), Estoc Brûlant (Forgelance : poussée « depuis le lanceur » en cône, mauvaise case d'arrivée) ; le Forgelance n'a encore aucun cas
  2. Fumée du sort entier : chaque grade complet (normal et critique) lancé d'un bloc, pour les interactions entre effets que les contrats isolés ne voient pas
- Commun : `FightEffects`, `FightLife`, `FightBuffs`, `FightDisplace` | Serveur : —
- Protocole : —
- Client : —
- Tests : `test_spell_cases.gd` (les deux cas rétablis), fumée dans `test_spell_contracts.gd`
- Parité : ☐ règles sourcées ☐ tests ☐ sim_cli ☐ capture ☐ doc

### [x] H.02 Golden des sorts : un instantané par sort de classe
- Dépend : H.01, P1.18b
- Données : `spells.json`, `tests/spells/` (`SpellArena`, `spell_check`, `spell_index`)
- Règles :
  - pour chaque sort de classe (par `spells.id`, plus ses variantes Sobre / Saoul) : un duel standard dans `SpellArena` ; instantané de l'effet (PV, PA / PM, états, buffs, positions, marques, invocations) comparé à `tests/golden/spells/<classe>.json` ;
  - `--update-golden` régénère les fichiers (le diff est relu au commit) ;
  - un test paramétré par sort via `TestCase.sub()`, filtrable par `TEST_CASE=`.
- Commun : — | Serveur : —
- Protocole : —
- Client : —
- Tests : casser une valeur de dégâts fait échouer le golden et le contrat du sort concerné (test de mutation manuel)
- Parité : ☑ règles sourcées (sans objet) ☑ tests (golden de 1 730 grades en 11 s ; mutation +5 dégâts : 2 172 échecs, restaurée ; TEST_CASE filtre) ☐ sim_cli (sans objet) ☐ capture (sans objet) ☑ doc

### [x] H.03 Audit et garde de couverture des sorts
- Dépend : H.02
- Données : `spells.json`, `SpellGaps`
- Règles :
  - `tools/spell_audit.gd` écrit `docs/SPELL_AUDIT.md` (effets jamais testés, par classe) ;
  - un test échoue si un grade n'a ni contrat, ni golden, ni écart déclaré dans `SpellGaps` ;
  - 4 à 8 cas multi-tours par classe pour les mécaniques sensibles (`spell_cases.gd`).
- Commun : — | Serveur : —
- Protocole : —
- Client : —
- Tests : un sort factice sans ligne de golden fait échouer le garde de couverture
- Parité : ☐ règles sourcées (sans objet) ☐ tests ☐ sim_cli ☐ capture ☐ doc

### [x] H.04 Matrice monstres : un test par monstre, paramétré par famille
- Dépend : H.03
- Données : table `monsters`, zones chargées (`monsters.json`), `FightRewards`
- Règles :
  - pour chaque monstre jouable : stats, niveau et résistances lus ; tous ses sorts présents et complets ; apparition en combat ; une partie de N tours contre un mannequin standard sans erreur ni blocage (seed fixe, déterministe) ; XP et drops conformes aux formules ;
  - familles regroupées (invocateur, soigneur, bombe, tireur…) en tests paramétrés : même combat, attendus différents par famille.
- Commun : — | Serveur : —
- Protocole : —
- Client : —
- Tests : `tests/test_monster_matrix.gd` (8 tests, 1 343 monstres : incarnam, dofus, boss), `TEST_CASE=dofus:4108` ; casser les dégâts (`FightLife.damage`) fait échouer `test_every_monster_plays` ; un monstre sans ligne de `tests/golden/monsters/matrix.json` échoue
- Parité : ☑ règles sourcées (sans objet) ☑ tests ☐ sim_cli (sans objet) ☐ capture (sans objet) ☑ doc ; mode serveur : échantillon rejoué par `NetBackend` dans H.06

### [x] H.05 Golden de l'IA : trace du premier tour par profil et par famille
- Dépend : H.04
- Données : `tests/test_ai_profiles.gd`, `FightAi`
- Règles : par profil d'IA et par famille de monstres, la trace des actions du premier tour est comparée à `tests/golden/monsters/*.json` ; toute dérive de comportement est visible au diff.
- Commun : — | Serveur : —
- Protocole : —
- Client : —
- Tests : modifier le choix de cible de l'IA fait échouer le golden du profil concerné
- Parité : ☐ règles sourcées (sans objet) ☐ tests ☐ sim_cli ☐ capture ☐ doc

### [x] P1.17b Sorts « partial » restants : classes et autres zones
- Dépend : P1.17
- Données : 18 grades de classe encore `partial` (`spells.json`), tous des codes de déclencheur sans source (DV, CI, CT, DI) ; les effets 1045, 2935, 335... sont lus depuis les lots précédents, 1097 l'est depuis le morceau 16 ; les monstres des autres sous-zones (`--world dofus` : 2 851 grades de sorts, 70 seulement chargés)
- Règles : lire chaque effet (texte i18n `effects.descriptionId`, enums du client), l'ajouter à `spells.py` et à `FightEffects` avec son test, par ordre de fréquence
- Commun : `FightEffects`, `spells.py` | Serveur : —
- Protocole : —
- Client : —
- Tests : chaque effet ajouté a son test
- Parité : ☐ règles sourcées ☐ tests ☐ sim_cli ☐ capture ☐ doc

### [x] P1.14 Combat, partie 5 : exactitude des formules
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
- Parité : ☐ règles sourcées (formules communautaires, `APPROX(P1.14)` documentés) ☑ tests ☐ sim_cli (sans objet) ☐ capture (sans objet) ☑ doc

### [x] H.06 Parité serveur et process : le harnais fait partie du workflow
- Dépend : H.05, P1.17b, P1.14
- Données : —
- Règles :
  - un échantillon de la matrice (sorts et monstres) est rejoué via `NetBackend` (127.0.0.1) pour vérifier l'identité local / réseau ;
  - `/suite` (`.claude/commands/suite.md`) et `CLAUDE.md` : « tout nouveau sort ou monstre ⇒ ligne golden + test » ;
  - docs `CARTE.md`, `COMMANDES.md`, `ARCHITECTURE.md` à jour ;
  - suite complète verte deux fois de suite, total de tests supérieur au départ.
- Commun : — | Serveur : —
- Protocole : —
- Client : —
- Tests : `test_matrix_net` (échantillon identique en `LocalBackend` et `NetBackend`)
- Parité : ☑ règles sourcées (sans objet) ☑ tests ☐ sim_cli (sans objet) ☐ capture (sans objet) ☑ doc

### [x] P1.18c Tests des sorts : cas multi-tours des classes 1, 2, 6, 7, 8, 9
- Dépend : P1.18b, H.03
- Données : `spells.json`, descriptions FR (`tools/i18n_lookup.py`)
- Règles : faites : 23 cas multi-tours dans `tests/spells/spell_cases.gd` (Féca 3, Osamodas 4, Ecaflip 4, Eniripsa 4, Iop 5, Cra 4), valeurs = dés des données, durées lues dans `duration` / `delay`. Le reste est dans P1.18d
- Commun : `FightEffects` | Serveur : — (aucune mécanique nouvelle : `test_matrix_net` rejoue déjà un sort par classe)
- Protocole : —
- Client : —
- Tests : `TEST_ONLY=test_spell_cases` vert ; `TEST_TIER=fast`
- Parité : ☑ règles sourcées ☑ tests ☐ sim_cli ☐ capture ☐ doc (sans objet : tests seuls)

### [x] H.04b Sorts des monstres hors Incarnam et Astrub
- Dépend : H.04
- Données : sorts des monstres de `dofus` (`monsters.json`)
- Règles : sans objet (chargement des données ; `SpellGaps` pour les écarts de contrat)
- Commun : `spells.py`, `SpellGaps`, `MonsterGaps` | Serveur : —
- Fait : `spells.py classes --world incarnam+astrub+dofus` charge les 2 449 grades de sorts des monstres de `dofus` entièrement simulés (2 851 référencés) ; les 244 grades encore `partial` hors Incarnam / Astrub restent hors des données. Matrice : 1 241 monstres passifs tombent à 145.
- Tests : `test_monster_matrix`, `test_spell_contracts`, `test_spell_coverage` verts
- Parité : ☑ règles sourcées ☑ tests ☐ sim_cli ☐ capture ☑ doc

### [x] P1.18d Tests des sorts : ménage, cas des classes 12, 14, 18 et écarts à trancher
- Dépend : P1.18c
- Données : `spells.json`, descriptions FR (`tools/i18n_lookup.py`)
- Règles :
  1. Cas multi-tours des classes 12, 14, 18 (Pandawa 5, Zobal 3, Ouginak 6, source par cas) ; Mots, Pavois et Balise Tactique tranchés dans le moteur (voir Découvertes P1.18d)
  2. Ménage : `SpellArena` accepte un `layout`, 11 anciens `Arena` en héritent (reste : P1.18e)
- Commun : `FightEffects` | Serveur : `test_matrix_net`
- Protocole : —
- Client : —
- Tests : `TEST_TIER=fast` vert
- Parité : ☑ règles sourcées ☑ tests ☑ sim_cli ☐ capture ☑ doc

### [x] H.04c Sorts des monstres : les 13 écarts de contrat
- Dépend : H.04b
- Données : les 13 grades de `SpellGaps` marqués `APPROX(H.04c)` (vol avec durée, reflet Drako, invocations case 327, Macro-Ondes, Noyade, Ossuaire)
- Règles : `*h` / `*m` / `*j`… = le lanceur est de ce type (`TargetMask`, APPROX) ; retrait de PA / PM esquivable : les jets ne portent que sur les points détenus (`FightBuffs.resource`, APPROX) ; contrats corrigés (vol durable = coup immédiat, reflet une fois par porteur, vol de PM dont la zone contient le lanceur, conditions « lanceur = monstre n »)
- Commun : `SpellGaps`, `TargetMask`, `FightBuffs` | Serveur : `test_matrix_net` (monstres 3153, 3670, 3392, 831)
- Tests : `SpellGaps` ne garde plus de ligne `APPROX(H.04c)` ; goldens des sorts et de la matrice régénérés
- Parité : ☑ règles sourcées ☑ tests ☐ sim_cli ☐ capture ☐ doc

## U — Interface : audit et refonte (docs/ui/)

### [x] U.01 Zone de jeu réservée : la map ne passe plus derrière l'UI
- Dépend : —
- Règles : comme Dofus, la map entière tient dans la zone libre, hors des bandes du HUD (barre de sorts, barre de combat et ses options, timeline) et des panneaux (chat, minimap, suivi de quêtes, défis). Aucune règle de transparence ou de contour d'un personnage caché par un décor n'existe dans le code décompilé (DOFUS_UI.md L5) : pas inventée.
- Client : `client/ui/game_area.gd` (`GameArea`, bandes + rectangles, zoom maximal sans chevauchement, position la plus proche du centre), `ClientSession._sync_area` / `_fit_camera`, `FightHud.reserved_top / reserved_bottom / banner_rect`, chat posé au-dessus de la bande basse.
- Tests : `test_game_area.gd` (5 tailles dont 1280x1024 et 1024x576 : la grille, coins compris, hors bandes et panneaux ; pas de signal sans mouvement).
- Parité : ☑ sans objet (client seul) ☑ tests ☑ capture ☑ doc

## Journal

| Date | Lot | Fait | Reste / suite |
|---|---|---|---|
| 2026-09-27 | A.01–A.04 | Acquis antérieurs : rendu, exploration, combat complet v1, personnage persistant | — |
| 2026-09-27 | P0.01 | `ROADMAP.md`, `tools/roadmap.py`, commande `/suite`, workflow dans `CLAUDE.md` | Prochain : P0.02 |
| 2026-09-27 | P0.02 | `Persistence` (documents et collections, `commit`), `Clock`/`SystemClock`, `DataFiles`, `LocalServer` (un `WorldSim` par monde, partageable), comptes sur les personnages, une session par personnage ; `CharacterStore` supprimé ; 5 tests dans `test_hosting.gd` ; 72 tests verts, `sim_cli` et capture OK | Prochain : P0.03 ou P0.04. Le multijoueur local (P3.01) est désormais possible avec `LocalServer` |
| 2026-09-27 | P0.03 | `extract.py --tables all` (204 tables, 205 Mo, incrémental, garde-fou disque), `catalog.py` → `docs/data_catalog.md`, `gamedata.py table` → `game/data/tables/` (breeds, namingrules, constants), `GameData.table/row` générique, `DataFiles` avec erreurs lisibles ; 75 tests verts | Prochain : P0.04 |
| 2026-09-27 | P0.04 | `Protocol.SCHEMA` (source unique), `validate`, `VERSION` 2 dans hello/welcome, `seq` sur les commandes (backend) et les événements (sim), `ref` sur les erreurs ; 29 codes `E_*` renvoyés par les règles à la place de textes ; `docs/PROTOCOL.md` généré (`tools/protocol_doc.gd`) ; `ErrorTexts` et `Toast` côté client ; 82 tests verts, capture du toast OK | Prochain : P0.05 (scénarios JSONL), qui s'appuie sur `seq` |
| 2026-09-27 | P0.05 | `Scenario` (`api/scenario.gd` : format JSONL, rejeu sur tout `GameBackend`, correspondance partielle et ordonnée, enregistrement), `ScenarioBot` (joue comme un client), `sim_cli --record/--scenario/--bot/--character`, 3 scénarios (`explore`, `fight_won`, `fight_lost`), `test_scenarios.gd` ; `docs/RULES_SOURCES.md` + `tools/rules_sources.py` (8 APPROX recensés, 38 formules officielles indexées) ; 86 tests verts | Prochain : P0.06 (kit d'UI) ou P1.07 |
| 2026-09-27 | P0.06 | Kit `client/ui/` : `UiStyle` (palette darkStone, thème global), `UiWindow` (déplaçable, Échap, position mémorisée), `UiTabs`, `ItemSlot`, `SpellButton`, `UiTooltips` (objet, sort, groupe), `UiBar`, `Toast`, `ContextMenu`, `Shortcuts`. `InventoryPanel` remplacé par `CharacteristicsWindow` (C) et `InventoryWindow` (I, onglets par catégorie) ; `FightResultWindow` et `PlayerHud` migrés ; infobulle et clic droit sur les groupes de monstres (la sim expose `members: [{name, name_id, level}]`) ; textures UI extraites (emplacements, icônes de menus et de caractéristiques) ; `itemtypes` dérivée ; 87 tests verts, 3 captures relues | Fondations P0 terminées. Prochain : P1.01 (connexion, choix du personnage) ou P1.07 (tout Incarnam) |
| 2026-09-27 | P1.01 | `GameSession` (sim : une connexion, choix du personnage puis jeu ; `LocalBackend` n'est plus qu'un transport), `CharacterRoster` (liste, création, suppression, sélection ; noms `namingrules` via `servercommunities.namingRulePlayerNameId`, uniques par monde sans la casse, 5 par compte, propriété par compte, anciennes sauvegardes sans compte adoptées), `NameRules` (shared), look par défaut = `breeds.maleLook/femaleLook` + premier visage `heads` + `breeds.*Colors`, `Character.breed/sex`. Protocole : `hello.name` optionnel, `list/create/delete/select_character`, `characters`, `character_created`, 7 codes d'erreur. Client : `CharacterSelectScreen` (cartes avec les vraies têtes de classe, aperçu animé sur socle, Jouer/Entrée, double-clic, création avec validation du nom en direct, suppression confirmée par `UiConfirm`). `ui.py classes` (têtes et symboles), tables `servercommunities`, `heads`. 96 tests verts, scénario `characters.jsonl`, 4 captures relues | Les scénarios existants passent le joueur de `cli` à `Cli` (règle de nom), sans autre changement. Retour au choix du personnage depuis le jeu : à faire avec le menu principal (P5.04). Écran de login réel : S.02. Prochain : P1.02 (création : toutes les classes, visages, couleurs) ou P1.07 |
| 2026-09-27 | P1.02 | `LookBuilder` (shared) : look = `breeds.maleLook/femaleLook` (os, échelle) + `bodies.skins` + `heads.skins` + `breeds.*Colors` remplaçables ; `check` (corps et visages de la classe et du sexe, `availableAtCreation`, non payants ; couleurs ≤ nombre de la classe, 0..0xFFFFFF). `create_character{name, breed, sex, body, head, colors}`, erreur `bad_look`, `characters.breeds` (classes créables, décidées par le jeu). `Character.body/head/colors` gardés pour un futur relooking. Client : `CharacterCreationScreen` plein écran (19 classes dans l'ordre Dofus avec symbole, description et rôles `breedroles`, sexe, corps et visages en vignettes réelles, 6 couleurs avec sélecteur, aperçu animé rotatif sur socle, nom validé en direct). `ui.py cosmetics`, tables `bodies`, `breedroles`. 99 tests verts, scénario `characters.jsonl` réenregistré (création avec choix), 4 captures relues (Pandawa, Pandawa féminine recolorée, Féca, Forgelance) | Les 18 autres classes s'affichent mais ne se créent qu'avec leurs sorts (P1.03 ouvre `PLAYABLE_BREEDS`). Les couleurs ne sont pas nommées (le client Dofus ne donne pas le nom des emplacements). Prochain : P1.03 (sorts de toutes les classes) |
| 2026-09-27 | P1.03 | `spells.py classes` : tous les grades des 836 sorts des 19 classes (1 729 grades, `spells.json` compact 1,7 Mo) + icônes + os de FX. Un sort lançable = un grade (id 1 000 000 + `spelllevels.id`, comme les monstres). `SpellBook` : paires `spellvariants` dans l'ordre `breeds.breedSpellsId`, `grade_for` (plus haut grade dont `minPlayerLevel` ≤ niveau), `known_ids(breed, level, variants)`, `bar_layout`. Commandes `choose_variant{spell}` (hors combat) et `move_spell{spell, slot}` (aussi en combat), erreurs `spell_locked`, `spell_not_simulated`, `bad_slot` ; `player_stats.spells` (grades) et `.bar` (40 cases). Toutes les classes sont créables (`CharacterRoster.playable_breeds()`). Client : `SpellBookWindow` (S : 22 paires, sorts verrouillés avec leur niveau, détail : description, grades, coûts, effets, « Utiliser ce sort »), `SpellBar` 2 × 10 hors combat et en combat, glisser-déposer (`SpellSlot`) ; `UiWindow` s'ajuste aussi quand son contenu rétrécit. 105 tests verts ; scénarios de combat réenregistrés **identiques** aux anciens hormis les ids de sorts ; nouveau scénario `spells.jsonl` ; 4 captures relues (grimoire Pandawa 120 avec variante, barre hors combat, barre en combat avec portée, grimoire Iop 60) | 473 grades 1 sur 836 ont des effets non simulés (`partial`) et 121 aucun effet simulé (refusés) : invocations (181), érosion, glyphes, pièges, porter… → P1.11–P1.14. Pas de sort commun hors `breedSpellsId` (le coup d'arme viendra avec l'équipement, P1.06). Prochain : P1.04 (caractéristiques) ou P1.05 |
| 2026-09-27 | P1.04 | `shared/StatFormulas`, source unique du personnage et du combattant : coût du capital par palier (`breeds.statsPointsFor*` : identique pour toutes les classes, 1 / 2 / 3 / 4 dès 0 / 100 / 200 / 300, Vitalité 1, Sagesse 3), PV, PA (7 dès 100), PM, initiative, prospection, pods (+ part des métiers `luaformulas 46`), tacle, fuite, esquive et retrait PA/PM ; `Fighter`, `FightEffects` (esquive PA/PM) et `FightRewards` (prospection) l'utilisent. `boost_stat{stat, points?}` (capital dépensé point par point, le reste gardé), `reset_stats`, `player_stats.derived` et `.bonus` (vide jusqu'à P1.06). Client : `CharacteristicsWindow` refaite sur les tables `characteristics` / `characteristiccategories` (onglets Primaires, Secondaires, Dommages, Résistances dans l'ordre Dofus, icônes réelles, Base / Bonus / Total, coût et paliers en infobulle, Maj+clic = 10 points, Réinitialiser avec confirmation). 109 tests verts ; tous les scénarios réenregistrés sont identiques (champs ajoutés seulement) ; nouveau `characteristics.jsonl` ; 2 captures relues | APPROX : formules d'initiative, tacle, fuite, esquive/retrait, prospection et pods de base (communautaires, absentes des données) ; restat gratuit hors combat (en Dofus, objet ou PNJ). Dommages et résistances à 0 tant que l'équipement n'existe pas (P1.06). Prochain : P1.05 (objets, partie 1) |
| 2026-09-27 | P1.05 | Objets instanciés `{uid, id, qty, effects}` (`sim/Inventory`, uids par `Persistence.next_uid`), jets à la création (`shared/ItemEffects.roll` : bonus de caractéristique `effects.useDice` + `bonusType` ≠ 0 tirés une fois avec le RNG seedé du monde ; coups d'arme et effets d'utilisation gardent leurs dés), piles d'objets identiques, pods portés et surcharge (`overloaded` : plus de déplacement ni de changement de map), `use_item` (110 soin, 600 rappel au point de sauvegarde, 606-611 parchemins de caractéristique additionnelle ; conditions `items.criterions` lues par `shared/Criteria`), `destroy_item`. Protocole : `inventory`, `item_added`, `item_removed` (l'inventaire sort de `player_stats`, qui gagne `additional`, `weight`, `max_weight`). Données : `items.json` avec effets / `usable` (bit 0 de `m_flags`) / conditions / description, `EXTRA_ITEMS` (pain, potions, rappel, parchemins, 2 équipements), table `effects`. Client : `InventoryWindow` (barre de pods rouge en surcharge, tri Type / Nom / Niveau / Poids / Quantité, double-clic = utiliser, clic droit Utiliser / Détruire avec confirmation), infobulle d'objet avec effets réels (modèles `effects.descriptionId`), description, conditions ; parchemins dans la colonne Bonus des caractéristiques. Anciennes sauvegardes converties (uids attribués à la connexion). 116 tests verts ; les 6 scénarios existants identiques hors nouveaux événements d'objets ; nouveau `items.jsonl` ; 2 captures relues (inventaire, infobulles) | APPROX : point de sauvegarde = départ du monde tant qu'il n'y a pas de zaap (P1.08). Effets non gérés : énergie (139, P1.10), apprentissage de sort (604), XP de métier (614), gains d'objets (193). Pas de source d'objets hors drops : les boutiques viendront avec P2.02 (outil `give` pour tester). Prochain : P1.06 (équipement) |
| 2026-09-27 | P1.06 | `shared/Equipment` : emplacements Dofus 0-15 (`itemtypes.superTypeId` → `itemsupertypes.possiblePositions`), bonus des objets (`effects.characteristic` signé par `bonusType`) et des panoplies (`itemsets.effects[n − 1]`), coup d'arme (sort propre au combattant `Fighter.own_spells`, id `WEAPON_SPELL` : `items.apCost`, portée, `criticalHitProbability`, `criticalHitBonus` ajouté aux dégâts en critique, `maxCastPerTurn`, zone `itemtypes.rawZone`), « Coup de poing » (`spells` 0, extrait avec les classes) sans arme. `shared/CriteriaEval` remplace `Criteria` : PL, PG, PS, C*/c* (dont PA/PM), PO, Ps/Pa, BI ; clés inconnues = refus (`unknown_keys`). `equip{uid, slot}` / `unequip{slot}` : niveau `items.level`, conditions, un seul exemplaire de chaque Dofus, l'objet déjà porté revient au sac, séparation / fusion des piles ; erreurs `item_level`, `already_equipped`, `item_worn` (objet porté indestructible). Bonus dans `Character.stat` → caractéristiques, PA/PM, PV, stats dérivées et combattant ; dégâts : + dommages élémentaires, − résistances fixes. Données : champs d'arme et `sets` dans `items.json`, tables `itemsupertypes`, `itemtypes.rawZone`. Client : `EquipmentWindow` (personnage animé au centre, pictogrammes Dofus des emplacements, 6 Dofus, panoplies portées et bonus actuel), glisser-déposer inventaire ↔ équipement, double-clic / clic droit « Équiper », infobulle de panoplie ; case d'arme dans la barre de combat. 121 tests verts ; 7 scénarios identiques ; nouveau `equipment.jsonl` ; 3 captures relues (équipement, fenêtre corrigée, arme en combat) | L'apparence des objets portés n'est pas dans les données du client : nouveau lot P1.06b. APPROX : pas deux fois le même objet de panoplie (anneaux). Non gérés : armes à deux mains / bouclier, dommages critiques (86/87), clés de conditions Qa/PJ/Pk… (refusées). Prochain : P1.07 (monde) |
| 2026-09-28 | P1.07 | Monde `incarnam` = les 50 maps extérieures d'Incarnam (`maps.py world --area 45` : voisins réels, `mapscrollactions` prioritaire, 44 Mo de contenu) + la Taverne et sa cave. Sorties par cellule : `cellsData.mapChangeData` (`MapData.map_change`, `SIDE_BITS`, `exit_dirs`, `can_exit`) ; 4 liens de voisins sans aucune cellule de passage (falaises) sont fermés. Arrivée : cellule miroir si elle ramène, sinon la plus proche qui ramène (`arrival_cell`). Portes : `MapData.triggers` depuis `worlds/incarnam/links.json`, commande `use_trigger{cell}` ; `WorldSim.teleport` (bords, portes, rappel). `map_enter` : `subarea`, `area`, `area_name_id`, `outdoor`, `map_change`, `triggers`. Client : étiquette « Zone - Sous-zone » + coordonnées, cellule de sortie / porte éclairée au survol, clic sur une porte puis `use_trigger` à l'arrivée, fondu au noir ; outils `goto`, `grid`, `mark`, `trigger` (client_shot), `use_trigger` (sim_cli). 127 tests verts (nouveau `test_world.gd` : tout Incarnam parcouru depuis le départ sans cul-de-sac et retour possible, bits de sortie, voisin fermé, porte → Taverne → cave → dehors) ; 8 scénarios identiques ; nouveau `world.jsonl` ; captures relues (porte, fondu, Taverne, Cimetière avec la grille) | Les autres intérieurs (Mine, Crypte, maisons, Temple Céleste) : nouveau lot P1.07b. APPROX : cellules des portes. Prochain : P1.08 (carte, zaaps : le zaap d'Incarnam est sur la map 153880064, Cimetière) |
| 2026-09-28 | P1.08 | Zaaps : les 3 d'Incarnam (`waypoints` : Cimetière 153880064, Route des âmes 154010371, Pâturages 153879813 ; cellules dans `links.json`), `MapData.zaap` / `world_map` / `use_cells` (interactif utilisé depuis une cellule voisine). Enregistrement à l'entrée sur la map (`Character.known_zaaps`, `zaap_known`), `use_zaap` → `zaap_list{zaap, destinations, save_map}`, `zaap_travel{map}` payant (`shared/Travel.zaap_cost` : 10 × distance entière, ÷ 4 depuis Incarnam, wiki Dofus), `set_save_point` ; `WorldSim.save_point` pour la potion de rappel et la défaite (au lieu du départ du monde) ; erreurs `not_at_zaap`, `unknown_zaap`, `not_enough_kamas`. Carte du monde : tuiles réelles extraites (`maps.py worldmap 2`, catalogue Addressables binaire décodé, 1,7 Mo), table `worldmaps` ; `WorldMapView` (tuiles, map du joueur, zaaps connus, point de sauvegarde, molette, glisser), `WorldMapWindow` (M), minimap en haut à droite (clic = carte). `ZaapWindow` (destinations triées, prix, Voyager, Sauvegarder), clic sur le zaap = marcher à côté puis l'utiliser. Outils : client_shot `zaap`, `travel`, `worldmap`, `kamas` ; sim_cli `use_zaap`, `zaap_travel`, `set_save_point`. 132 tests verts (nouveau `test_travel.gd` : prix, 3 zaaps présents, enregistrement unique, liste et voyage payant, refus, point de sauvegarde → rappel et défaite) ; 9 scénarios identiques ; nouveau `zaap.jsonl` ; captures relues (fenêtre de zaap, carte du monde, minimap) | Zaapis : aucun dans Incarnam, reportés à P4.07 (Astrub). APPROX : prix (règle communautaire Dofus 2), enregistrement à l'entrée sur la map, cellules des zaaps. Prochain : P1.09 (monstres par sous-zone) ou P1.07b |
| 2026-09-28 | P1.09 | Groupes composés par la sim : `MonsterSpawner` lit `worlds/<id>/monsters.json` (extracteur `world_monsters` : monstres de chaque sous-zone, 5 grades, agressivité ; boss et mini-boss exclus, `monsters.m_flags` bits 2/3), 2 à 3 groupes par map de 1 à 4 monstres, nouvelle composition au respawn ; aucun groupe sans `ALLOW_MONSTER_RESPAWN` (`MapData.monster_spawn`, `mapsinformation.m_flags` bit 13 : maps de zaap, Taverne). Étoiles : `SubareaBonus` par sous-zone (−50 % à +100 %, Dofus 2.51, pas d'étoiles dans Incarnam/Astrub), horloge réelle, sauvegardé dans `Persistence` (`worlds`), = `Fight.reward_rate` (`luaformulas` 99 rewardRate) sur l'XP et les drops. Agression (devblog 2.45) : vision du chef, 3 s, écart de niveau > `aggressiveLevelDiff`, immunité, capacité `ALLOW_MONSTER_AGRESSION` (bit 20), priorité au premier vu puis au plus faible ; `group_alert{group, target}` ; `WorldSim._start_fight`. `shared/FightXp` (`luaformulas` 2, 99, 100) partagé par `FightRewards` et l'infobulle (XP estimée, étoiles `star0`/`star1`, « ! » d'alerte). Outils client_shot `stars`, `aggro`. 138 tests verts (nouveau `test_spawn.gd` : composition de toutes les maps d'Incarnam, respawn recomposé, étoiles, rewardRate, agression et ses 5 refus) ; `fight_won` / `fight_lost` réenregistrés (changement de règle voulu : groupes composés par la sim ; XP identique au rejeu avant le changement) ; autres scénarios identiques ; 3 captures relues (infobulle Incarnam, étoiles monde test, alerte puis combat) | APPROX : nombre/taille/grades des groupes, vitesse des étoiles (sources divergentes : 20 %/h retenu, 2 %/h ailleurs), `aggressiveAttackDelay` inutilisé. Incarnam n'a ni étoiles ni monstre agressif possible (niveaux 1-11, écart 50). Prochain : P1.07b ou P1.10 |
| 2026-09-28 | P1.10 | Énergie et mort : `sim/energy.gd` (`Energy`), `Character.energy` / `life` / `rest_x2`. Règles du tutoriel du client Dofus 3 (`notifications` 12-14) : une défaite coûte de l'énergie et renvoie au point de sauvegarde, à 0 le personnage devient fantôme (`GameRolePlayPlayerLifeStatus` 2, pas de tombe en Dofus 3 : déclencheur « 0:2 »), un fantôme rejoint un phénix (`use_phoenix`, `MapData.phoenix`), l'énergie revient avec les consommables (effet 139, `E_ENERGY_FULL` = i18n 4691) et hors ligne, deux fois plus vite en taverne/maison/temple (`MapData.tavern` = bit 9 `ALLOW_TAVERN_REGEN`, seule la Taverne dans Incarnam ; `saved_at`). Montants (Dofus wiki, lus via résultats de recherche) : 10 000 max, 10 par niveau à la défaite, 1 000 au phénix, 1 point/minute hors ligne. Nouveau message `info{code, args}` (textes Dofus : i18n 5231, 4704, 4840, 5384, notification 14) ; `player_stats` : `energy`, `max_energy`, `life`, `phoenixes` ; `actor.life` ; récompense `energy`, `energy_lost`. Fantôme : marche seulement, pas de combat / zaap / objet, jamais agressé. Client : jauge d'énergie (caractéristique 29), fantôme translucide, « Fantôme » dans le HUD, cases du phénix éclairées et cliquables, phénix sur la carte du monde, « -N énergie » en fin de combat. Données : `links.json` `phoenixes`, `maps.py` (`tavern`, `phoenix`, `world.json phoenixes`), Michette (521) dans `EXTRA_ITEMS`. Outils client_shot `energy:<n>`, `phoenix`. 144 tests verts (nouveau `test_energy.gd` : perte 10/niveau, fantôme à 0, interdits, phénix, récupération hors ligne x2 en taverne, pas pour un fantôme, Michette) ; `fight_lost` réenregistré (seules différences : `energy`/`energy_lost` et `info energy_lost`) ; autres scénarios identiques ; 5 captures relues (fantôme, phénix, résurrection, jauge, carte, défaite) | APPROX : position du phénix d'Incarnam (Cimetière (4,-1), aucune source : ni client ni JondoEmu), seuil « énergie basse » 2 000, perte plafonnée au niveau 200, interdits du fantôme, fantôme qui marche. Source de données serveur trouvée : JondoEmu (`Documents/Dofus3+/datos`) débloque P1.06b. Prochain : P1.06b |
| 2026-09-28 | P1.06b | Apparence des objets portés : source = `equipment_skins.json` de JondoEmu (`Documents/Dofus3+/datos`, `gamedata.py` `JONDO_DATOS`) : `items.json` gagne `skin` et `skin_src` (« measured » : 286 relevés sur captures ; « inferred » : 455 par comparaison d'images ; les 82 `_inferred_needs_review` écartés). `LookBuilder.with_equipment` / `worn_skins` (skins ajoutés après corps et visage, ordre des emplacements ; le moteur masque les parties couvertes via `skinslotsrules`), `Character.display_look()` (acteur, combattant, `player_stats.look`, `worn_look` sauvegardé pour la liste des personnages), `actor_look{id, looks}` diffusé à la map (`WorldSim._refresh_look`), `ActorView.set_look`. Nouveaux objets : Chapeau / Cape / Bouclier de l'intrépide (niveau 1, skins 460-462 mesurés). Outil `tools/make_character.gd` (personnage de test dans la sauvegarde locale : « Testeur » niveau 200 avec les 42 objets créé à la demande de l'utilisateur). 147 tests verts (3 nouveaux dans `test_equipment.gd` : skins, diffusion à un autre joueur, anneau sans effet, retrait, combattant, liste des personnages) ; nouveau `look.jsonl` ; 10 scénarios identiques ; 2 captures relues (fenêtre d'équipement, personnage sur la map avec coiffe, cape, bouclier) | Familiers (`pets`, sous-entité `1@0=`) et montures (`mounts`) de la même source : P2.13 / P2.14. Objets d'apparat (`appearances`) : plus tard. Cape et chapeau de l'Aventurier : skins « inferred ». Prochain : P1.07b (portes de JondoEmu : `interactive_teleports_*`, `casas_mundo_*`) |
| 2026-09-28 | P1.07b | Intérieurs d'Incarnam : 24 intérieurs (maisons des Champs, du Lac, de la Forêt, des Pâturages, de la Route des âmes ; la Mine en 7 salles ; Taverne et cave) reliés par 49 portes ; le monde passe de 55 à 74 maps. Cellule d'une porte = élément interactif de la map du client (`m_interactionId` + `cellId`, dans `references`) ; destination = dumps JondoEmu (`tools/extractor/jondo.py` : 39 lignes Giny 2.68 rattachées à l'élément, 7 du graphe du monde 2.73, 3 lignes Giny ambiguës résolues par la porte retour ; portes à condition de quête et arrivées « centre de map » écartées). `maps.py world_doors` vérifie chaque élément sur sa cellule, ajoute les intérieurs de la zone et écarte ceux sans sortie ; `links.json` ne garde que zaaps et phénix. Une porte s'utilise depuis sa cellule ou une voisine (`use_cells`, comme le zaap) : `WorldSim._on_use_trigger`, `MapData.door_near` (clic sur la porte ou une cellule bloquée qu'elle couvre), le client marche à côté puis envoie `use_trigger`. Les cellules relevées à la main en P1.07 sont remplacées (Taverne : JondoEmu donne 411 = sortie et 387 = cave, là où P1.07 avait 411 = cave). Outils : client_shot `door:<cell>`. 148 tests verts (`test_world.gd` : tout Incarnam avec ses intérieurs sans cul-de-sac, porte trop loin refusée, salles de la Mine) ; nouveau `doors.jsonl` ; 11 scénarios identiques ; capture relue (entrée de la Mine depuis les Pâturages → Mine avec ses Champignons) | Écartés : Crypte de Kardorim (porte du Cimetière sous condition de quête, salles non reliées dans les dumps : P2.03 / P4.01), Temple Céleste (446), Tutoriel (536), Queue du Dragon (815, quête), maison du Cimetière 153356288 (arrivée « centre de map », pas de sortie connue). Prochain : P1.11 (invocations) ou P2.01 (PNJ, avec `npcs_reales.json`) |
| 2026-09-28 | P1.11 | Invocations : `spells.py` convertit les effets 181 / 1011 / 1008 (`summon`), 180 (`double`), 405 / 2796 (`replace`, cible `F<monstre>`) et écrit `spells.json` `summons` (80 monstres : grades, `bonusCharacteristics`, look résolu, `monsters.m_flags` bits 0 emplacement / 1 bombe / 6 joue / 7 tacle ; leurs sorts ajoutés). `sim/fight/Summons` : PV = grade + bonus × (niveau de l'invocateur + 10) / 20 (mesure JondoEmu `Summons.cs` sur 18 invocations réelles), limite `BASE_SUMMONS` + caractéristique 26 (`summon_limit`), ids négatifs. `Fight` : `add_summon` (joue juste après son invocateur et ses invocations plus anciennes ; celles qui ne jouent pas, Arbre, bombes, hors de l'ordre), `handle_deaths` (mort en chaîne), `_check_end` sans les invocations ; `FightRewards` les ignore ; `FightAI` les joue et sait invoquer ; tacle selon `tackles`. Effet `summon{summoner, fighter, order}` ; le client ajoute le combattant (fondu) et reconstruit la timeline. Bug corrigé au passage : `spells.py world_monster_spells` lisait encore les groupes des maps (supprimés en P1.09) : les monstres d'Incarnam n'avaient que 5 de leurs 36 sorts, ils en ont 30 (les 6 autres ne font que se buffer). Os, skins et portraits des invocations extraits par `spells.py` (68/69 os). Outils : client_shot `summon:<sort>`, `ScenarioBot` invoque une fois par combat. Capture relue : le Tofu invoqué à côté du joueur, son portrait dans la timeline juste après lui, « Tour de Tofu ». 156 tests verts (nouveau `test_summons.gd` : sorts extraits, ordre de jeu, PV, limite et +1, Arbre sans tour ni emplacement, mort en chaîne et défaite, La Folle remplace l'Arbre, Double, pas de gains) ; nouveau `summons.jsonl` ; 12 scénarios identiques | APPROX : les autres bonus suivent l'échelle des PV, niveau de l'invocation = celui de l'invocateur, 1011 et 1008 traités comme 181, Double sans sorts, poids de l'invocation dans l'IA. Non simulés : sort de départ des invocations (`startingSpellId` : auras, déclencheurs 792 → P1.13), explosions et murs des bombes (P1.13), invocations contrôlées, durée de vie limitée (balises), `delay` des effets. Prochain : P1.12 (porter et lancer) |
| 2026-09-28 | P1.12 | Porter et lancer : `spells.py` convertit 50 (`carry`, avec les états 3 « Porteur » / 8 « Porté » et leurs drapeaux), 51 (`throw`), garde les variantes K (`carried`) au lieu de les jeter, `carry_range` (effet 281 de Karcham / Chamrak sur eux-mêmes), drapeau `cant_switch` (`cantSwitchPosition`) ; les sorts Pandawa Karcham, Chamrak, Brancard, Pandikulation, Propulsion, Eau-de-vie, Cascade ne sont plus `partial`. `sim/fight/Carry` (porter, lancer, suivre, séparer), `Fighter.carrying` / `carried_by` / `cast_forbidden`, `FightRules.for_caster` / `needs_state` / `CARRIER_STATE`, `Fight.fighter_at` sans les portés, `handle_deaths` libère la paire, `move` d'un porté le fait descendre (`fighter_move.effects`). L'échange de place respecte `cant_switch`. Buffs d'état : `flags` dans le dict. Client : sous-entité `LIFTED_ENTITY` dans le look du porteur, `AnimPickup` / `AnimThrow` / `AnimDrop` / `*Carrying` réelles, vol en arc du lancé, barre grisée par l'état Porteur. Outils : client_shot `carry:` / `throw:`, `ScenarioBot` lance ce qu'il porte. 165 tests verts (nouveau `test_carry.gd`, 9 tests) ; `fight_won.jsonl` réenregistré (changement de règle voulu : Karcham posait l'état Porteur sur la cible, il porte maintenant le Tofu puis le lance ; toujours une victoire) ; 12 autres scénarios identiques ; captures relues (le Tofu sur la tête du Pandawa, barre réduite à Karcham ; le Tofu lancé à 4 cases) | APPROX : un porté qui marche descend de son porteur ; un porté n'est ni ciblé ni touché par les zones (sorts sur la cellule = le porteur) ; Karcham / Chamrak en portant visent une cellule libre malgré leur drapeau « cellule occupée ». Zones `l` (Brancard, Cascade) encore lues comme un point. Prochain : P1.13 (glyphes, pièges, déclencheurs) |
| 2026-09-28 | P1.13a | P1.13 découpé en 4 (a : pièges et glyphes, b : déclencheurs et sous-sorts, c : invisibilité, d : runes, portails, bombes). Pièges et glyphes : `spells.py` convertit 400 (`trap`), 401 (`glyph_start`), 402 (`glyph_end`) avec leur sous-sort (`diceNum` / `diceSide` → grade lançable, ajouté à `spells.json` : 57 sous-sorts), leur couleur (`value` RGB), leurs cellules (`mark`), et 2018 (`unmark`) ; zone `*` = étoile. Correction au passage : les filtres du masque (`E<n>`, `F<n>`…) comptaient comme des lettres de camp, ces effets tombaient en « tous ». `sim/fight/FightMarks` : piège déclenché en entrant (la marche et les poussées s'arrêtent dessus, sort lancé par le poseur depuis le centre, puis retiré), glyphes de début / fin de tour (le sort ne frappe que le combattant concerné : `apply_spell(only)`), durée sur les tours du poseur, retirés à sa mort. `fighter_move.triggered` (effets à l'arrivée), les effets de fin de tour partent avec le `fight_turn` suivant. Une attraction en zone tire vers le centre de la zone (« attire vers son centre »), vers le lanceur pour un sort sur la cible. Client : cellules des marques dans leur couleur réelle, pièges ennemis non dessinés. Outils : client_shot `lay:<sort>`, `ScenarioBot` pose un piège par combat. Les 13 pièges Sram n'ont plus rien de `partial`. 173 tests verts (nouveau `test_marks.gd`) ; nouveau `traps.jsonl` (un Sram niveau 15 piège un monstre qui s'arrête dessus) ; 13 autres scénarios identiques ; captures relues (piège Sournois rouge, glyphe de Défiance bleu nuit) | APPROX : forme de l'étoile (`*`), pièges envoyés à tous les clients (filtrage par destinataire en P1.13c). Non faits : glyphes-auras 1091 et glyphe 1165 (P1.13b), la Lanterne et les sous-sorts 1160 des glyphes Eliotrope restent `partial`. Prochain : P1.13b |
| 2026-09-28 | P1.13b | Déclencheurs : `spells.py` garde `triggers` (`on`, sans « I » ; `now` s'il y est aussi) et `effectTriggerDuration` (`turns`, 63 = tout le combat) ; codes simulés TB, TE, DBE (mesurés par JondoEmu), D, DA/DE/DF/DW/DN, DBA, DM, DR, H, X (APPROX), un code inconnu rend le sort `partial`. `sim/fight/FightTriggers` : buff « trigger » posé sur la cible, déclenché par le lanceur du buff sur son porteur ; les coups attendent dans `Fight.hits` jusqu'à `flush` (les effets sortent après le coup) ; un déclencheur ne se relance pas lui-même, chaînes limitées à 4. 1163 / 1159 multiplient les dommages subis / soins reçus après la formule (JondoEmu). Sous-sorts : 8 effets de la famille « lance un sort » (JondoEmu : diceNum = sort, diceSide = grade) → `cast`, 1 632 sous-sorts ajoutés à `spells.json` (4,1 Mo) ; 792 lancé par la cible (APPROX : Échange du Double tue son lanceur). Retardement : `delay` n'était pas lu (le Double se tuait aussitôt, l'Arbre poussait tout de suite) → buff « delay » qui applique l'effet quand il expire. Aussi : glyphe-aura 1091 (`FightMarks.auras`, buffs marqués `aura`, retirés à la sortie ou à la fin de la marque), sort de départ des invocations (`startingSpellId` : le Tofu ne tacle pas et n'est pas taclé), 1109 soin en % des PV max, 141 tue, 406 retire les buffs d'un sort, `maxStack`, formes `a` (toute la carte), `+`, `#` (mesurées par JondoEmu). `partial` compte aussi les sous-sorts : 894 grades de classe sur 1 730 (759 avant, sans les sous-sorts). Scénarios : `fight_turn.effects` et `fighter_move.triggered` sont maintenant enregistrés ; `summons.jsonl` réenregistré (sort de départ du Tofu), `traps.jsonl` réenregistré (déclenchement du piège figé), nouveau `triggers.jsonl` (Arsenic, poison TB) ; le bot lance d'abord un sort à effet déclenché. Client : textes des buffs `trigger` / `delay`, client_shot `tip`. 182 tests verts (nouveau `test_triggers.gd`) ; captures relues (Brume : cases vertes et « -3 PO » ; Arsenic : « Effet déclenché en début de tour (2 tours) ») | APPROX : codes D, DA…, DBA, DM, DR, H, X ; 792 par la cible ; multiplicateurs multipliés entre eux ; retardement au début du tour du lanceur ; pas de re-déclenchement. Non faits (nouveau lot P1.13e) : codes EON / EOFF / DIS / PD / CC…, lettres de masque P / h / U…, renvoi de sort, 786, 765, 1061, 1165. Prochain : P1.13c |
| 2026-09-28 | P1.13c | Invisibilité : `spells.py` convertit 150 en état 250 « Invisible » avec le drapeau `invisible` (APPROX : lien fait par les noms), 202 en `reveal`. `sim/fight/FightVisibility` : chaque joueur reçoit la vue de son équipe (`WorldSim._fight_emit`) : l'autre équipe reçoit les marches d'un invisible sans chemin, ses dicts de combattant avec `cell` -1, ses déplacements de sort sans chemin, et `spell_cast.from` quand il lance un sort (APPROX) ; les pièges cachés ne lui sont plus envoyés (fin de l'APPROX de P1.13a). La fin d'une invisibilité (202, fin de l'état) envoie à tous `reveal {cell}`. `FightAI` ne vise pas et ne suit pas un ennemi invisible (APPROX : il ne devine pas). Brume rend aussi ses alliés invisibles (son aura). Client : translucide pour son équipe, caché pour l'autre, « ? » à la case d'où il lance ; client_shot `self:<sort>`. Bot : se rend invisible une fois par combat. 189 tests verts (nouveau `test_visibility.gd`) ; nouveau `invisible.jsonl` (les monstres ne font rien pendant le tour d'invisibilité, `reveal` ensuite) ; captures relues (Sram translucide, Tofu ennemi disparu) | APPROX : 150 ↔ état 250, `from`, IA qui ne devine pas. Une case visée qui contient un invisible donne encore `need_taken_cell` à l'autre équipe (la vérification se fait côté sim). Prochain : P1.13d |
| 2026-09-28 | P1.13d | Runes et bombes (portails sortis dans le nouveau lot P1.13f). `spells.py` : 2022 → marque `rune`, 2023 → `runes`, 1009 → `detonate` ; les bombes ont `explode` / `chain` / `instant` (table `spellbombs`, par grade) et `wall` (`spellbombwalls`) ; masques `F` / `f` → conditions de monstre (mesurées par JondoEmu), `p` / `P` → joueur / non-joueur (APPROX, lu sur les masques des bombes) ; 1171 / 1172 dommages finaux, 2971 soins finaux, 1027 dommages combo, 753 tacle, 754 fuite, 1040 bouclier fixe, 320 vol de PO ; 1060 (taille) et 149 (apparence) ignorés. `FightMarks` : runes déclenchées seulement par 2023 sur la cible (une par case, APPROX), murs entre bombes alignées du même type et du même lanceur (déclenchés comme un glyphe de début de tour ou à l'arrivée, APPROX). `Summons.detonate` : réaction en chaîne puis explosion (qui tue la bombe) ; une bombe déjà morte (Poudre, X) lance l'instantané ; une fois par bombe ; un lanceur qui explose finit son sort même mort. Corrigés en route : les monstres des groupes n'avaient pas leur id de monstre (`Fighter.monster`), les conditions sur la cible étaient lues pendant le sort (le Combo montait de 9 niveaux d'un coup) → instantané au lancer comme pour le lanceur ; `maxStack` s'applique aussi aux buffs de caractéristique (par sort). Partiels : 801 grades de classe (873 avant). Bot : pose ses bombes près de l'ennemi et les fait exploser. 202 tests verts (nouveau `test_bombs.gd`) ; nouveau `bombs.jsonl` (deux bombes, explosions, victoire au premier tour) ; `invisible`, `traps`, `triggers` réenregistrés (Truanderie plafonnée par son maxStack 2) ; captures relues (mur rouge entre deux bombes, double « Boum ! » ; rune rouge sous le monstre puis Runification) | APPROX : p / P, une rune par case, murs (paires du même type, déclenchement), rôle des sorts chainReaction / instant, combo compté comme dommages finaux, dommages finaux après les résistances, maxStack par sort et caractéristique. Les explosions sont trop fortes (bonus des invocations, nouveau lot P1.11b). Godot plante (segfault) en quittant client_shot, déjà avant ce lot, sans effet sur les captures. Prochain : P1.13f |
| 2026-09-28 | P1.13f | Portails Eliotrope. `spells.py` : 1181 → `portal` {spell = Téléportail (diceSide est un spelllevels.id, `sub_level`), bonus = value, per_cell = diceNum}, 1182 → `teleportal`, 1183 → `unportal` (forme A → `all`), masques `R` / `r` → cond `{portal}`, déclencheurs `PT` / `CPT`, `start_states` 3737 / 3738 sur les grades de Portail / Errance (`VARIANT_STATES`, lu par `WorldSim`). `FightMarks` : portails (un par case et par lanceur, 4 au plus), réseau au plus proche, traversée (marche qui s'arrête dessus, ou 1182 : Exil, Résonance), projection (`Fight.cast` : le sort atterrit sur la sortie, `Fighter.projecting` pour les conditions R / r et le bonus, `Fight.cast_from` pour les zones et poussées), désactivation jusqu'au tour du lanceur, ennemis bloqués en marchant au tour 1 (`Fight.fight_round`). Client : marques au-dessus des cases de portée (elles étaient cachées pendant son tour), infobulles des conditions `player` / `portal` (plantaient sur `has`). Bot : Portail, Exil sur l'ennemi puis attaque projetée. Partiels : 782 grades de classe (801 avant). 214 tests verts (nouveau `test_portals.gd`) ; nouveau `portals.jsonl` ; captures relues (deux portails, le monstre sorti par le Portail ; Affront projeté « Portail +4 % », le monstre meurt) | APPROX : parcours au plus proche (égalité : plus petite case), réseau par lanceur, 4 portails, traversée seulement en marchant ou par 1182, sortie occupée = pas de traversée, projection seulement sur ses portails et pas sur sa case, bonus appliqué en dernier, R / r et PT / CPT lus sur les textes, états Portail / Errance donnés par la variante, Exil fait traverser même au tour 1, zone A = tous les portails. Non fait : 290 (Transcendance), XD (Résonance), le remboursement de PA de Neutral (120 ignoré). Prochain : P1.11b |
| 2026-09-28 | P1.11b | Caractéristiques des invocations. Hypothèse du lot fausse : `monsters.characRatios` existe pour les 4 976 monstres et va dans les formules officielles de mise à l'échelle (`characteristics.scaleFormulaId` : PV et vitalité → luaformulas 4, forces / sagesse / puissance → 5, PM → 3, portée → 12) ; appliquée aux balises Ocra mesurées par JondoEmu (1 050 PV), la formule 4 donne 2 200 000 PV : ce n'est pas la règle des invocations. `bonusCharacteristics` hors PV ne prend que 50 / 75 / 100, dans l'élément de l'invocation (Tofu : agilité + dommages Air ; Bouftou : force + dommages Terre ; palier 1 / 2 / 3 de l'Osamodas), 100 partout pour les bombes, tourelles, fées : lu comme la part (%) des caractéristiques de l'invocateur (`Summons.create`, APPROX). Les PV gardent la mesure JondoEmu. Effet : une Explobombe d'un Roublard niveau 10 sans équipement fait environ 10 dommages (24 avant, et +1 050 dommages Feu à 200). 219 tests verts (2 nouveaux dans `test_summons.gd`, un ancien corrigé) ; `bombs.jsonl` réenregistré (changement voulu : le Roublard niveau 10 perd désormais) ; capture relue (explosions -10 / -9). Une autre session a ajouté en parallèle la commande GM `admin_cmd` (tests de protocole un moment rouges, verts à la fin) | APPROX : bonus = % des caractéristiques de l'invocateur (prises à l'arrivée, sans suivre ses buffs ensuite). Non utilisé : la mise à l'échelle des monstres (`characRatios`, luaformulas 3 / 4 / 5 / 12) : pour les monstres dont le niveau change (à rattacher au lot qui en aura besoin). Prochain : P1.13e |
| 2026-09-28 | S.06 (partiel), P4.07 | Monde complet et tp GM. `maps.py full dofus` : les 17 353 maps du client en un monde (visuels, maps de la sim, portes JondoEmu, monstres des 531 sous-zones, ~1 h, reprenable par bundle via `_build.jsonl`), `maps.py coords` → `coords.json`. Protocole `admin_cmd{cmd, args}` (rôle GM : `PlayerActor.gm`, donné par l'hôte, `LocalBackend.gm` en standalone), erreurs `not_gm` et `unknown_map` ; `tp` par id ou par coordonnées (monde de la map actuelle, puis Amakna ; map prioritaire, extérieure, plus petit id). Client : `CommandLine` (Entrée, historique). Le client démarre sur `dofus` (personnages copiés depuis `incarnam`). 3 tests dans `test_world.gd` ; 219 tests verts ; captures Astrub (4,-19) et combat au Coin des Bouftous (5,10) | S.06 : autres commandes (give, kick…), console serveur. P4.07 : cellules des zaaps hors Incarnam (`links.json`), phénix, PNJ ; 24 props animés absents du client |
| 2026-09-28 | P1.13e | Source nouvelle : les assemblys que Cpp2IL (MelonLoader) laisse dans l'installation gardent les enums du client : `tools/client_enums/client_enums.cs` → `docs/client_enums.md` (`Metadata.Effect.ActionId` : nom de chaque effet ; `Metadata.Enums.SpellZoneShape` : nom de chaque lettre de zone ; les 98 codes de déclencheurs connus du client, sans leur sens). Formes (`FightRules.zone`, `spells.py SHAPES`) : `A` WholeMapWithTheDead, `l` LineFromCaster (param2 = longueur), `V` Cone, `U` HalfCircle, `F` Fork, `-` / `/` lignes diagonales, `W`, `I` ajoutées ; `+` / `#` corrigées (croix diagonale, avec ou sans centre, lues étoile / carré avant) ; `T` reste PerpendicularLine (JondoEmu la disait croix). Effets : 786 `heal_attackers`, 765 `intercept` (l'intercepteur = le combattant sur la case ciblée, sinon le lanceur : Sac Animé, tourelle de Brise l'Âme, Sacrieur), 1061 `share`, 1165 `glyph_now` (FightAddGlyphCastingSpellImmediate) ; `FightEffects.damage` renvoie tous les coups ; `CCMPARR` une fois par PM utilisé en marchant. Sac Animé : son 141 retardé sur `C` tue le Sac, pas l'Enutrof. `ScenarioBot` : `--bot=fight:<spells.id>`. 13 sorts de classe deviennent lançables (Agitation, Supplice, Sac Animé, Musette Animée, Poursuite…), partiels : 760 grades (782 avant). 233 tests verts (nouveaux `test_zones.gd`, `test_redirects.gd`) ; nouveau `intercept.jsonl` ; capture relue (le Sac Animé prend les coups des Tofus, le personnage reste à 34 PV) | APPROX : géométrie des formes nommées (cône, demi-cercle, fourche, diagonales), intercepteur, dommages interceptés non re-réduits, partage égal, glyphe immédiat sans effet ensuite, CCMPARR seulement en marchant, Sac Animé. Non fait (P1.13g) : les autres codes et lettres, formes `D` `B` `R` `Z` `N` `;`, renvoi de sort. Prochain : P1.13g |
| 2026-09-29 | P1.13g | Lot recentré sur les formes de zone (masques → P1.13h, déclencheurs et renvoi de sort → P1.13i, baisse des dommages en zone → P1.13j, nouveaux lots). Source nouvelle : le **code natif du client**. Les assemblys Cpp2IL gardent l'adresse de chaque méthode (`[Address(RVA)]`), Ghidra (déjà installé dans `C:/dofus3_reversing`) décompile `GameAssembly.dll` sans analyse complète : `tools/client_code/client_code.py` (`names`, `import`, `find`, `xref`, `decomp`, projet hors dépôt). Lu : la fabrique `gru.blgy` (lettre → classe `SpellZoneShape*Behavior`), les 14 classes, la direction `og.ovk` (8 directions exactes, sinon -1) et les coordonnées `oh.owg` / `owh`. `FightRules.zone` réécrite pas à pas sur le client (`dir8`, `_step8`, `_rot`), plus d'APPROX de géométrie. Corrigé : `param2` = minimum des cercles, croix, lignes (`C2` `param2` 1 : plus de 450 effets de classe sans centre), les bras diagonaux de `+` comptent leurs pas, `G` au moins 3 × 3, `W` sans centre, fourche à dents de `param1 + 1`, `l` limitée à `param2` cases et arrêtée sur la cible seulement si `isStopAtTarget`, direction aucune si non aligné (ligne, cône : la case ciblée seule ; `T` : direction 1). Nouvelles formes `D` damier, `B` boomerang, `R` rectangle (`length`), `Z` hors cercle euclidien. `spells.py` : `min` / `length` / `stop` ; `Equipment.zone` : `param2` seulement avec 4 nombres. `sim_cli --rerecord` (mêmes commandes, nouvelles attentes) ; `client_shot aim:<sort>:<dx>:<dy>` (aperçu de zone). 240 tests verts (`test_zones.gd` : 13 tests, 8 nouveaux) ; nouveau `zones.jsonl` (Steamer niveau 45, Foène touche un monstre à 2 cases sur la dent, victoire) ; `traps.jsonl` réenregistré (changement voulu : ordre des cases de la croix du piège, donc des tirages : 13 → 12 dommages) ; capture relue (aperçu de Foène : 7 cases en fourche) | APPROX : aucune de géométrie. Non fait : `forcedDirection`, `onlyAffectIfInSightLine`, `includeCarried`, les cases que le client exclut via son fournisseur de combat (`grw.blhz`), `;` (cellIds, monstres), la baisse des dommages en zone (P1.13j). Prochain : P1.13h |
| 2026-09-29 | P1.13h | Filtre des masques trouvé dans le code natif : lettres en constantes de la classe `gty`, vérification dans `gtz` (`blqi` = camp `blqf` et aucune condition en échec `blqh` → `blqe` par jeton, `blqc` = lettres de condition, `blqd` = `B` / `F` / `Z` au choix). Les chaînes du client sont chiffrées : `client_code.py strings` retrouve le tableau d'octets dans `global-metadata.dat` (octet i ^ i ^ 0xAA, 28 218 littéraux) et `decomp` les écrit en clair ; `methods.cs` montre les offsets des champs et les constantes caractère ou chaîne courtes (`chars <n>`). Sim : `TargetMask` (`sim/fight/target_mask.gd`), `FightEffects` l'utilise quand l'effet a son `mask` (brut, ajouté par `spells.py`) ; `target` n'est plus qu'un résumé ; `p` / `P` quittent `cond` ; `Fighter.breed`. Changements voulus : `g` ne touche plus le lanceur (seuls `C`, `c`, `a`), `C` touche le lanceur même hors zone (Cri du Corbac : +1 PM au lanceur), `P` = famille d'invocation (plus « joueur ») : la bombe ne pose plus Combo à son invocation (la Ruse du Roublard part sur le Roublard), la Harponneuse ne se tue plus elle-même, Sac Rifice ne s'intercepte plus lui-même. `summons`, `bombs`, `intercept`, `zones` réenregistrés (`zones` ne finit plus en 60 s). 247 tests verts (`test_target_mask.gd`, 7 tests). Aussi (demande) : fenêtre de répartition des caractéristiques par lot (clic sur le nom ou clic droit sur « + » : nombre de points, Max, coût et reste, un seul `boost_stat`), `client_shot points:<stat>[:<n>[:ok]]`, captures relues (60 en Force d'un coup, capital 545 → 485) | APPROX : `T` / `W` / `U` lues comme vraies, « statique » = ne joue pas, `K` sans le repli par buff. Constaté : `AP` / `ap` / `MP` / `mp` ne sont jamais évaluées par le client (première lettre refusée par `blqc`), un jeton de condition inconnu (`PR`, `*h`…) vaut le drapeau « projeté ». Pas de capture de lot (rien d'affiché). Prochain : P1.13i |
| 2026-09-29 | P1.13i | Codes de déclencheurs lus dans le **code natif du client** : son aperçu de combat (classe `gzp` : `bmzx` coup subi, `bnaa` / `bmzz` ce que fait le porteur, `bmzy` autres événements, `bnab` portails) dit quel événement allume quel bit de `Core.Features.Fight.Spells.Triggers` ; `grr.blfm` donne le nom de chaque bit (ordre de `docs/client_enums.md`), l'analyseur `grs.blfu` lit les lettres de chaque partie « | » (un code inconnu est ignoré : `XD`, `TP`, `DTB`, `DV`, `CCMPARR`… ne sont jamais évalués par le client), `Triggers.blgb` / `blga` / `blfz` lisent `EON<n>` / `EOFF<n>` et `EK:<masque>` (vérifié par `gtz.blqi`). Sim : `FightTriggers.event` (événements en file comme les coups), `dealer_codes`, `state_changed`, `died` ; `Fight.hit_source`, `Fighter.last_hit_by`. Nouveaux codes : `DS`, `DT`, `DG`, `PD` (une poussée contre un obstacle n'est plus `D`), `CD` / `CDA`… / `CDBA` / `CDBE` / `CDM` / `CDR` / `CDS` / `CDT` / `CDG`, `CH`, `CS`, `CC`, `K`, `KWS`, `EK:<masque>`, `M`, `P`, `MA`, `APA`, `MPA`, `R`, `LPU`, `EON<n>`, `EOFF<n>`, `ION`, `IOFF` ; D, éléments, DBA / DBE, H, X sourcés (plus APPROX) ; `DBA` / `DM` valent aussi pour ses propres coups (le client ne l'exclut pas) ; `H` jamais par un vol de vie (`gzj.bmvy`, déjà le cas). `spells.py` : `known_trigger` ; 725 grades de classe partiels (760 au dernier compte). Client : texte de chaque code dans l'infobulle. 255 tests verts (nouveau `test_trigger_codes.gd`, 8 tests) ; les 20 scénarios existants identiques ; nouveau `attraction.jsonl` (Roublard 35 : bombe alignée puis Aimantation, `MA` lance le sous-sort) ; capture relue (Toxines, sous-sort Sram : « Effet déclenché quand un piège le frappe (2 tours) ») | APPROX : `DM` / `DR` à distance 1 (`gyp.bmrd` non lu), pas de `DS` pour un poison, pas de codes d'auteur pour une poussée, `CC` une fois par lancer critique, `M` pour tout déplacement par effet. Sorti du lot (nouveau P1.13k) : lettres `T` / `W` / `U`, « statique », repli de `K`, codes non connus ou non évalués par le client, renvoi de sort (106 / 107 / 220 : aucun sort de classe, seulement des monstres hors d'Incarnam). Prochain : P1.13j |
| 2026-09-29 | P1.13j | Baisse des dommages en zone lue dans le **code natif du client** : `gru.blgz` construit pour chaque forme une classe de distance (`grz` Manhattan `oh.owi` : `*` B D I L T Z, et C / Q / X / l avec `param2` en décalage, O avec `param1` ; `gsc` Manhattan / 2 : `+` (décalage `param2`), `#` `-` `/` U ; `gse` plus grand écart : G R W ; `gsa` / `gsb` le long de la direction lanceur → centre : V, F ; `gsd` 0 : a, A), `grz.blil` / `grt.blgw` = min(100, min(distance − décalage, `maxDamageDecreaseApplyCount`) × `damageDecreaseStepPercent`) si `param1` < 51 ; `hs.nfg` : `param1` ≥ 1 et forme autre que P. L'aperçu (`HitContext.bmuv` → `gzm.bmyw`) multiplie par (100 − %) / 100 ; `gzm.bmyv` l'applique aux dommages côté lanceur (`hal`, `ra.fay` : arrondi à l'inférieur), avant ceux de la cible (`ham.bndg`), sauf 80, 90, 1047, 1048 (`gzj.bmws`), boucliers 1020 / 1039 / 1040 et éclaboussures (`gzj.bmvt`). Sim : `FightRules.efficiency`, `FightEffects` (dommages, vols, soins directs : `zone_pct`) ; `spells.py zone_of` et `Equipment.zone` ajoutent `step` / `steps` (`spells.json` régénéré, rien d'autre ne change). 261 tests verts (nouveau `test_zone_decrease.gd`, 6 tests) ; `bombs` et `zones` réenregistrés (changement voulu : Foène 19 → 15 sur la dent à 2 cases, explosions 9 → 8) ; capture relue (deux bombes : −10 et −8 sur le Tofu selon la distance) | APPROX : poisons et effets déclenchés gardent leurs dommages pleins, soins placés comme les dommages (après les soins fixes, avant les soins finaux). Les dés restent tirés par cible (non lu). Sorti du lot (nouveau P1.13l) : `onlyAffectIfInSightLine`, `forcedDirection`, `includeCarried`, `cellIds` (`grw.blhz`). Prochain : P1.13k ou P1.13l |
| 2026-09-29 | P1.13l | Options de zone lues dans le **code natif du client**. Offsets de `SpellZoneDescr` (Cpp2IL) : `forcedDirection` 0xE, `includeCarried` 0xF, `onlyAffectIfInSightLine` 0x10 ; `gru.blhb` passe les deux derniers à `gru.blha`, rangés dans la zone `grt` (0x20, 0x19). Lecteurs trouvés par recherche d'octets dans `GameAssembly.dll` : `gtb.blnr` → `gtb.blnw` retire des cases de l'effet celles que le fournisseur de carte ne voit pas depuis la case ciblée (le **centre**) ; `gtz.nhs` laisse hors zone un combattant en état 8 « Porté » (`gvr.bmcs` → `gui.bluz(8)`) sauf avec `includeCarried` (1 sur tous les points ; Holmgang `A,E8` le confirme : il vise les ennemis portés) ; la forme `;` est la classe `grx` (les `cellIds` absolues, cases de la carte). `forcedDirection` : aucun lecteur (serveur seul). `spells.py zone_of` : `sight`, `with_carried` (hors points), `custom` / `cells` (`spells.json` régénéré avec `--world incarnam` : seulement ces ajouts). Sim : `FightRules.zone_in`, `touches_carried`, `area(…, map, occupés)` ; `FightEffects.targets` cherche aussi les portés (sur la case du porteur) ; l'IA évalue ses zones avec `zone_in`. Client : aperçu et effet de zone filtrés par la ligne de vue. 267 tests verts (nouveau `test_zone_options.gd`, 6 tests) ; `fight_won.jsonl` réenregistré avec le bot (changement voulu : le Béco d'un Tofu sur le Pandawa touche aussi le Tofu qu'il porte, qui meurt ; plus de lancer, toujours une victoire), les 20 autres identiques ; capture relue (`aim:` Martinet, cercle 63 en vue : cases derrière les monstres et la clôture exclues) | APPROX : la ligne de vue du fournisseur prise comme celle du lancer (`has_los` : les combattants bloquent). Remplacé : APPROX(P1.12) « un porté n'est jamais touché par les zones ». Non fait (vers P1.13k) : `forcedDirection`, les fournisseurs de `grw.blhz` / `blia` / `grx`, `includeCarried` des marques, la baisse des dommages d'une forme `;` (classe `ekp`). Prochain : P1.13k |
| 2026-09-29 | P1.13k | Lot découpé (trop gros) : fait ici les lettres de masque `T` / `W` / `U`, « statique » et le repli de `K` ; codes de déclencheurs → P1.13m, Téléfrag → P1.13n, renvoi / direction forcée / fournisseurs de zone → P1.13o. Source nouvelle : les **types lus par emplacement de métadonnées** du code natif (IL2CPP v39 : `client_code.py usage` retrouve `Il2CppMetadataRegistration.types` et le nom du type dans `global-metadata.dat`, `refs` les fonctions qui lisent une adresse ; `methods.cs … x` donne le type des champs ; Il2CppDumper v39 ne trouve pas les registres de ce client). Lu : `gtz.blqe` (T → `gvs.bmdh`, W → `gvs.bmdi`, code identique : un événement de déplacement `gzw` du combattant dont `newPosition` passe `ezl` emplacement 18 = `enq.babz` → `enq.babg(x, y, true, -1, -1)`, le `pointMov` de la carte ; U → `gvs.bmdp` : un événement d'invocation `haa` ; K : porté (états 8 / 3, id porté du lanceur) ou un `gzw` dont `throwerEntityId` est le lanceur), `FightState.bmjp` (liste d'événements par combattant de l'aperçu), `gyn.bmqg` (statique = `MonsterData.canPlay` faux). Sim : `Fight.cast_log` / `log_cast` (déplacements par effet, échanges, téléportations, portails, lancers, invocations), vidée par le `FightEffects.apply_spell` le plus externe ; `TargetMask` T / W / U / K ; le drapeau `carried` ne sert plus à K. 270 tests verts (`test_target_mask.gd` : 3 nouveaux, dont Frappe de Xélor : Téléfrag seulement si la cible a bougé) ; les 21 scénarios existants identiques ; nouveau `double.jsonl` (Sram 10, Double : `a,U` ne touche que le double) ; capture relue (le double et ses effets au-dessus de lui seul) | APPROX(P1.13n) : T tel que l'aperçu du client (toute cible déplacée pendant le lancer), le serveur en demande sans doute plus (« Peut générer un Téléfrag ») ; une téléportation vers une case occupée échoue encore (le client échange : `hai.bnca`). Remplacés : APPROX(P1.13h) sur T / W / U, « statique » et K. Prochain : P1.13m, P1.13n ou P1.14 |
| 2026-09-29 | P1.13m | Codes de déclencheurs restants lus dans l'aperçu du client (`gzp`), avec les noms de champs des sorties d'aperçu (leurs `ToString` : `gzt` FightPreviewDamageOutput {damageRange `gzd` DamageRange (isShield 0x1c, isHeal 0x1d, isCritical 0x1e, isCollision 0x1f), isPermanentDamage}, `gzu` Death, `gzv` Dispel, `gzw` Movement {newPosition, swappedEntityId, dragType…}, `gzy` Stat {statId, delta, isSteal}, `gzz` State) et le tableau exact bit → code (`grr.blfm`, `EACT` = 95, dernier). Sim : `MS` (échangé), `PO` (le porteur déplace un combattant, lui compris), `CAPA` / `CMPA` + vol de PA / PM (84 / 77 : nouveaux, `resource` `steal`), `DIS` + désenvoûtement (132 : nouveau, `dispellable` des effets gardé par `spells.py`, `Buff.dispellable`), `DCAC` / `CDCAC` / `KWW` (`Fight.cast_weapon`, `Fighter.last_hit_weapon`), `DCCBA` / `DCCBE` / `CDCCBA` / `CDCCBE` (`Fight.cast_crit`), `CION` / `CIOFF`, `V` / `VA` (coup, poussée, soin, vol de vie, bouclier), `VM` / `VE` connus (jamais : pas d'érosion), `PPD`. `M` : le client ne filtre pas par genre, il vérifie la case d'arrivée (`ezl` emplacement 18, comme T) : APPROX(P1.13i) retiré. Partiels : 725 → 712 grades de classe (Barricade, Bastion, Flèche d'Immobilisation, Rabattage, Imposture entièrement simulés). 276 tests verts ; les 22 scénarios existants identiques ; nouveau `steal.jsonl` (Crâ 30, Flèche d'Immobilisation : le Crâ gagne le PM volé) ; capture relue (Féca 10, Barricade sur soi : « Effet déclenché quand il est désenvoûté ou quand on le frappe à distance ») ; `client_shot tip:me` | APPROX(P1.13m) : le drapeau `hs`+0x1c lu comme « critique » (nom des codes), les écouteurs `DIS` désenvoûtables réagissent au désenvoûtement qui les retire (Barricade / Bastion), le client allume aussi `ION` / `IOFF` de l'auteur (pas ici). Restent (nouveau P1.13p) : codes du serveur seul (`XD`…, `CPD`, `TP`, `DTB` / `DTE` / `DV`, `CI`, `CMPAS`…), `DI`, `PMD`, `PST` / `PDT`. Prochain : P1.13n, P1.13o ou P1.14 |
| 2026-09-30 | P1.13n | Téléfrag lu dans l'aperçu des téléportations du client (`hai.bnca` / `dht` / `hbl` / `mwk`) : une téléportation (4, 1104, 1105, et l'échange 8 / 1101) vers une case occupée échange les deux combattants si `gvr.st` le permet dans les deux sens (`FightEffects.can_swap` : ni porteur ni porté, ni `cantBeMoved` (propriété d'état 3), `cantSwitchPosition` (propriété 18) seulement pour 8 / 784 / 1099 / 1100 / 1104-1106 (`gzj.bmxr`), monstre : `canSwitchPos` / `canSwitchPosOnTarget` (`m_flags` bits 9 / 10) sauf 4 / 1023 (`gzj.bmww`)), sinon rien ne bouge ; l'occupant bouge d'abord ; `swapped` / `telefrag` sur les `move`. Téléfrag = lanceur Xélor (`gyn`+0x14 = `breedId`, `ToString` « EntityData type / breedId ») ; **changement de règle voulu** : `T` = téléfragué pendant ce lancer (avant : déplacé ; `W` le reste) : `T` n'existe que sur les sorts Xélor, à côté du sous-sort Téléfrag, et l'aide du jeu (i18n « Les Téléfrags ») dit « générés lorsque deux entités échangent de positions suite aux effets de téléportation d'un sort Xélor » : APPROX(P1.13n) retiré. `spells.json` régénéré (seuls ajouts : `effect` des déplacements, `switch` / `switch_on_target` des invocations, vérifié par comparaison), `monsters.json` d'incarnam / dofus complétés (31 grades sans échange dans dofus). 282 tests verts, les 23 scénarios existants identiques ; nouveau `telefrag.jsonl` (Xélor 10, Téléportation vers une case prise : échange, 251 / 244 pendant 2 tours, +2 PA « sur Téléfrag ») ; capture relue (Frappe de Xélor, `client_shot mirror` : les deux Bouftous échangés, 6 → 3 → 5 PA ; l'infobulle `tip` ne s'est pas affichée sur cette capture, les états sont vérifiés par les tests) | Reste (nouveau P1.13q) : 1106 / 1100 / 1099 / 1023 / 784 non extraits (retours en arrière, symétrie au point d'impact), l'effet sans `gvr.st` de `hai.hbl` (0x50). Prochain : P1.13o, P1.13p, P1.13q ou P1.14 |
| 2026-10-02 | P1.13o | Lot découpé : fait ici le renvoi de dommages 107 / 220 (kind `reflect`, buff sur `D`, montant fixe `diceNum`, `APPROX` : aucune formule trouvée ; 107 ajoute la stat `reflect`), `test_reflect.gd`, tests verts (285). Reste (P1.13r) : renvoi de sort 106, `forcedDirection`, fournisseurs de zone, `includeCarried` des marques. Ligne « sources » non cochée (APPROX), pas de capture (aucun sort d'Incarnam concerné). |
| 2026-10-02 | P1.13p / P1.14 | Aucun code : P1.13p est bloqué faute de source (aucun des codes `XD`, `XPD`, `CMPARR`, `DTB`… dans les dumps JondoEmu ni dans les enums du client : seul le nom existe, pas l'événement qui les allume) ; P1.14 : `luaformulas` ne contient aucune formule de combat (dommages, poussée, érosion, retrait PA / PM : index = XP, butin, alliances), il faudrait lire le code natif du client (`client_code.py`) ou des captures serveur. Les deux restent `todo`. Prochain à choisir : P1.16, P1.17, P2.01 ou P1.13q |
| 2026-10-02 | P1.13q | Retours en arrière : `Fighter.prev_cell` / `turn_begin_cell` / `start_cell` (le setter de `cell` garde la précédente ; remises à -1 / courant au début du combat et à l'invocation), effets 1100 `rollback_prev`, 1099 `rollback_turn`, 784 `to_start`, 1106 `sym_impact` (tous `spells.py MOVES`, `spells.json` régénéré : 73 + 63 + 10 effets, 784 n'est dans aucun sort d'Incarnam / des classes), 1023 devient un `swap` (échange forcé sans `gvr.st`, déjà géré par `_swap`). Case d'arrivée occupée = échange + Téléfrag Xélor comme P1.13n. 297 tests verts (`test_rollback.gd` : 7), scénarios existants identiques ; nouveau `rollback.jsonl` (Xélor 100, Rembobinage : retour de 273 à 287). Rembobinage reste `partial` (1026 / 1045 / 2792). | APPROX(P1.13q) : 1106 renvoie la cible de l'autre côté de la case visée (le point exact du client n'est pas lu) ; l'effet sans `gvr.st` de `hai.hbl` (0x50) toujours pas identifié. Prochain : P1.16, P1.17 ou P2.01 (P1.13p, P1.14 bloqués faute de source) |
| 2026-10-02 | P1.17 | Audit « partial » d'Incarnam et d'Astrub (`spells.py classes --world incarnam+astrub` : les monstres des 9 sous-zones d'Astrub, 100 sorts de monstres au lieu de 30) : Incarnam était déjà entier (5 sorts de pur buff du lanceur sont écartés par `convert`) ; Astrub avait 10 sorts partiels, 15 effets : les Deboost 152 / 154 / 155 / 157 (caractéristiques), 215-219 (% résistance élémentaire), 163 (esquive PM), 179 (soins), 752 (fuite) rejoignent `STATS`, 1076 (+% résistance à tous les éléments, stat `res_all` lue par `Fighter.stat`), 1071 (`hp_pct` : % des PV courants de la cible, dommage neutre) et 1132 (`per_ap` : dommages Eau par PA utilisé du porteur à la fin de son tour, `Fighter.ap_spent`). 302 tests verts (`test_audit_effects.gd` : 5), scénarios identiques ; aucun sort de monstre d'Incarnam / Astrub n'est plus `partial`. | APPROX(P1.17) : 1071 et 1132 d'après leur seul texte (PV courants, formule de dommages habituelle). Pas de scénario ni de capture (rien de nouveau à voir). Reste : P1.17b (662 grades de classe, autres zones). Prochain : P1.16, P2.01 ou P2.05 |
| 2026-10-02 | P1.13r | Renvoi de sort 106 : buff `spell_reflect` (`level` = `diceSide`, `pct` = `value`, `turns` = `duration`, les codes `APA|D` des données sont ignorés), lu dans `FightEffects._reflector` : un sort ennemi de grade <= `level` (effets nuisibles `REFLECTABLE`) lancé sur le porteur revient au lanceur avec `pct` % de chance, un seul tirage par porteur et par lancer ; effet `reflected` (protocole, client : texte flottant et texte du buff). `forcedDirection` : aucun lecteur dans le client (déjà établi en P1.13l), abandonné (serveur seul). 289 tests verts (nouveau `test_spell_reflect.gd`, 4 tests), `PROTOCOL.md` régénéré, `rules_sources --check` passe. Non fait : fournisseurs de zone et `includeCarried` des marques (nouveau lot P1.13s), `spells.json` non régénéré (les 34 grades sont des sorts de monstres hors d'Incarnam), pas de scénario ni de capture (aucun sort concerné). | APPROX(P1.13r) : sens de `diceSide` / `value` de 106 et liste des effets renvoyés, aucune source. |
| 2026-10-02 | P1.13s | `includeCarried` des marques lu dans le code natif : `MarkedCellsService.bfib` construit la zone d'un glyphe / d'une aura par `gru.blha` (cercle C ou croix X de rayon `size`) avec **tous les drapeaux à 0**, donc sans `includeCarried` : un combattant porté n'est jamais touché ni pris dans une marque (déjà le comportement de `FightMarks`, désormais testé : `test_zone_options`, 290 tests verts). Fournisseur de cases de `grw` (champ +0x10, copié du parent `grt`, appelé par `blhz(case, origine)` : vrai = case exclue, et `blia(x, y)` : faux = case ignorée) : le décompilé ne montre pas qui le renseigne (ce n'est pas `tz`, l'entrée de marque), laissé en `APPROX(P1.13s)` : filtre de validité de case = cases de la carte, déjà fait par `FightRules.zone`. Pas de scénario ni de capture (aucun effet visible). | APPROX(P1.13s) : identité du fournisseur de zone. |
| 2026-10-02 | P1.16 | Profils d'IA (`FightAI.profile` : agressif, prudent, soigneur, invocateur, kamikaze, lus dans les sorts, `APPROX(P1.16)`), fuite sous 30 % de PV, distance de tir, soigneur vers ses alliés blessés. `test_ai_profiles.gd` (10 tests, dont budget de décision < 150 ms), 312 tests verts. **Changement de règle voulu** : les monstres à distance gardent leur portée, 15 scénarios réenregistrés. Lot terminé côté sim ; pas de capture (rien de nouveau côté client), sources non cochées (aucune donnée de comportement). |
| 2026-10-02 | P2.01 | PNJ : positions réelles (`gamedata.py npcs <monde>` : JondoEmu `npcs_reales.json`, relevées sur les déclarations du serveur officiel : 4 PNJ dans Incarnam, 422 sur 202 maps dans `dofus`) → `worlds/<id>/npcs.json` ; table `npcs` légère (`game/data/tables/npcs.json`, 327 modèles). Sim : `NpcActor` (kind `npc`), `Dialog` (arbre `{start, nodes}`, réponses filtrées par `CriteriaEval`, actions `teleport` / `give_kamas` / `give_item`, `shop` / `quest` transmises au client), `WorldSim._on_npc_talk` / `_on_dialog_reply` (joueur à côté, toute autre commande ferme le dialogue). Protocole : `npc_talk`, `dialog_reply`, `dialog_close`, `dialog`, `dialog_end` + `not_at_npc` / `no_dialog` / `no_reply`. Client : `DialogWindow` (textes i18n du client), clic sur un PNJ = marche à côté puis parle, nom au-dessus ; `client_shot npc`. 320 tests verts (`test_npcs.gd` : 8 ; piège : une erreur de parse dans un fichier de test est silencieuse, les tests ne tournent pas, vérifier le nombre total), capture relue (Pyracelse). | APPROX(P2.01) : l'arbre de dialogue n'est pas dans le client (`dialogMessages` / `dialogReplies` = listes plates de toutes les répliques possibles, l'enchaînement est côté serveur) : un PNJ sans arbre écrit à la main dit son premier message sans réponse ; distance de parole = case voisine. Pas de nouveau scénario `.jsonl` (aucune règle de combat). Prochain : P2.02 (boutiques, dépend de P2.01) ou P1.17b |
| 2026-10-02 | P1.17b | Premier morceau : les effets de relance 1045 (relance fixée à #3), 1036 (-#3 tour) et 1035 (+#3 tour) (`spells.py` `COOLDOWNS`, effet `cooldown{mode, origin, turns}` ; `FightEffects.cooldown` agit sur tous les grades du combattant ciblé du sort `origin`, jamais sous 0 ; effet protocole `cooldown{spell, turns}` pour la pastille de la barre). `spells.json` régénéré (`--world incarnam+astrub`) : 662 à 646 grades de classe `partial`. 321 tests verts (+1, `test_audit_effects.gd`), pas de scénario ni de capture (pastille seule). | Reste, par fréquence : 2935 (soins de base), 1160, 335 (apparence), 2822, 2792, 1026, 776, 414, 285, 115. APPROX(P1.17b) : 1045 / 1036 / 1035 d'après les textes i18n et l'enum du client (diceNum = sort, value = tours). Le lot reste `doing` |
| 2026-10-02 | P1.17b | Deuxième morceau : les buffs 115 (+% critique), 178 (+soins) et 414 (+dommages de poussée) rejoignent `STATS` (déjà lus par `Fighter.stat`, le tirage de critique et la poussée) ; 285 (`#1 : -#3 PA`) et 2935 (`#1 : +#3 soins de base`) deviennent des buffs `stat` nommés `spell_mod:<ap\|heal>:<spells.id>` (`spells.py` `SPELL_MODS`), lus par `Fighter.spell` qui renvoie une copie du sort avec son coût en PA (jamais sous 0) et la base de ses soins modifiés (le livre n'est pas touché). `spells.json` régénéré : 646 à 568 grades de classe `partial`. 325 tests verts (+4, `test_audit_effects.gd`), scénarios identiques, pas de capture (aucun rendu nouveau). | Reste, par fréquence : 1160, 2822, 2792 + 1026, 776 (érosion), 335 (apparence), 1078, 2828, 182, 420 (résistance aux critiques, aucun lecteur en sim). APPROX(P1.17b) : 285 / 2935 d'après leurs textes (diceNum = sort, value = quantité) ; le pré-contrôle des PA du client (`fight_view`) lit encore le coût de base. Le lot reste `doing` |
| 2026-10-02 | P1.17b | Troisième morceau : 2822 / 2828 (dommages / vol du « meilleur élément » : `element: "best"`, `FightEffects.best_element` = la plus haute caractéristique d'élément du lanceur), 1078 (`stat` vitalité avec `pct` : % des PV max de la cible), 420 (stat `crit_res` : réduction fixe des dommages d'un coup critique, `cast_crit`), 2905 / 2906 (`spell_mod:rmax\|rmin:<spells.id>` : portée fixée, lue par `Fighter.spell`), 1026 (`glyph_trigger` : `FightMarks.trigger_glyphs`), 335 (apparence, ignorée). `spells.json` régénéré : 568 à 406 grades de classe `partial`. 331 tests verts (+6, `test_audit_effects.gd`), scénario `zones.jsonl` réenregistré (un monstre d'Incarnam lance désormais un sort qui était partiel : écart voulu à partir de 45,6 s), pas de capture (aucun rendu nouveau). | Reste : 1160 / 792 (codes de déclencheurs inconnus : XD, TP, DTB, DTE, XPD, CMPAS…), 2792, 776 (érosion), 182 (invocations max). APPROX(P1.17b) : « meilleur élément » et 1026 d'après leurs seuls textes (1026 : les glyphes du lanceur sous la cible, les deux types) ; 420 appliqué après la résistance fixe, avant les % ; 335 ignoré (apparence). Le lot reste `doing` |
| 2026-10-02 | P1.17b | Quatrième morceau : 182 (`+#1 Invocation` = stat `summons`, lue par `Summons.max_summons`) et 776 (`#1% Érosion` = stat `erosion`) rejoignent `STATS`, 2792 (limite globale de lancer, Xélor) est ignoré (`IGNORED`). `spells.json` régénéré : 406 à 301 grades de classe `partial`. 333 tests verts (+2, `test_audit_effects.gd`), scénarios identiques, pas de capture (aucun rendu nouveau). | APPROX(P1.17b) : 776 n'a aucun lecteur (l'érosion elle-même est P1.14, bloqué faute de formule) ; 2792 (diceNum = un sort, value = un nombre, texte « #1 », inactif) non appliqué : les sorts Xélor gardent leurs limites `per_turn` / `per_target`. Reste : 1160 / 792 / 90 / 145 (codes de déclencheurs du serveur, P1.13p bloqué), 2027, 3002, 1048, 2973, 265, 290…. Le lot reste `doing` |
| 2026-10-02 | P1.17b | Cinquième morceau : buffs 145 (-dommages), 160 / 162 (esquive PA), 410 / 412 (`ap_attack` / `mp_attack`), 416 (`push_res`), 418 (`crit_damage`), 755 (-tacle) rejoignent `STATS`, et les vols de caractéristiques 266-271 (chance, vitalité, agilité, intelligence, sagesse, force) `STEAL_STATS` comme 320. `spells.json` régénéré : 301 à 251 grades de classe `partial`. 334 tests verts (+1, `test_audit_effects.gd`), scénarios identiques, pas de capture (aucun rendu nouveau). | APPROX(P1.17b) : signes et noms de stats d'après les noms de l'enum `ActionId` seulement ; `ap_attack`, `mp_attack`, `crit_damage` n'ont pas encore de lecteur dans les formules. Reste : 1160 / 792 / 90 (déclencheurs inconnus), 2027 (contrôle d'entité), 3002, 1048, 2973, 265, 280, 289, 290, 1223. Le lot reste `doing` |
| 2026-10-02 | P1.17b | Sixième morceau : modificateurs de sort 290 (+lancers par tour), 287 (+% critique), 280 (+portée minimale), 289 (ligne de vue désactivée), 299 (case libre nécessaire) (`SPELL_MODS`, lus par `Fighter.spell`), 1048 (-% PV, buff de vitalité négatif en %), 419 / 421 (-dommages / -résistance critiques), 265, 2800 / 2803 / 2804 / 2812 (`STATS`). `spells.json` régénéré : 251 à 196 grades de classe `partial`. 335 tests verts (+1, `test_audit_effects.gd`), scénarios identiques, pas de capture (aucun rendu nouveau). | APPROX(P1.17b) : signes d'après les textes i18n et les opérateurs ; 280 s'ajoute au minimum ; 265, 2800, 2803, 2804, 2812, 419 n'ont pas de lecteur dans les formules. Reste : 1160 / 792 / 90 (déclencheurs), 2027 (contrôle d'entité), 3002, 2973, 1223, 89, 2793, 1406, 1031, 2184, 781, 783, 952. Le lot reste `doing` |
| 2026-10-02 | P1.17b | Septième morceau : 1031 (Passe le tour : `pass_turn`, `Fighter.pass_turn`, le tour du ciblé finit après le sort, ou est sauté s'il n'est pas le courant), 3002 (soins du meilleur élément : `heal` `element: "best"`), 295 (`spell_mod rminadd` négatif), 2793 et 333 ignorés. `spells.json` régénéré : 407 à 364 entrées `partial` (sorts de classe et de monstres, sous-sorts compris). 336 tests verts (+1, `test_audit_effects.gd`), scénarios identiques, pas de capture (aucun rendu nouveau). | APPROX(P1.17b) : 1031 d'après son nom d'enum seulement ; 2793 ignoré comme 2792 ; 333 (couleur) ignoré. Reste : 1160 / 792 / 90 (déclencheurs), 2027 (contrôle d'entité), 2973 / 1223 (soins / dommages en éclaboussure), 2184, 89, 1406, 314 / 297. Le lot reste `doing` |
| 2026-10-02 | P1.17b | Huitième morceau : 89 (`Dommages Neutre : #1 à #2% PV du lanceur` : `damage` `caster_hp_pct`, lu par `FightEffects._base`) et 1406 (`Enlève les effets du rang #1 du sort #2` : `unbuff` avec `grade`, ne retire que les buffs lancés par ce grade). `spells.json` régénéré : 196 à 172 grades de classe `partial` (356 en tout avec les monstres). 337 tests verts (+1, `test_audit_effects.gd`), scénarios identiques, pas de capture (aucun rendu nouveau). | APPROX(P1.17b) : 89 d'après son texte (PV courants du lanceur, % tiré entre #1 et #2, puis formule de dommages habituelle) ; 1406 : diceSide = rang, value = spells.id (comme 406). Reste : 1160 / 792 / 90 (déclencheurs), 2027 (contrôle d'entité), 2973 / 1223 (soins / dommages en éclaboussure : il faut mémoriser les dommages faits / subis), 2184, 781 / 783, 952. Le lot reste `doing` |
| 2026-10-02 | P1.17b | Neuvième morceau : 279 (`caster_missing_pct` : % des PV manquants du lanceur, `FightEffects._base`), 2832 (dommages du « pire élément » : `element: "worst"`, `worst_element`), stats 2802 / 2806 / 2807 (`melee_res` / `ranged_res`), 2805 (`ranged_damage` -), 2972 (`final_heals` -), vitalité en % 2844 / 1033, modificateurs de sort 291 (`pertarget`), 297 / 314 (case occupée off / on), 798 (`need_visible_target`), 2017 ignoré. `spells.json` régénéré (`classes --world incarnam+astrub`) : 172 à 157 grades de classe `partial`. 338 tests verts (+1, `test_audit_effects.gd`), scénarios identiques, pas de capture (aucun rendu nouveau). | APPROX(P1.17b) : signes et noms d'après les textes i18n et l'enum `ActionId` ; 2802 / 2806 / 2807 / 2805 / 2972 sans lecteur dans les formules ; `need_visible_target` (798) non lu par `FightRules` ; « pire élément » : ex aequo dans l'ordre terre, feu, eau, air. Reste : 1160 / 792 / 90 (déclencheurs), 2027 (contrôle d'entité), 2973 / 1223 (éclaboussure), 1013 / 1016 (% PM restants), 1092 / 1118 (PV érodés : P1.14), 2184, 781 / 782 / 783, 952, 1097, 1100 sous-effets. Le lot reste `doing` |
| 2026-10-02 | P1.17b | Dixième morceau : 1012-1016 (`#1 à #2 dommages <élément> (% PM restants)`) : `damage` `mp_left`, dés multipliés par la part de PM restants de la cible (`FightEffects._base`). `spells.json` régénéré. 339 tests verts (+1, `test_audit_effects.gd`), scénarios identiques, pas de capture (aucun rendu nouveau). | APPROX(P1.17b) : formule d'après le seul texte i18n (aucune source), dés x PM restants / PM max. Reste : 1160 / 792 / 90 (déclencheurs), 2027, 2973 / 1223, 1020 (bouclier : pas de `kind` shield), 781 / 782 / 783, 952, 2184, 1097. Le lot reste `doing` |
| 2026-10-06 | P1.17b | Onzieme morceau : 90 (`transfer_hp` : le lanceur donne #1 a #2% de ses PV courants a la cible), 2973 (`heal_dealt` : soin d'un % des dommages que le lanceur a faits dans ce lancer, `Fight.cast_dealt`) et 1223 (`splash_taken` : dommages neutres d'un % du coup qui a declenche le buff, `Fight.trigger_amount`). `spells.json` regenere : 76 a 44 grades de classe `partial`. 741 tests verts (+1, `test_audit_effects.gd`), scenarios identiques, pas de capture ni de message nouveau (donc pas de test NetBackend). | APPROX(P1.17b) : 90 / 2973 / 1223 d'apres leurs seuls textes i18n (aucune formule trouvee) ; 1223 en dommages neutres sans resistance. Reste : 1160 / 792 (declencheurs), 2027 (controle d'entite), 781 / 782 / 783, 952, 1097, 1118 / 1092 (P1.14), 2020. Le lot reste `doing` |
| 2026-10-06 | P1.17b | Douzieme morceau : 783 (Pousse jusqu'a) et 1043 (Tire jusqu'a) lus comme `push` / `pull`, 1018 (le lanceur lance le sort sur la cible) dans `CAST`, 781 / 782 (`roll_min` / `roll_max` : tirages de dommages et soins du porteur forces au minimum / maximum, `FightEffects.roll(fight, e, bearer)`). `spells.json` regenere : 44 a 38 grades de classe `partial`. 742 tests verts (+1 `test_p117b12_forced_rolls`; test p117b11 corrige : la cible morte n'etait pas ranimee), scenarios identiques, pas de capture ni de message nouveau (donc pas de test NetBackend). | APPROX(P1.17b) : 781 / 782 d'apres leurs noms d'enum seulement (porteur, le maximum l'emporte) ; 783 / 1043 traites comme un push / pull normal (obstacle = arret). Reste : 1160 / 792 (declencheurs), 2027 (controle d'entite), 952, 1097, 2020, 2184, 1118 / 1092 (P1.14). Le lot reste `doing` |
| 2026-10-06 | P1.17b | Treizieme morceau : 2020 (`splash_heal` : soin d'un % des dommages subis qui ont declenche le buff, `Fight.trigger_amount`, jumeau de 1223) et 952 (`Desactive l'etat #3` lu comme `unstate`). `spells.json` regenere : 38 a 33 grades de classe `partial`. 743 tests verts (+1 `test_p117b13_splash_heal`), scenarios identiques, pas de capture ni de message nouveau (donc pas de test NetBackend). | APPROX(P1.17b) : 2020 d'apres son seul texte i18n ; 952 retire l'etat au lieu de le suspendre. Reste : 1160 / 792 (declencheurs), 2027 (controle d'entite : Double / Comploteur Sram), 2184 (suit le lanceur), 1097 (illusions), 1163 (dommages subis x%), 1118 / 1092 (P1.14). Le lot reste `doing` |
| 2026-10-06 | P1.17b | Quatorzieme morceau : le declencheur CMPARR (nom du client de CCMPARR : un PM utilise en marchant) devient connu (`TRIGGERS` de `spells.py`, `FightTriggers.ALIASES`), 2184 (`TargetFollowCaster`) est ignore (`IGNORED`). Laisse Spirituelle n'est plus `partial` (class `partial` : 33 a 29 grades). 744 tests verts (+1 `test_p117b14_cmparr_and_2184`), scenarios identiques, pas de capture ni de message nouveau (donc pas de test NetBackend). | APPROX(P1.17b) : 2184 ignore (la cible qui suit les deplacements du lanceur n'est pas simulee). Reste : 1160 avec le declencheur CI (Faille), Mandragore (sous-sorts partiels), 2027 (controle d'entite), 1097 (illusions), 1118 / 1092 (P1.14). Le lot reste `doing` |
| 2026-10-06 | P1.17b | Quinzieme morceau : 2027 (`ControlEntity`, texte i18n « Prend le controle de l'entite », buff sans duree sur une invocation / un Double / une tourelle) est ignore (`IGNORED` de `spells.py`). `spells.json` regenere : 29 a 14 grades de classe `partial`. Test `test_p117b15_control_entity_ignored`, pas de message nouveau (donc pas de test NetBackend). | APPROX(P1.17b) : le joueur ne prend pas le tour de l'entite, FightAI continue de la jouer (Double, tourelles Steamer). Reste : 792 avec le declencheur DV (Berserk), 1160 / CI (Faille), 1097 (illusions), 1118 / 1092 (P1.14), 406 / 1163 (Ataraxie). Le lot reste `doing` |
| 2026-10-02 | P2.02 | Boutiques de PNJ. `shared/NpcShop` (prix d'achat `items.price`, rachat `price / 10`, `check_buy` : kamas puis pods), `WorldSource.get_shop` / `set_shops` + `worlds/<id>/shops.json`, `gamedata.py shops <monde>` (contenus réels JondoEmu `npc_shops.json` : 51 marchands placés dans `dofus`, 5 556 offres, 5 310 objets ajoutés à `items.json` avec leur prix et leurs icônes). Sim : `_open_shop` (bouton « Acheter/Vendre » i18n 8944 ajouté au dialogue par `Dialog.with_shop`, ouverture directe pour un marchand muet, action `shop` d'un arbre écrit à la main), `_on_shop_buy` / `_on_shop_sell`, toute autre commande ferme la boutique, un fantôme ne commerce pas. Protocole : `shop_buy`, `shop_sell`, `shop_close`, `shop_open`, `shop_end` + erreurs `no_shop`, `not_sellable` (réutilise `not_enough_kamas`, `overloaded`, `item_worn`, `unknown_item`). Client : `ShopWindow` (onglets Acheter / Vendre, quantité, boutons grisés), `client_shot` `reply` / `buy` / `sell`, `sim_cli` `npc_talk` / `dialog_reply` / `shop_*`. 354 tests verts (`test_shops.gd` : 15) ; scénarios existants identiques, nouveau `shops.jsonl` (à pied jusqu'à Lykhen, achat, kamas insuffisants, vente) ; capture relue (boutique de Lykhen Lesurviven). | APPROX(P2.02) : rachat à `price / 10` (règle communautaire, ratio serveur absent des données) ; objet à prix 0 non racheté ; achat refusé s'il dépasse les pods (règle du lot, les butins ne le sont jamais) ; tous les marchands rachètent tout (les actions 11 « Acheter » / 12 « Vendre » seules ne sont pas distinguées) ; Incarnam n'a aucun vrai marchand : Lykhen Lesurviven reçoit un stock de débutant écrit à la main (`worlds/incarnam/shops.json`). Pas de prix variables ni de stock limité. Prochain : P2.03 (quêtes) ou P2.05 |
| 2026-10-03 | P2.03 | Quêtes. Données : `gamedata.py quests <monde>` (tables `quests` / `queststeps` / `questobjectives` / `queststeprewards`) écrit `worlds/<id>/quests.json` (quêtes dont le PNJ de départ est sur une map du monde, dont tous les objectifs sont d'un type suivi et sur une map du monde : 19 dans Incarnam, 1 191 dans `dofus`), les ids de textes des arguments (`args`, `#1 #2 #3` des `questobjectivetypes`), les PNJ des quêtes que `npcs.json` ne place pas (1769 en `dofus`, 14 en Incarnam : cellule choisie, `approx: true`) et leurs modèles dans la table `npcs`, puis les objets (`items <monde>`, 8 405 objets). Sim : `QuestLog` (état dans `Character`, sauvegardé : `quests`, `emotes`, `titles`, `quest_spells`), `QuestEngine` (offres selon les critères, objectifs 0-9, 14, 16, 17, étapes enchaînées, récompenses par étape, vues pour le client). `CriteriaEval` lit `BT`, `Qf`, `Qa`. `WorldSim` : événements `talk` / `map` / `fight` / `use` / `item` rapportés au moteur, réponse « Nouvelle quête » ajoutée au dialogue du PNJ (`QuestEngine.with_offers`, arbre propre au joueur : `PlayerActor.dialog_tree`), remise d'objets prise dans le sac, récompenses données (XP, kamas, objets). Protocole : `quest_start`, `quest_update`, `quest_complete`, `quest_list` (à la connexion). Client : `QuestWindow` (journal, Q), `QuestTracker` (suivi sous la minimap), notifications avec les textes du client (5347, 5308), réponse de quête dans le dialogue. 369 tests verts (`test_quests.gd` : 15, dont 1639 de bout en bout dans Incarnam et un vrai combat qui valide « en un seul combat ») ; nouveau `quests.jsonl` ; `shops.jsonl` réenregistré (Lykhen offre maintenant la quête 1632 : réponse en plus, voulu) ; capture relue (offre dans le dialogue, suivi, journal) | APPROX(P2.03) : voir Découvertes. Reste P2.03b. Prochain : P2.04 ou P2.05 |
| 2026-10-09 | P1.14 | Premier morceau : érosion (`FightEffects.hurt` : 10 % des PV perdus, hors bouclier, + stat `erosion` 776, plafond 50 %, retire du max PV ; `Fighter.eroded`, `max_hp`/`eroded` dans l'effet `damage`, `fighter.eroded` dans `to_dict`), la barre du client suit le max érodé. Test `test_erosion.gd` ; 31 scénarios réenregistrés (champs ajoutés). APPROX(P1.14b) : valeurs communautaires, la formule du client n'est pas décodée. | Reste : plafond de 50 % de résistance en JCJ (pas de notion de JCJ dans `Fight`), dommages de poussée / critique, taclage et esquive PA/PM (APPROX dans `fight.gd` et en tête de `fight_effects.gd`) : formules à décoder avec `tools/client_code`. P1.15 reste `doing` (dépend de P1.14). `test_a_decision_stays_under_the_budget` échoue sur la durée (159 ms), sans lien. |
| 2026-10-09 | P3.02b | Premier morceau : canal groupe `/p` (`Chat.GROUP` disponible, destinataires = membres du groupe de l'expéditeur, `channel_unavailable` sans groupe), liens d'objets `{item:ID}` (`Chat.link_ids`, `chat_msg.links` = ids existants, le client affiche `[Nom]`), onglet Groupe. Tests `test_chat.gd`. Correctif C.02 : un cache téléchargé d'un serveur masquait le monde en solo (`no_start_map`, écran gris) : `ClientSession` lit `res://` hors `NetBackend` ; test `test_solo_ignores_cache.gd`. | Reste : smileys / émotes, infobulle au survol d'un lien, canaux guilde et alliance (pas de lots), test via `NetBackend` du canal groupe (dette) |
| 2026-10-03 | P1.15 | Reprise : le code (FightChallenges, options, fuite/abandon, timeout, protocole, HUD) était déjà fait et testé ; vérifié (388 tests verts), capture relue, boutons d'option remontés au-dessus de la barre (ils masquaient « Abandonner »), doc ARCHITECTURE. APPROX : bonus 25 %, nombre de challenges. | Laissé `doing` : la dépendance P1.14 (érosion, formules exactes) n'est pas faite, `check` refuse `done` avant elle. Passer P1.15 à done une fois P1.14 faite |
| 2026-10-03 | P2.05a | Récolte (le lot P2.05 est coupé : a = règles + protocole + clic, b = bonus, retours visuels, fenêtre). Données : `gamedata.py interactives <monde>` écrit `worlds/<id>/interactives.json` (éléments récoltables par map : JondoEmu `interactive_elements.json` croisé avec `recursos_*.json`, gfx → compétence ; les gfx `discrepa` et la cellule 559 « hors grille » écartés ; 527 éléments sur 46 maps d'Incarnam, 16 778 sur 3 845 maps de `dofus`) et les tables légères `skills` / `jobs`. `MapData.interactives` (envoyé dans `map_enter`, `interactive_near`), `WorldSource.set_interactives`. `shared/Jobs` (niveau requis `skills.levelMin`, quantité, XP, table de niveaux), `sim/JobLog` (XP par métier, sauvé avec le personnage, `player_stats.jobs`), `sim/InteractiveState` (par `MapInstance` : repousse, élément pris par un seul joueur). `interactive_use{element, skill}` : joueur à côté, niveau de métier, élément libre ; `interactive_start` à toute la map (animation), après `Jobs.HARVEST_MS` : ressource (`give_item`, donc les quêtes « ramener » avancent), `job_xp`, `interactive_state{ready: false, until}` puis `ready: true` à la repousse ; un déplacement, une autre commande, un combat ou la déconnexion annulent (`interactive_end{done: false}`) ; un nouvel arrivant reçoit l'état des éléments déjà récoltés. Client : clic sur la ressource (marche à côté, puis `interactive_use`), animation `skills.useAnimation`, toast « +N XP métier ». 397 tests verts (9 nouveaux dans `test_jobs.gd`) ; nouveau scénario `harvest.jsonl` ; capture relue (le toast après la récolte d'un frêne à Incarnam) ; correctif en passant : `fight_result_window.gd` ne compilait pas en fenêtre (`var won :=` sur un Variant, P1.15) | APPROX(P2.05) : durée 3 s, repousse 5 min, XP = 10 + niveau requis, quantité 1-2 (+1 mini tous les 50 niveaux au-dessus, +1 maxi tous les 20), table d'XP des métiers = celle du personnage, tous les métiers au niveau 1 dès le départ ; ressources bonus, ressource grisée, curseur et fenêtre des métiers : P2.05b. Prochain : P2.05b ou P1.15 |
| 2026-10-03 | P2.05b | Lot coupé : b = règles, c = client et bonus. Critère `PJ<op><métier>,<niveau>` dans `CriteriaEval` (lit `Character.criteria_values().jobs`, `JobLog.levels()` ; un métier jamais pratiqué = niveau 1 ; `PJ>2,80` = Bûcheron au-dessus du niveau 80, `PJ=44,200` = niveau 200, d'après les valeurs de `items.criteria`) ; effet 614 `[614, 0, métier, XP]` des parchemins de métier (`ItemEffects.JOB_XP`, `use_item` : XP + `job_xp`) ; `queststeprewards.jobsReward` extrait (`gamedata.py quests`, champ `jobs`, une seule étape : les métiers 27 et 47) et enseigne le métier (`JobLog.learn`, `rewards.jobs`). Recherche de sources dans `datos` de JondoEmu (table d'XP des métiers, XP par récolte, durée, repousse, ressources bonus) : rien. `quests.json` d'Incarnam et de `dofus` régénérés (+ `items`). | APPROX(P2.05b) : 614 lu comme XP = 4e valeur (parchemin Bûcheron = 100), texte de l'effet non vérifié ; récolte jamais refusée faute de pods (comme les butins). Pas de scénario ni de capture (aucun client touché). Reste P2.05c. Prochain : P2.04 |
| 2026-10-03 | P2.04a | Lot coupé : a = règles, b = marqueurs affichés. `QuestEngine.can_start` (répétable : `repeatType` 1 tout de suite, 2 et 3 une fois par jour, 0 et -1 jamais deux fois ; `QuestLog.finished_day`, sauvé, jour de `Clock`), `offers` / `markers` prennent le jour ; chaînes = critères `Qf=` (testées). Abandon : `quest_abandon{quest}` (progression perdue, `quest_list` renvoyé, rien de rendu). `map_markers{map, markers: [{kind: offer / goal, quest, npc, map}]}` envoyé à l'arrivée sur une map et à chaque changement de quête. Client : bouton « Abandonner » du journal (capture relue) ; `map_markers` ignoré pour l'instant (P2.04b). 423 tests verts (5 nouveaux), scénario `quest_abandon.jsonl` ; `sim_cli` gagne `quest_abandon:<id>` ; `protocol.gd` repasse sous 800 lignes en retirant une ligne vide entre les constructeurs. | APPROX(P2.04) : sens de `repeatType` et délai quotidien (non dans les données du client, `repeatLimit` vaut toujours 1). Reste P2.04b. Prochain : P2.06 |
| 2026-10-03 | P2.08 | Banque et coffres. `shared/BankRules` (coût d'accès, quantités), `sim/Bank` (kamas + `Inventory`, stocké dans `accounts/<compte>` de `Persistence`, relu à chaque opération, écrit avec le personnage par `Persistence.commit`). `WorldSource.is_banker` + `worlds/<id>/bank.json` (liste des banquiers, `placed` pour poser Ruth Banke à Incarnam). Sim : bouton « Consulter son coffre personnel. » (i18n 913010) ajouté au dialogue du banquier (`Dialog.with_bank`, action `bank`) ou ouverture directe s'il est muet ; `_open_bank` (accès payé, `not_enough_kamas` sinon), `_on_bank_move` / `_on_bank_kamas` (distance, pods au retrait, objet porté refusé, effets conservés), toute autre commande ferme le coffre. Protocole : `bank_move`, `bank_kamas`, `bank_close`, `bank_open`, `bank_update`, `bank_end` + erreur `no_bank` ; `PROTOCOL.md` régénéré. Client : `BankWindow` (deux grilles Sac / Coffre, double-clic, kamas), `client_shot` `npc:<id>` / `bank_in` / `bank_out` / `bank_kamas`. Tests : `test_bank.gd` (13), scénario `bank.jsonl`, `Scenario.RECORDED` gagne les événements `bank_*` ; capture relue (Ruth Banke, objet et kamas déposés). | APPROX(P2.08) : coût d'accès = 1 kama par pile stockée (le texte du banquier dit seulement qu'il dépend du nombre d'objets, aucune formule dans `luaformulas`) ; aucun objet n'est refusé pour liaison ou quête (`items.m_flags` non lu) ; aucun banquier réel à Incarnam (Ruth Banke y est posée à la main, `worlds/incarnam/bank.json`). Pas de coffres de maison ni de lingots (P4 maisons). |
| 2026-10-03 | R.01 | Refactoring sans changement de comportement. `WorldSim` (1 296 lignes) devient un routeur de 392 lignes ; les règles passent dans 7 gestionnaires `RefCounted` hérités de `WorldHandler` : `WorldItems`, `WorldTravel`, `WorldNpcs` (dialogues, boutiques, banque), `WorldQuests`, `WorldJobs`, `WorldDeath`, `WorldFights` (API publique inchangée ; `_player_fighter`, `_quest_event`, `_quest_views` gardés en relais pour les tests). `ClientSession` : les 6 `_pending_*` deviennent un `PendingAction` ; `_dispatch` découpé en `_on_*_event`. `FightRules.zone` (une fonction par famille de formes), `FightEffects._apply` (`_apply_life` / `_apply_buff` / `_apply_removal`, déplacements dans `FightDisplace`), `FightView._apply_effects` (`_effect_vitals` / `_status` / `_world`, textes dans `FightTexts`, FX et porter / lancer dans `FightVisuals`). Nouveau test de taille (<= 800 lignes, aucune exception). 411 tests verts (410 + la règle de taille), aucun scénario réenregistré (tous rejoués identiques), captures PNJ (clic puis dialogue) et porter / lancer relues | Prochain lot de fonctionnalités inchangé. Les plus gros fichiers sont maintenant `protocol.gd` (797) et `fight_view.gd` (773) : à découper avant de les agrandir |
| 2026-10-03 | P1.13p | Codes du serveur déduits de la DESCRIPTION i18n des sorts qui les utilisent (`tools/extractor/trigger_codes.py`, 31 couples code / effet, maintenant tous listés) : `XD` / `XPD` / `XDM` / `XDTB` = `D` / `PD` / `DM` / `DTB` (Pénitence « si elle subit des dommages », Flibuste « dommages de poussée », Couronne d'Épines « subis en mêlée »), `TP` = déplacé (`M` : Férocité « attirée, poussée, transposée, téléportée »), `CPD` = le porteur déplace un combattant (`PO` : Toupet « attire, repousse, échange »), `CMPAS` / `CAPAS` = vol de PM / PA (`CMPA` / `CAPA` : Ronces Agressives « Vole des PM »), `DTB` = dommages d'un poison (début de tour : Distillation), `DTE` connu mais jamais allumé (aucun poison de fin de tour). `FightTriggers.ALIASES` + `_matches`, `spells.py TRIGGERS`, `spells.json` régénéré (`classes --world incarnam+astrub`), 4 tests (`test_trigger_codes.gd`) ; 415 tests, 0 failures, scénarios existants identiques. Pas de capture (aucun rendu nouveau). | APPROX(P1.13p) : sens déduits des textes, pas mesurés sur capture ; la « tentative de retrait de PM » de `TP` n'est pas simulée. Restent inconnus (sans source) : `DV` (Berserk), `CI`, `CT`, `CMPARR`, `CMPDEP`, `CAP`, `TR`, `Y`, `iQ`, `il`, `DI`, `PMD`, `PST` / `PDT`. |
| 2026-10-03 | P2.04b | Marqueurs de quête affichés : `ClientSession._apply_markers` pose un « ! » (offre) ou « ? » (objectif en cours) au-dessus des PNJ (nœud `QuestMark`, réappliqué à l'ajout d'un acteur) et `WorldMapView.quest_mark` dessine un badge doré sur la map du joueur (carte du monde et minimap). Capture relue (Incarnam, PNJ Ternette Nhin). 423 tests, 0 échec. Reste : `map_markers` ne couvre que la map courante, donc pas de marqueur d'objectif sur une autre map (il faudrait des coordonnées de destination côté sim, lot futur). |
| 2026-10-03 | P2.06a | Lot coupé : a = règles + protocole, b = fenêtre cliente. `shared/Crafting` (index des recettes par compétence et ingrédients, cases, grimoire, XP), `sim/WorldCrafting` (atelier = état du joueur, `PlayerActor.craft`), messages `craft_open` / `craft_set` / `craft_do{count}` / `craft_close`, `craft_state{slots, result, max, book}`, `craft_done` ; table légère `recipes` (4858 recettes, 664 Ko). Un craft pose les ingrédients de la recette (quantités exactes), `craft_do{n}` prend n fois et donne n objets aux jets propres (`give_item` un par un), XP de métier, `quests.event item`. 431 tests (8 nouveaux), scénario `craft.jsonl`, `sim_cli` gagne `craft_open/set/do/close`. | APPROX(P2.06) : cases = 2 + niveau/20 (max 8, règle Dofus 2 ; `items.recipeSlots` donne ce qu'une recette demande), XP = 10 + niveau de l'objet par craft (`craftXpRatio` vaut -1 pour 96 % des recettes), aucun élément d'atelier requis (donnée serveur absente), pas de niveau de métier minimum par recette. Reste P2.06b. Prochain : P2.07 |
| 2026-10-03 | P2.06b | Fenêtre d'atelier : `CraftModel` (état testable sans Node) + `CraftWindow` (touche J, sac / cases / résultat / Fabriquer / grimoire, liste des compétences), clic sur un élément de craft = `craft_open`, toast `craft_done`. 4 tests (`test_craft_client.gd`), capture relue (Forger, Épée de Boisaille x2). `client_session.gd` frôle la limite de 800 lignes : le prochain lot client doit en extraire un domaine. Reste : aucun atelier réel sur les maps (APPROX, voir le lot). 435 tests, 0 échec. |
| 2026-10-03 | P2.07a | Lot coupé : a = règles + protocole, b = fenêtre cliente. Aucune formule de forgemagie dans le client (`luaformulas`, tables : vérifié), seules les 195 runes (type 78) sont des données : `gamedata.py items` les garde maintenant toutes. `shared/Smithmagic` (poids, chance, issues crit / success / neutral / fail / overmax, puits, exotiques), `sim/WorldSmithmagic`, messages `fm_apply` / `fm_result`, erreurs `fm_item` / `fm_rune` / `fm_reserve` ; le puits (`reserve`, centièmes de poids) est un champ de l'instance d'objet : jamais empilé avec un objet sans puits, suit l'objet à l'équipement et au coffre. 444 tests (9 nouveaux), scénario `smithmagic.jsonl` (`sim_cli` gagne `fm_apply:<uid>:<rune>`). | APPROX(P2.07) : tout le modèle (voir le lot). Reste P2.07b (fenêtre). |
| 2026-10-03 | P2.07b | Reprise d'un agent arrêté en cours de chaîne : le code de la fenêtre de forgemagie était complet (`SmithmagicModel`, `SmithmagicWindow`, `JobTexts`, touche K, raccourci d'outil `forge` / `forge_pick` / `forge_apply`, `test_smithmagic_client`). Vérifié : import propre, 448 tests, 0 échec, aucune « SCRIPT ERROR » ni « Parse Error », capture de la fenêtre relue. Statut passé à fait. Rien à annuler. | `client_session.gd` reste à 798 lignes : extraire un domaine avant d'y ajouter quoi que ce soit |
| 2026-10-03 | M (plan serveur) | Intégration de `docs/PLAN_SERVEUR.md` : nouvelle phase **M** (avant P1) avec S.01 (complété : WebSocket, `NetBackend`, ping/pong, deux ports), P3.01, S.02a (découpe de S.02 : comptes minimaux), C.01 ContentSource, C.02 paquets de monde et API de contenu, C.03 écran de chargement, X.01 export, puis M2 (P3.02, P3.03, P3.04, S.02b reconnexion, A1.01 console GM et métriques) et M3 (S.03, A1.02 admin web, S.04, S.05, S.07), et G.01 (étude moteur multi-jeux). Les anciens S.01 à S.07 et P3.01 à P3.04 ont quitté leur section (renvois laissés) ; S.06 est remplacé par A1.01 / A1.02. Lots de contenu P2.03b, P2.05c, P2.09 à P2.14 mis en pause (dépendance de calendrier sur X.01, champ « Pause »). `roadmap.py next` propose S.01. Aucun code. | Prochain lot : S.01 |
| 2026-10-03 | S.01 | Serveur headless et `NetBackend`. `src/server/server_host.gd` (`ServerHost` : `TCPServer` + un `WebSocketPeer` par connexion, un `GameSession` chacune, tick du `LocalServer`, trames > 64 Ko refusées, id de monde filtré) et `main.gd` (`godot --headless --path game -s res://src/server/main.gd -- --server --port=7777 --world=a,b --save-dir=… [--bind= --gm= --seconds=]`, arrêt propre sur fermeture : personnages sauvegardés) ; `api/net_backend.gd` (`GameBackend` sur WebSocket, file d'attente avant l'ouverture, erreur `network` au lieu d'une exception, horloge = médiane de 5 `ping`/`pong`, relancée toutes les 10 s et à chaque `hello`, jamais en arrière) ; protocole : `ping{t0}` / `pong{t0, server_ms}` + `E_NETWORK`, `PROTOCOL.md` régénéré ; client : `LaunchScreen` (scène principale `launch.tscn` : Solo, ou adresse:port + monde mémorisés dans `user://launch.cfg`, message si injoignable), `client.tscn` reste la scène des outils ; `FilePersistence` ne crie plus quand le dossier n'existe pas encore ; outils : `client_shot --server=<ip:port>`, `launch_shot.gd`. 12 tests dans `test_net.gd` (serveur dans le même process sur 127.0.0.1 : exploration hello / move / change_map, erreurs avec `ref`, monde inconnu, deux clients, horloge virtuelle et réelle, refus de connexion, coupure serveur, trames invalides, formes d'adresse) + `test_architecture` (rien ne dépend de `server/`) : 460 tests verts (448 avant). Vérifié aussi à la main : serveur incarnam lancé en processus séparé, client fenêtré `--server=127.0.0.1:7791` qui marche, capture relue, serveur arrêté avec « characters saved » | Prochain : P3.01 (plusieurs joueurs sur une map). Reste : `sim_cli` n'a pas de `--connect` (S.07 rejouera les scénarios JSONL via `NetBackend`) |
| 2026-10-03 | P3.01 | Plusieurs joueurs sur une map. La sim était déjà multi-session (`MapInstance.broadcast`, `actor_add/remove/move/look`) : le lot ajoute la fiche publique d'un joueur (`PlayerActor.to_dict` : `breed`, `level`, `life` si fantôme ; liste blanche `PlayerActor.PUBLIC_KEYS`, vérifiée par test), `tests/test_players.gd` (8 tests, deux à quatre `LocalBackend` sur un `LocalServer` : arrivée avec look / classe / niveau, déplacements diffusés dans les deux sens et marche en cours donnée au nouvel arrivant, les joueurs se traversent, départ et arrivée à un changement de map, un joueur en combat n'est plus sur la map ni pour les arrivants puis revient, déconnexion, rien de privé (compte, kamas, stats, inventaire) sur le fil de l'autre, look porté diffusé) et `test_net.gd::test_players_see_each_other_over_websocket` (même flux via deux `NetBackend` : fiche, marche, sortie par une issue, déconnexion, schéma, rien de privé). Client : `client/other_players.gd` (`OtherPlayers` : nom au-dessus de la tête, infobulle nom / niveau / classe, menu clic droit : « Informations » actif, Message privé / Inviter / Défier / Échanger grisés en attendant leur lot) ; `ClientSession` y délègue (sorti `_exit_for` vers `PendingAction.exit_for` pour rester sous 800 lignes : 789) ; `client_shot --mate=<nom>` (second joueur sur le même serveur, `mate:move|goto|change_map|attack`, `hoverplayer`, `playermenu`). `PROTOCOL.md` régénéré. 469 tests verts (460 avant), captures relues (nom, infobulle « Niveau 1 · Pandawa », menu) | Prochain : S.02a (comptes minimaux). Reste : menu contextuel complet avec P3.02 (chat), P3.03 (groupe) ; aucun scénario JSONL (la trace est à une session) |
| 2026-10-03 | S.02a | Comptes minimaux. `server/auth/` : `PasswordHash` (sel 16 octets + SHA-256 itéré 100 000 fois, comparaison en temps constant, nombre de tours stocké avec le hachage), `AccountStore` (`accounts/<login>` via `Persistence`, section `auth` {salt, hash, iterations, role, created} à côté de la banque ; login `[a-z0-9_-]{3,24}` insensible à la casse, mot de passe 6 à 128 caractères ; rôle `player` / `gm`), `AuthService` (jeton de 32 octets en hex, valable tant que la connexion vit, une connexion par compte, `login_for_token` pour C.02). Protocole : `register`, `login`, `login_ok{token, role, login}`, `login_error{code, cmd}` + 7 codes (`bad_credentials`, `login_taken`, `bad_login`, `already_connected`, `not_logged_in`, `registration_closed`, `too_many_attempts`), `PROTOCOL.md` régénéré ; `ServerHost.auth` (null = hôte ouvert comme avant, compte `ip-<adresse>` ; posé = `login` obligatoire avant tout le reste, 5 mots de passe faux coupent la connexion) ; `main.gd` : auth par défaut, `--no-register`, `--no-auth`, `--gm=<login>` ; `NetBackend.token` / `role` ; `LaunchScreen` : identifiant, mot de passe (masqué, jamais mémorisé), « Se connecter » / « Créer un compte », erreur lisible ; la describe() de `Protocol` passe dans `ProtocolDoc` (protocol.gd dépassait 800 lignes). 10 tests dans `test_accounts.gd` (création puis connexion et jeu, mauvais mot de passe = inconnu, double connexion refusée puis libérée, jeton valide puis mort, règles de création, coupure après 5 échecs, rôle gm, aucun mot de passe dans les fichiers, hachage, schémas) : 479 tests verts (469 avant). Vérifié aussi en processus séparé : serveur incarnam, `launch_shot` avec mauvais mot de passe (message rouge relu) puis création de compte (`accounts/jean.json`, partie lancée) | Prochain : C.01. Reste : le nom du personnage reste unique par monde (pas par compte) ; limite de débit par adresse en S.05 |
| 2026-10-03 | C.01 | ContentSource. `shared/content_source.gd` : chemins logiques (`content/`, `data/`, `worlds/<id>/`, `mods/`), deux racines (`res://` en dev et solo, cache `user://worlds/<id>/` quand son `manifest.json` existe, sinon repli sur `res://`), `use_world(id)`, `exists`, `read_bytes/text/json`, `read_result` (erreur claire), `load_image/texture/resource` (PNG / WebP bruts via `Image.load_from_file`), `list_files/dirs`, `on_changed`. `DataFiles`, `GameData`, `SpellBook`, `Mods`, `JsonWorldSource.for_world` lisent par chemins logiques ; `dofus_renderer` reste autonome : nouveau point d'injection `dofus_renderer/content_provider_script` (project.godot) vers `client/content_provider.gd` (`ContentSourceProvider` : mods puis `content/`), `ClientSession` appelle `use_world`. 489 tests verts (479 avant : +9 dans `test_content_source.gd`, +1 `test_architecture` : plus aucun `res://content|data|worlds|mods` hors de la couche) ; capture Incarnam avant / apres identique au pixel pres (seul le compteur de fps du titre differe) | Reste : C.02 (paquets de monde, manifeste, API HTTP) ; le cache est seulement lu, rien ne l'ecrit encore. Prochain : C.02 |
| 2026-10-03 | C.02 | Paquets de monde et API de contenu. `shared/content_manifest.gd` (`ContentManifest`, pur : `make`, `version_of` = SHA-256 des lignes `chemin:hash` triées, `validate` (format, chemins sûrs sans `..` ni absolu, hash, version), `diff`, `stale`, `unique_blobs`, globs). `server/world_package.gd` (`WorldPackage.build(id, racine, dossier)` : `worlds/<id>/**` sans les fichiers `_*`, `data/**`, plus les globs de `world.json` `content` ; `name` et `module` lus dans `world.json` ; cache `index.json` (date, taille, hash) : seuls les fichiers modifiés sont re-hachés ; aucune copie, les octets sont servis là où ils sont ; dossier configurable `--package-dir`) ; `api/file_hash.gd`. `server/http_server.gd` (HTTP/1.1 à la main sur `TCPServer`, GET, `Connection: close`, fichiers par blocs de 1 Mo) et `server/content_api.gd` (`/worlds`, `/worlds/<id>/manifest.json`, `/worlds/<id>/files/<hash>` : `Authorization: Bearer` = jeton de `login_ok`, 401 sinon et sans rien révéler ; liste blanche = hash du manifeste, 404 pour le reste (`..`, chemin, hash en capitales, monde inconnu) ; `Content-Length`, `ETag`, `Range` 206 / 416 ; 409 si le fichier a changé depuis la construction). `ServerHost.listen_http` ; `main.gd` : `--http-port`, `--package-dir`, `--content-root`, `--build-packages`, `--rebuild`. Client sans écran : `client/http_fetch.gd` (GET non bloquant) et `client/content_client.gd` (`list_worlds`, `fetch_manifest`, `diff`, `download`, `update` : `.part` repris par `Range`, SHA-256 vérifié avant le renommage, doublons de contenu téléchargés une fois, fichiers périmés supprimés, `progress.json` de reprise, `manifest.json` écrit en dernier) ; `ContentSource.cache_relative`. 21 tests dans `test_content_api.gd` (manifeste stable et sensible à un octet, rien hors du paquet, `diff`, `Range`, 401 sans jeton / jeton inconnu / serveur sans comptes, liste blanche, 409, trois requêtes simultanées, jeton d'un vrai login WebSocket puis mort avec la connexion, téléchargement dans le cache puis lu par `ContentSource`, reprise, hash faux rejeté, manifeste dangereux refusé, mise à jour avec suppression, paquet réel d'Incarnam) : 510 tests verts (489 avant). Vérifié en processus séparés : serveur incarnam `--http-port`, client qui s'inscrit, puis télécharge les 104 fichiers (14 Mo) ; 2e mise à jour = 0 fichier ; `curl` sans jeton = 401 | Reste : C.02b (choix des assets d'un monde : sans globs le paquet ne contient que les données). Pas de capture : aucun écran avant C.03 |
| 2026-10-03 | C.03 | Écran de chargement client. `client/world_loader.gd` (`WorldLoader`, modèle sans Node : `refresh` = liste des mondes + manifeste de chacun comparé au cache, statuts `current` / `new` / `partial` / `update` ; `install` = espace disque vérifié d'abord, puis seulement le manquant, progression (fichiers, octets, vitesse) ; `cancel` ; `launch` = `ContentSource.use_world` une fois le cache complet), `world_load_screen.gd` (liste, boutons Jouer / Télécharger / Reprendre / Mettre à jour, barre, Annuler / Réessayer / Retour ; appels bloquants dans un `Thread`), `disk_space.gd`. `LaunchScreen` : après `login_ok` il ouvre l'écran de chargement (le champ « monde » disparaît, le dernier monde choisi est mémorisé et surligné). `ContentClient` : `cancel_requested`, `verify_cache` (SHA-256 complet après une coupure), débit réglable (captures) ; `HttpFetch.abort`. `ContentSource._notify` ignore les rappels dont le propriétaire est libéré. 9 tests dans `test_world_loader.gd` (premier lancement = tout puis rien ; un fichier changé = un fichier ; annulation puis reprise ; disque plein refusé avant de commencer ; fichier abîmé trouvé après une coupure ; jeton d'un vrai login WebSocket ; erreurs en clair ; écran piloté jusqu'à `world_ready` ; textes) : 519 tests verts (510 avant). Capture relue avec un serveur Incarnam réel : liste (Incarnam, Monde de test), barre à 47 % (6,5 / 13,7 Mo, 28 Mo/s), 2e lancement « À jour · Jouer » | Reste : C.02b (assets). |
| 2026-10-03 | Bug combat (hors lot) | « Après deux morts d'ennemis, un des ennemis a arrêté de jouer » (serveur). Reproduit avec `tools/fight_stress.gd` (nouveau : IA contre IA, 19 classes x niveaux x graines, signale les ennemis sans action pendant 3 tours, les combats sans fin, un mort qui garde le tour) : le dernier ennemi blessé d'un profil prudent / soigneur / invocateur (< 30 % de PV) fuyait sans fin, et une fois acculé terminait chaque tour sans rien faire ; de plus un monstre bloqué derrière un obstacle (minimum local de la distance à vol d'oiseau) ou un tireur sans ligne de vue à sa portée idéale restaient immobiles. Corrigé dans `FightAI` : fuite limitée à `FLEE_MAX_TURNS` = 3 tours (`Fighter.flee_turns`), repli au combat si rien n'a pu être fait du tour, `_detour` (case atteignable la plus proche par le chemin réel), approche quand aucun sort n'est lançable avec tous ses PA. Côté client : `SequenceGuard` + `FightView.watchdog` (une séquence animée qui n'émet jamais `sequence_done` bloquait tous les événements suivants : délai de sécurité 15 s, jeton d'époque pour ignorer la fin tardive), `_slide` ignore un chemin sans pas (un Tween vide ne finit jamais). Tests : 535 tests, 0 échec (+7 : `test_ai_profiles` x4, `test_net` (survivant blessé dans un coin, via NetBackend), `test_fight_view` x2) ; les deux tests de régression échouent bien sans le correctif. Stress après correctif : 171 combats incarnam (19 classes, niveaux 5/30/80, 3 graines) + 4 dans `dofus`, plus aucun ennemi inactif ; restent des combats lents où c'est le joueur IA qui n'avance pas (pas un défaut des ennemis). | APPROX(P1.16) : fuite plafonnée à 3 tours (les monstres Dofus ne fuient pas). Non confirmé : la cause côté client (séquence bloquée) n'a pas été reproduite, seulement gardée par le watchdog ; si le bug revient, chercher `FightView: a sequence lasted` dans la sortie du client. |
| 2026-10-03 | X.01 | `game/export_presets.cfg` (Client : exe unique sans `content/`, `data/`, `worlds/`, `mods/` ; Serveur : exe + console), `tools/build_release.py` (espace C:, modèles, `--import`, deux exports, `worlds/` et `data/` copiés, `content/` en jonction, `override.cfg`, `--zip`, `--smoke`), `tools/release/` (`serveur-lancer.bat`, `LISEZMOI.txt` pour les amis), `docs/EXPORT.md`. Serveur : logique déplacée dans `ServerApp` (nœud, `scenes/server/server.tscn`) car un export ignore `-s` ; `main.gd` n'est plus que l'entrée `-s` ; `--check` (`ServerCheck`) ; `ContentSource.set_dev_root` (racine des données à côté de l'exe). Client : pas de bouton Solo sans monde local (`LaunchScreen.solo_available`), `AutoRun` (`--auto-connect=…`) pour piloter un client exporté. Vérifié : serveur exporté démarre (ports 7791/7792), client exporté crée le compte, télécharge `test`, affiche la map (capture relue) ; `test_release.gd` (6 tests) ; 525 tests, 0 échec. Client : exe 105 Mo, zip 39 Mo. | Prochain : C.02b |
| 2026-10-03 | C.02b | Assets d'un monde dans le paquet : `server/world_assets.gd` + `tools/world_assets.gd` écrivent `worlds/<id>/_content.json` (globs), lu par `WorldPackage`. Incarnam 1,87 Go au lieu de 22 Go ; trace `ContentSource` de 5 sessions client : 3113 chemins, 0 hors paquet ; client exporté joue depuis le cache. Reprise : un `any()` sur `PackedStringArray` dans `test_content_api.gd` (parse error, ce fichier n'était plus chargé : 507 tests) corrigé : 528 tests, 0 échec, aucune SCRIPT ERROR. Pas de capture ni sim_cli (sans objet) | Reste : C.02c (téléchargement plus rapide, skins d'objets par monde) |
| 2026-10-03 | P3.02a | Chat, premier morceau (le lot est coupé : P3.02b garde groupe / guilde / alliance, liens d'objets, smileys, sourdine). `shared/chat.gd` (`Chat` : canaux et raccourcis de la table `chatchannels`, `parse` des commandes `/s /b /r /w /t…`, nettoyage, anti-flood), `sim/world_chat.gd` (`WorldChat` : routage général = la map ou, en combat, les combattants ; commerce et recrutement = le monde ; privé avec écho à l'expéditeur ; `player_offline` pour un absent ou soi-même ; journal borné à 200), protocole `chat_send{channel, text, to?}` / `chat_msg{channel, from, from_id, text, at, to?}` + erreurs `chat_flood`, `channel_unavailable`, `player_offline` (PROTOCOL.md régénéré ; `protocol.gd` à 799 lignes : le prochain message doit en sortir du code). Client : `ChatPanel` (onglets Général / Privé / Commerce / Recrutement, remplace la ligne de commande : les mots sans canal comme `/tp` restent des commandes GM), `ChatBubble` (5 s au-dessus du personnage), texte du joueur échappé en BBCode ; `client_shot say:<ligne>` et `mate:say:<ligne>`. `tests/test_chat.gd` : 12 tests (règles pures, routage, privé hors ligne, flood, combat, journal, ligne client, flux complet par deux `NetBackend` sur 127.0.0.1) : 549 tests verts (537 avant), 0 échec, capture relue (bulle, onglets) | Prochain : P3.03 (groupes). Reste P3.02b |
| 2026-10-03 | P3.03a | Groupes, premier morceau (le lot est coupé : P3.03b garde le client, cadre du groupe et marqueurs). `shared/party.gd` (`Party`, règles pures : 8 membres, chef = premier, exclusion, commandement), `shared/protocol_party.gd` (`ProtocolParty` : messages, schéma, erreurs, constructeurs ; `protocol.gd` était à 799 lignes, `Protocol.validate`, `ERROR_CODES` et `protocol_doc.gd` lisent aussi cette table), `sim/world_party.gd` (`WorldParty` : invitations valables 60 s, accepter / refuser, quitter, exclure, passer le commandement, suivre, `party_update` envoyé quand la composition, la carte, le combat ou les PV changent, au plus une fois par seconde ; quitter le jeu quitte le groupe). Branchement dans `WorldSim` (commandes `party_*` acceptées aussi en combat, `teleport` appelle `on_moved`). `tests/test_party.gd` : 16 tests dont le flux par deux `NetBackend` (549 -> 565 tests, 0 échec). `docs/PROTOCOL.md` régénéré. Reste : P3.03b (client), `/p` (P3.02b), bonus d'XP effectif à plusieurs en P3.04 (le calcul `FightRewards` compte déjà les joueurs du combat). |
| 2026-10-03 | P3.04a | Combats à plusieurs, premier morceau (le lot est coupé : P3.04b garde le client ; P3.04 dépendait de P1.15, fait mais `doing` derrière P1.14 : dépendance relâchée). `shared/protocol_watch.gd` (`ProtocolWatch` : `fight_join`, `fight_spectate`, `fight_watch`, `fighter_joined`, `fighter_left`, 5 erreurs ; `protocol.gd` reste à 799 lignes, `validate`, `ERROR_CODES`, `protocol_doc.gd` lisent la table), `Fight.join / spectate / team_size / watch_dict` et `Fighter.left`, `sim/fight_actor.gd` (épées de la map), `sim/world_fight_watch.gd` (`WorldFightWatch` : acteur « combat » créé au début et renvoyé quand équipes, phase ou options changent, rejoindre, regarder, quitter, fuite, fin de combat), branchement dans `WorldSim` (un spectateur ne peut que `fight_leave`, chat et groupe ; `disconnect_player` ne termine plus un combat où d'autres joueurs restent). `FightRewards` et `_reward_players` ignorent les fuyards. `tests/test_fight_join.gd` : 18 tests dont le flux par trois `NetBackend` (565 -> 583, 0 échec). `docs/PROTOCOL.md` régénéré. Reste : P3.04b (client), agression d'un groupe avec plusieurs joueurs dans la zone (APPROX : toujours un seul agressé, les autres rejoignent via les épées), IA qui reprend un déconnecté (S.02b). | APPROX(P3.04) : 8 par équipe ; spectateur sans siège (ne voit pas les invisibles) ; déconnexion = fuite (compte comme mort, sans gain) au lieu de « passe son tour puis IA ». Prochain : P3.04b ou P3.02b |
| 2026-10-04 | P3.04b | Combats à plusieurs, client. `client/fight_swords.gd` (`FightSwords` : épées dessinées avec la palette du kit, « n vs m », menu au clic gauche ou droit : « Rejoindre » (placement, non verrouillé) / « Regarder » (non secret)), `client/fight_flow.gd` (`FightFlow` : vie de la vue de combat sortie de `client_session.gd`, 793 -> 785 lignes : `fight_start`, `fight_watch`, `fighter_joined`, `fighter_left`, `fight_end`), `FightView.spectator / on_joined / on_left`, `FightHud` sans barre de sorts ni bouton « Prêt » pour un spectateur (bouton « Quitter » = `fight_leave`), `fight_end` sans fenêtre de gains pour un spectateur, un fuyard ou une sortie (bandeau à la place), chat visible pendant un combat (Entrée l'ouvre, placé sous les défis). `FightVisuals.procedural_fx / dofus_fx` sortis de `fight_view.gd` (820 -> 792 lignes). `tests/test_fight_watch_client.gd` : 3 tests (épées après JSON, droits du menu, flux complet avec de vraies `ClientSession` : voir les épées, regarder, rejoindre, voir arriver et partir, sortir) ; `tests/run_tests.gd` tourne désormais au premier cadre (la racine n'est pas dans l'arbre avant) et attend les tâches de `DofusContent.preload_clips` (`DofusContent.wait_preloads`) avant de quitter : un `ActorView` créé en test faisait planter le moteur à la sortie (segfault, code 139) ; `client_shot` fait pareil. `client_shot` : `join`, `watch`, `swordsmenu` (+ `mate:attack` existant). Captures relues : épées + menu, placement après avoir rejoint (2 joueurs, chat sous les défis), vue spectateur. 583 -> 622 tests, 0 échec (les autres lots ont ajouté le reste). Reste : onglet « Équipe » du chat (`/t`) et chat des spectateurs (P3.02b), vraie texture des épées (le client Dofus n'en donne pas d'extraite ; dessin en code), info-bulle des épées (liste des combattants). Dette : la session de test tourne sur `LocalBackend` (le flux WebSocket au niveau protocole est `test_fight_join::test_join_and_watch_over_websocket`) : une `ClientSession` sur `NetBackend` dans les tests n'a pas été essayée jusqu'au bout (le segfault, cause trouvée seulement ensuite, la masquait) ; à reprendre avec S.07. | Aucun APPROX nouveau. Prochain : P3.02b ou S.03 |
| 2026-10-03 | S.02b | Reconnexion, côté sim et serveur (le lot est coupé : S.02c garde le client : reconnexion automatique et bandeau ; `client_session.gd` est à 799 lignes). Sim : `Fighter.absent_since` / `ai_takeover`, `Fight.set_absent` (au placement le joueur absent est prêt) / `set_present`, `Fight.tick` : le tour d'un absent est passé aussitôt, puis l'IA joue pour lui après `ABSENT_GRACE_MS` (60 s) ; `sim/world_resume.gd` (`WorldResume` : `detach` garde un combattant dans son combat, `reattach` vide l'outbox périmée et renvoie welcome, stats, inventaire, quêtes, `fight_start`, options, défis, `fight_begin`, `fight_turn` ; `tick` libère un détaché dont le combat est fini), `PlayerActor.detached`. `GameSession.detach()` / `resume()` (retient `last_world` / `last_name` : hors combat rien n'est gardé, la reprise rejoue la connexion du même personnage, la map et la cellule viennent de la sauvegarde ; avant le choix, la liste des personnages). Serveur : `AuthService.park / resume / expire / is_parked` (`park_ttl_ms` 10 min), `ServerHost` : une coupure sans logout (code de fermeture différent de 1000) parque la session, `NetBackend.close()` (1000) = déconnexion propre, `resume{token}` -> `resume_ok{token, role, login, state{world, name, playing, in_fight}}` puis les événements, `login` avec le bon mot de passe sur une session parquée rend la même session (`login_ok` puis `resume_ok`), une connexion silencieuse depuis `idle_ms` (20 s) est remplacée par `login` ou `resume`, sinon `already_connected` ; 5 jetons faux coupent la connexion ; `bad_token` ; le `NetBackend` en échec ferme en 4000 (pas 1000). `shared/protocol_resume.gd` (protocol.gd reste à 799 lignes), `PROTOCOL.md` régénéré. `tests/test_resume.gd` (15 : règles de la sim, flux complet par `NetBackend` sur 127.0.0.1, expiration, logout, double connexion active / inactive, schéma) : 598 tests verts (583 avant), 0 échec | APPROX(S.02b) : 60 s de grâce, 10 min de jeton, 20 s d'inactivité (aucune source Dofus) ; un joueur détaché reste dans `players` (chat privé, groupe) ; hors combat, une coupure fait quitter la map aussitôt. Sans `sim_cli` ni capture (pas d'écran). Prochain : S.02c |
| 2026-10-04 | S.02c | Reconnexion automatique du client. `NetBackend` : `auto_reconnect` (activé par `LaunchScreen`), état `reconnecting`, `_lose` (coupure après login : jeton connu, pas `close()`, pas de code 4001 / 4003) puis `_try_again` aux délais 1, 2, 4, 8 s puis 8 s, `resume{token}` envoyé en premier sur la nouvelle connexion, commandes jetées pendant la coupure, `resume_ok` remet `attempt` à 0, `login_error` pendant la reprise : `already_connected` = on réessaie, sinon (`bad_token`) fin avec `failure` = le code. Nouveau message de transport `net_reconnecting{attempt, delay_ms, reason}` (`ProtocolResume`, `PROTOCOL.md` régénéré). Client : `client/session_link.gd` (`SessionLink` : bandeau, oubli du combat et des fenêtres à `resume_ok`, retour à l'écran de lancement avec le message sur `bad_token` ou fin de lien si `back_to_launch`), `client/reconnect_banner.gd` (kit UI), `client/quest_events.gd` (sorti de `client_session.gd`, 799 -> 789 lignes), `LaunchScreen.notice`. `tests/test_reconnect.gd` : 9 tests par `NetBackend` sur 127.0.0.1 (coupure puis retour et combat rejoué, délais, jeton expiré, close, retrait, option absente, avant login, bandeau) : 614 tests verts (598 avant), 0 échec. Capture `tools/banner_shot.gd` relue | APPROX(S.02c) : délais 1, 2, 4, 8 s (aucune source Dofus) ; pas de limite du nombre d'essais (le jeton expire côté serveur, bad_token met fin). Reste : le bandeau n'a pas été vu dans une vraie session (pas de `client_shot` avec coupure). Prochain : P3.02b ou P1.15 |
| 2026-10-03 | A1.01a | Console GM, premier morceau (le lot est coupé : A1.01b garde les métriques HTTP). `sim/world_admin.gd` (`WorldAdmin` : tp, give, kamas, level, heal, say, who, kick, ban, unban, mute, unmute, reload ; rôle vérifié dans la sim, hors combat ; audit en mémoire + `audit_sink`), `sim/sanctions.gd` (ban / mute par compte, dans le document du compte), `shared/protocol_admin.gd` (`admin_result`, `announce`, erreurs `banned` / `muted` / `kicked` ; `protocol.gd` reste à 799 lignes), `server/admin/audit_log.gd` (`--audit-log`, JSON par ligne), `WorldSim.kick_player`, `GameSession.kicked` + `ServerHost` (ferme la socket après 300 ms), `AuthService` (login / resume d'un banni refusés). Client : résultats et annonces dans l'onglet Général du chat, `/help`, virgule = séparateur seulement pour `/tp` ; `ClientSession` 798 lignes. `sim_cli --cmd=100:admin:give:683:3`. Vérifié : `tests/test_admin.gd` (8 tests dont le flux par `NetBackend` avec comptes, kick qui coupe la vraie socket, ban refusé au login, fichier d'audit), capture `client_shot` relue (give, level, who, say, commande inconnue, /help), `PROTOCOL.md` régénéré ; 606 tests, 0 échec, aucune SCRIPT ERROR. Pas de scénario enregistré (aucune règle de jeu). | Reste : A1.01b (métriques) |
| 2026-10-04 | P3.03b | Groupes, client. `client/party_frame.gd` (`PartyFrame`, dans `PlayerHud.party`, sous le nom de la map) : une ligne par membre (symbole de classe, nom, niveau, barre de PV, étoile du chef, « (suivi) », coordonnées si autre map, « en combat »), clic sur une ligne = menu (Suivre / Ne plus suivre ; le chef : Passer le commandement, Exclure), bouton Quitter, invitations reçues en cartes Accepter / Refuser (expirent après 60 s comme la sim), toasts (refus, exclusion, dissolution) ; marqueur (pastille or pour le chef, bleue sinon) au-dessus du sprite des membres présents sur la map (`sync_marks`, rappelé à chaque `actor_*`). Routage : `ClientSession._dispatch` envoie les 4 `party_*` à `PartyFrame.on_event` (+4 lignes, 793 au total). `OtherPlayers.menu` : « Inviter dans le groupe » actif (`party_invite`). `client_shot` : `mate:invite`, `partyaccept`, `inviteplayer`, `invitemenu`. `tests/test_party_client.gd` : 5 tests (événements, textes, invitations et expiration, marqueurs, flux complet par deux `NetBackend`). Capture relue (cadre à deux membres, pastille, menu avec l'entrée active). Reste : `/p` du chat (P3.02b), flèche vers la sortie pour un membre d'une autre map (non faite : coordonnées affichées à la place). |
| 2026-10-04 | A1.01b | Métriques HTTP. `server/admin/metrics.gd` (`ServerMetrics` : fenêtre de 600 durées de poll, moyenne et max, instantané des sims), `server/admin/admin_api.gd` (`AdminApi` : `GET /admin/metrics`, jeton admin comparé en temps constant), `ServerHost._route` (admin vs contenu), `--admin-token=` / `SUPERDOFUS_ADMIN_TOKEN` dans `ServerApp`. Vérifié : `tests/test_admin_metrics.gd` (2 clients `NetBackend` : joueurs 2, maps actives 1 puis 2, combat 1 ; 404 sans jeton configuré, 401 sans jeton / mauvais jeton / jeton de session ; le jeton admin n'ouvre pas le contenu ; JSON valide ; fenêtre bornée). Doc : « Métriques d'administration » dans ARCHITECTURE. | A1.01 terminé |
| 2026-10-04 | A1.02a | Admin web, premier morceau (le lot est coupé : A1.02b garde debug, mondes et contenu). Page `server/admin/web/index.html` (publique, demande le jeton, vue d'ensemble rafraîchie toutes les 5 s, comptes, fiches, actions, audit, maintenance), routes `/admin/overview`, `accounts`, `account`, `character`, `audit` et `POST /admin/action` (`AdminViews`, `AdminActions`, `AdminApi`), `WorldAdmin.run_web` (même règles et même audit que la console GM, GM transitoire `web-admin`), `AccountStore.set_password` / `note_seen` / `logins`, `ServerHost` note la dernière connexion (heure, adresse), `HttpServer` lit un corps de requête (16 Ko, 413), `HttpFetch.start_post`, export : `include_filter="*.html"`. Vérifié : `tests/test_admin_web.gd` (3 tests : 401 / 404 / 405 / 400 / 413, deux clients `NetBackend` sur 127.0.0.1, fiche = sauvegarde, 13 actions avec ligne d'audit, ban refusé au login) ; 640 tests, 0 échec, aucune SCRIPT ERROR ; syntaxe JS de la page vérifiée avec `node --check`. Pas de capture : la page n'a pas été ouverte dans un navigateur (dette, à faire en A1.02b). | Reste : A1.02b |
| 2026-10-04 | essai | Essai bout en bout, hors lot (`docs/ESSAI_SERVEUR.md`) : vrai serveur headless (incarnam, `--gm`, dossier temporaire, ports 7791 / 7792) et deux comptes `NetBackend` pilotés par `tools/essai_serveur.gd` (+ `essai_peer.gd`) : inscription / connexion, personnages, déplacements croisés, chat map et `/w`, groupe et suivi, combat solo, combat à deux (rejoindre, spectateur, fuite), boutique, banque, quête, récolte, coupure en combat puis reprise, console GM, API de contenu : 94 OK, 4 MANQUE (`/p`, échange, amis, guilde), 0 bug restant. Deux bugs corrigés avec test de régression (`test_admin.gd`) : `login_ok.role` ne disait pas `gm` pour un compte de `--gm` ; `admin_cmd` refusait les nombres JSON (`683.0`). Arrêt propre du serveur vérifié. | Lot P3.11 (échange entre joueurs) ajouté. 626 tests, 0 failures. |
| 2026-10-04 | P3.11a | Échange entre joueurs, premier morceau (le lot est coupé : P3.11b garde le client). `shared/trade_rules.gd` (`TradeRules` : lignes normalisées, offre vérifiée contre le sac et la bourse, poids), `shared/protocol_trade.gd` (`ProtocolTrade` : 6 commandes, 4 événements, 3 erreurs ; `protocol.gd` reste à 799 lignes : `validate` et `ERROR_CODES` lisent la table, `protocol_doc.gd` et le fuzz de `test_security` aussi ; `docs/PROTOCOL.md` régénéré), `sim/trade_session.gd` (état d'un échange : offres, validations), `sim/world_trade.gd` (`WorldTrade` : invitation 60 s, un seul échange par joueur, même map, ni combat ni fantôme ni fenêtre ouverte ; `trade_set` remplace l'offre et annule les deux validations ; à la validation chaque côté est revérifié (objets toujours là, non portés, kamas, poids des deux sacs) puis les deux personnages sont écrits dans un seul `Persistence.commit` ; sac plein = `overloaded` sans rien perdre ; journal `log` + `sim.admin.audit_sink` : une entrée `cmd: trade` par échange ouvert, réussi ou non). Branchement `WorldSim` : commandes `trade_*` hors combat ; toute autre commande d'un joueur en échange l'annule (`action`), `teleport` (`moved`), début de combat ou rejoindre (`fight`), `disconnect_player` (`disconnected`). `tests/test_trade.gd` : 16 tests dont le flux par deux `NetBackend` ; `tools/essai_serveur.gd` : la sonde passe à un scénario réel (`tools/essai_trade.gd`, le script dépassait 800 lignes). Piège : un test qui change `SpellBook.use_file` doit le remettre (`use_file("")`), sinon le test réel qui suit (`test_travel`, ordre alphabétique) combat avec les sorts de test. 675 tests, 0 failures (avant : 626 + les autres lots ; sondes de l'essai : l'échange passe de MANQUE à OK). Reste : P3.11b (client). | APPROX(P3.11) : durée d'invitation 60 s, 20 piles et 100000 par ligne (rien dans les tables ni `luaformulas`) ; pas de limite de distance autre que « même map » ; pas d'objets liés / de quête refusés (`items.m_flags` non lu, comme la banque) ; un échange ouvert n'expire pas. Prochain : P3.11b ou P3.02b |
| 2026-10-04 | S.03 | `server/persistence/server_persistence.gd` (`ServerPersistence` étend `FilePersistence`) : écriture atomique (tmp relu et vérifié, puis renommage), copies tournantes dans `<save-dir>/_backups/<collection>/<clé>/<ms>.json` (10 dernières, une par 5 min et par document, une copie forcée à la suppression), reprise d'un document illisible depuis sa dernière copie valide (`recovered`), `restore(collection, clé, stamp)`, `sweep_tmp` au démarrage ; sauvegarde périodique des personnages connectés (`ServerHost.autosave_ms`, `LocalServer.save_all`) ; options `--autosave= --backups= --backup-interval=` ; `tests/test_server_persistence.gd` (10 tests dont un via `NetBackend` 127.0.0.1) ; 637 tests, 0 échec | SQLite (HDV, échanges) si le besoin apparaît ; commande GM de restauration (`admin_cmd restore`) non faite |
| 2026-10-04 | S.04a | Plusieurs mondes sur un serveur (le lot est coupé : S.04b garde les instances d'un même contenu). `shared/protocol_cluster.gd` (`server_list` / `servers`, erreur `world_closed`), `server/cluster/world_cluster.gd` (`list`, `start`, `stop`), `ServerHost.cluster` + `close_world_sessions` + `pin_allowed`, `GameSession.world_closed`, actions admin `world_start` / `world_stop` (auditées) et `GET /admin/worlds` + section Mondes de la page, `/worlds` de l'API de contenu porte `players`, l'écran de chargement l'affiche, `ServerApp` construit le paquet d'un monde ouvert à chaud. `tests/test_cluster.gd` : 5 tests, 645 tests au total, 0 échec. Reste : capture de l'écran de chargement, S.04b. | Prochain lot : S.04b |
| 2026-10-04 | S.05a | Sécurité, premier morceau (le lot est coupé : S.05b garde l'audit des échanges, la fuite d'information et les mots de passe). `server/security/rate_limiter.gd` (`RateLimiter` : seau à jetons, temps donné par l'hôte), `shared/protocol_security.gd` (`rate_limited`), `ServerHost` : seau par connexion (60 puis 30 / s), 20 refus d'affilée = coupure 1008, 16 connexions par adresse, seau de 30 tentatives de login / register / resume par adresse (0,5 / s), compteurs `refused_rate` / `refused_connections`, limites réglables (`rate_burst`…) ; texte client dans `ErrorTexts` ; `PROTOCOL.md` régénéré. `tests/test_security.gd` : 11 tests dont le fuzz des commandes (2400 messages tirés du SCHEMA, valeurs plausibles ou absurdes, en combat ou non), les déchets binaires / JSON sur le fil et les chemins hostiles de l'API de contenu : 656 tests (645 avant), 0 échec, aucun SCRIPT ERROR | APPROX(S.05) : toutes les limites. Prochain : S.05b ou P3.02b |
| 2026-10-04 | S.07 | Parité standalone / serveur. `tests/test_scenarios_net.gd` : chaque scénario JSONL est rejoué à travers un vrai `ServerHost` (127.0.0.1) et un `NetBackend` (classe `NetRig`, horloge virtuelle), mêmes événements attendus dans le même ordre que `LocalBackend`, schéma validé ; un scénario à deux joueurs (hello, marche, chat, changement de map, déconnexion) donne les mêmes événements aux deux clients sur un `LocalServer` partagé et sur le serveur réseau. `Scenario.run` accepte tout backend avec `prepare_scenario(header)` ; `Scenario.check(events, ignore_time)`. Reste : option `sim_cli --server`. Lot terminé. |
| 2026-10-04 | P3.05a | Amis, ennemis, ignorés, premier morceau (le lot est coupé : P3.05b garde la fenêtre du client). `shared/contacts.gd` (`Contacts`, règles pures : trois listes, 100 entrées, un joueur sur une seule liste, soi-même refusé), `shared/protocol_contacts.gd` (`contacts_get` / `contact_add` / `contact_remove`, `contacts`, `contact_status`, cinq erreurs ; ajouté à `Protocol.validate`, `ERROR_CODES` et `protocol_doc`), `sim/world_contacts.gd` (`WorldContacts` : listes dans le document de compte via `Persistence`, résolution du nom parmi les connectés puis les sauvegardes du monde, notices aux amis à la connexion et à la déconnexion du dernier personnage du compte, filtre `ignores` appelé par `WorldChat`). Les listes ne sont envoyées à la connexion que si le compte a un contact (les scénarios enregistrés ne changent pas). `error_texts.gd` complété. 686 tests verts (+11, `test_contacts.gd`, dont un flux à deux comptes par `NetBackend`), `docs/PROTOCOL.md` régénéré. | P3.05b (fenêtre, capture), filtrer aussi invitations de groupe et d'échange des ignorés. |
| 2026-10-05 | C.04 | Dossier des mondes configurable. `ContentSource.set_cache_base`, `ContentFolder` (résolution `--content-dir` > mémorisé > ancien `user://worlds`, validation, migration), `ContentFolderScreen` (premier lancement + « Changer… »), messages de `WorldLoader` pour disque absent / plein. 696 tests, 0 échec (+7). Reste : progression d'un déplacement entre disques. |
| 2026-10-05 | C.05 | Zip de base par monde. `shared/content_bundle.gd` (partition déduite du manifeste : 256 Mo et 400 contenus par partie au plus), `server/world_bundle.gd` (zips `part-NNN.zip`, entrées nommées par hash, images stockées, reconstruits seulement si la version change), routes `bundle.json` et `bundle/<part>` de `ContentApi` (jeton, Range, liste blanche), `ContentClient.install_bundle` (reprise par Range, empreinte du zip refusée si fausse, décompression `ZIPReader` vérifiée contre le manifeste, reprise après coupure en pleine décompression), `WorldLoader` (phases archive / décompression / fichiers, temps restant, repli sur les fichiers si le zip est inutilisable), `--bundle-mb` / `--no-bundle`. Tests : `test_content_bundle.gd` (7), 703 tests, 0 échec (696 avant). **Mesure Incarnam** (19 880 fichiers, 1 881 Mo) : zip de **981 Mo en 8 parties** (52 %), construit en 20 s ; installation complète en local (client et serveur dans un processus, Windows, disque C:) : **165 s** par le zip (archive 15 s, décompression ~150 s) contre ~10 min fichier par fichier (échantillon de 1 500 fichiers : 32 fichiers/s, 5,8 Mo/s, soit ~620 s pour 19 880) ; sur Hamachi le gain est surtout en octets (981 Mo au lieu de 1 881 Mo) et en requêtes (8 au lieu de 19 880). Reste : une barre de progression de la construction côté serveur (quelques secondes), la décompression reste liée au coût des petits fichiers sous Windows. |
| 2026-10-05 | P3.05b | Amis, fenêtre du client. `client/contacts_model.gd` (listes, texte des notices, commandes de chat `/friend /enemy /ignore` et `/unfriend /unenemy /unignore`), `client/contacts_window.gd` (`ContactsWindow`, touche F : trois onglets, pastille en ligne, niveau et classe, Chuchoter, retirer, ajout par nom ; rouvrir redemande les listes), `ClientSession` route `contacts` / `contact_status` (toast de connexion), menu d'un joueur : Message privé (ouvre `/w nom `), Ajouter en ami, Ignorer. Sim : `WorldParty` et `WorldTrade` ne transmettent plus l'invitation d'un joueur ignoré (silence, comme le chat). `client_shot` : `friends[:kind]`, `friend_add|enemy_add|ignore_add:<nom>` ; le mate a son propre compte. `tests/test_contacts_client.gd` (+5 tests, flux `NetBackend` compris), capture relue. `tests/run_tests.gd` : `TEST_SKIP=<sous-chaîne>`. | Rien pour ce lot. |
| 2026-10-04 | S.05b | Sécurité, deuxième morceau (le lot est coupé : S.05c garde mots de passe, débit par session, sanction automatique). Audit : les échanges étaient déjà audités (P3.11a), vérifiés de bout en bout dans le fichier d'audit (2 clients WebSocket). Fuite corrigée : `fight_start` de la reprise, `fight_start` d'un joueur qui rejoint et `watch` d'un spectateur donnaient la case d'un invisible ; ils passent maintenant par `FightVisibility.view`. `tests/test_security_audit.gd` : 3 tests, suite à 689 tests, 0 échec, aucun SCRIPT ERROR | Prochain : S.05c ou P3.02b |
| 2026-10-05 | P3.11b | Échange, client. `client/trade_model.gd` (`TradeModel`, sans nœud), `trade_window.gd` (fenêtre : mon offre, celle de l'autre, sac en bas, double-clic pour poser / reprendre, kamas + Poser, Valider / Annuler, état « Validé » des deux côtés ; fermer = annuler), `trade_invites.gd` (cartes Accepter / Refuser sous le groupe), entrée « Échanger » du menu d'un joueur, branchements `PlayerHud` / `ClientSession` (`trade_*`, bourse et sac suivis). `client_shot` : `trade`, `tradeaccept`, `tradeput`, `tradekamas`, `tradeready`, `mate:give`, `mate:trade`, `mate:tradeput`, `mate:tradeready` ; capture relue (offres des deux côtés, kamas, validé). `run_tests.gd` : `TEST_ONLY=<fichier>`. `tests/test_trade_client.gd` : 6 tests (modèle, flux de vraies `ClientSession` sur `LocalBackend`, flux des modèles par deux `NetBackend` 127.0.0.1). Suite : 716 tests (avant : 710), 0 échec, aucun SCRIPT ERROR. | Pas d'APPROX. Prochain : C.02d |
| 2026-10-05 | C.02c | Monde dofus pour le client léger. **Mesure** (`world_assets.gd --world=dofus --zones --dry`, 25 min sur ce disque) : 17 353 maps en 533 zones (sous-zones), assets utilisés = 10,3 Go (22 Go dans `content/`) : base 1 761 Mo (zone de départ 444 + interface 80 Mo + personnages jouables, dont les squelettes de combat des classes ≈ 1 Go) et 8 548 Mo de zones ; zone médiane 31 Mo, plus grosse 577 Mo (zone `0` : 1 993 maps sans sous-zone), somme avec fichiers partagés recomptés 21,6 Go. Paquet réel (`--build-packages`, 29 min la première fois, hash en cache ensuite) : base 17 849 fichiers dont 17 353 de la sim retirés par `server_only`, zip de base 902 Mo en 45 parties (117 s), 425 613 fichiers hachés au total. **Stratégie** : base légère + zones à la demande (`zone_key` dans `world.json`), serveur sans copie. Code : `ContentZones` (index versionné, pur), `WorldAssets.compute_zoned` (base + zones, listes par dossier : `_content.json` de dofus 4,9 Mo), `WorldPackage` (manifeste par zone, `server_only`), routes `zones.json` / `zones/<z>/manifest.json`, `ContentClient.install_zone` (`download(..., finish=false)`), `ZoneStreamer` (`ensure`, `prefetch`). `ContentManifest.hash_bytes` accepte un tampon vide (zone sans fichier). Tests : `test_content_zones.gd` (7, via WebSocket 127.0.0.1 + HTTP) ; 710 tests, 0 échec (703 avant). | Reste : C.02d (brancher sur `map_enter`, indicateur), C.02e (base 1,8 Go trop lourde : classes à la demande, zone `0`). Pas de capture (aucun écran). |
| 2026-10-06 | C.02d | Zones à la demande branchées sur le jeu. `client/zone_gate.gd` (`ZoneGate`, nœud) : file de zones (index d'abord, la zone attendue en tête, les voisines derrière), un fil de téléchargement (`ContentClient` à lui, `progress` pour la barre), `admit(map_enter)` : vrai si la zone est au cache (et lance le préchargement des zones des maps voisines : `neighbors`, `map_change`, `triggers`), faux sinon (retenue + signal `zone_ready`) ; un échec garde l'état `failed` (message) et réessaie après `retry_s`, les maps des zones installées restent jouables ; sans index (petits mondes, API HTTP absente) la map est montrée telle quelle et l'index est redemandé à la map suivante. `client/zone_indicator.gd` (panneau « Chargement de la zone… » + barre, ou « Zone indisponible »). `SessionLink.handle` retient le `map_enter` (remis en tête de file, `_blocked`) : `client_session.gd` +2 lignes (799). `LaunchScreen._zone_gate` crée la porte pour un monde de serveur ; `ZoneStreamer.ensure_zone`. Le `tp` GM passe par le même `map_enter`. `tests/test_content_zones.gd` : +5 tests (retenue puis remise, préchargement, échec puis reprise, sans index, `SessionLink`, vrai fil avec serveur HTTP en 127.0.0.1) : 725 tests, 0 échec ; captures `tools/zone_shot.gd` relues (chargement, échec) | APPROX(C.02d) : retenue en cas d'échec sans limite d'essais (réessai toutes les 5 s, aucune source) ; le serveur a déjà fait entrer le joueur dans la map. Pas de test avec une vraie `ClientSession` sur `NetBackend` (plante à la sortie en headless, voir P3.04b) : `SessionLink` testé à la main. Option « tout télécharger » et zip par zone : C.02f. Prochain : C.02e |
| 2026-10-06 | C.02e | Base plus légère. `WorldAssets.compute_zoned` : (1) zones de classe `class_<breed>` (squelettes `1-<classe>-*` du `families.json` + skins de création `heads` / `bodies` de la classe et de ses deux looks ; la base garde l'os de repli 666 et les bundles génériques) ; (2) zones de plus de `zone_max_bytes` (150 Mo) coupées en deux récursivement selon le grand côté des coordonnées (`world_map`, `coords`), ids `<zone>-<n>`, le bloc de `start_map` va dans la base. Client : `ZoneStreamer.class_zone / class_ready / missing_zones`, `ZoneGate` retient `characters` et `map_enter` jusqu'aux zones de classe des joueurs montrés, `observe` (joueur d'une autre classe vu : téléchargement derrière) et `class_installed` (`SessionLink` redessine les vues de la classe), aperçu de création qui attend sa classe. **Mesure** (dofus) : base 1 761 Mo à **506 Mo** (non < 400), 19 zones de classe de 43 à 99 Mo (1,2 Go en tout), 573 zones, plus grosse zone `10-1` 430 Mo (monstres répétés dans chaque bloc : la coupe ne l'allège pas), les autres blocs <= 148 Mo ; calcul complet ~45 min. Mesure de connexion Hamachi non faite (pas de second poste) : reportée en C.02g. 5 tests de plus dans `test_content_zones.gd` (classe hors base, blocs, bloc de départ dans la base, retenue de `characters` / `map_enter` par `NetBackend` 127.0.0.1, joueur d'une autre classe derrière) ; tous les tests verts ; `_content.json` de dofus régénéré. Reste : C.02g. |
| 2026-10-05 | release (hors lot) | export reconstruit (client 110 Mo, zip 38,9 Mo, --check vert) ; parcours ami vérifié avec les exe exportés (monde incarnam, dossier de contenu hors défaut, zip de base 981 Mo, reprise, relance sur cache complet, capture OK) ; LISEZMOI, EXPORT.md, nouveau GUIDE_AMIS.md. Dette : segfault à la fermeture auto du client exporté (fuites au quit). | — |
| 2026-10-06 | C.02g | Base sous 400 Mo. `WorldAssets.compute_zoned` : (1) zone `equipment` : les skins des objets de boutiques, quêtes et recettes (`_gather_items`) quittent la base (170 Mo ; `skins` dans l'index pour que le client sache quand la demander) ; (2) zones requises : `requires` dans l'index (`ContentZones.make_index / validate`, `WorldPackage` le garde hors des manifestes) : `<zone>-m` (monstres d'une sous-zone qui pèsent plus de la moitié de la zone ou d'un bloc) et `<zone>-c<n>` (ce que les deux moitiés d'une coupe demandent toutes deux), `_ref_with` ; (3) une coupe ne s'arrête plus quand une moitié reste lourde si l'autre est légère (on recoupe la lourde) : la règle des 95 % porte sur les deux moitiés. Client : `ZoneStreamer.equipment_zone / equipment_ready / needs_equipment / requires_of` (`missing_zones`, `zones_to_fetch`, `ensure` mettent les zones requises avant le bloc), `ZoneGate.observe` (`actor_add`, `actor_look`, `map_enter`) et `ask_equipment` (ouverture de l'inventaire), signal `equipment_installed` (`SessionLink` redessine les joueurs). **Mesure** (dofus, 33 min de calcul) : base 506 à **344 Mo** (< 400), zone `equipment` 162 Mo, 579 zones, plus gros bloc jouable 148 Mo ; la zone `10-3` (409 Mo) est la map 0 (map de repli des 255 PNJ sans position : personne n'y va). 6 tests de plus dans `test_content_zones.gd` (zone d'équipement, requise par `NetBackend` 127.0.0.1, zone de monstres, zone commune, inventaire) ; le fichier est coupé : fixtures dans `tests/zones_rig.gd` (`ZonesRig`) ; 735 tests verts ; `_content.json` de dofus régénéré. | La cause annoncée (monstres de la zone 10) était fausse : 4 Mo de monstres, le poids vient des PNJ de la map 0. APPROX(C.02g) : un objet que le monde ne distribue pas (commande `give`) et que lâche un monstre d'une zone non visitée est dessiné sans skin ; `<zone>-m` / `-c` se téléchargent en bloc à la première entrée ; mesure Hamachi non faite (un seul poste) : estimation base ~175 Mo en zip + classe ~70 Mo, soit ~245 Mo, ~2 min à 2 Mo/s. Reste : C.02h (mesure réelle). |
| 2026-10-06 | S.04b | Instances d'un meme contenu. `WorldSource.instance(id, name)` (memes donnees, `info.id` = instance, `info.content`), `LocalServer.instances` + `source_of`, `WorldCluster.create` / `remove` / `restore` / `content_of` / `sync_content`, `instances.json` du dossier de sauvegarde rouvert par `ServerApp`, actions admin `world_create{id, content, name?}` / `world_remove{id}` (auditees), `servers[].content`, `welcome.world` / `characters.world` portent `content` (`WorldSim.world_summary`), `ContentApi.instances` (liste l'instance sous son id avec `content`, sert le paquet du contenu meme si seul l'instance est ouverte), `WorldLoader.content_of` (cache et manifeste par contenu), `ClientSession.content_id`. `tests/test_instances.gd` (4 tests via vrais WebSockets : personnages separes, listes, API de contenu, creation / suppression, redemarrage) + 1 test de `WorldLoader`. 750 tests, 0 echec apres correction de `test_architecture` (client_session a 800 lignes pile). | APPROX(S.04b) : supprimer une instance garde ses personnages sauvegardes ; pas de formulaire de creation dans la page admin (action HTTP seulement) ni de choix d'instance dedie dans l'ecran de chargement (elle y est une ligne comme un monde). Pas de capture. `P1.17b` : les 14 grades restants n'ont aucune source (declencheurs CI, DV, TR<n>, EC, PMD... sans sens connu), laisse `doing`. Prochain : C.02h (mesure a deux postes) ou S.05c |
| 2026-10-06 | S.05c | Securite, dernier morceau. Hachage dans un thread : `server/auth/auth_job.gd` (`AuthJob`, `WorkerThreadPool`), `ServerHost._login` lit les identifiants sur le fil principal, lance le job, `_finish_jobs` (appele par `poll`) termine le login ; les tentatives d'une connexion pendant un hachage sont mises en file (8 au plus), `AccountStore.register_precheck` / `credentials` / `register(..., prepared)`, `AuthService.login_checked`. Debit par session : seau `Conn.costly` pour `chat_send` et `admin_cmd` (`error{rate_limited}`, sans coupure). Sanction automatique : `server/security/address_penalties.gd` (`AddressPenalties`, `ServerHost.penalties`) : une adresse coupee 3 fois en 10 min (debit, mauvais mots de passe) est refusee 10 min a l'`accept`. `WorldContacts.cached_book` (2 s de temps sim, invalide par `_save`) pour le filtre des ignores ; les invitations de groupe / d'echange d'un ignore etaient deja filtrees (P3.05b). `test_security.gd` : 4 tests (le tick ne bloque pas pendant 0,4 s de hachage, debit par session, `AddressPenalties`, bannissement par l'hote via vrais WebSockets), `test_contacts.gd` : 1. 755 tests, 0 echec. | APPROX(S.05c) : 10 puis 2 / s pour les commandes couteuses, 3 coupures / 10 min = 10 min de ban, cache de 2 s (un changement fait par un autre monde est vu apres au plus 2 s), argon2 : aucune extension Godot disponible, SHA-256 itere garde (APPROX(S.02a)). Dette : pas d'audit de l'HDV (n'existe pas), le bannissement d'adresse est en memoire (perdu au redemarrage), pas de commande GM pour le lever (`penalties.clear`). Lot done. `P1.17b` reste `doing` (14 grades sans source), `P1.15` attend P1.14 |
