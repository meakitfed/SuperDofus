# Plan : jouer à plusieurs (serveur, comptes, contenu par monde, admin, export)

But : un **serveur sur ta machine**, joint par tes amis via **Hamachi** (réseau privé virtuel : une IP:port comme sur un réseau local, pas de redirection de port). Le client est un petit programme ; **les données et les assets d'un monde se téléchargent depuis le serveur** (API de contenu), avec un écran de chargement. Dofus n'est que le premier monde : le moteur doit pouvoir servir d'autres jeux.

Base existante : la sim est déjà multi-session (`connect_player`, `GameSession`, `LocalServer` partagé, `Persistence` / `Clock` injectées, tests d'hébergement).

## Architecture visée
```
Client léger (exe, quelques dizaines de Mo, sans contenu)
   │  Hamachi (IP:port du serveur)
   ▼
Serveur Godot headless (ta machine)
   ├─ API de jeu     : WebSocket JSON (le même protocole), un WorldSim par monde
   ├─ API de contenu : HTTP, par monde  /worlds                    liste des mondes
   │                                    /worlds/<id>/manifest.json  fichiers + empreintes (hash) + version
   │                                    /worlds/<id>/files/<hash>   le fichier (données, maps, images, sons…)
   └─ Admin web      : HTTP, jeton admin (tableau de bord)
```
Le **paquet d'un monde** (`world package`) = sa définition (`world.json`, maps, quêtes…), ses données (`game/data`-équivalent) et ses assets, décrits par un manifeste. Le client choisit un monde, compare le manifeste à son cache local (`user://worlds/<id>/`), télécharge seulement ce qui manque ou a changé, puis charge **depuis ce cache** au lieu de `res://content/`.

Conséquence technique principale : tout ce que le client lit aujourd'hui dans `res://` (`content/`, `data/`, `worlds/`) doit passer par une **couche de chargement de contenu** (`ContentSource`) qui sait lire `res://` (dev, solo) ou le cache téléchargé. C'est le chantier le plus transversal du plan (lot C.01).

## Jalon M1 : « on se voit et on bouge ensemble »
| Lot | Contenu |
|---|---|
| **S.01** Serveur headless + `NetBackend` | `server/main.gd` héberge un `LocalServer` ; WebSocket JSON ; `NetBackend` implémente `GameBackend` ; horloge synchronisée (`ping`/`pong`) ; écran de connexion « solo / serveur (adresse:port) » |
| **P3.01** Plusieurs joueurs sur une map | autres joueurs rendus (look, nom), arrivée / départ, déplacements diffusés, menu contextuel |
| **S.02-min** Comptes | login / mot de passe haché, jeton de session, une connexion par compte, création de compte |
| **C.01** `ContentSource` | une couche unique pour lire données et assets : `res://` ou cache `user://worlds/<id>/` ; aucun chemin en dur dans le client |
| **C.02** Paquets de monde et API de contenu | format de manifeste (fichiers, hash, version) ; outil serveur qui construit le paquet d'un monde depuis `game/` + `game/content/` ; endpoints HTTP `/worlds`, `manifest`, `files/<hash>` ; reprise de téléchargement, vérification des hash |
| **C.03** Écran de chargement client | liste des mondes du serveur, barre de progression, cache local, « mettre à jour » quand le manifeste change |
| **X.01** Export | presets d'export Windows : client léger, serveur headless ; script de build ; dossier à donner aux amis (exe + Hamachi + adresse) |

Résultat M1 : tes amis installent un petit exe, rejoignent ton réseau Hamachi, choisissent le monde, le contenu se télécharge, et vous êtes ensemble sur la map.

## Jalon M2 : « on joue ensemble »
| Lot | Contenu |
|---|---|
| **P3.02** Chat | canaux (map, privé, groupe), anti-flood, `/w` |
| **P3.03** Groupes | invitation, chef, suivre, bonus d'XP, cadre du groupe |
| **P3.04** Combats à plusieurs | rejoindre en placement, 8 par équipe, épées sur la map, spectateur |
| **S.02** Comptes complets | reconnexion en combat (le combat attend N s), double connexion refusée |
| **A.01** Admin : console GM + métriques | commandes GM en jeu, métriques en JSON (joueurs, ticks, mémoire) |

À soigner pour les combats à plusieurs : tour de chacun avec timer (fait en P1.15), déconnexion en combat (passer le tour puis IA), agression d'un groupe quand plusieurs joueurs sont dans la zone, partage de l'XP et du butin.

## Jalon M3 : « on peut le laisser tourner »
| Lot | Contenu |
|---|---|
| **S.03** Persistance fiable | `FilePersistence` côté serveur + sauvegardes périodiques et copies ; SQLite plus tard si besoin |
| **A.02** Admin web | tableau de bord HTTP (voir plus bas) |
| **S.04** Plusieurs mondes | « créer un serveur » = lancer une instance de monde depuis l'admin, chacune avec son paquet de contenu |
| **S.05** Sécurité | validation de toutes les commandes, limitation de débit, audit, fuzz ; accès contenu : liste blanche des fichiers du manifeste |
| **S.07** Parité | scénarios JSONL identiques via `LocalBackend` et `NetBackend` |

## Moteur multi-jeux (plus tard, mais à ne pas empêcher)
Aujourd'hui `sim/` contient des règles **Dofus** (sorts, effets, géométrie 14×20, criteria…) et le rendu est `dofus_renderer`. Pour servir d'autres jeux, il faudra séparer :
- le **noyau** : sessions, comptes, réseau, persistance, contenu par monde, admin, protocole générique ;
- le **module de jeu** (`game module`) : règles, rendu, données d'un jeu. Dofus = le premier module.

Lot **G.01** (étude, sans code) : lister ce qui est générique ou propre à Dofus, définir l'interface d'un module et le format d'un paquet de monde (qui référence son module). À faire **après M1** : l'expérience du serveur et du paquet de contenu dira où passe la frontière. D'ici là, règle simple pour les agents : ne rien ajouter de « Dofus » dans le code de session, réseau, comptes, contenu, admin.

## Admin (A.01 puis A.02)
Tableau de bord web servi par le serveur (jeton admin) + console GM en jeu (`admin_cmd`, rôle requis).
- **Vue d'ensemble** : joueurs connectés, maps actives, combats en cours, durée de tick, mémoire, version, uptime.
- **Comptes et personnages** : recherche, fiche (niveau, classe, position, kamas, inventaire, quêtes, dernière connexion, IP), historique.
- **Actions** : téléporter, donner objet / kamas / niveau, kick, ban, muet, réinitialiser un mot de passe, soigner / ressusciter.
- **Debug** : suivre un combat en direct, derniers événements d'un joueur, journal d'erreurs et d'audit, forcer un respawn, recharger des données.
- **Mondes et contenu** : créer / démarrer / arrêter un monde, reconstruire le paquet de contenu et voir quels clients sont à jour, sauvegarde manuelle et restauration, message à tous, arrêt programmé.
- **Sécurité** : toutes les actions admin journalisées.

## Hamachi : ce qu'il faut savoir
- Le jeu ne dépend pas de Hamachi : le client se connecte à **une adresse IP:port**. Hamachi, Tailscale ou ZeroTier se valent ; seule l'adresse change.
- L'offre gratuite de Hamachi limite le nombre de machines par réseau (à vérifier : de l'ordre de 5) ; au-delà, offre payante ou un autre VPN.
- Le trafic de Dofus (tour par tour) tolère bien la latence d'un VPN. Le téléchargement des assets passe aussi par le VPN : prévoir un cache solide (on ne télécharge qu'une fois) et la reprise après coupure.
- Le serveur n'est joignable que quand ta machine est allumée et connectée au réseau Hamachi.

## Droits
Servir les assets Ankama à tes amis via ton serveur reste de la redistribution, même sur un réseau privé : c'est ta décision pour un cercle d'amis, mais le serveur ne doit pas être exposé publiquement. Côté code, le serveur n'envoie que les fichiers listés dans le manifeste, uniquement aux comptes authentifiés (jamais d'URL publique de contenu). Ce choix reste ouvert : un autre jeu aurait ses propres assets libres de droits.

## Ordre d'exécution recommandé
S.01 → P3.01 → S.02-min → C.01 → C.02 → C.03 → X.01 (M1) ; puis P3.02 → P3.03 → P3.04 → A.01 → S.02 (M2) ; puis M3 ; G.01 après M1.
Les lots de contenu P2.xx restants (P2.05c, P2.07, P2.09 à P2.14…) sont mis en pause tant que M1 n'est pas fini.

## Décisions encore ouvertes
- Un monde persistant unique partagé, ou un monde par groupe d'amis (S.04 permet les deux).
- Quels fichiers sont téléchargés : seulement les assets, ou aussi les données de règles (`game/data`, `worlds`) : je prévois les deux, pour que le client et le serveur utilisent exactement la même version.
