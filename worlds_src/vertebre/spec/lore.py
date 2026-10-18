"""Bible de lore de La Vertebre : source unique des textes (le reste du monde la cite).

Le secret (revele au sommet) : la Vertebre n'est pas une tour, c'est l'epine d'un Dormeur colossal dont
le crane est la Couronne. Le Concile des Cinq voulait gravir la Tour pour "retisser le Ciel" (le Dormeur
s'etait mis a le faire tomber, lentement, sur le monde). Orsolan Vey, le Sixieme du Concile, a coupe le Fil
qui reliait les Cinq a mi-ascension, parce qu'il avait compris qu'a la Couronne ils eveilleraient le Dormeur.
Le Fil coupe, la Tour s'est effondree sur elle-meme : les etages sont tombes les uns dans les autres, et les
Cinq, lies a leur etage par le Fil brise, sont devenus des Fragments. Orsolan a passe 300 ans au Pied-de-Tour
a attendre quelqu'un capable de finir ce qu'il a empeche.
"""

TITLE = "La Vertèbre"
TAGLINE = "Trois cents ans après l'Effondrement, quelqu'un doit gravir ce qui reste de la Tour."

CHRONOLOGY = [
    ("An 0", "Les Tisseurs élèvent la Vertèbre au-dessus du Gouffre : une colonne de pierre-éther censée soutenir le Ciel, qui s'affaisse."),
    ("An 212", "Le Ciel s'abaisse d'une lieue en une nuit. Le Concile des Cinq se forme pour gravir la Tour et « retisser le Ciel » à la Couronne."),
    ("An 218", "Les Cinq montent, liés par le Fil, une corde d'éther qui les maintient unis. Un sixième membre reste au Pied-de-Tour pour tenir l'autre bout."),
    ("An 223", "Le Fil est coupé. C'est l'Effondrement : les cinq étages s'écrasent les uns sur les autres. Personne n'en est revenu."),
    ("An 223-523", "Les survivants fondent le Pied-de-Tour. Chaque étage est tenu par un Fragment, reste d'un des Cinq, qui répète sans fin sa dernière heure."),
    ("An 523", "Le Sixième, devenu le Vieux Veilleur, accueille enfin quelqu'un qui n'a pas peur de monter : vous."),
]

FACTIONS = {
    "veilleurs": ("Les Veilleurs du Pied", "Survivants du camp, tenus de génération en génération à garder la Porte Noire et à nourrir ceux qui montent."),
    "mycelie": ("Le Culte de la Mycélie", "Ils croient que les racines sont les nerfs de la Tour et que la Racine-Mère leur parle. Elle leur parle, en effet."),
    "cendreux": ("Les Cendreux", "Clans du marais devenus gris à force de respirer la cendre. Ils vénèrent le Capitaine Éteint, qui les a protégés puis consumés."),
    "renverses": ("Les Renversés", "Les automates de la Cité, qui ont continué d'obéir à des ordres dont plus personne ne se souvient."),
    "noyes": ("La Confrérie Noyée", "Copistes et lecteurs morts avec leurs livres. Ils relisent depuis trois siècles la même page, la dernière."),
    "aures": ("Les Aurés", "Éclats célestes qui ont pris forme de gardiens autour de la Couronne. Ils ne savent pas ce qu'ils gardent."),
}

# etage : (nom, niveau mini-maxi, ambiance, couleur principale RGB, accent RGB, faction)
FLOORS = {
    0: dict(name="Le Pied-de-Tour", lv=(1, 1), color=(110, 98, 84), accent=(255, 190, 90), faction="veilleurs",
            blurb="Un camp de tentes et de planches serré contre la Porte Noire, la seule entrée de la Vertèbre. On y chuchote, la nuit, pour ne pas réveiller ce qui dort au-dessus."),
    1: dict(name="Les Racines", lv=(1, 10), color=(84, 112, 70), accent=(170, 110, 255), faction="mycelie",
            blurb="La Tour s'est enracinée dans sa propre ruine. Les galeries sont tapissées de mousse phosphorescente ; quelque chose respire dans les murs."),
    2: dict(name="Le Marais des Cendres", lv=(11, 20), color=(112, 108, 108), accent=(255, 120, 50), faction="cendreux",
            blurb="Un étage effondré dans un ancien lac. L'eau est grise, l'air aussi, et des braises flottent encore à hauteur d'homme."),
    3: dict(name="La Cité Renversée", lv=(21, 30), color=(150, 120, 70), accent=(70, 220, 200), faction="renverses",
            blurb="Une ville entière retournée par la chute : les enseignes pendent du sol, les rues se parcourent au plafond. Des automates y balaient encore."),
    4: dict(name="Les Archives Noyées", lv=(31, 40), color=(60, 84, 130), accent=(230, 220, 160), faction="noyes",
            blurb="La bibliothèque des Tisseurs a été engloutie par une nappe d'éther liquide. Les livres flottent, les mots aussi."),
    5: dict(name="La Couronne", lv=(41, 50), color=(190, 180, 215), accent=(255, 220, 100), faction="aures",
            blurb="Les derniers étages tiennent par miracle : plateformes de pierre claire suspendues à rien, sous un ciel trop proche."),
}

# ── les cinq du Concile, devenus Fragments (les boss) ───────────────────────────
BOSSES = {
    1: dict(name="Mère Ysmène", title="la Racine-Mère", role="guérisseuse du Concile",
            story="Ysmène a nourri la Tour de sa propre vie pour qu'elle tienne un jour de plus. La Tour a pris tout ce qu'elle donnait, et davantage.",
            intro="« Chut... Ils dorment. Si tu marches doucement, ils ne sentiront que tes pas. Mais toi, tu as faim, n'est-ce pas ? Viens, mon enfant, je vais te nourrir. »",
            defeat="« Merci... Dis à Orsolan que j'ai tenu mon bout du Fil aussi longtemps que j'ai pu. »"),
    2: dict(name="Korvus Cendrelame", title="le Capitaine Éteint", role="épée du Concile",
            story="Korvus a mis le feu au lac pour arrêter ce qui montait du Gouffre. Le feu l'a gardé : il ne s'éteint pas, lui non plus.",
            intro="« Un pas de plus et c'est la garde. Je n'ai pas quitté mon poste. Je n'ai jamais quitté mon poste. Quelle heure est-il ? Dis-moi que la relève arrive. »",
            defeat="« La relève... Enfin. Prends mon épée, elle est plus lourde que la mémoire. »"),
    3: dict(name="Tarq-9", title="l'Architecte Muet", role="bâtisseur du Concile",
            story="Tarq a transféré son esprit dans les plans de la Cité pour la réparer de l'intérieur. Les plans ont tenu, pas l'esprit.",
            intro="« ... Erreur de structure détectée dans l'objet : visiteur. Procédure : réajuster. Le visiteur sera intégré au bâtiment. »",
            defeat="« ... Plan achevé. Révision demandée : l'étage supérieur n'est pas conforme. Il n'était pas prévu qu'il y ait un ciel. »"),
    4: dict(name="Séléné Vael", title="la Bibliothécaire Noyée", role="mémoire du Concile",
            story="Séléné avait lu le dernier livre des Tisseurs et compris ce qu'était la Tour. Elle a tenté de l'oublier ; l'éther liquide a gardé la page à sa place.",
            intro="« Chaque page que tu lis me déchire un peu. Ne lis pas la suivante. Je t'en prie, ferme ce livre. Il parle de toi. »",
            defeat="« Il le savait, Orsolan. Demande-lui pourquoi il n'est jamais monté. Demande-lui qui tenait l'autre bout du Fil. »"),
    5: dict(name="Aurelian", title="le Premier Gravit", role="chef du Concile",
            story="Aurelian a atteint la Couronne seul, après la chute des autres. Il y a vu le visage du Dormeur et n'a plus jamais voulu en redescendre.",
            intro="« Je les ai tous perdus en montant. Je ne perdrai pas la Couronne. Laisse-moi finir. Laisse-moi tout retisser, ou je te briserai comme eux. »",
            defeat="« Orsolan a eu raison. Je l'ai haï trois cents ans de l'avoir eu. Va, la Couronne est derrière moi. Choisis mieux que nous. »"),
}

# ── le mentor ──────────────────────────────────────────────────────────────────
ORSOLAN = dict(
    name="Orsolan Vey", title="le Vieux Veilleur",
    bio="Dernier survivant de l'époque du Concile, Orsolan tient la Porte Noire depuis trois cents ans. Il ne monte plus. "
        "Il dit que ses genoux ne suivent pas, mais il ne regarde jamais l'escalier en le disant.",
)

# ── les 20 fragments de mémoire (4 par étage) : textes courts, objets de quête lisibles ──
FRAGMENTS = {
    1: [
        ("Fragment de sève séchée", "« Ysmène plante ses mains dans le mur. Elle dit que la Tour est malade et qu'elle va la soigner. Aurelian regarde ailleurs. »"),
        ("Fragment de journal détrempé", "« Jour 4 de la montée. Le Fil vibre quand nous marchons à l'unisson. Orsolan, en bas, nous répond par trois secousses. »"),
        ("Fragment de comptine", "« Un pas pour la Tour, deux pas pour le Ciel, trois pas pour celui qui reste. » (On chantait cela aux enfants du camp.)"),
        ("Fragment de carte griffonnée", "Un plan des Racines. Une salle est entourée d'un cercle rouge. En marge : « Ne pas réveiller ce qui est dessous. Ce n'est pas la Tour. »"),
    ],
    2: [
        ("Fragment d'ordre de mission", "« Capitaine Korvus : tenir le lac, jour et nuit, jusqu'à nouvel ordre. Signé : Aurelian. » Le sceau est brûlé à moitié."),
        ("Fragment de lettre calcinée", "« Si tu lis ceci, c'est que le feu a pris. Ne laisse pas les enfants du marais s'approcher du Gouffre. »"),
        ("Fragment de médaille fondue", "Une médaille du Concile, tordue par la chaleur. Au dos : « Pour avoir marché sur l'eau. »"),
        ("Fragment de chant cendreux", "« Il brûle pour nous, il brûle pour nous, et quand il s'éteindra, nous éteindrons aussi. »"),
    ],
    3: [
        ("Fragment de plan de la Cité", "Les plans montrent la ville à l'endroit. Une note de Tarq : « Elle n'était pas faite pour tomber. Elle était faite pour monter. »"),
        ("Fragment de ticket de tramway", "Un ticket pour « Le Sommet, correspondance : le Ciel ». Il n'a jamais été composté."),
        ("Fragment de circuit gravé", "« Je me recopie dans la Cité. Si je me perds, qu'on me relise. Orsolan, reviens. »"),
        ("Fragment d'enseigne retournée", "« Horloger de la Tour : réparations en tous genres, même du temps. » Le temps est resté en panne."),
    ],
    4: [
        ("Fragment de page trempée", "« Le dernier livre des Tisseurs parle d'un dormeur. Il n'y a aucune image, seulement une phrase : ne pas gravir. »"),
        ("Fragment d'index effacé", "L'index ne cite que deux noms : celui de Séléné, et un autre, rayé si fort que le papier est troué."),
        ("Fragment de marque-page", "« J'ai demandé à Orsolan pourquoi il n'était pas monté avec nous. Il a répondu qu'il tenait le Fil. Il l'a répondu trop vite. »"),
        ("Fragment d'encrier brisé", "Une dernière note : « Quand le Fil a claqué, ce n'est pas la Tour qui a crié. C'était le Dormeur. »"),
    ],
    5: [
        ("Fragment d'éclat d'azur", "« Aurelian a gravi la dernière marche seul. Il a regardé le ciel. Le ciel l'a regardé aussi. »"),
        ("Fragment de cantique des Aurés", "« Nous gardons la porte. Nous ne savons pas ce qu'elle garde. Nous la gardons, c'est ainsi. »"),
        ("Fragment de lettre d'Orsolan", "« Pardonne-moi, Aurelian. Si je n'avais pas coupé, tu l'aurais éveillé. Pardonne-moi d'avoir eu raison. »"),
        ("Fragment de souffle", "Un murmure, plus qu'un texte : « Retisser... ou délier. Le Ciel attend celui qui choisira. »"),
    ],
}

# ── les deux fins ──────────────────────────────────────────────────────────────
ENDINGS = {
    "retisser": dict(
        name="Retisser le Ciel",
        text="Vous nouez le Fil à la Couronne. Le Dormeur se rendort, la Tour se redresse, étage après étage. Les Fragments s'apaisent, "
             "mais le Fil vous tient désormais, et vous restez là-haut, à votre tour, pour le tenir."),
    "delier": dict(
        name="Délier la Tour",
        text="Vous tranchez ce qui reste du Fil. La Tour s'effondre pour de bon, libérant les Fragments, et le Dormeur s'étire. "
             "Le Ciel remonte. Plus rien ne retient personne, ni les morts, ni les vivants."),
}

# ── les PNJ (nom, titre, étage, rôle, ligne de présentation) ─────────────────────
NPCS = {
    "orsolan": dict(name="Orsolan Vey", floor=0, role="quest", look="elder"),
    "brenna": dict(name="Brenna Maille", floor=0, role="forge", look="smith"),
    "tomas": dict(name="Tomas le Boiteux", floor=0, role="alchemist", look="merchant"),
    "ilda": dict(name="Sœur Ilda", floor=0, role="bank", look="priest"),
    "kael": dict(name="Kael, apprenti cartographe", floor=0, role="exploration", look="young"),
    "echo": dict(name="L'Écho", floor=0, role="fragments", look="ghost"),
    "dorn": dict(name="Dorn Lestrad", floor=0, role="trade", look="merchant"),
    "porte": dict(name="Le Gardien de la Porte Noire", floor=0, role="gate", look="guard"),
    "cueilleuse": dict(name="Vess la Cueilleuse", floor=1, role="lore", look="hood"),
    "novice": dict(name="Un novice de la Mycélie", floor=1, role="lore", look="hood"),
    "cendreux": dict(name="Hob l'Éteint", floor=2, role="lore", look="young"),
    "passeur": dict(name="Mara la Passeuse", floor=2, role="shortcut", look="guard"),
    "automate": dict(name="Balai-12", floor=3, role="lore", look="golem"),
    "horloger": dict(name="Maître Pivot", floor=3, role="lore", look="merchant"),
    "noye": dict(name="Un copiste noyé", floor=4, role="lore", look="ghost"),
    "libraire": dict(name="Madame Quire", floor=4, role="shop", look="priest"),
    "aure": dict(name="Un Auré égaré", floor=5, role="lore", look="ghost"),
    "voix": dict(name="La Voix du Dormeur", floor=6, role="finale", look="ghost"),
}
