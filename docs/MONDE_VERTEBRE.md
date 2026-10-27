# La Vertèbre : guide du monde

> Généré par `worlds_src/vertebre/gen/build_all.py` : ne pas éditer à la main (modifier `worlds_src/vertebre/`).

Trois cents ans après l'Effondrement, quelqu'un doit gravir ce qui reste de la Tour.

Monde `vertebre` : 12 maps, 5 classes, 50 créatures (dont 5 boss), 124 objets en 10 panoplies, 16 quêtes, 28 PNJ. Créatures, PNJ, classes, icônes et skins d'équipement empruntent les vrais sprites Dofus (`spec/dofus_map.py`, copiés depuis `game/content` par `gen/dofus_skin.py`, jamais commités) ; sols, décors et icônes de ressources restent dessinés par `worlds_src/vertebre/build`.

## Chronologie

- **An 0** : Les Tisseurs élèvent la Vertèbre au-dessus du Gouffre : une colonne de pierre-éther censée soutenir le Ciel, qui s'affaisse.
- **An 212** : Le Ciel s'abaisse d'une lieue en une nuit. Le Concile des Cinq se forme pour gravir la Tour et « retisser le Ciel » à la Couronne.
- **An 218** : Les Cinq montent, liés par le Fil, une corde d'éther qui les maintient unis. Un sixième membre reste au Pied-de-Tour pour tenir l'autre bout.
- **An 223** : Le Fil est coupé. C'est l'Effondrement : les cinq étages s'écrasent les uns sur les autres. Personne n'en est revenu.
- **An 223-523** : Les survivants fondent le Pied-de-Tour. Chaque étage est tenu par un Fragment, reste d'un des Cinq, qui répète sans fin sa dernière heure.
- **An 523** : Le Sixième, devenu le Vieux Veilleur, accueille enfin quelqu'un qui n'a pas peur de monter : vous.

## Les factions

- **Les Veilleurs du Pied** : Survivants du camp, tenus de génération en génération à garder la Porte Noire et à nourrir ceux qui montent.
- **Le Culte de la Mycélie** : Ils croient que les racines sont les nerfs de la Tour et que la Racine-Mère leur parle. Elle leur parle, en effet.
- **Les Cendreux** : Clans du marais devenus gris à force de respirer la cendre. Ils vénèrent le Capitaine Éteint, qui les a protégés puis consumés.
- **Les Renversés** : Les automates de la Cité, qui ont continué d'obéir à des ordres dont plus personne ne se souvient.
- **La Confrérie Noyée** : Copistes et lecteurs morts avec leurs livres. Ils relisent depuis trois siècles la même page, la dernière.
- **Les Aurés** : Éclats célestes qui ont pris forme de gardiens autour de la Couronne. Ils ne savent pas ce qu'ils gardent.

## Les classes

### Veilleur (Gardien de pierre)

Les Veilleurs montent la garde au pied de la Tour depuis trois siècles. Ils encaissent, ancrent leur position dans la pierre, puis rendent le choc au centuple. Plus ils tiennent debout, plus ils frappent fort.

| Niveau | Sort | PA | Portée | Description |
|---|---|---|---|---|
| 1 | Coup de Rempart | 3 | 1-1 | Un coup de bouclier. Ancré, il repousse la cible d'une case. |
| 1 | Garde de Pierre | 3 | 0-0 | Vous vous ancrez : bouclier et résistances pendant quelques tours. |
| 5 | Sentinelle | 4 | 1-4 | Un glyphe de pierre : qui finit son tour dedans est frappé. |
| 9 | Harpon de Garde | 2 | 2-5 | Attire un ennemi à vous et lui retire un PA. |
| 14 | Onde de Choc | 4 | 0-0 | Une onde autour de vous ; plus forte si vous êtes ancré. |
| 20 | Stèle de Veille | 4 | 1-3 | Dresse une stèle qui soigne les alliés proches à chaque tour. |
| 28 | Représailles | 2 | 0-0 | Les coups reçus sont en partie rendus à leur auteur. |
| 36 | Chute de la Tour | 6 | 1-5 | L'étage entier tombe sur la cible. Dépense l'Ancre pour frapper bien plus fort. |

### Fendeur de Brèche (Lame entre les plans)

Un Fendeur ne se bat pas : il apparaît. Sa lame ouvre des brèches dans l'air, et il passe à travers. Marquez une cible d'une faille, puis refermez-la sur elle.

| Niveau | Sort | PA | Portée | Description |
|---|---|---|---|---|
| 1 | Brèche | 3 | 2-6 | Vous traversez l'air jusqu'à la case visée. |
| 1 | Entaille | 3 | 1-1 | Une entaille qui laisse une faille dans la cible. |
| 5 | Échange Spatial | 2 | 1-5 | Échange votre place avec celle d'un autre combattant. |
| 9 | Déchirure | 3 | 1-5 | Un piège d'air : qui l'effleure est lacéré et marqué d'une faille. |
| 14 | Double Lame | 4 | 1-1 | Deux coups. Sur une faille, le second lacère plus profond. |
| 20 | Pas Fantôme | 3 | 0-0 | Vous disparaissez un tour et gagnez deux PM. |
| 28 | Sillage de Lames | 4 | 1-4 | Une ligne de lames devant vous. |
| 36 | Fracture de l'Instant | 6 | 1-3 | Un coup brutal. Sur une faille, il rend un PA et frappe plus fort. |

### Tisseur d'Éther (Mage des runes)

Les Tisseurs ont bâti la Tour avec des fils d'éther, et certains savent encore les nouer. Ils posent des runes sur le champ de bataille et les font toutes parler d'un seul mot.

| Niveau | Sort | PA | Portée | Description |
|---|---|---|---|---|
| 1 | Rune de Feu | 3 | 1-5 | Pose une rune ; Détonation la fait exploser. |
| 1 | Trait d'Éther | 3 | 1-6 | Un trait d'énergie pure. |
| 5 | Rune de Givre | 3 | 1-5 | Une rune qui gèle : dégâts d'eau et retrait de PA. |
| 9 | Détonation | 3 | 1-5 | Fait parler toutes les runes de la zone. |
| 14 | Fil Tendu | 3 | 2-6 | Un fil d'éther attire la cible et la ralentit. |
| 20 | Voile d'Éther | 3 | 1-4 | Un voile protège les alliés proches. |
| 28 | Tempête Nouée | 5 | 2-5 | Un glyphe de tempête qui brûle et ralentit au début de chaque tour. |
| 36 | Éclipse d'Éther | 6 | 1-5 | Une nova d'éther qui déclenche ensuite toutes les runes touchées. |

### Chasseur d'Ombre (Traqueur invisible)

Il vous voit avant que vous ne le voyiez, et il vous a déjà marqué. Le Chasseur d'Ombre frappe de loin, disparaît, et n'a pas de pitié pour ce qui porte sa marque.

| Niveau | Sort | PA | Portée | Description |
|---|---|---|---|---|
| 1 | Flèche Perçante | 4 | 2-6 | Traverse jusqu'à quatre cibles alignées. |
| 1 | Tir Silencieux | 3 | 2-7 | Un tir précis. Depuis l'ombre, il frappe de moitié plus fort. |
| 5 | Piège d'Ombre | 3 | 1-5 | Blesse et ralentit qui marche dessus. |
| 9 | Disparition | 2 | 0-0 | Invisible pendant deux tours : vos tirs frappent plus fort. |
| 14 | Marque du Chasseur | 2 | 1-7 | La proie est marquée et perd des résistances. |
| 20 | Pluie d'Ombre | 5 | 2-6 | Une pluie de traits en croix. |
| 28 | Repli | 2 | 0-0 | Vous reculez de trois cases et gagnez un PM. |
| 36 | Exécution | 6 | 3-8 | Un tir mortel. Sur une proie marquée, il frappe beaucoup plus fort. |

### Archiviste (Gardien des mémoires)

Les Archivistes consignent tout ce que la Tour a oublié. Leur encre soigne, protège, retire aux ennemis ce qu'ils savaient, et leurs Tomes se battent à leur place.

| Niveau | Sort | PA | Portée | Description |
|---|---|---|---|---|
| 1 | Plume Acérée | 3 | 1-5 | Une plume d'encre. |
| 1 | Soin d'Encre | 3 | 1-5 | Soigne un allié. |
| 5 | Tome Gardien | 4 | 1-3 | Invoque un Tome qui soigne vos alliés et frappe vos ennemis. |
| 9 | Annotation | 2 | 1-5 | Annote les alliés proches : puissance accrue. |
| 14 | Citation | 3 | 2-6 | Vole des PA à l'ennemi. |
| 20 | Marque-page | 2 | 1-6 | Échangez votre place avec un allié et protégez-le. |
| 28 | Chapitre Final | 6 | 1-4 | Soigne les alliés et blesse les ennemis de la zone. Les annotés guérissent plus. |
| 36 | Réécriture | 5 | 0-0 | Efface les blessures : soin massif autour de vous. |

## Les étages

### Le Pied-de-Tour (niveaux 1-1)

Un camp de tentes et de planches serré contre la Porte Noire, la seule entrée de la Vertèbre. On y chuchote, la nuit, pour ne pas réveiller ce qui dort au-dessus.

### Les Racines (niveaux 1-10)

La Tour s'est enracinée dans sa propre ruine. Les galeries sont tapissées de mousse phosphorescente ; quelque chose respire dans les murs.

| Créature | Niv. | Élément | PV | Rôle (sorts) | Note |
|---|---|---|---|---|---|
| **Pousse-Gluante** | 1 | earth | 14 | Morsure gluante, Bave collante | La première chose qu'on rencontre dans les Racines. Elle ne mord pas par méchanceté : elle a faim, et il y a de la sève sur vos bottes. |
| **Rongeur de Sève** | 2 | earth | 22 | Coup de groin, Charge poussive | Il creuse les galeries à la recherche de sève. Plus c'est profond, plus il est gros. Les plus gros n'ont jamais été vus. |
| **Sporelin** | 3 | air | 23 | Jet de spores, Nuage paralysant | Un champignon qui a décidé de flotter. Ses spores donnent des rêves, puis des maux de tête, puis des rêves plus longs. |
| **Fouisseur Cuirassé** | 4 | earth | 45 | Mandibule, Carapace | Un insecte de la taille d'un chien, cuirassé d'écorce. Il attend sans bouger qu'on lui tourne le dos. |
| **Acolyte des Racines** | 5 | water | 36 | Prière de sève, Bénédiction de la mousse | Un fidèle de la Mycélie. Il croit que les racines parlent. Elles parlent, d'ailleurs, mais pas pour lui. |
| **Garde-Écorce** | 6 | earth | 65 | Coup de bouclier, Peau d'écorce, Repoussoir | Ce qu'il reste d'un des gardes d'Ysmène. L'écorce a pris l'armure, puis l'homme. Il monte toujours la garde. |
| **Lierre-Étrangleur** | 7 | air | 52 | Étreinte, Étranglement | Il ne se déplace presque jamais. Il n'en a pas besoin : on finit toujours par passer à portée. |
| **Cueilleur Fongique** | 8 | water | 59 | Récolte, Fauchée, Fondu dans la mousse | Il cueille tout ce qui pousse, y compris ce qui marche. La Mycélie lui en sait gré. |
| **Colosse de Mousse** (élite) | 9 | earth | 150 | Poing moussu, Piétinement, Mousse épaisse | Il a mis trois siècles à pousser. Il n'a jamais appris à marcher, seulement à tomber vers l'avant. |

**Boss : Mère Ysmène, la Racine-Mère** (niv. 10, 316 PV) : Ysmène a nourri la Tour de sa propre vie pour qu'elle tienne un jour de plus. La Tour a pris tout ce qu'elle donnait, et davantage.

> « Chut... Ils dorment. Si tu marches doucement, ils ne sentiront que tes pas. Mais toi, tu as faim, n'est-ce pas ? Viens, mon enfant, je vais te nourrir. »
>
> « Merci... Dis à Orsolan que j'ai tenu mon bout du Fil aussi longtemps que j'ai pu. »

Sorts : Étreinte des racines, Floraison, Sporée, Sève nourricière, Éveil des pousses, Racines enchevêtrées, Bouclier d'écorce

### Le Marais des Cendres (niveaux 11-20)

Un étage effondré dans un ancien lac. L'eau est grise, l'air aussi, et des braises flottent encore à hauteur d'homme.

| Créature | Niv. | Élément | PV | Rôle (sorts) | Note |
|---|---|---|---|---|---|
| **Braise-Folle** | 11 | fire | 43 | Dernière flamme, Étincelle | Une flamme qui n'a plus rien à consumer et ne le sait pas. Elle se jette sur ce qui bouge, puis sur elle-même. |
| **Rôdeur Cendreux** | 12 | fire | 76 | Lame de braise, Voile de cendre, Entrave | Un enfant du marais. Il a appris à ne pas être vu avant d'apprendre à lire. Il ne lira pas. |
| **Crapaud de Suie** | 13 | earth | 110 | Langue collante, Rot de suie | Il vit dans les mares de cendre. Il a l'air de sourire, c'est seulement la forme de sa bouche. |
| **Spectre de Fumée** | 14 | air | 79 | Souffle de fumée, Voile asphyxiant, Brouillard | Ce qu'il reste d'un Cendreux mort sans avoir fini sa phrase. Il tousse, encore. |
| **Écorcheur du Marais** | 15 | fire | 137 | Griffes brûlantes, Éventrement, Bond du marais | Les Cendreux le dressent, comme d'autres dressent des chiens. Il n'a jamais appris à rapporter. |
| **Sangsue Ardente** | 16 | fire | 124 | Morsure incandescente, Spirale de feu | Elle pompe la chaleur plus que le sang. On sort de là gelé, ce qui, dans le marais, est une expérience nouvelle. |
| **Prêtre des Cendres** | 17 | fire | 119 | Feu votif, Onction de cendre, Ferveur | Il prie le Capitaine Éteint de ne pas s'éteindre tout à fait. Sa prière est entendue, ce qui est le problème. |
| **Meute Charbonnée** | 18 | neutral | 127 | Morsure charbonneuse, Course de meute | Ils chassaient ensemble, avant. Maintenant ils chassent aussi ensemble, mais avec les mêmes yeux. |
| **Bourreau Calciné** (élite) | 19 | fire | 322 | Hache rougie, Décapitation en rond, Cuirasse de braise | Le bourreau du Capitaine. Il n'a jamais eu de condamné. Il a donc élargi la définition. |

**Boss : Korvus Cendrelame, le Capitaine Éteint** (niv. 20, 624 PV) : Korvus a mis le feu au lac pour arrêter ce qui montait du Gouffre. Le feu l'a gardé : il ne s'éteint pas, lui non plus.

> « Un pas de plus et c'est la garde. Je n'ai pas quitté mon poste. Je n'ai jamais quitté mon poste. Quelle heure est-il ? Dis-moi que la relève arrive. »
>
> « La relève... Enfin. Prends mon épée, elle est plus lourde que la mémoire. »

Sorts : Estoc ardent, Charge du Capitaine, Brasier, Cercle de feu, Braise liée, Cuirasse de braise, Ordre de garde

### La Cité Renversée (niveaux 21-30)

Une ville entière retournée par la chute : les enseignes pendent du sol, les rues se parcourent au plafond. Des automates y balaient encore.

| Créature | Niv. | Élément | PV | Rôle (sorts) | Note |
|---|---|---|---|---|---|
| **Rouage Errant** | 21 | neutral | 119 | Dent de rouage, Grippage | Un rouage échappé d'une machine disparue. Il tourne, il roule, il se cogne. Il cherche son axe. |
| **Sentinelle Inversée** | 22 | neutral | 220 | Lame réglementaire, Garde à vue, Évacuation | Elle garde un bâtiment qui n'existe plus, la tête en bas depuis le premier jour. Elle ne s'en est pas aperçue. |
| **Araignée Mécanique** | 23 | fire | 164 | Aiguillon, Toile d'acier, Fil | Elle tisse. Quelqu'un lui a demandé de tisser une ville. Elle tisse, depuis. |
| **Automate Chanteur** | 24 | air | 155 | Note aiguë, Refrain, Crescendo | Il chante la même chanson depuis l'Effondrement. Ceux qui l'ont écoutée jusqu'au bout ne sont plus là pour la juger. |
| **Nettoyeur Fou** | 25 | earth | 234 | Coup de balai, Grand nettoyage | Il nettoie. Il nettoie tout ce qui bouge. Ce qui ne bouge plus est propre. |
| **Drone d'Alarme** | 26 | air | 132 | Sirène, Alerte générale, Rapport de dégâts | Il crie dès qu'il vous voit. Il n'a jamais appris à faire autre chose. |
| **Mécano Rouillé** | 27 | fire | 196 | Piège à clef, Clef à molette, Zone de maintenance | Il répare, il règle, il pose des pièges. Pour lui, la différence n'est pas évidente. |
| **Chien de Garde en Fonte** | 28 | earth | 307 | Morsure d'acier, Course de garde | Ses maîtres ne reviennent jamais. Il garde la porte, sans se demander de quel côté. |
| **Colosse-Pendule** (élite) | 29 | neutral | 555 | Balancier, Mouvement perpétuel, Contrepoids | Il balance, d'un côté, de l'autre, depuis trois siècles. Ça marque. |

**Boss : Tarq-9, l'Architecte Muet** (niv. 30, 1021 PV) : Tarq a transféré son esprit dans les plans de la Cité pour la réparer de l'intérieur. Les plans ont tenu, pas l'esprit.

> « ... Erreur de structure détectée dans l'objet : visiteur. Procédure : réajuster. Le visiteur sera intégré au bâtiment. »
>
> « ... Plan achevé. Révision demandée : l'étage supérieur n'est pas conforme. Il n'était pas prévu qu'il y ait un ciel. »

Sorts : Tourelle de plan, Plan de masse, Intégration, Réajustement, Réparation, Bouclier de plans, Découpe

### Les Archives Noyées (niveaux 31-40)

La bibliothèque des Tisseurs a été engloutie par une nappe d'éther liquide. Les livres flottent, les mots aussi.

| Créature | Niv. | Élément | PV | Rôle (sorts) | Note |
|---|---|---|---|---|---|
| **Livre Vorace** | 31 | water | 207 | Coup de reliure, Page avalée, Lecture hâtive | Il dévore les lecteurs distraits. Les autres, il les cite. |
| **Poisson-Scribe** | 32 | water | 239 | Morsure d'encre, Hameçon d'encre | Il copie les inscriptions à la nage. Ses fautes d'orthographe sont mortelles. |
| **Spectre Lecteur** | 33 | neutral | 223 | Mot de passe, Citation en retour, Silence de bibliothèque | Il lit par-dessus votre épaule. Si vous le dérangez, il vous fait taire. |
| **Copiste Noyé** | 34 | water | 282 | Plume affûtée, Rature, Ré-encrage | Il recopie. Il recopie ce qu'il vient de recopier. Il y a longtemps qu'il n'a plus de livre. |
| **Gardien d'Encre** | 35 | water | 265 | Marée d'encre, Goutte, Voile d'encre | Il garde les pages blanches, qui sont les plus dangereuses : on n'y a pas encore écrit ce qu'elles diront. |
| **Méduse d'Archive** | 36 | water | 412 | Filament, Sécrétion salvatrice, Étreinte molle | Elle flotte entre les rayons comme un mauvais souvenir. Son poison est en fait une très vieille encre. |
| **Archiviste Dévoyé** | 37 | neutral | 312 | Appeler un Livre, Citation tronquée, Annotation | Il a décidé que les livres devaient se défendre. Ils l'ont pris au mot. |
| **Bête des Rayons** | 38 | earth | 469 | Coup de corne, Bousculade | Elle vit entre les rayons, et mange les plus anciens. On dit qu'elle ne digère que l'éther. |
| **Léviathan de Papier** (élite) | 39 | water | 786 | Étreinte de pages, Déferlante, Plongeon | Mille cahiers de papier mâché, dans lesquels quelqu'un a mis le feu, puis l'eau. |

**Boss : Séléné Vael, la Bibliothécaire Noyée** (niv. 40, 1497 PV) : Séléné avait lu le dernier livre des Tisseurs et compris ce qu'était la Tour. Elle a tenté de l'oublier ; l'éther liquide a gardé la page à sa place.

> « Chaque page que tu lis me déchire un peu. Ne lis pas la suivante. Je t'en prie, ferme ce livre. Il parle de toi. »
>
> « Il le savait, Orsolan. Demande-lui pourquoi il n'est jamais monté. Demande-lui qui tenait l'autre bout du Fil. »

Sorts : Citation en retour, Page tournée, Ruée d'encre, Spectre de marge, Silence, Lecture dévorante, Marée haute, Voile d'encre

### La Couronne (niveaux 41-50)

Les derniers étages tiennent par miracle : plateformes de pierre claire suspendues à rien, sous un ciel trop proche.

| Créature | Niv. | Élément | PV | Rôle (sorts) | Note |
|---|---|---|---|---|---|
| **Éclat Céleste** | 41 | air | 257 | Rayon d'azur, Éclatement | Un morceau de ciel qui a oublié qu'il est tombé. Il continue de briller, par politesse. |
| **Aurore Rampante** | 42 | air | 364 | Morsure de lumière, Reflet captif | Un lever de soleil qui rampe. Elle ne comprend pas pourquoi les gens se cachent le visage. |
| **Séraphin Déchu** | 43 | air | 443 | Lame d'aurore, Piqué, Ailes repliées | Il est tombé de très haut, et n'a pas fini de tomber. Ses ailes ne battent plus, elles se souviennent. |
| **Lame d'Azur** | 44 | neutral | 350 | Double azur, Éclipse, Estoc | Elle a servi la Couronne. Elle a fini de servir, mais personne n'a osé le lui dire. |
| **Chimère Stellaire** | 45 | fire | 541 | Morsure d'étoile, Souffle céleste, Bond stellaire | Une constellation qui a trouvé un corps. Elle a mal choisi. |
| **Œil du Firmament** | 46 | fire | 482 | Regard solaire, Éblouissement, Larme brûlante | Il regarde. C'est tout ce qu'il fait. Ceux qu'il regarde se mettent à brûler, mais ça n'a rien à voir. |
| **Prêtre du Ciel** | 47 | air | 419 | Prière stellaire, Rayon bienfaisant, Bénédiction d'azur, Auréole | Il prie quelqu'un. Ce quelqu'un le regarde, d'en haut, depuis un peu plus près chaque année. |
| **Gardien de Voûte** | 48 | neutral | 782 | Marteau de voûte, Mur de lumière, Seuil | La porte de la Couronne lui a été confiée. On ne lui a pas dit de laquelle. |
| **Titan Fragmenté** (élite) | 49 | earth | 1204 | Poing du ciel, Chute de morceaux, Armure de gravats | Il y en avait neuf. Il ne reste que celui-là, tenu ensemble par l'habitude. |

**Boss : Aurelian, le Premier Gravit** (niv. 50, 2101 PV) : Aurelian a atteint la Couronne seul, après la chute des autres. Il y a vu le visage du Dormeur et n'a plus jamais voulu en redescendre.

> « Je les ai tous perdus en montant. Je ne perdrai pas la Couronne. Laisse-moi finir. Laisse-moi tout retisser, ou je te briserai comme eux. »
>
> « Orsolan a eu raison. Je l'ai haï trois cents ans de l'avoir eu. Va, la Couronne est derrière moi. Choisis mieux que nous. »

Sorts : Lame du Premier Gravit, Piqué céleste, Éclat de couronne, Cime, Appel des Aurés, Armure d'aurore, Gravir, Pardon

## Les panoplies

### Panoplie de la Sève-Mère

- Capuche de Sève (niv. 4) : Tissée dans les fibres que Mère Ysmène donnait à la Tour. Elle est tiède, comme un être vivant.
- Manteau de Mousse (niv. 6) : Fait partie de la Panoplie de la Sève-Mère. Tissée dans les fibres que Mère Ysmène donnait à la Tour.
- Pendentif de Résine (niv. 8) : Fait partie de la Panoplie de la Sève-Mère. Tissée dans les fibres que Mère Ysmène donnait à la Tour.
- Ceinture de Lianes (niv. 10) : Fait partie de la Panoplie de la Sève-Mère. Tissée dans les fibres que Mère Ysmène donnait à la Tour.
- Bottes de Racine (niv. 12) : Fait partie de la Panoplie de la Sève-Mère. Tissée dans les fibres que Mère Ysmène donnait à la Tour.
- Anneau de Bourgeon (niv. 13) : Fait partie de la Panoplie de la Sève-Mère. Tissée dans les fibres que Mère Ysmène donnait à la Tour.

### Panoplie de l'Écorce Ferrée

- Heaume d'Écorce (niv. 5) : Les gardes des Racines laissaient l'écorce pousser sur leurs armures, jusqu'à ne plus savoir où finissait la peau.
- Bouclier de Mousse-Ferrée (niv. 7) : Fait partie de la Panoplie de l'Écorce Ferrée. Les gardes des Racines laissaient l'écorce pousser sur leurs armures, jusqu'à ne plus savoir où finissait la peau.
- Anneau de Lichen (niv. 9) : Fait partie de la Panoplie de l'Écorce Ferrée. Les gardes des Racines laissaient l'écorce pousser sur leurs armures, jusqu'à ne plus savoir où finissait la peau.
- Brodequins d'Écorce (niv. 11) : Fait partie de la Panoplie de l'Écorce Ferrée. Les gardes des Racines laissaient l'écorce pousser sur leurs armures, jusqu'à ne plus savoir où finissait la peau.
- Masse de Bois-Dur (niv. 13) : Fait partie de la Panoplie de l'Écorce Ferrée. Les gardes des Racines laissaient l'écorce pousser sur leurs armures, jusqu'à ne plus savoir où finissait la peau.

### Panoplie Cendrelame

- Heaume Calciné (niv. 14) : Le Capitaine Korvus fit forger ces pièces dans le feu même du lac. Elles ne refroidissent jamais tout à fait.
- Cape de Braise (niv. 16) : Fait partie de la Panoplie Cendrelame. Le Capitaine Korvus fit forger ces pièces dans le feu même du lac.
- Collier de Médailles Fondues (niv. 18) : Fait partie de la Panoplie Cendrelame. Le Capitaine Korvus fit forger ces pièces dans le feu même du lac.
- Ceinture du Capitaine (niv. 20) : Fait partie de la Panoplie Cendrelame. Le Capitaine Korvus fit forger ces pièces dans le feu même du lac.
- Bottes de Suie (niv. 22) : Fait partie de la Panoplie Cendrelame. Le Capitaine Korvus fit forger ces pièces dans le feu même du lac.
- Anneau de Cendre (niv. 23) : Fait partie de la Panoplie Cendrelame. Le Capitaine Korvus fit forger ces pièces dans le feu même du lac.

### Voile de Brume

- Capuche de Brume (niv. 15) : Les chasseurs du marais s'enveloppaient de brume pour qu'on ne les voie pas arriver. La brume les a gardés.
- Arc de Brume (niv. 17) : Fait partie de la Voile de Brume. Les chasseurs du marais s'enveloppaient de brume pour qu'on ne les voie pas arriver.
- Anneau de Vapeur (niv. 19) : Fait partie de la Voile de Brume. Les chasseurs du marais s'enveloppaient de brume pour qu'on ne les voie pas arriver.
- Bottes de Fumée (niv. 21) : Fait partie de la Voile de Brume. Les chasseurs du marais s'enveloppaient de brume pour qu'on ne les voie pas arriver.
- Ceinture de Gaze (niv. 23) : Fait partie de la Voile de Brume. Les chasseurs du marais s'enveloppaient de brume pour qu'on ne les voie pas arriver.

### Panoplie du Rouage-Inversé

- Casque de Cuivre (niv. 24) : Chaque pièce tourne sur elle-même quand on ne la regarde pas. Les Renversés prétendent qu'ainsi elle garde l'heure.
- Cape de Poulies (niv. 26) : Fait partie de la Panoplie du Rouage-Inversé. Chaque pièce tourne sur elle-même quand on ne la regarde pas.
- Amulette d'Horloge (niv. 28) : Fait partie de la Panoplie du Rouage-Inversé. Chaque pièce tourne sur elle-même quand on ne la regarde pas.
- Ceinture à Engrenages (niv. 30) : Fait partie de la Panoplie du Rouage-Inversé. Chaque pièce tourne sur elle-même quand on ne la regarde pas.
- Bottes à Ressort (niv. 32) : Fait partie de la Panoplie du Rouage-Inversé. Chaque pièce tourne sur elle-même quand on ne la regarde pas.
- Anneau de Pignon (niv. 33) : Fait partie de la Panoplie du Rouage-Inversé. Chaque pièce tourne sur elle-même quand on ne la regarde pas.

### Panoplie du Mécanicien Muet

- Chapeau de Mécanicien (niv. 25) : Tarq-9 ne parle plus, mais ses outils, eux, continuent de le faire à sa place : un cliquetis, de loin en loin.
- Bouclier d'Engrenage (niv. 27) : Fait partie de la Panoplie du Mécanicien Muet. Tarq-9 ne parle plus, mais ses outils, eux, continuent de le faire à sa place : un cliquetis, de loin en loin.
- Anneau de Rivet (niv. 29) : Fait partie de la Panoplie du Mécanicien Muet. Tarq-9 ne parle plus, mais ses outils, eux, continuent de le faire à sa place : un cliquetis, de loin en loin.
- Brodequins de Fonte (niv. 31) : Fait partie de la Panoplie du Mécanicien Muet. Tarq-9 ne parle plus, mais ses outils, eux, continuent de le faire à sa place : un cliquetis, de loin en loin.
- Marteau de Tarq (niv. 33) : Fait partie de la Panoplie du Mécanicien Muet. Tarq-9 ne parle plus, mais ses outils, eux, continuent de le faire à sa place : un cliquetis, de loin en loin.

### Panoplie de la Marée-Savante

- Capuche Détrempée (niv. 34) : Les pages gorgées d'eau ne s'effacent pas : elles pèsent. Ces vêtements portent trois siècles de lecture.
- Cape de Pages (niv. 36) : Fait partie de la Panoplie de la Marée-Savante. Les pages gorgées d'eau ne s'effacent pas : elles pèsent.
- Collier d'Encrier (niv. 38) : Fait partie de la Panoplie de la Marée-Savante. Les pages gorgées d'eau ne s'effacent pas : elles pèsent.
- Ceinture de Reliure (niv. 40) : Fait partie de la Panoplie de la Marée-Savante. Les pages gorgées d'eau ne s'effacent pas : elles pèsent.
- Bottes Gorgées (niv. 42) : Fait partie de la Panoplie de la Marée-Savante. Les pages gorgées d'eau ne s'effacent pas : elles pèsent.
- Anneau Marque-Page (niv. 43) : Fait partie de la Panoplie de la Marée-Savante. Les pages gorgées d'eau ne s'effacent pas : elles pèsent.

### Panoplie de l'Encre-Noire

- Chapeau de Scribe Noir (niv. 35) : L'encre de Séléné ne sèche pas. On dit qu'elle écrit encore, la nuit, dans la marge de ceux qui l'ont lue.
- Dague de Plume (niv. 37) : Fait partie de la Panoplie de l'Encre-Noire. L'encre de Séléné ne sèche pas.
- Anneau d'Index (niv. 39) : Fait partie de la Panoplie de l'Encre-Noire. L'encre de Séléné ne sèche pas.
- Bottes de Papier (niv. 41) : Fait partie de la Panoplie de l'Encre-Noire. L'encre de Séléné ne sèche pas.
- Livre-Bouclier (niv. 43) : Fait partie de la Panoplie de l'Encre-Noire. L'encre de Séléné ne sèche pas.

### Panoplie de l'Aurore-Brisée

- Diadème d'Aurore (niv. 44) : Les Aurés laissent tomber des éclats en passant. Quelqu'un a eu l'idée de les coudre.
- Cape d'Azur (niv. 45) : Fait partie de la Panoplie de l'Aurore-Brisée. Les Aurés laissent tomber des éclats en passant.
- Amulette de la Couronne (niv. 46) : Fait partie de la Panoplie de l'Aurore-Brisée. Les Aurés laissent tomber des éclats en passant.
- Ceinture de Lumière (niv. 47) : Fait partie de la Panoplie de l'Aurore-Brisée. Les Aurés laissent tomber des éclats en passant.
- Bottes d'Éclat (niv. 48) : Fait partie de la Panoplie de l'Aurore-Brisée. Les Aurés laissent tomber des éclats en passant.
- Anneau d'Aube (niv. 49) : Fait partie de la Panoplie de l'Aurore-Brisée. Les Aurés laissent tomber des éclats en passant.

### Panoplie du Premier Gravit

- Heaume du Gravit (niv. 45) : Les armes d'Aurelian, fondues à la lueur de la Couronne. Elles pèsent le poids de ce qu'on perd en montant.
- Lame du Premier Gravit (niv. 46) : Fait partie de la Panoplie du Premier Gravit. Les armes d'Aurelian, fondues à la lueur de la Couronne.
- Bouclier de Voûte (niv. 47) : Fait partie de la Panoplie du Premier Gravit. Les armes d'Aurelian, fondues à la lueur de la Couronne.
- Anneau de Cime (niv. 48) : Fait partie de la Panoplie du Premier Gravit. Les armes d'Aurelian, fondues à la lueur de la Couronne.
- Bottes de Cime (niv. 49) : Fait partie de la Panoplie du Premier Gravit. Les armes d'Aurelian, fondues à la lueur de la Couronne.

## Les quêtes

### Gravir : les Racines

- **Franchir la Porte Noire** : Orsolan vous demande de descendre dans les Racines et de voir, de vos yeux, ce que la Tour est devenue.
- **Ce qui garde l'étage** : Les Gardes-Écorce barrent la route vers la Racine-Mère. Il faudra en abattre quelques-uns.
- **La Racine-Mère** : Mère Ysmène attend, au bout de la grande galerie, derrière la porte de sève.
- **Rapport à Orsolan** : Rapportez à Orsolan ce que Mère Ysmène a dit en tombant.

### Gravir : le Marais des Cendres

- **Le deuxième étage** : Montez l'escalier de la Racine-Mère jusqu'au Marais des Cendres.
- **Les bêtes du marais** : Les Meutes Charbonnées gardent le passage du Capitaine. Chassez-en quelques-unes.
- **Le Capitaine Éteint** : Le Capitaine Korvus tient toujours son poste, au bout du marais.
- **Rapport à Orsolan** : Dites à Orsolan que la relève est arrivée.

### Gravir : la Cité Renversée

- **Le troisième étage** : Montez jusqu'à la Cité, qui est à l'envers.
- **Les sentinelles** : Les Sentinelles Inversées gardent la ville. Réduisez leur nombre.
- **L'Architecte Muet** : Tarq-9 s'est intégré à ses propres plans. Il faudra le démonter.
- **Rapport à Orsolan** : Rapportez à Orsolan ce que Tarq-9 a dit : un plan, une erreur.

### Gravir : les Archives Noyées

- **Le quatrième étage** : Montez jusqu'aux Archives, sous l'éther liquide.
- **Les gardiens de l'encre** : Les Gardiens d'Encre protègent les pages blanches. Abattez-en.
- **La Bibliothécaire** : Séléné Vael garde le dernier livre. Elle vous suppliera de ne pas le lire.
- **Ce que Séléné a dit** : Elle a dit de demander à Orsolan qui tenait l'autre bout du Fil. Retournez le lui demander.

### Gravir : la Couronne

- **Le cinquième étage** : Montez jusqu'à la Couronne, là où la Tour touche à ce qui n'est plus elle.
- **Les gardiens de la voûte** : Les Gardiens de Voûte barrent la dernière marche. Abattez-en.
- **Le Premier Gravit** : Aurelian est resté seul à la Couronne. Allez le trouver.
- **Le sommet** : Aurelian vous laisse passer. Montez à la dernière marche et écoutez ce qui vous attend.

### Les Cartes de Kael

- **Récits d'étage** : Kael dessine des cartes de ce qu'il y a au-dessus. Il vous demande de visiter chaque étage et de lui raconter.
- **Retour auprès de Kael** : Racontez-lui ce que vous avez vu.

### Le Pan de Mur Creux

- **Une salle derrière le mur** : Vess ne peut pas aller dans la salle derrière le pan de mur creux. Si vous la trouvez, rapportez-lui ce qui s'y cache.
- **Merci, étranger** : Vess garde le secret. Elle vous remet quelque chose en échange.

### Le Passage de Mara

- **La médaille perdue** : Mara a perdu une médaille fondue à l'ouest, entre les deux monticules. Allez la chercher.
- **Le passage** : Mara vous ouvre son passage, qui évite les meutes jusqu'à la porte de l'antre.

### Réparer l'heure

- **Pièces de rechange** : Maître Pivot a besoin de ressorts brisés et de rouages cuivrés pour réparer ce qui peut l'être.
- **L'heure retrouvée** : Maître Pivot fait sonner son horloge, pour la première fois depuis trois siècles.

### Pages perdues

- **Les pages dispersées** : Madame Quire cherche des pages mouillées et un index effacé pour reconstituer un livre.
- **Le livre reconstitué** : Madame Quire relie ce que vous lui avez rapporté, et vous prête un volume précieux.

### Ce qui garde la porte

- **La tâche d'un Auré** : L'Auré égaré ne se rappelle plus ce qu'il gardait, mais il sent que les Gardiens de Voûte l'oublient aussi. Abattez-en trois.
- **Un souvenir** : L'Auré égaré se rappelle, un instant, la porte qu'il gardait.

### Mémoire des Racines

- **Les quatre fragments** : L'Écho veut les quatre fragments de mémoire de cet étage pour les lire à voix haute. Ils sont cachés : fouillez les recoins, les salles secrètes, les coffres, les cadavres.
- **Ce que disent les murs** : L'Écho a lu. Écoutez-le, à votre tour.

### Mémoire des Marais des Cendres

- **Les quatre fragments** : L'Écho veut les quatre fragments de mémoire de cet étage pour les lire à voix haute. Ils sont cachés : fouillez les recoins, les salles secrètes, les coffres, les cadavres.
- **Ce que disent les murs** : L'Écho a lu. Écoutez-le, à votre tour.

### Mémoire des Cité Renversée

- **Les quatre fragments** : L'Écho veut les quatre fragments de mémoire de cet étage pour les lire à voix haute. Ils sont cachés : fouillez les recoins, les salles secrètes, les coffres, les cadavres.
- **Ce que disent les murs** : L'Écho a lu. Écoutez-le, à votre tour.

### Mémoire des Archives Noyées

- **Les quatre fragments** : L'Écho veut les quatre fragments de mémoire de cet étage pour les lire à voix haute. Ils sont cachés : fouillez les recoins, les salles secrètes, les coffres, les cadavres.
- **Ce que disent les murs** : L'Écho a lu. Écoutez-le, à votre tour.

### Mémoire des Couronne

- **Les quatre fragments** : L'Écho veut les quatre fragments de mémoire de cet étage pour les lire à voix haute. Ils sont cachés : fouillez les recoins, les salles secrètes, les coffres, les cadavres.
- **Ce que disent les murs** : L'Écho a lu. Écoutez-le, à votre tour.

## Les deux fins

- **Retisser le Ciel** : Vous nouez le Fil à la Couronne. Le Dormeur se rendort, la Tour se redresse, étage après étage. Les Fragments s'apaisent, mais le Fil vous tient désormais, et vous restez là-haut, à votre tour, pour le tenir.
- **Délier la Tour** : Vous tranchez ce qui reste du Fil. La Tour s'effondre pour de bon, libérant les Fragments, et le Dormeur s'étire. Le Ciel remonte. Plus rien ne retient personne, ni les morts, ni les vivants.

## Les fragments de mémoire

**Les Racines**

- *Fragment de sève séchée* : « Ysmène plante ses mains dans le mur. Elle dit que la Tour est malade et qu'elle va la soigner. Aurelian regarde ailleurs. »
- *Fragment de journal détrempé* : « Jour 4 de la montée. Le Fil vibre quand nous marchons à l'unisson. Orsolan, en bas, nous répond par trois secousses. »
- *Fragment de comptine* : « Un pas pour la Tour, deux pas pour le Ciel, trois pas pour celui qui reste. » (On chantait cela aux enfants du camp.)
- *Fragment de carte griffonnée* : Un plan des Racines. Une salle est entourée d'un cercle rouge. En marge : « Ne pas réveiller ce qui est dessous. Ce n'est pas la Tour. »

**Le Marais des Cendres**

- *Fragment d'ordre de mission* : « Capitaine Korvus : tenir le lac, jour et nuit, jusqu'à nouvel ordre. Signé : Aurelian. » Le sceau est brûlé à moitié.
- *Fragment de lettre calcinée* : « Si tu lis ceci, c'est que le feu a pris. Ne laisse pas les enfants du marais s'approcher du Gouffre. »
- *Fragment de médaille fondue* : Une médaille du Concile, tordue par la chaleur. Au dos : « Pour avoir marché sur l'eau. »
- *Fragment de chant cendreux* : « Il brûle pour nous, il brûle pour nous, et quand il s'éteindra, nous éteindrons aussi. »

**La Cité Renversée**

- *Fragment de plan de la Cité* : Les plans montrent la ville à l'endroit. Une note de Tarq : « Elle n'était pas faite pour tomber. Elle était faite pour monter. »
- *Fragment de ticket de tramway* : Un ticket pour « Le Sommet, correspondance : le Ciel ». Il n'a jamais été composté.
- *Fragment de circuit gravé* : « Je me recopie dans la Cité. Si je me perds, qu'on me relise. Orsolan, reviens. »
- *Fragment d'enseigne retournée* : « Horloger de la Tour : réparations en tous genres, même du temps. » Le temps est resté en panne.

**Les Archives Noyées**

- *Fragment de page trempée* : « Le dernier livre des Tisseurs parle d'un dormeur. Il n'y a aucune image, seulement une phrase : ne pas gravir. »
- *Fragment d'index effacé* : L'index ne cite que deux noms : celui de Séléné, et un autre, rayé si fort que le papier est troué.
- *Fragment de marque-page* : « J'ai demandé à Orsolan pourquoi il n'était pas monté avec nous. Il a répondu qu'il tenait le Fil. Il l'a répondu trop vite. »
- *Fragment d'encrier brisé* : Une dernière note : « Quand le Fil a claqué, ce n'est pas la Tour qui a crié. C'était le Dormeur. »

**La Couronne**

- *Fragment d'éclat d'azur* : « Aurelian a gravi la dernière marche seul. Il a regardé le ciel. Le ciel l'a regardé aussi. »
- *Fragment de cantique des Aurés* : « Nous gardons la porte. Nous ne savons pas ce qu'elle garde. Nous la gardons, c'est ainsi. »
- *Fragment de lettre d'Orsolan* : « Pardonne-moi, Aurelian. Si je n'avais pas coupé, tu l'aurais éveillé. Pardonne-moi d'avoir eu raison. »
- *Fragment de souffle* : Un murmure, plus qu'un texte : « Retisser... ou délier. Le Ciel attend celui qui choisira. »

