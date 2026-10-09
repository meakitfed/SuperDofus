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

`dist/serveur-lancer.bat` (port 7777, API de contenu 7778, mondes, dossier de sauvegarde, `BIND`, `GM` : variables en
tête du fichier). `serveur-lancer.bat check` ou `SuperDofusServeur.console.exe --headless -- --check --world=incarnam`
vérifie les mondes, `data/`, `content/`, l'écriture des sauvegardes, les paquets construits et les ports, puis quitte
(code 1 si quelque chose bloque). Les paquets sont **publiés avant** (`--build-packages`, voir « Publication du contenu ») : le serveur les lit au démarrage et refuse de démarrer s'ils manquent (`--build-on-start` pour l'ancien comportement).

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

## Zip de base (C.05)

À la publication (`--build-packages`) le serveur construit aussi, pour chaque monde, un zip de base en
parties (`<dossier des paquets>/<monde>/versions/<release>/bundle/`, environ la moitié du poids d'Incarnam : 981 Mo pour 1,9 Go ;
reconstruit seulement quand le monde change). Un client sans cache le télécharge (reprise après coupure,
vérification des empreintes) puis ne reçoit que des mises à jour fichier par fichier. `--no-bundle` le désactive,
`--bundle-mb=<n>` règle la taille des parties (défaut 256). Prévoir de la place pour le zip en plus des fichiers.

## Publication du contenu (C.06)

Le serveur de jeu **ne calcule plus le contenu** : une étape de build explicite le hache, le zippe et le publie, le
serveur lit ensuite le résultat (démarrage en une fraction de seconde au lieu de plusieurs minutes pour Incarnam, et
tout un monde `dofus` de plusieurs Go ne se recalcule plus à chaque lancement).

```bash
# publier (reprenable : relancer après une interruption repart de ce qui est écrit)
python tools/publish_content.py --world incarnam --package-dir D:/packages
SuperDofusServeur.console.exe --headless -- --build-packages --world=incarnam --package-dir=D:/packages   # serveur exporté, même code
serveur-lancer.bat publier                 # idem, avec les réglages du .bat (publie aussi tout seul au premier démarrage)
# démarrer : lit les paquets publiés (existence et taille seulement), ne hache rien
SuperDofusServeur.console.exe --headless -- --world=incarnam --http-port=7778 --package-dir=D:/packages
```

Options de la publication : `--rebuild` (ignore le cache de hachage), `--no-bundle`, `--bundle-mb=<n>`, `--no-zone-packs`,
`--copy-files`, `--keep-versions=<n>` (défaut 3). `--build-on-start` donne l'ancien comportement (publier ce qui manque,
puis démarrer : tests, premier essai). Sans paquet publié, le serveur s'arrête avec « paquet <monde> non publié : lancer
l'étape de build » ; `--check` le signale (FAIL si l'API de contenu est demandée).

**Reprise et atomicité.** L'index de hachage est écrit toutes les 5 s pendant le calcul, chaque partie du zip de base et
chaque zip de zone dès qu'elle est finie ; une coupure perd au plus le fichier en cours. Une version est écrite sous
`<paquets>/<monde>/versions/<release>/` (le nom dérive de ce qu'elle contient : un dossier publié n'est jamais modifié),
puis le tampon `release.json` (taille de chaque artefact), puis le pointeur `<paquets>/<monde>/current.json` en tout
dernier. Un serveur qui démarre à un moment quelconque voit la version complète précédente ou la nouvelle, jamais un mélange ;
les versions inachevées sont supprimées, les plus anciennes élaguées. Un serveur déjà lancé continue sur la version qu'il
a lue (la redémarrer pour passer à la nouvelle ; ne pas élaguer en dessous de ce qu'il utilise).

**Contenu d'une version** (même forme que l'API de contenu, `GET /worlds/<id>/...`) :

| fichier | rôle |
|---|---|
| `manifest.json` | liste `{path, hash, size}` du monde et sa version |
| `bundle.json`, `bundle/part-NNN.zip` | zip de base en parties (C.05), entrées nommées par empreinte |
| `zones.json`, `zones/<zone>/manifest.json` | index des zones et fichiers de chaque zone (C.02c) |
| `zones/<zone>/pack.zip` | **un zip par zone** (C.06c) : une requête au lieu de N ; `pack: {size, hash}` dans le manifeste de la zone ; le client retombe sur les fichiers un par un si le zip manque ou est abîmé |
| `files/<empreinte>` | (`--copy-files`, au niveau du monde, partagé entre versions) les octets de chaque contenu, pour un hébergement statique |
| `release.json`, `blobs.json` | tampon (taille de chaque artefact) et table empreinte -> fichier lue par le serveur de jeu : pas à publier |

Sans `--copy-files` rien du contenu n'est copié (les 22 Go de `content/` restent où ils sont, `blobs.json` dit où lire
chaque empreinte) : le serveur de jeu sert ainsi sans duplication.

**Hébergement statique.** Le format est de simples fichiers : manifeste, fichiers nommés par empreinte, zips. Poser
`worlds/<monde>/` (le contenu d'une version + `files/`) et `worlds.json` sur n'importe quel hébergement statique ou CDN suffit
à les servir ; `python tools/publish_content.py --world <monde> --package-dir <d> --copy-files --static-out <dossier>`
assemble cette arborescence. Attention : un hébergement public n'a pas le jeton de session que l'API de contenu du
serveur exige (« jamais d'URL publique ») ; le mettre derrière un accès restreint (URL signées, réseau privé) et noter
que le client ne sait aujourd'hui lire le contenu que depuis le serveur de jeu (reste de C.06d).

**Export.** `python tools/build_release.py --publish` publie les mondes du build avec le serveur exporté dans
`dist/server/packages/`. `serveur-lancer.bat` passe `--package-dir=<dist>\server\packages` (variable `PACKAGES`), publie tout
seul un monde jamais publié, et `serveur-lancer.bat publier` republie après un changement de maps ou d'assets.

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
Relancer le client et recliquer « Télécharger » : reprise par partie et par empreinte, rien n'est reredemandé. Si l'espace manque, il
le dit avant de commencer ; changer de dossier avec « Changer… » (les fichiers déjà reçus ne suivent pas : les copier à la main).

### Envoyer un cache déjà prêt (Smash, clé USB)
Sur un PC qui a déjà le monde : compresser le dossier `<dossier de stockage>\incarnam` en zip (≈ 1,9 Go, déjà compressé, peu gagné) et
l'envoyer (Smash : gratuit jusqu'à 2 Go par envoi, sinon découper). L'ami décompresse dans **son** dossier de stockage (celui choisi au
premier lancement, ou affiché à l'écran de lancement) de façon à obtenir `<son dossier>\incarnam\manifest.json`, lance le jeu, choisit le
monde : le client vérifie le manifeste et ne télécharge que les fichiers manquants ou changés.

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
