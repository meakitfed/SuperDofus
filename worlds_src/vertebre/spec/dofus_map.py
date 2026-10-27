"""Which real Dofus creature, NPC or item stands for each Vertebre one (names -> Dofus ids, see gen/dofus_skin.py).

Monsters/bosses/summons: Dofus `monsters` row id (its `look` and portrait `gfxId` are used). NPC kinds: Dofus `npcs` row id.
Anything not listed keeps its generated look. Ids come from game/content/Content/Data/*dataroot.json."""

MONSTERS = {
    # Racines
    "Pousse-Gluante": 7730, "Rongeur de Sève": 104, "Sporelin": 5085, "Fouisseur Cuirassé": 106, "Acolyte des Racines": 53,
    "Garde-Écorce": 5082, "Lierre-Étrangleur": 3344, "Cueilleur Fongique": 371, "Colosse de Mousse": 282,
    # Marais des Cendres
    "Braise-Folle": 3273, "Rôdeur Cendreux": 149, "Crapaud de Suie": 796, "Spectre de Fumée": 378, "Écorcheur du Marais": 290,
    "Sangsue Ardente": 2697, "Prêtre des Cendres": 3690, "Meute Charbonnée": 5266, "Bourreau Calciné": 396,
    # Cité Renversée
    "Rouage Errant": 264, "Sentinelle Inversée": 3907, "Araignée Mécanique": 52, "Automate Chanteur": 4228, "Nettoyeur Fou": 4227,
    "Drone d'Alarme": 3910, "Mécano Rouillé": 2641, "Chien de Garde en Fonte": 4809, "Colosse-Pendule": 3740,
    # Archives Noyées
    "Livre Vorace": 3971, "Poisson-Scribe": 8267, "Spectre Lecteur": 379, "Copiste Noyé": 5004, "Gardien d'Encre": 7302,
    "Méduse d'Archive": 4461, "Archiviste Dévoyé": 3694, "Bête des Rayons": 5263, "Léviathan de Papier": 4471,
    # Couronne
    "Éclat Céleste": 5477, "Aurore Rampante": 927, "Séraphin Déchu": 3403, "Lame d'Azur": 2638, "Chimère Stellaire": 8077,
    "Œil du Firmament": 2448, "Prêtre du Ciel": 2577, "Gardien de Voûte": 4320, "Titan Fragmenté": 3743,
    # Boss (lore.BOSSES names are filled by gen/dofus_skin.py through BOSS_BY_FLOOR)
    # Invocations des boss et du Dévoyé
    "Livre invoqué": 3971, "Jeune Pousse": 7730, "Braise liée": 242, "Tourelle de Plan": 3910, "Spectre de Marge": 380, "Éclat de Couronne": 5478,
    # Invocations de classe
    "Stèle de Veille": 264, "Tome Gardien": 3971,
}
BOSS_BY_FLOOR = {1: 4167, 2: 292, 3: 3742, 4: 450, 5: 3418}

# NPC kinds (gen/world.py NPC_LOOK) -> Dofus `npcs` row id; "m<id>" = a `monsters` row (for the floating seals and doors)
NPCS = {"elder": 123, "smith": 4199, "merchant": 3424, "priest": 163, "young": 7556, "ghost": 993, "guard": 1112, "hood": 3846, "golem": 6290,
        "seal": "m5477", "door": "m2448"}

# Vertebre breed -> Dofus breed whose body, faces, colours and class icons it wears (the player look is the family bone 1 + skins)
BREEDS = {901: 1, 902: 8, 903: 5, 904: 4, 905: 7}

# Floors: Dofus map whose background layer is reused as the ground of each Vertebre theme (gen/world.py THEME), picked by map id
GROUNDS = {"roots": [88082696], "marsh": [171442178], "city": [54161728], "archive": [178259202], "crown": [196215818], "camp": [158861312]}
# Props: (theme or "*", kind) -> Dofus Maps/Gfx ids (Content/Maps/Gfx/<id>), one per variant; a kind without an entry keeps its drawn sprite
PROPS = {
    ("roots", "shroom"): [30330], ("roots", "root"): [801703, 801136, 801145], ("roots", "rock"): [7401], ("roots", "boulder"): [7401],
    ("marsh", "dead_tree"): [802780, 802758], ("marsh", "boulder"): [52782, 52781], ("marsh", "rock"): [52789, 52718], ("marsh", "bones"): [54177, 54182],
    ("*", "crate"): [7945], ("*", "rock"): [11267, 39643], ("*", "boulder"): [13407, 11267],
}
