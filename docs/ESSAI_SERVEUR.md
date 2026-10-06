# Essai bout en bout : deux comptes sur un vrai serveur local (2026-10-04)

But : vérifier, avec un **vrai serveur headless** (processus séparé, WebSocket sur 127.0.0.1) et **deux clients `NetBackend`** (deux comptes, deux personnages), ce qui marche et ce qui manque de la phase M. Aucune mock : seuls des messages du protocole circulent, comme pour un vrai client.

## Résultat
98 vérifications : **94 OK, 4 MANQUE (fonctions pas encore écrites), 0 bug restant**. Deux bugs ont été trouvés et corrigés pendant l'essai (voir plus bas), chacun avec un test de régression (`test_admin.gd`, `test_numeric_args_and_the_role_announced_to_a_gm_account`). Tests du projet : 626 tests, 0 failures (622 avant).

Mise à jour P3.11a : l'échange est maintenant un vrai scénario (6 vérifications) ; nouvel essai : 103 vérifications, 100 OK, 3 MANQUE (`/p`, amis, guilde), 0 bug.

## Reproduire
```
godot --headless --path game -s res://src/server/main.gd -- --server --port=7791 --http-port=7792 --world=incarnam --save-dir=<dossier temporaire> --gm=essaia --seconds=330
godot --headless --path game -s res://tools/essai_serveur.gd -- --server=127.0.0.1:7791 --gm=essaia --out=essai.json
```
- Le serveur doit être neuf (le script inscrit `essaia` et `essaib`) ; `--gm=essaia` donne le rôle GM au premier compte seulement.
- `--seconds=330` : arrêt propre du serveur (personnages sauvegardés) ; vérifié : `server: stopped, characters saved`, un fichier par compte, par personnage, et `admin_audit.jsonl`.
- `tools/essai_serveur.gd` (script) et `tools/essai_peer.gd` (une connexion) ; durée : environ 110 s. Les combats sont joués par `ScenarioBot` (le bot des scénarios) via les événements, comme un client.
- `--http-port` : le script vérifie aussi l'API de contenu (port de jeu + 1).

## Bilan par fonctionnalité
| Fonctionnalité | État | Détail |
|---|---|---|
| Connexion WebSocket, horloge (ping / pong) | OK | décalage mesuré après `hello` |
| Comptes : inscription, connexion | OK | refus avant inscription (`bad_credentials`), login trop court (`bad_login`), nom pris (`login_taken`), mauvais mot de passe |
| Une connexion par compte | OK | 2e connexion refusée (`already_connected`) |
| Rôle GM | OK après correction | `login_ok.role` disait `player` pour un compte de `--gm` alors que la session était GM (bug 1) |
| Personnages : liste, création (2 classes), doublon refusé, sélection | OK | `welcome`, `map_enter`, inventaire et stats reçus |
| Sauvegarde | OK | après fermeture propre puis nouvelle connexion : personnage, niveau, kamas conservés |
| Joueurs sur la même map | OK | chacun voit l'autre (`actor_add`), fiche publique sans donnée privée |
| Déplacements croisés | OK | chacun voit marcher l'autre (`actor_move`), arrivée à la bonne case, case invalide refusée |
| Chat de map | OK | reçu par l'autre, écho à l'expéditeur, ne traverse pas les maps |
| Chat privé `/w` | OK | reçu, écho, absent refusé ; commande inconnue refusée ; anti-flood actif |
| Groupe : invitation, acceptation, `party_update`, quitter, absent refusé | OK | |
| Groupe : suivre | OK | B rejoint la map de A après un vrai `change_map` de A |
| Combat solo (bot) | OK | début, tours, `fight_end` victoire, XP, kamas, butin |
| Combat à deux | OK | B voit l'épée sur la map, rejoint pendant le placement, A voit `fighter_joined`, les deux jouent, les deux reçoivent la fin et leurs gains |
| Spectateur, fuite | OK | `fight_watch`, `fight_leave` |
| Coupure en combat puis reprise | OK | `resume_ok`, `in_fight`, combat rejoué, même jeton ; reprise hors combat : quêtes et inventaire reviennent |
| Boutique de PNJ | OK | dialogue, `shop_open`, achat, vente, achat trop cher refusé |
| Banque | OK | dépôt d'objets et de kamas, retrait |
| Quête | OK | offre dans les réponses du dialogue, `quest_start`, quête conservée à la reprise |
| Récolte de métier | OK | `interactive_start`, fin, XP de métier, objet, élément marqué récolté, deuxième récolte refusée |
| Console GM | OK après correction | `give`, `kamas`, `level`, `who`, `say` (diffusé), `tp`, `mute` / `unmute`, `kick` (motif envoyé), `ban` (login refusé `banned`) / `unban` ; refusé au joueur (`not_gm`) ; `give` / `kamas` avec des nombres JSON échouaient (bug 2) |
| API de contenu HTTP | OK | 401 sans jeton, `/worlds`, manifeste, fichier hors manifeste refusé |
| Chat de groupe `/p`, guildes | MANQUE | `channel_unavailable` (P3.02b) ; guilde : P3.06 |
| Amis / ignorés | MANQUE | P3.05 |
| Échange entre joueurs | OK (P3.11a) | invitation, fenêtre, offre vue par l'autre, double validation (objet et kamas échangés), annulation, absent refusé : `tools/essai_trade.gd` ; ce n'était qu'une sonde MANQUE avant le lot |

## Bugs trouvés et corrigés
1. **`login_ok` / `resume_ok` annonçaient le mauvais rôle** : `--gm=<login>` rend la session GM, mais le rôle envoyé au client était celui du document de compte (`player`). Corrigé dans `ServerHost._login` et `_resume` (le rôle annoncé est celui de la session).
2. **`admin_cmd` refusait les nombres** : JSON rend `683` en `683.0`, `str()` donnait `"683.0"` (pas un entier) donc `bad_message`. Seule la boîte de chat (qui envoie des chaînes) marchait. Corrigé dans `WorldAdmin._run` (flottant entier -> entier).

## Dettes et limites de l'essai (notées au Journal)
- L'essai n'utilise aucune interface : il valide le protocole et le serveur, pas le rendu (les captures `client_shot` restent la référence).
- Non rejoué en temps réel : l'IA qui reprend un combattant après 60 s de coupure (testée en virtuel dans `test_resume.gd`) ; la limitation de débit sous charge (S.05).
- Les codes d'erreur de certains refus (anti-flood, achat trop cher, `/w` vers un absent) sont acceptés « n'importe lequel » par le script : à resserrer si un code change.
- Les noms de personnage n'acceptent que des lettres (une majuscule initiale) : le script les génère en conséquence.
