# Audit visuel de l'interface (Recherche B)

Date : 2026-10-17. Méthode : `client_shot` (monde `incarnam`, raccourcis de `docs/COMMANDES.md`) et `launch_shot`, avec `--resolution` 1280x720, 1920x1080, 1024x768 (format plus carré) et 2560x1440 (fenêtre rognée à 2560x1325 par l'écran). Toutes les captures citées ont été relues avec l'outil Read. Captures hors dépôt (scratchpad de session). Aucune modification de code.

Limites :
- Le chargement n'a pas pu être capturé comme écran : il n'existe qu'un fondu d'entrée du HUD (voir T8).
- Le toast n'a été vu que pour « pas assez de kamas ».
- L'hôtel de vente n'a pas pu être ouvert par `client_shot` (deux essais) : non audité. La console : capture inexploitable.
- Le raccourci `mark` ne dessine rien en combat : le défaut des mobs masqués est établi par la géométrie du code (`_fit_camera`, `FightHud._process`) et par les captures, pas par un marquage de cases.
- Toutes les tailles n'ont pas été capturées pour chaque écran : 1280x720 et 1920x1080 pour presque tous, 1024x768 et 2560x1440 pour 14 scènes clés (lancement, lobby, création, HUD, inventaire, caractéristiques, grimoire, quêtes, boutique, craft, échange, combat, résultat).

## Défauts transversaux (classés par impact)

| # | Impact | Défaut | Preuve | Correctif proposé |
|---|---|---|---|---|
| T1 | Majeur | Aucune mise à l'échelle de l'UI : à 1920x1080 et surtout 2560x1440 tout reste en pixels fixes (texte ~13 px, barre de sorts 475 px de large) : minuscule et peu lisible ; à 1024x768 les éléments se chevauchent. | hud, fight, characteristics aux 4 tailles | Facteur d'échelle UI unique dans le kit (`UiStyle`), déduit de la fenêtre et réglable ; tailles de police du kit en unités, pas en pixels. |
| T2 | Majeur | Combat : la barre de combat (bandeau + ligne d'options, ~175 px, haut à y=545 sur 720) recouvre le bas de la map, alors que `_fit_camera` ne réserve que la bande d'exploration (`reserved_bottom` = barre de sorts + 24 px). La timeline (y 58-120) et le chat de combat (déplacé en y 232-418, `chat.position = Vector2(12, 230)`) couvrent aussi des cases. Les mobs et le joueur placés dans la rangée du bas ou à gauche sont masqués : sur `fight_1280x720` le premier Tofu est à moitié sous le chat, et la ligne d'options coupe la rangée basse. | fightplace, fight, fighttip aux 4 tailles | Réserver en combat la bande haute (timeline) et la bande basse (barre + options) dans `_fit_camera` via `band_changed` ; intégrer la ligne d'options à la barre ; sortir le chat du champ (repli en icône ou à droite sous le minimap) ; test visuel avec combattants sur les rangées 0 et 19. |
| T3 | Majeur | Les fenêtres s'ouvrent à des positions fixes qui se chevauchent entre elles ou avec le HUD : Métiers et Amis recouvrent le minimap ; Zaap sous Carte du monde (boutons « Sauvegarder » et « Voyager » coupés) ; Quêtes sur le dialogue de PNJ à 1280 (texte illisible) ; Caractéristiques sur le chat et la barre à 1024. | jobs, friends, worldmap, quests, characteristics_1024 | Gestionnaire de fenêtres : cascade à l'ouverture, clamp dans la zone libre (hors minimap, chat, barre), focus au clic qui remonte la fenêtre. |
| T4 | Élevé | Ligne d'aide/debug (« 136 fps · clic : se déplacer… ») affichée en permanence en haut : tronquée par le minimap (« Tab : éléments interactifs · » puis « S » coupé), blanche sur la map, passe sous la timeline en combat, entre en collision avec les toasts. | toutes les captures de jeu | La mettre derrière une option ou un bouton d'aide ; séparer les fps (debug) de l'aide. |
| T5 | Élevé | À 1024x768 chat, barre de sorts et cadre du joueur se chevauchent : la barre cache « 0 K » et la fin de la barre de PV. | hud_1024x768 | Placement en flux au bas de l'écran avec priorités ; largeur du chat bornée par `vp.x` moins la barre et les marges. |
| T6 | Élevé | Texte technique et doublon dans le grimoire : clé brute `+3 spell_mod:dmg:12815` et ligne « 10 à 13 dommages Eau » répétée. | spells aux 4 tailles | Passer la clé par les textes (`info_texts`/i18n) ; dédoublonner les effets d'un même grade. |
| T7 | Moyen | Chat inactif : tout le panneau, onglets compris, devient quasi transparent (onglets illisibles sur la map claire). | inventory, characteristics, fight | Ne fondre que le fond ; garder onglets et saisie à contraste suffisant ; ne pas fondre quand une fenêtre est ouverte. |
| T8 | Moyen | Pas d'écran de chargement : après « Jouer », un fondu d'entrée du HUD seul. | loading_1280x720_1100 | Écran de chargement avec progression sur le visuel du kit (`world_load_screen` existe : à brancher à la sélection du personnage). |
| T9 | Moyen | Barres : texte centré sur la barre entière et non sur le trait plein ; texte d'énergie de ~8 px jaune sur jaune, quasi illisible ; XP collée à la bordure. | characteristics, cadre du joueur | `UiBar` : hauteur minimale = police + 4, contour de texte, énergie en infobulle ou sous la barre. |
| T10 | Moyen | Kamas affichés « K » seul, sans icône ni helper commun (« 1 300 K », « 42 K »). | shop, bank, hud, fightresult | Icône de kama du client et un `UiStyle.kamas(n)` partout. |
| T11 | Faible | Fenêtres de hauteur arbitraire avec beaucoup de vide : Zaap (~300 px vides), Métiers, Amis (aucun état « aucun ami »), Fin du combat (colonne droite vide). | zaap, jobs, friends, fightresult | Hauteur au contenu (min/max), états vides avec texte et icône. |

## Tableau par écran

Notes /5 données à 1280x720, avec la réserve de T1 aux grandes tailles.

| Écran | Note | Défauts concrets | Correctifs proposés (par impact décroissant) |
|---|---|---|---|
| Lancement (launch) | 3/5 | Trois boutons dorés de même poids (Jouer en solo, Se connecter, Créer un compte) : pas de hiérarchie ; message d'erreur rouge visible d'emblée ; chemin « Mondes téléchargés » gris minuscule ; pas de fond ni de logo Dofus ; à 1920 le bloc reste petit au milieu d'un grand vide. | 1) Un seul bouton primaire, les autres secondaires. 2) Erreur seulement après une tentative. 3) Fond illustré et logo. 4) Dossier de mondes dans une section avancée repliée. |
| Choix du personnage (lobby) | 4/5 | Carte sélectionnée claire, aperçu au centre ; ordre déroutant (Aelia avant Jean-Luc créé en premier) ; « Supprimer » presque aussi large que « Jouer » ; sous-titres gris peu contrastés ; le bloc ne grandit pas à 1920. | 1) Ordre = dernier joué. 2) « Supprimer » discret. 3) Contraste des sous-titres. 4) T1. |
| Création de personnage (creation) | 3,5/5 | Complet et lisible à 1280. À 1024 le panneau droit est rogné (« Féminin », « Par défaut », colonne de visages) ; à 1920 le personnage est repoussé en bas sous un grand vide central, panneaux collés aux bords ; icônes de classes sans nom avant sélection ; pastilles de couleur sans libellé. | 1) Panneaux adaptatifs ou en onglets sous ~1100 px. 2) Personnage centré dans l'espace libre. 3) Infobulle de nom par classe. 4) Libellés des couleurs. |
| Chargement (loading) | 1,5/5 | Pas d'écran : fondu du HUD. | T8. |
| HUD (hud) | 3/5 | T4, T5, T7 ; nom de zone et coordonnées « -1, -5 » en deux petites lignes de texte nu ; barre de sorts à deux rangées dont une vide au niveau 1 ; texte de PV excentré dans le cadre du joueur ; chat large (550 px) qui mange la map. | 1) T4, T5, T7. 2) Cartouche zone + coordonnées. 3) Seconde rangée repliée tant qu'elle est vide. 4) Chat redimensionnable et mémorisé. |
| Chat (hud, trade) | 3/5 | Six onglets dans 550 px ; texte 13 px ; saisie grisée ; fondu agressif (T7). | 1) Défilement d'onglets et pastille de non lus. 2) Couleurs de canal du client. 3) T7. |
| Groupe (party, partyinvite) | 3,5/5 | Cadre propre (étoile du chef, PV) mais sous la ligne de debug ; invitation sans minuteur d'expiration ; Refuser et Accepter de même style. | 1) Accepter primaire, Refuser secondaire, minuteur. 2) Placement sous le cartouche de zone. |
| Inventaire (inventory) | 3,5/5 | Bonne grille et barre de pods ; filtres en icônes sans libellé ; « Trier par » est un menu déroulant natif qui détonne ; haut de fenêtre (y=103) recouvre le minimap (jusqu'à 148). | 1) Menu de tri du kit. 2) Infobulle d'onglet. 3) Placement hors minimap (T3). |
| Équipement (equipment) | 3,5/5 | Emplacements vides très sombres (contraste faible) ; personnage petit ; panoplie lisible ; non aligné avec l'inventaire (haut à y=122 contre 103). | 1) Emplacements vides plus clairs avec icône par type. 2) Aligner les deux fenêtres. 3) Agrandir l'aperçu. |
| Caractéristiques (characteristics, characteristics2) | 4/5 | Bonne hiérarchie (nom, barres, onglets, tableau) ; colonne « + » vide sous « Total » ; énergie illisible (T9) ; bas de fenêtre collé à la barre de sorts à 1280, recouvre la barre et le chat à 1024 ; Réinitialiser aussi visible que le reste. | 1) T9. 2) « + » grisé sans capital. 3) Réinitialiser secondaire avec confirmation. |
| Grimoire (spells) | 3/5 | T6 ; liste coupée net en bas (« Ébriété » rognée) ; description longue sans séparation ; bouton « Sort utilisé » grisé sans explication ; hauteur 565 px sur 720. | 1) T6. 2) Dégradé de fin de liste. 3) Hauteur max 80 %. 4) Libellé explicite du bouton. |
| Métiers (jobs) | 2,5/5 | À l'état initial : un texte et une grande surface noire ; recouvre le minimap (T3). | État vide avec icône et conseil ; hauteur réduite ; placement. |
| Succès (achievements) | 3,5/5 | Deux colonnes claires ; catégories coupées en bas (« Songes Infinis ») ; points en gris peu lisible. | Dégradé de fin de liste ; progression par catégorie. |
| Quêtes (quests) | 3/5 | Lisible seule, mais superposée au dialogue à 1280 (T3) ; « Abandonner » pleine largeur, sans confirmation visible ; suivi sous le minimap correct. | 1) Z-order et placement. 2) Abandonner discret avec `UiConfirm`. |
| Dialogue (dialog) | 3/5 | Aucun portrait ni icône de PNJ ; texte 14 px ; « Fermer » pleine largeur étiré. | Portrait du PNJ, réponses en liste, bouton à largeur de contenu. |
| Banque (bank) | 3,5/5 | Double grille Sac/Coffre claire ; quantité en deux endroits (haut et bas) ; boutons éloignés de leur grille ; kamas en bas peu visibles. | Un seul champ de quantité ; boutons entre les grilles ; indice de double-clic. |
| Boutique (shop) | 4/5 | Liste claire ; prix rouge et bouton grisé si fonds insuffisants (bon retour) ; barre de défilement fine ; quantité séparée du bouton ; liste coupée net en bas. | Infobulle d'objet complète ; dégradé de fin de liste. |
| Atelier de craft (craft) | 3/5 | Trois colonnes denses ; ingrédients sans nom ni « possédé/requis » ; recettes sans icône ; « x0 possible » inexpliqué ; liste de recettes coupée. | 1) Icône + « 3/5 » par ingrédient (rouge si manquant). 2) Icône dans les recettes. 3) Recherche. |
| Forgemagie (forge) | 2,5/5 | Deux messages quasi identiques (« Choisissez un équipement. » et « Choisissez un équipement et une rune. ») ; grilles vides sans légende ; Historique vide ; recouvre la ligne d'aide ; pas d'aperçu de l'objet. | Un seul message guidant ; aperçu de l'objet et des runes ; états vides. |
| Échange (trade) | 3/5 | Deux grilles et état « En attente » corrects ; hauteur perdue sous la grille de l'autre joueur ; Annuler et Valider de même style ; recouvre la barre de sorts à 1280 ; spinner natif. | 1) Valider primaire, coche d'acceptation par côté. 2) Réduire la hauteur. |
| Zaap (zaap) | 3/5 | Un seul élément dans une fenêtre de ~420 px ; coût doré lisible ; chevauchement avec la carte (T3). | Hauteur au contenu ; carte intégrée. |
| Carte du monde (worldmap) | 4/5 | Belle et lisible, légende en bas ; légende en gris petit ; marqueurs distingués par la seule couleur (rouge/cyan/orange). | Formes différentes par type ; légende plus grande. |
| Contacts (friends) | 3/5 | Titre décalé et sans icône (seule fenêtre dont l'en-tête diffère) ; liste vide sans état (T11) ; recouvre le minimap ; champ d'ajout sans libellé fort ; « × » petit sans infobulle. | Icône de titre, état vide, infobulles, placement. |
| HUD de combat (fightplace, fight, fighttip, fightcast) | 3/5 | T2 ; timeline claire avec barres de PV ; chat translucide sur le champ de bataille ; liste de défis à gauche en texte doré sans titre ni valeur ; 6 cases remplies sur 20 ; « Fin du tour » et « Abandonner » de même style, sans confirmation visible ; infobulle de timeline qui masque les tuiles voisines. | 1) T2. 2) Fin du tour primaire, Abandonner secondaire avec confirmation. 3) Titre « Défis ». 4) Options intégrées à la barre. |
| Résultat de combat (fightresult) | 3/5 | Titre « Victoire » fort ; barre d'XP sans valeurs ; « Niveau supérieur ! » et « 42 K » mal alignés ; butin sans noms ; barres de PV pleines et vertes sous les perdants ; colonne de droite vide ; recouvre et atténue la barre de sorts. | 1) Gains en tableau aligné (XP, kamas, butin). 2) Barres des perdants à zéro. 3) Infobulles d'objet. 4) Fermer en primaire. |
| Infobulles (hovertooltip, fighttip) | 3,5/5 | Contenu net (niveau, XP estimée en bleu) ; infobulle de timeline masquant les tuiles voisines. | Décalage anti-chevauchement, largeur limitée. |
| Menu contextuel joueur (playermenu) | 2,5/5 | Police ~11 px, interligne serré, aucune icône ni séparation entre actions sociales et hostiles (Ignorer, Défier, Échanger) ; cible de clic petite. | Police 14 px du kit, séparateurs, icônes, lignes de 28 px. |
| Toasts (toasterr) | 3,5/5 | Lisible, fond opaque, haut-centre ; collision avec la ligne de debug (T4) ; pas d'icône par gravité ; 2,5 s court pour une erreur. | Icône et couleur par gravité, durée selon la longueur. |
| Console | non évalué | Capture inexploitable. | À refaire avant envoi. |
| Hôtel de vente | non évalué | Fenêtre non ouverte par l'outil. | À refaire. |

## Plan d'action proposé

1. T2 (mobs masqués en combat) : réserves haut et bas de la caméra, chat de combat, test.
2. T1 + T5 : échelle UI unique et fin des chevauchements à 1024.
3. T3 (gestionnaire de fenêtres) puis T4 (ligne de debug).
4. T6, T7, T9, T10 : correctifs du kit (`UiBar`, kamas, chat).
5. Écrans : lancement, création à 1024, résultat de combat, menu contextuel, craft et forge.
