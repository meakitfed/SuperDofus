# Export : client léger et serveur headless (X.01)

## Construire

```bash
python tools/build_release.py --zip --smoke            # client + serveur (mondes incarnam, test), zip du client, --check du serveur exporté
python tools/build_release.py --worlds dofus --content link
python tools/build_release.py --only client
```

Prérequis : modèles d'export Godot 4.7 installés (`%APPDATA%\Godot\export_templates\4.7.stable`) ; le script vérifie
l'espace libre sur C: (2 Go minimum, le build écrit ~215 Mo) puis lance `--import` et `--export-release`.

Presets (`game/export_presets.cfg`) :

| Preset | Sortie | Contenu |
|---|---|---|
| `Client` | `dist/client/SuperDofus.exe` (exe unique, PCK intégré) | scènes, scripts, addon `dofus_renderer`. **Sans** `content/`, `data/`, `worlds/`, `mods/` (le contenu se télécharge du serveur) |
| `Serveur` | `dist/server/SuperDofusServeur.exe` + `.console.exe` | mêmes scripts, aucun asset dans le PCK |

Le **serveur** lit `worlds/`, `data/`, `content/`, `mods/` posés à côté de son exe (`ServerApp` : `--content-root`, par
défaut le dossier de l'exe). `build_release.py` copie `worlds/<monde>` et `data/`, et met une **jonction** vers
`game/content` (22 Go : jamais copié). Un serveur exporté ignore `-s` : `dist/server/override.cfg` ouvre
`scenes/server/server.tscn` (nœud `ServerApp`, la même logique que `src/server/main.gd`).

Tailles mesurées : exe client 105 Mo (le modèle d'export Godot standard fait déjà 104 Mo : « quelques dizaines de Mo » ne
s'atteint qu'avec un modèle compilé sur mesure), **zip du client 39 Mo**. Les assets d'un monde ne sont pas dedans.

## Lancer le serveur

**Sur le PC du projet** : `serveur.bat` à la racine lance le serveur depuis le projet (toujours le code à jour, aucun export) ; `serveur.bat publier` republie le contenu, `serveur.bat check` vérifie. Sauvegardes dans `saves\` (racine, hors git), contenu publié dans `%APPDATA%\Godot\app_userdata\SuperDofus\packages`. Ce qui suit concerne le serveur exporté (une machine sans le projet).

`dist/serveur-lancer.bat` (port 7777, API de contenu 7778, mondes, dossier de sauvegarde, `BIND`, `GM` : variables en
tête du fichier). `serveur-lancer.bat check` ou `SuperDofusServeur.console.exe --headless -- --check --world=incarnam`
vérifie les mondes, `data/`, `content/`, l'écriture des sauvegardes, le contenu publié et les ports, puis quitte
(code 1 si quelque chose bloque). Le contenu est **publié avant** (`serveur-lancer.bat publier`, voir « Distribution du contenu ») :
le serveur démarre instantanément et le sert tel quel ; un monde non publié est listé « non publié ».

## Donner le jeu aux amis

`dist/SuperDofus-client.zip` (ou le dossier `dist/client/`) contient `SuperDofus.exe` et `LISEZMOI.txt`, le guide :
installer Hamachi, rejoindre le réseau, saisir `adresse:port`, créer un compte, choisir le monde (téléchargement au
premier lancement). Le texte source est `tools/release/LISEZMOI.txt`.

Le client exporté n'a aucun monde en local : l'écran de lancement n'affiche pas « Jouer en solo » (`LaunchScreen.solo_available`)
et explique qu'il faut un serveur ; le solo reste disponible depuis le projet. L'adresse et l'identifiant sont mémorisés.

## Test d'un export

```bash
# serveur exporté (ports de test) puis client exporté piloté (AutoRun) : crée le compte, télécharge le monde, joue, capture
SuperDofusServeur.console.exe --headless -- --world=test --port=7791 --http-port=7792 --save-dir=./saves --seconds=100
SuperDofus.exe -- --auto-connect=127.0.0.1:7791 --login=ami1 --password=secret12 --register=1 --pick=test --character=Eli --auto-shot=s.png --auto-seconds=20
```

Le monde `test` n'a pas de liste `content` : la map s'affiche (grille générée) mais pas les personnages.

## Dossier des mondes téléchargés (C.04)

Les mondes téléchargés peuvent peser plusieurs Go. Au premier lancement le client demande où les
ranger (n'importe quel disque, par exemple `D:\Jeux\SuperDofus`) et affiche l'espace libre ; le choix
est mémorisé dans `launch.cfg` et modifiable avec « Changer… » sur l'écran de lancement. Les anciens
mondes de `user://worlds` peuvent être déplacés vers le nouveau dossier. En ligne de commande :
`SuperDofus.exe -- --content-dir=D:\Jeux\SuperDofus` (mémorisé aussi, aucune question posée).
L'espace nécessaire est vérifié avant chaque téléchargement.

## Distribution du contenu (C.07)

Le contenu d'un monde est distribué comme le font les launchers (Riot, Ankama/Zaap, Steam) : une **étape de
publication** explicite, faite une fois, produit une arborescence de fichiers **immuables** que le serveur de jeu sert
telle quelle (n'importe quel hébergement statique pourrait la servir aussi). Le serveur ne calcule, ne lit et ne publie
**rien** au démarrage : il ouvre ses ports et liste les mondes en lisant `worlds.json` (quelques centaines d'octets).

```bash
# publier (la première fois, puis après un changement de maps ou d'assets ; incrémental et reprenable)
python tools/publish_content.py --world incarnam --package-dir D:/packages
SuperDofusServeur.console.exe --headless -- --build-packages --world=incarnam --package-dir=D:/packages   # serveur exporté, même code
serveur-lancer.bat publier                 # idem, avec les réglages du .bat
# démarrer : instantané, le contenu publié est servi tel quel
SuperDofusServeur.console.exe --headless -- --world=incarnam --http-port=7778 --package-dir=D:/packages
```

Un monde ouvert mais jamais publié est listé « non publié » (le client affiche « Indisponible ») ; `--check` le signale.
Options de la publication : `--rebuild` (ignore le cache de hachage), `--bundle-mb=<n>` (taille d'un bundle, défaut 32),
`--keep-versions=<n>` (releases gardées par monde, défaut 3).

**Arborescence publiée** (`--package-dir`, format `shared/content_release.gd`) :

| fichier | rôle |
|---|---|
| `worlds.json` | le pointeur de chaque monde : `{release, name, size, files, zones, zones_size}`, écrit **en dernier** |
| `<monde>/releases/<release>.json` | l'index d'une release : la base et les zones (leurs maps, leurs `requires`), chacune avec l'empreinte de son manifeste ; `<release>` = 16 hex du SHA-256 de ses octets |
| `manifests/<hh>/<empreinte>.json.gz` | le manifeste d'un fragment (la base ou une zone) : `[chemin, empreinte, taille, bundle, offset]` par fichier |
| `bundles/<hh>/<empreinte>.bundle` | ~32 Mo de contenus bout à bout, nommé par le SHA-256 de ses octets ; partagé par toutes les releases et tous les mondes |
| `bundles.json`, `<monde>/index.json`, `<monde>/history.json` | index de la publication (où est chaque contenu), cache de hachage, historique : **pas servis** |

**Incrémental.** Chaque contenu (par empreinte) n'est écrit qu'une fois dans tout le dossier : republier sans changement
n'écrit rien ; un fichier modifié ajoute un petit bundle, les autres sont réutilisés. Une ancienne release est élaguée
avec les manifestes et bundles que plus aucune release gardée n'utilise.
**Reprise et atomicité.** Le cache de hachage et l'index des bundles sont sauvegardés pendant le travail ; une coupure perd
au plus le bundle en cours (un bundle à moitié écrit n'a pas de nom). Tout ce qui est sous le pointeur est immuable et nommé
par son contenu, le pointeur bouge en dernier : un client voit l'ancienne release complète ou la nouvelle.

**Côté client** (`client/content_client.gd`, `range_downloader.gd`, `world_loader.gd`) :
- Liste des mondes : **une** requête (`GET /worlds`), comparée au fichier d'état du cache (`<monde>/_install/state.json` :
  release installée et fragments) ; aucun manifeste, aucun parcours ni hachage du cache. « À jour » s'affiche tout de suite,
  la taille exacte d'une mise à jour est calculée ensuite en arrière-plan (« ≤ » jusque-là).
- Installation : index de la release + manifestes des fragments (gardés dans `_install/`), comparés **en mémoire** aux
  manifestes installés ; les contenus manquants sont groupés en requêtes `Range` (fichiers voisins dans un bundle = une requête,
  ≤ 8 Mo), 8 connexions en parallèle, flux découpé en fichiers, SHA-256 vérifié, écriture sur threads.
- Reprise : chaque fichier écrit est ajouté à `_install/journal.log` ; un téléchargement coupé reprend sans rien rehacher.
- « Vérifier » (écran des mondes) : hache tout le cache, sur demande seulement ; un fichier abîmé est retéléchargé seul.
- Un cache des versions précédentes (`manifest.json` à sa racine) est adopté sans retéléchargement.
- Zones (C.02c) : l'index des zones est l'index de la release gardé avec la base (aucune requête) ; une zone = un fragment.

## Grand monde : base légère et zones (C.02c)

Le monde `dofus` (17 353 maps) pèse environ 10,3 Go d'assets utilisés (mesure : `tools/world_assets.gd --world=dofus --zones --dry`, qui n'écrit rien ; compter 25 minutes sur ce disque). Il n'est donc pas téléchargé d'un bloc : `world.json` y déclare `zone_key` (une zone = une sous-zone, 533 zones) et `server_only` (les 17 353 fichiers de maps de la sim ne vont pas aux clients). Le paquet de base (celui que C.03 / C.05 téléchargent au premier lancement) contient l'interface, les personnages jouables et la zone de départ ; chaque autre zone se télécharge à la demande (`ZoneStreamer`). Après un changement de maps ou de monstres : relancer `world_assets.gd --world=dofus --zones` (sans `--dry`, il écrit `worlds/dofus/_content.json`), puis le serveur reconstruit les paquets (`--build-packages`). Le branchement du jeu sur ce téléchargement est le lot C.02d : en attendant, un client qui joue `dofus` n'a que la base et les zones qu'il demande à la main.

## Parcours d'un ami, vérifié avec les exécutables exportés (release, 2026-10-05)

Build : `python tools/build_release.py --zip --smoke` : client 110 Mo (zip 38,9 Mo), serveur, `--check` tout vert.
Essai : serveur exporté (monde `incarnam`, ports 7795/7796) puis `SuperDofus.exe -- --auto-connect=127.0.0.1:7795 --login=ami1
--password=secret12 --register=1 --pick=incarnam --character=Eli --content-dir=<dossier hors défaut> --auto-shot=…`.
- Le serveur construit le zip de base au démarrage (50 parties, 981 Mo, 22 s) puis ouvre l'API de contenu.
- Le client télécharge dans le dossier choisi (1,9 Go, `<dossier>\incarnam\{manifest.json,content,data,world}`), mesuré à ~47 Mo/s
  en local. Un lancement coupé à 60 s a été repris sans retélécharger ; le lancement suivant, cache complet, entre directement en jeu
  (capture : Incarnam, personnage et interface affichés). Le cache est **rejouable tel quel** : le dossier `incarnam` copié dans le
  dossier de stockage d'un autre ordinateur suffit.
- Le client piloté fait un « Segmentation fault » à la fermeture automatique (`--auto-seconds`) : fuites de ressources au quit, sans
  effet sur le jeu ni sur les sauvegardes (non corrigé).

### Temps de téléchargement estimé (zip de base 981 Mo + décompression locale ~1 min)
| Débit montant de l'hébergeur (Hamachi) | Durée |
|---|---|
| 0,5 Mo/s (ADSL) | ~33 min |
| 2 Mo/s | ~8 min |
| 5 Mo/s | ~3,5 min |
| local / même machine | < 1 min |
Plusieurs amis en même temps se partagent le débit de l'hébergeur : pour 4 amis, multiplier par 4 ou leur envoyer le cache.

### Si le téléchargement s'arrête
Relancer le client et recliquer « Reprendre » : reprise au fichier près (journal), rien n'est redemandé. Si l'espace manque, il
le dit avant de commencer ; changer de dossier avec « Changer… » (les fichiers déjà reçus ne suivent pas : les copier à la main).

### Envoyer un cache déjà prêt (Smash, clé USB)
Sur un PC qui a déjà le monde : compresser le dossier `<dossier de stockage>\incarnam` en zip (≈ 1,9 Go, déjà compressé, peu gagné) et
l'envoyer (Smash : gratuit jusqu'à 2 Go par envoi, sinon découper). L'ami décompresse dans **son** dossier de stockage (celui choisi au
premier lancement, ou affiché à l'écran de lancement) de façon à obtenir `<son dossier>\incarnam\_install\state.json`, lance le jeu, choisit le
monde : le client adopte ce cache (son `_install/` dit ce qu'il contient) et ne télécharge que ce qui manque.

## Dépôt GitHub, build automatique et mise à jour du client (X.02)

Le code (sans `game/content`, `game/data`, `game/worlds`, `game/mods`, dérivés du contenu Ankama / JondoEmu) est sur
`github.com/meakitfed/SuperDofus` (public). Chaque `git push` sur `master` lance `.github/workflows/build.yml` :
numéro de build = numéro du run (remplace `BuildInfo.BUILD`), import, test `test_update_check`, export du preset `Client`,
puis release `build-<n>` portant `SuperDofus.exe`.

Au lancement, un client exporté (`BuildInfo.BUILD > 0`) lit `releases/latest` (`SelfUpdater`, `UpdateCheck`) ; si le
build est plus récent il télécharge l'exe dans `user://update/`, vérifie le sha256 donné par GitHub, quitte et laisse
`swap.bat` remplacer l'exe puis le relancer. Hors ligne ou à jour : rien ne s'affiche. `--no-update` désactive ;
un client lancé depuis le projet (build 0) ne se met jamais à jour. Le serveur n'est pas concerné (build à la main).
Pousser : `git push` (le dépôt est configuré sur `master`).

## Performance du contenu (démarrage instantané, téléchargement rapide)
Mesures et décisions (Windows, l'antivirus analyse chaque **ouverture** de fichier : 8 à 22 ms à froid, contre 0,05 ms pour un stat) :
- Ne jamais ouvrir un fichier pour connaître sa taille : `FileHash.size_of` / `FileAccess.get_modified_time`.
- Serveur HTTP de contenu : thread dédié (`HttpServer.start_thread`, `--http-in-tick` pour l'ancien mode), connexions
  persistantes ; tout le contenu (y compris `/worlds`) est servi sur ce thread, seul `/admin` passe par le thread du jeu.
- Démarrage : aucune lecture du contenu (C.07) ; publication hors du serveur, incrémentale, lectures en parallèle (pool de threads).
- Client : une requête pour la liste, plages d'octets de bundles sur 8 connexions, aucun hachage du cache hors « Vérifier ».
- Outils de mesure : `tools/bench_download.gd` (liste, release, plan, premier octet, débit), `tools/probe_worlds.gd`.
