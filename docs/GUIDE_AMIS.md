# Guide : jouer entre amis (Hamachi)

Tout ce qu'il faut pour faire jouer des amis sur ton PC. Version courte pour l'ami : `LISEZMOI.txt` dans le zip du client.

## Pour l'hébergeur

1. **Construire** (une fois, ou après une mise à jour du jeu) : `python tools/build_release.py --zip --smoke`. Sortie dans `dist/` :
   `dist/server` (à garder), `dist/serveur-lancer.bat`, `dist/SuperDofus-client.zip` (à donner, 39 Mo).
2. **Hamachi** : installer (vpn.net), créer un compte, « Créer un nouveau réseau » (nom + mot de passe). Noter ton adresse IPv4
   Hamachi (25.x.x.x, clic droit > Copier). Gratuit : environ 5 machines par réseau.
3. **Pare-feu Windows** : à la première exécution, autoriser `SuperDofusServeur` sur le réseau privé ; ports 7777 (jeu) et 7778 (contenu).
4. **Régler `dist/serveur-lancer.bat`** : `PORT` (7777), `WORLDS` (`incarnam,test`), `BIND` (`*`, ou ton adresse Hamachi pour ne
   répondre qu'à ce réseau), `GM` (voir plus bas).
5. **Vérifier** : `serveur-lancer.bat check` (ports, dossiers, paquets : « tout est prêt »).
6. **Lancer** : `serveur-lancer.bat`. Au premier démarrage, le zip de base (981 Mo) se construit (~25 s ici) : attendre
   `server: content API on port 7778`. Laisser la fenêtre ouverte ; la fermer (ou Ctrl+C) sauvegarde proprement les personnages.
7. **Inviter** : envoyer à chaque ami le zip du client, le nom du réseau Hamachi, son mot de passe, `ton.adresse.hamachi:7777`.
8. **Comptes GM** : mettre `set GM=tonidentifiant` (plusieurs : séparés par des virgules) puis relancer. Les comptes se créent depuis le
   client (« Créer un compte ») ; le compte GM doit exister (ou être créé ensuite). Commandes dans la boîte de chat (Entrée) :
   `/help`, `/give <objet> [n]`, `/tp <map> [cellule]`, `/kamas`, `/level`, `/heal`, `/say`, `/who`, `/kick`, `/ban`, `/mute`…
   Les sauvegardes sont dans `dist/server/saves` (copier ce dossier = sauvegarde ; `admin_audit.jsonl` journalise les commandes GM).
9. **Mise à jour** : refaire le build, remplacer `dist/server` en gardant `saves/`, renvoyer le client si le protocole a changé.
   Les amis ne retéléchargent que les fichiers modifiés.
10. **Si un ami a une connexion lente** : lui envoyer le cache déjà prêt (voir `docs/EXPORT.md`, « Envoyer un cache déjà prêt »).

## Pour l'ami

1. Installer Hamachi, rejoindre le réseau (nom et mot de passe de l'hébergeur), vérifier que l'hébergeur apparaît en vert.
2. Décompresser `SuperDofus-client.zip`, lancer `SuperDofus.exe`.
3. Premier lancement : choisir le **dossier de stockage** du monde (2 Go libres, n'importe quel disque ; modifiable via « Changer… »).
4. Saisir `adresse-hamachi:7777`, un identifiant et un mot de passe, « Créer un compte » (la fois suivante : « Se connecter »).
5. Choisir le monde, « Télécharger » (de moins d'une minute à environ 30 minutes selon l'hébergeur ; reprend après une coupure).
6. Créer son personnage (classe, sexe, couleurs) puis jouer. Entrée = chat, I inventaire, C caractéristiques, S sorts, Q quêtes, M carte.

## Ce qui marche (essayé avec les exécutables exportés ou par tests sur un vrai serveur local)

- Comptes, reconnexion automatique après une coupure (le combattant est gardé 60 s), plusieurs personnages par compte.
- Monde Incarnam complet (74 maps), déplacements, joueurs visibles entre eux, chat (général, privé `/w`, commerce, recrutement).
- Combats contre les monstres, à plusieurs (rejoindre, regarder), toutes les classes, XP, butin.
- Groupes, échange entre joueurs, amis / ignorés, boutiques de PNJ, banque, quêtes, métiers (récolte), zaaps, phénix.
- Console GM, bans, sourdine, métriques et page `/admin` (jeton admin).
- Téléchargement du monde avec reprise, dossier de stockage au choix.

## Ce qui ne marche pas encore

- Monde `dofus` complet (17 353 maps) : trop gros pour le client léger, les zones à la demande ne sont pas branchées (C.02d).
- Chat de groupe `/p`, guildes, hôtel de ventes, mariage, montures, donjons : à venir.
- Le solo n'existe pas dans le client exporté (seulement depuis le projet).
- Hamachi : débit limité par l'envoi de l'hébergeur ; pas de connexion si Hamachi ou le serveur est éteint.
- Fermeture d'un client piloté par `--auto-seconds` : plantage inoffensif à la sortie (fuites au quit).
- Pas de chiffrement : mot de passe de compte non protégé hors du réseau Hamachi ; ne pas réutiliser un mot de passe important.
