"""NPCs, their dialogues and the 16 quests of the Vertebre.

Dialogue replies carry criteria (CriteriaEval: Qf=<quest> finished, Qa active, PO=<item> owned, PL>n level) so that
people change what they say as the player progresses. Quests are offered by their giver's first dialogue node
(QuestEngine.with_offers) and advance by the events the sim reports (talking, fighting, bringing, arriving).
The map ids come from world.py (MAPS) through the `maps` argument of build().
"""
from __future__ import annotations

import lore
from common import R, T, npc_id, objective_id, quest_id, step_id
from items import ITEM
from mobs import BOSS_IDS, MOBS

NPC: dict[str, int] = {}
Q: dict[str, int] = {}
NPC_NAME: dict[int, str] = {}


# ── dialogue DSL ───────────────────────────────────────────────────────────────

class Tree:
    def __init__(self):
        self.nodes: dict[str, dict] = {}
        self._rid = 0

    def node(self, nid, text, *replies):
        rs = []
        for r in replies:
            text_, nxt, crit, act = (list(r) + [None, None, None])[:4]
            self._rid += 1
            d = {"id": self._rid, "text": text_}
            if nxt:
                d["next"] = nxt
            if crit:
                d["criteria"] = crit
            if act:
                d["action"] = act
            rs.append(d)
        self.nodes[nid] = {"text": text, "replies": rs}
        return self

    def out(self, start="0"):
        return {"start": start, "nodes": self.nodes}


def go(map_id, cell):
    return {"type": "teleport", "map": map_id, "cell": cell}


def give(item, qty=1):
    return {"type": "give_item", "item": ITEM[item], "qty": qty}


BYE = ("À bientôt.", None, "", None)


def has(item):
    return "PO=%d" % ITEM[item]


def done(q):
    return "Qf=%d" % Q[q]


def active(q):
    return "Qa=%d" % Q[q]


# ── quest DSL ──────────────────────────────────────────────────────────────────

def _name_of(npc_key):
    return T(lore.NPCS[npc_key]["name"] if npc_key in lore.NPCS else NPC_NAME[NPC[npc_key]])


def ob_talk(npc_key, map_id=0):
    return dict(type=1, map=map_id, params=[NPC[npc_key]], args=[{"t": _name_of(npc_key)}])


def ob_back(npc_key, map_id=0):
    return dict(type=9, map=map_id, params=[NPC[npc_key]], args=[{"t": _name_of(npc_key)}])


def ob_bring(npc_key, item, qty=1, map_id=0):
    return dict(type=3, map=map_id, params=[NPC[npc_key], ITEM[item], qty], args=[{"t": _name_of(npc_key)}, {"t": R.items_by_id[ITEM[item]]["name_id"]}, {"n": qty}])


def ob_map(map_id, label):
    return dict(type=4, map=map_id, params=[], args=[{"t": T(label)}])


def ob_kill(monster_id, qty, name, map_id=0):
    return dict(type=14, map=map_id, params=[monster_id, qty], args=[{"t": T(name)}, {"n": qty}])


def ob_boss(monster_id, name, map_id=0):
    return dict(type=7, map=map_id, params=[monster_id], args=[{"t": T(name)}])


def step(name, desc, objectives, xp=0.0, kamas=0.0, items=(), level=1):
    return dict(name=name, desc=desc, objectives=objectives, xp=xp, kamas=kamas, items=list(items), level=level)


def quest(key, name, giver, giver_map, level, steps, criteria="BT=1", category=1):
    qid = Q[key]
    out = {"id": qid, "name_id": T(name), "category": category, "level_min": level, "level_max": 0, "criteria": criteria, "repeat": 0,
           "start": {"npc": NPC[giver], "map": giver_map}, "steps": []}
    for st in steps:
        objs = []
        for o in st["objectives"]:
            objs.append({"id": objective_id(), "type": o["type"], "map": o["map"], "params": o["params"], "args": o["args"]})
        out["steps"].append({"id": step_id(), "name_id": T(st["name"]), "desc_id": T(st["desc"]), "level": st["level"], "objectives": objs,
                             "rewards": [{"level_min": -1, "level_max": -1, "xp": float(st["xp"]), "kamas": float(st["kamas"]), "scale": 0,
                                          "items": [[ITEM[k], n] for k, n in st["items"]], "emotes": [], "spells": [], "titles": [], "jobs": []}]})
    R.quests[str(qid)] = out


# ── allocation ─────────────────────────────────────────────────────────────────

QUEST_KEYS = ["m1", "m2", "m3", "m4", "m5", "x1", "x2", "x3", "x4", "x5", "x6", "l1", "l2", "l3", "l4", "l5"]
SEAL_NAMES = {"stair": "Escalier scellé", "door": "Porte de l'antre"}


def alloc():
    R.items_by_id = {it["id"]: it for it in R.items}
    for k, n in lore.NPCS.items():
        NPC[k] = npc_id()
        NPC_NAME[NPC[k]] = n["name"]
    for f in range(1, 6):
        for kind in ("stair", "door"):
            k = "%s%d" % (kind, f)
            NPC[k] = npc_id()
            NPC_NAME[NPC[k]] = SEAL_NAMES[kind]
    for k in QUEST_KEYS:
        Q[k] = quest_id()


def boss_name(f):
    return lore.BOSSES[f]["name"]


# ── dialogues ──────────────────────────────────────────────────────────────────

def dialogs(M):
    """M: the map ids and arrival cells from world.py: M['hub'], M['floor'][f], M['arena'][f], M['summit'], M['cells'][...]"""
    d = R.dialogs

    def add(key, tree, start="0"):
        d[str(NPC[key])] = tree.out(start)

    # Orsolan -------------------------------------------------------------------
    t = Tree()
    t.node("0", "« Tu as les yeux de ceux qui montent. J'en ai connu cinq comme toi, il y a trois cents ans. Qu'est-ce que tu veux savoir, voyageur ? »",
           ("Parlez-moi de la Tour.", "tour"), ("Qui sont les Fragments ?", "fragments"),
           ("Qu'est-ce que l'Effondrement ?", "effondrement"),
           ("Qui tenait l'autre bout du Fil, Orsolan ?", "aveu", "&".join([done("m4"), has("frag_4_4")])),
           ("« Ne pas gravir. » Vous l'avez lu, vous aussi.", "dormeur", has("frag_4_1")),
           ("Je reviens de la Couronne.", "retour", done("m5")), BYE)
    t.node("tour", "« La Vertèbre. Les Tisseurs l'ont dressée au-dessus du Gouffre pour tenir le Ciel, qui s'affaissait. Cinq étages, une porte noire en bas, une couronne en haut. "
           "Personne ne vous dira que la Tour est vivante. Personne ne vous dira non plus pourquoi elle est tiède. »", ("Et l'Effondrement ?", "effondrement"), ("Merci.", "0"))
    t.node("fragments", "« Cinq membres du Concile sont montés : Ysmène, qui guérissait ; Korvus, qui se battait ; Tarq, qui construisait ; Séléné, qui se souvenait ; et Aurelian, qui menait. "
           "Quand la Tour est tombée, chacun est resté prisonnier de son étage. Ce ne sont plus des gens. Ce sont des Fragments. Ils répètent leur dernière heure, et ils ne reconnaissent plus personne. »",
           ("Peut-on les délivrer ?", "delivrer"), ("Je vois.", "0"))
    t.node("delivrer", "« En les battant, oui. Cela leur rend, un instant, ce qu'ils étaient. C'est la seule chose qu'on puisse faire pour eux, et je n'ai jamais osé la faire moi-même. »", ("Je comprends.", "0"))
    t.node("effondrement", "« Il y a trois cents ans, le Fil a été coupé. Le Fil, c'était la corde d'éther qui reliait les Cinq entre eux, et eux à moi. Quand il a cassé, la Tour s'est effondrée sur elle-même. "
           "Les étages sont tombés les uns dans les autres. Voilà pourquoi il y a un marais à l'étage où il y avait une ville, et une cité renversée à l'étage où il y avait une bibliothèque. »",
           ("Qui a coupé le Fil ?", "qui_coupe"), ("Merci.", "0"))
    t.node("qui_coupe", "« ... Personne ne sait. On dit qu'il s'est rompu. Les fils se rompent. Va, voyageur, il y a des gens qui t'attendent en haut. »", ("Hum.", "0"))
    t.node("aveu", "« Séléné t'a dit de me le demander. ... Je tenais l'autre bout du Fil, oui. En bas, au Pied-de-Tour, avec une main sur le premier barreau. "
           "J'ai senti la Tour trembler quand ils ont atteint le cinquième étage. Et j'ai compris ce que c'était, la Couronne. »",
           ("Et vous avez coupé.", "aveu2"), ("Je ne veux pas entendre ça.", "0"))
    t.node("aveu2", "« Je l'ai coupé. Un coup de dague dans le Fil, un seul. Je savais qu'à la Couronne ils réveilleraient le Dormeur. Je pensais sauver le monde. J'ai tué mes amis, et j'ai failli tuer la Tour. "
           "Voilà ce que je suis : le Sixième du Concile, celui qui est resté en bas. »", ("Que fait-on maintenant ?", "aveu3"), ("Je dois réfléchir.", "0"))
    t.node("aveu3", "« Au sommet, il y a un choix. Retisser le Fil, rendormir le Dormeur, et la Tour se redresse, mais quelqu'un doit rester en haut pour le tenir. Ou le délier, et laisser tout s'effondrer pour de bon, "
           "et le Dormeur s'étire, et le Ciel remonte. J'ai attendu trois cents ans quelqu'un qui saurait choisir. Ce ne sera pas moi. Je n'ai pas le droit. »", ("Je choisirai.", "0"))
    t.node("dormeur", "« Ils t'ont dit de ne pas gravir ? Oui. Le dernier livre des Tisseurs ne contenait que cela, une phrase, parce qu'ils savaient. Ils savaient, et ils ont construit la Tour quand même. Je ne leur ai jamais pardonné. »", ("Hm.", "0"))
    t.node("retour", "« Tu es revenu. Ça, ni moi ni les Cinq ne l'avons jamais fait. Si tu as choisi, la Tour te le dira. Sinon... il n'est pas trop tard pour monter un peu plus haut, et regarder. »", ("Merci, Orsolan.", "0"))
    add("orsolan", t)

    # Brenna (forge) ------------------------------------------------------------
    t = Tree()
    t.node("0", "« Armes, armures, réparations. Tout ce que je vends est forgé avec du métal que les Renversés m'envoient par le puits : il vient des forges de Tarq, mais c'est le meilleur qu'on ait. »",
           ("Voir vos marchandises.", None, "", {"type": "shop"}), ("Pourquoi les Renversés vous envoient-ils du métal ?", "metal"), BYE)
    t.node("metal", "« Ils ne le savent pas non plus. Ils ont une procédure : quand un étage est trop plein, on envoie le surplus vers le bas. C'est ainsi que le métal arrive ici, en plus de quelques pièces d'horloge. »", ("Intéressant.", "0"))
    add("brenna", t)
    R.shops[str(NPC["brenna"])] = {"items": [ITEM[k] for k in ("seve_hat", "seve_ring", "ecorce_hat", "ecorce_boots", "ecorce_hammer", "brume_hat", "brume_belt", "brume_boots", "cendrelame_belt", "cendrelame_ring")]}

    # Tomas (potions) -----------------------------------------------------------
    t = Tree()
    t.node("0", "« Potions, onguents, élixirs. Je les prépare moi-même, sauf quand ils sont mauvais, auquel cas ce sont les Renversés qui les ont préparés. »",
           ("Voir vos potions.", None, "", {"type": "shop"}), ("Et la jambe ?", "jambe"), BYE)
    t.node("jambe", "« Un Écorcheur du marais. Il y a dix ans. Je le revois encore dans mes rêves, il me demande si je veux qu'il revienne. »", ("Courage.", "0"))
    add("tomas", t)
    R.shops[str(NPC["tomas"])] = {"items": [ITEM[k] for k in ("potion1", "potion2", "potion3", "potion4", "potion5", "rappel")]}

    # Dorn (trade) --------------------------------------------------------------
    t = Tree()
    t.node("0", "« Parchemins, rumeurs, bonnes affaires. Les trois sont authentiques, celles-ci surtout. »", ("Voir les parchemins.", None, "", {"type": "shop"}),
           ("Des rumeurs ?", "rumeurs"), BYE)
    t.node("rumeurs", "« On dit que chaque étage cache une pièce que personne n'a trouvée. Mara, au marais, connaît un passage. Kael dessine des cartes qui mentent exprès. Et il paraît que, certains soirs, la Porte Noire est plus tiède. »", ("Merci.", "0"))
    add("dorn", t)
    R.shops[str(NPC["dorn"])] = {"items": [ITEM[k] for k in ("parch_str", "parch_int", "parch_cha", "parch_agi", "parch_vit", "parch_wis", "rappel")]}

    # Ilda (bank) ---------------------------------------------------------------
    t = Tree()
    t.node("0", "« Que la Tour vous garde, voyageur. Voulez-vous confier quelque chose à la Mémoire ? Elle rend toujours, même ce qu'on a voulu oublier. »", ("Ouvrir ma banque.", None, "", {"type": "bank"}),
           ("Qui est la Mémoire ?", "memoire"), BYE)
    t.node("memoire", "« Le coffre sous le camp. Il était là avant nous, et il contenait déjà des choses. Je n'ai pas demandé lesquelles. »", ("Hum.", "0"))
    add("ilda", t)

    # Kael (exploration) --------------------------------------------------------
    t = Tree()
    t.node("0", "« Moi, je dessine. Je dessine des cartes de ce qu'il y a au-dessus. Personne n'est jamais revenu vérifier. Alors je mets ce que j'imagine, et je marque d'un ? ce que j'ai deviné. »",
           ("Où sont les passages secrets ?", "secrets"), ("Une carte, s'il vous plaît.", "carte"), BYE)
    t.node("secrets", "« Je ne mens que par amour du jeu. Mais voilà ce qu'on raconte : aux Racines, un pan de mur sonne creux au nord-est de la salle du milieu. Dans le Marais, cherchez à l'ouest, entre les deux monticules. "
           "Dans la Cité, au plafond, à droite de la grande enseigne. Aux Archives, là où l'eau est la plus noire. À la Couronne, ne cherchez pas : c'est la Couronne qui vous trouvera. »", ("Merci.", "0"))
    t.node("carte", "« Je n'ai plus de carte. Mais je vous en dessine une en échange d'un récit : visitez chaque étage, revenez me le raconter, et je vous offre ce que je trouve de mieux. »", ("D'accord.", "0"))
    add("kael", t)

    # L'Écho (fragments) --------------------------------------------------------
    t = Tree()
    t.node("0", "« ...Ah. Quelqu'un. J'étais en train de réciter ce que les murs m'ont dit. Je suis l'Écho : je ne suis personne, je répète. Apportez-moi des fragments de mémoire et je vous dirai ce qu'ils disent. »",
           ("Qu'est-ce qu'un fragment de mémoire ?", "frag"),
           ("Lisez-moi ce que disent les fragments des Racines.", "m1", done("l1")), ("Lisez-moi ce que disent les fragments du Marais.", "m2", done("l2")),
           ("Lisez-moi ce que disent les fragments de la Cité.", "m3", done("l3")), ("Lisez-moi ce que disent les fragments des Archives.", "m4", done("l4")),
           ("Lisez-moi ce que disent les fragments de la Couronne.", "m5", done("l5")), BYE)
    t.node("frag", "« Les choses qui ont été dites ici s'accrochent aux objets, comme la poussière. On les ramasse, on les assemble, et l'on entend. Il y en a quatre par étage. Quatre, parce que les Cinq ont écrit dessus, et que l'un d'eux a menti. »", ("Merci.", "0"))
    t.node("m1", "« Ysmène plantait ses mains dans les murs. Elle a nourri la Tour. La Tour a pris tout ce qu'elle donnait, et ce qui était à elle, et ce qui était à nous. Elle avait raison de craindre ce qui dormait sous les racines. »", ("Hm.", "0"))
    t.node("m2", "« Korvus a brûlé le lac pour arrêter ce qui montait. Ça n'a pas arrêté ce qui montait. Mais ça a donné aux enfants du marais de quoi croire en quelque chose. Le feu les a gardés. Il les garde encore. »", ("Hm.", "0"))
    t.node("m3", "« Tarq voulait réparer la Cité de l'intérieur. Il s'est copié dans ses plans. Les plans ont tenu, lui non. C'est un des rares architectes à avoir fini ses bâtiments : il est dedans. »", ("Hm.", "0"))
    t.node("m4", "« Séléné a lu le dernier livre. Une seule phrase : ne pas gravir. Elle a compris que la Tour ne tenait pas le Ciel, qu'elle tenait quelque chose qui dort. L'éther liquide a gardé la page à sa place. Elle ne l'a pas oubliée. Elle n'a jamais oublié. »", ("Hm.", "0"))
    t.node("m5", "« Aurelian a gravi la dernière marche seul. Il a regardé la Couronne, et la Couronne l'a regardé. Il n'a plus jamais voulu en redescendre. Il n'est pas prisonnier de la Tour, il est prisonnier de ce qu'il a vu. »", ("Hm.", "0"))
    add("echo", t)

    # Porte Noire (fast travel) -------------------------------------------------
    t = Tree()
    t.node("0", "« La Porte Noire. Ce que vous montez, vous ne le redescendez pas toujours. Passez-vous ? »", ("Franchir la Porte (les Racines).", None, "", go(M["floor"][1], M["entry"][1])),
           ("Gagner l'escalier de la Racine-Mère.", None, done("m1"), go(M["floor"][2], M["entry"][2])),
           ("Gagner l'escalier du Capitaine.", None, done("m2"), go(M["floor"][3], M["entry"][3])),
           ("Gagner l'escalier de l'Architecte.", None, done("m3"), go(M["floor"][4], M["entry"][4])),
           ("Gagner l'escalier de la Bibliothécaire.", None, done("m4"), go(M["floor"][5], M["entry"][5])),
           ("Pas encore.", None))
    add("porte", t)

    # floor 1 lore --------------------------------------------------------------
    t = Tree()
    t.node("0", "« Chut. Ne marchez pas trop fort. Ils sentent les pas, ici. Je cueille ce qui reste d'utile, des spores, de la sève, de quoi guérir. Je ne cueille jamais ce qui bouge. »",
           ("D'où viennent les Acolytes ?", "acolytes"), ("Où est la Racine-Mère ?", "mere"), ("Y a-t-il un secret, ici ?", "secret", "PL>0", None), BYE)
    t.node("acolytes", "« Des gens du camp qui avaient peur. La Mycélie leur a offert quelqu'un à croire. Ils ont troqué la peur contre une prière. Et la prière contre... ça. »", ("Triste.", "0"))
    t.node("mere", "« Au bout de la grande galerie, derrière la porte de sève. Elle ne vous attaquera pas par haine. Elle a faim, et elle n'a plus rien à manger que ce qui entre. »", ("Merci.", "0"))
    t.node("secret", "« Si vous trouvez la salle derrière le pan de mur creux, au nord-est, rapportez-moi ce qu'il y a dedans. Je ne peux pas y aller moi-même. J'ai déjà essayé. Il y a des choses que mes bottes refusent de contourner. »", ("Je verrai.", "0"))
    add("cueilleuse", t)
    t = Tree()
    t.node("0", "« Je suis arrivé ici pour guérir les gens. Je ne guéris plus personne, mais je continue de prier. Vous voulez prier avec moi ? Ça ne coûte rien. Ça ne rapporte rien non plus, mais ça fait du bien. »",
           ("Pourquoi le culte vous a-t-il accepté ?", "culte"), BYE)
    t.node("culte", "« Ils n'acceptent pas. Ils ne refusent jamais. Il suffit de rester assez longtemps pour que ça devienne vrai. »", ("Hm.", "0"))
    add("novice", t)

    # floor 2 lore --------------------------------------------------------------
    t = Tree()
    t.node("0", "« Oh, un visiteur. On n'en a plus. Je suis Hob. Je ne brûle pas, moi, je suis seulement un peu gris. C'est la cendre, ça se lave pas. »",
           ("Qui est le Capitaine ?", "capitaine"), ("Pourquoi vous appelle-t-on l'Éteint ?", "eteint"), BYE)
    t.node("capitaine", "« Korvus. Il a tenu le lac, jour et nuit, jusqu'à ce que le lac devienne cendres. Personne ne l'a relevé. Il attend. Quand on lui dit qu'il peut partir, il ne comprend pas la phrase. »", ("Je vois.", "0"))
    t.node("eteint", "« Parce que mon feu est éteint. Les autres ont gardé le leur, ça les rend fiers. Moi, j'ai préféré qu'il parte. Ça fait de moi quelqu'un qui peut encore dormir. »", ("Hm.", "0"))
    add("cendreux", t)
    t = Tree()
    t.node("0", "« Je passe les gens d'un bord à l'autre du marais, quand il y a un bord. Par ici, il y en a de moins en moins. J'ai un passage qui évite les meutes, mais je ne le montre qu'à ceux qui l'ont mérité. »",
           ("Comment le mérite-t-on ?", "merite"), ("Prendre le passage de Mara.", None, done("x3"), go(M["floor"][2], M["door_front"][2])), BYE)
    t.node("merite", "« Il y a, à l'ouest, entre les deux monticules, un endroit où personne ne va. Il contient une médaille fondue. Je l'ai perdue en fuyant. Rapportez-la-moi, et je vous montre. »", ("Compris.", "0"))
    add("passeur", t)

    # floor 3 lore --------------------------------------------------------------
    t = Tree()
    t.node("0", "« BONJOUR. JE SUIS BALAI-12. JE BALAIE. IL Y A BEAUCOUP À BALAYER. VOUS ÊTES SALE. »", ("Qu'est-ce que vous balayez ?", "balaie"), ("Vous savez ce qu'il y a au-dessus ?", "dessus"), BYE)
    t.node("balaie", "« LES MORCEAUX. IL Y A BEAUCOUP DE MORCEAUX. CERTAINS PARLENT. JE LES BALAIE QUAND MÊME. »", ("Hm.", "0"))
    t.node("dessus", "« AU-DESSUS : LE PLAFOND. EN DESSOUS : LE SOL. ICI : LA CITÉ. L'ARCHITECTE A DIT : « VOUS N'ÊTES PAS FAITS POUR MONTER. » J'AI ENREGISTRÉ. »", ("Merci.", "0"))
    add("automate", t)
    t = Tree()
    t.node("0", "« Maître Pivot, horloger de la Tour, réparations en tous genres, même du temps. Le temps ne marche plus depuis l'Effondrement, vous comprenez : il a besoin de pièces. »",
           ("Je peux vous aider ?", "aide"), ("Comment répare-t-on le temps ?", "temps"), BYE)
    t.node("aide", "« Apportez-moi trois ressorts brisés et trois rouages cuivrés. Je ne promets pas que l'heure reviendra. Je promets que ça fera un bruit rassurant. »", ("Je m'en occupe.", "0"))
    t.node("temps", "« Avec patience. Et un peu de colle. Ne répétez pas que c'est de la colle, ça ruine la mystique. »", ("Hm.", "0"))
    add("horloger", t)

    # floor 4 lore --------------------------------------------------------------
    t = Tree()
    t.node("0", "« ...Chut. J'allais finir la page. J'allais finir la page depuis... depuis. Vous êtes venu pour lire ? Vous ne devriez pas. Mais lisez : les mots n'ont pas de rancune. »",
           ("Que contient la page ?", "page"), ("Qui était Séléné ?", "selene"), BYE)
    t.node("page", "« Une phrase. Toujours la même. Je ne peux pas vous la dire : elle se recopie dans la bouche de celui qui l'entend. »", ("Hm.", "0"))
    t.node("selene", "« La plus grande lectrice de la Tour. Elle a lu le dernier livre des Tisseurs, et elle a posé sa plume. Je ne l'ai jamais vue sourire après. »", ("Hm.", "0"))
    add("noye", t)
    t = Tree()
    t.node("0", "« Madame Quire, libraire. Ma boutique est inondée, mais mes livres sont encore secs. Ce sont les clients qui sont mouillés. »", ("Une commission ?", "commission"), ("Qu'est-ce que vous vendez ?", "vend"), BYE)
    t.node("commission", "« Mes pages se sont dispersées. Il m'en faut trois, mouillées si possible, et un index effacé. Je saurai remettre tout cela à l'endroit. »", ("Compris.", "0"))
    t.node("vend", "« Rien. Je prête. Mais je prête cher. »", ("Hm.", "0"))
    add("libraire", t)

    # floor 5 lore --------------------------------------------------------------
    t = Tree()
    t.node("0", "« Je suis tombé de la Couronne. Je ne sais plus pourquoi. Je crois que je gardais quelque chose. Je ne sais plus quoi. »", ("Qu'est-ce que vous gardez ?", "garde"), ("Parlez-moi du Premier Gravit.", "gravit"), BYE)
    t.node("garde", "« Une porte. On ne m'a pas dit de laquelle. Ce n'était pas nécessaire. On est toujours en train de garder quelque chose, et c'est toujours la même chose, et c'est toujours la porte. »", ("Hm.", "0"))
    t.node("gravit", "« Il est monté seul. Il est resté seul. Il vous demandera de partir, puis de rester, puis de choisir à sa place. Ne choisissez pas à sa place. »", ("Merci.", "0"))
    add("aure", t)

    # seals ---------------------------------------------------------------------
    for f in range(1, 6):
        t = Tree()
        up = M["floor"][f + 1] if f < 5 else M["summit"]
        up_cell = M["entry"][f + 1] if f < 5 else M["summit_cell"]
        down = M["floor"][f - 1] if f > 1 else M["hub"]
        down_cell = M["after_stair"][f - 1] if f > 1 else M["hub_gate"]
        t.node("0", "Un escalier de pierre claire monte dans l'obscurité. Une empreinte, à hauteur de main, attend un sceau.",
               ("Présenter le Sceau de %s." % boss_name(f).replace("Mère ", "Mère ").split(",")[0], None, has("key%d" % f), go(up, up_cell)),
               ("Examiner le sceau.", "after", has("key%d" % f)), ("Redescendre.", None, "", go(down, down_cell)), ("Partir.", None))
        t.node("after", "Le sceau est tiède. Il garde la dernière phrase de son maître : %s" % lore.BOSSES[f]["defeat"], ("Hm.", "0"))
        add("stair%d" % f, t)
        t = Tree()
        lv = lore.FLOORS[f]["lv"][0] + 5
        t.node("0", "Une porte lourde. Derrière, une voix. %s" % lore.BOSSES[f]["intro"],
               ("« Entrer dans l'antre de %s. »" % lore.BOSSES[f]["name"], None, "PL>%d" % max(0, lv - 8), go(M["arena"][f], M["arena_entry"][f])),
               ("Écouter encore.", "story"), ("Reculer.", None))
        t.node("story", lore.BOSSES[f]["story"], ("Hm.", "0"))
        add("door%d" % f, t)

    # the Voice of the Dormant (summit) ----------------------------------------
    t = Tree()
    none = "PO!%d&PO!%d" % (ITEM["fil_noue"], ITEM["fil_tranche"])
    either = "PO=%d|PO=%d" % (ITEM["fil_noue"], ITEM["fil_tranche"])
    t.node("0", "Il n'y a pas de visage. Seulement, très haut, quelque chose qui respire. Une voix, comme venant du roc : « Tu es monté. Les autres sont montés aussi, et ils sont restés. "
           "Tu as le Fil entre les mains. Veux-tu me rendormir, ou me laisser m'étirer ? »",
           ("Retisser le Fil. (Rendormir le Dormeur.)", "retisser", none), ("Délier le Fil. (Laisser le Dormeur s'étirer.)", "delier", none),
           ("Qui es-tu ?", "qui"), ("J'ai fait mon choix.", "fait", either), ("Je ne suis pas prêt.", None))
    t.node("qui", "« Ce sur quoi vous avez bâti. Vous m'avez donné un nom, et vous avez construit sur mon dos. Je n'ai pas bougé pendant des siècles. Puis le Ciel s'est affaissé, et j'ai tenté de le soulever. Vous avez cru que j'allais tomber. »", ("Je comprends.", "0"))
    t.node("retisser", lore.ENDINGS["retisser"]["text"], ("... (Fin : Retisser le Ciel)", None, "", give("fil_noue")))
    t.node("delier", lore.ENDINGS["delier"]["text"], ("... (Fin : Délier la Tour)", None, "", give("fil_tranche")))
    t.node("fait", "« Tu as choisi. Va, maintenant. Ou reste, si tu veux. Personne n'est jamais resté tout à fait de son plein gré, ici. »", ("Adieu.", None))
    add("voix", t)


# ── quests ─────────────────────────────────────────────────────────────────────

def mob_id(key):
    return next(m["id"] for m in MOBS if m["key"] == key)


def quests(M):
    h = M["hub"]
    # main line: one per floor ---------------------------------------------------
    quest("m1", "Gravir : les Racines", "orsolan", h, 1, [
        step("Franchir la Porte Noire", "Orsolan vous demande de descendre dans les Racines et de voir, de vos yeux, ce que la Tour est devenue.", [ob_map(M["floor"][1], "Les Racines")], xp=1.5, kamas=1, level=1),
        step("Ce qui garde l'étage", "Les Gardes-Écorce barrent la route vers la Racine-Mère. Il faudra en abattre quelques-uns.", [ob_kill(mob_id("garde"), 3, "Garde-Écorce")], xp=2.0, kamas=2, level=3),
        step("La Racine-Mère", "Mère Ysmène attend, au bout de la grande galerie, derrière la porte de sève.", [ob_boss(BOSS_IDS[1], boss_name(1), M["arena"][1])], xp=3.0, kamas=4, level=9),
        step("Rapport à Orsolan", "Rapportez à Orsolan ce que Mère Ysmène a dit en tombant.", [ob_back("orsolan", h)], xp=4.0, kamas=5, items=[("parch_wis", 1), ("potion2", 3)], level=10)], category=1)
    quest("m2", "Gravir : le Marais des Cendres", "orsolan", h, 11, [
        step("Le deuxième étage", "Montez l'escalier de la Racine-Mère jusqu'au Marais des Cendres.", [ob_map(M["floor"][2], "Le Marais des Cendres")], xp=1.5, kamas=1, level=11),
        step("Les bêtes du marais", "Les Meutes Charbonnées gardent le passage du Capitaine. Chassez-en quelques-unes.", [ob_kill(mob_id("meute"), 4, "Meute Charbonnée")], xp=2.5, kamas=3, level=14),
        step("Le Capitaine Éteint", "Le Capitaine Korvus tient toujours son poste, au bout du marais.", [ob_boss(BOSS_IDS[2], boss_name(2), M["arena"][2])], xp=3.5, kamas=5, level=19),
        step("Rapport à Orsolan", "Dites à Orsolan que la relève est arrivée.", [ob_back("orsolan", h)], xp=4.5, kamas=6, items=[("parch_str", 1), ("potion3", 3)], level=20)],
        criteria="Qf=%d" % Q["m1"])
    quest("m3", "Gravir : la Cité Renversée", "orsolan", h, 21, [
        step("Le troisième étage", "Montez jusqu'à la Cité, qui est à l'envers.", [ob_map(M["floor"][3], "La Cité Renversée")], xp=1.5, kamas=1, level=21),
        step("Les sentinelles", "Les Sentinelles Inversées gardent la ville. Réduisez leur nombre.", [ob_kill(mob_id("sentinelle"), 3, "Sentinelle Inversée")], xp=3.0, kamas=4, level=23),
        step("L'Architecte Muet", "Tarq-9 s'est intégré à ses propres plans. Il faudra le démonter.", [ob_boss(BOSS_IDS[3], boss_name(3), M["arena"][3])], xp=4.0, kamas=6, level=29),
        step("Rapport à Orsolan", "Rapportez à Orsolan ce que Tarq-9 a dit : un plan, une erreur.", [ob_back("orsolan", h)], xp=5.0, kamas=7, items=[("parch_agi", 1), ("potion3", 3)], level=30)],
        criteria="Qf=%d" % Q["m2"])
    quest("m4", "Gravir : les Archives Noyées", "orsolan", h, 31, [
        step("Le quatrième étage", "Montez jusqu'aux Archives, sous l'éther liquide.", [ob_map(M["floor"][4], "Les Archives Noyées")], xp=1.5, kamas=1, level=31),
        step("Les gardiens de l'encre", "Les Gardiens d'Encre protègent les pages blanches. Abattez-en.", [ob_kill(mob_id("gardien_encre"), 3, "Gardien d'Encre")], xp=3.5, kamas=5, level=35),
        step("La Bibliothécaire", "Séléné Vael garde le dernier livre. Elle vous suppliera de ne pas le lire.", [ob_boss(BOSS_IDS[4], boss_name(4), M["arena"][4])], xp=4.5, kamas=7, level=39),
        step("Ce que Séléné a dit", "Elle a dit de demander à Orsolan qui tenait l'autre bout du Fil. Retournez le lui demander.", [ob_back("orsolan", h)], xp=6.0, kamas=8, items=[("parch_int", 1), ("potion4", 3)], level=40)],
        criteria="Qf=%d" % Q["m3"])
    quest("m5", "Gravir : la Couronne", "orsolan", h, 41, [
        step("Le cinquième étage", "Montez jusqu'à la Couronne, là où la Tour touche à ce qui n'est plus elle.", [ob_map(M["floor"][5], "La Couronne")], xp=2.0, kamas=2, level=41),
        step("Les gardiens de la voûte", "Les Gardiens de Voûte barrent la dernière marche. Abattez-en.", [ob_kill(mob_id("gardien_voute"), 2, "Gardien de Voûte")], xp=4.0, kamas=6, level=47),
        step("Le Premier Gravit", "Aurelian est resté seul à la Couronne. Allez le trouver.", [ob_boss(BOSS_IDS[5], boss_name(5), M["arena"][5])], xp=6.0, kamas=9, level=49),
        step("Le sommet", "Aurelian vous laisse passer. Montez à la dernière marche et écoutez ce qui vous attend.", [ob_map(M["summit"], "Le Sommet de la Vertèbre")], xp=8.0, kamas=10,
             items=[("parch_vit", 1), ("potion5", 3)], level=50)],
        criteria="Qf=%d" % Q["m4"])

    # exploration -----------------------------------------------------------------
    quest("x1", "Les Cartes de Kael", "kael", h, 1, [
        step("Récits d'étage", "Kael dessine des cartes de ce qu'il y a au-dessus. Il vous demande de visiter chaque étage et de lui raconter.",
             [ob_map(M["floor"][i], lore.FLOORS[i]["name"]) for i in range(1, 6)], xp=4.0, kamas=5, level=1),
        step("Retour auprès de Kael", "Racontez-lui ce que vous avez vu.", [ob_back("kael", h)], xp=6.0, kamas=8, items=[("potion3", 2), ("parch_cha", 1)], level=10)])
    quest("x2", "Le Pan de Mur Creux", "cueilleuse", M["floor"][1], 3, [
        step("Une salle derrière le mur", "Vess ne peut pas aller dans la salle derrière le pan de mur creux. Si vous la trouvez, rapportez-lui ce qui s'y cache.",
             [ob_bring("cueilleuse", "frag_1_4", 1, M["floor"][1])], xp=3.0, kamas=3, level=5),
        step("Merci, étranger", "Vess garde le secret. Elle vous remet quelque chose en échange.", [ob_back("cueilleuse", M["floor"][1])], xp=2.0, kamas=2, items=[("seve_belt", 1), ("potion2", 2)], level=6)])
    quest("x3", "Le Passage de Mara", "passeur", M["floor"][2], 13, [
        step("La médaille perdue", "Mara a perdu une médaille fondue à l'ouest, entre les deux monticules. Allez la chercher.",
             [ob_bring("passeur", "frag_2_3", 1, M["floor"][2])], xp=4.0, kamas=4, level=15),
        step("Le passage", "Mara vous ouvre son passage, qui évite les meutes jusqu'à la porte de l'antre.", [ob_back("passeur", M["floor"][2])], xp=2.5, kamas=3, items=[("brume_ring", 1)], level=16)])
    quest("x4", "Réparer l'heure", "horloger", M["floor"][3], 23, [
        step("Pièces de rechange", "Maître Pivot a besoin de ressorts brisés et de rouages cuivrés pour réparer ce qui peut l'être.",
             [ob_bring("horloger", "res_ressort", 3, M["floor"][3]), ob_bring("horloger", "res_rouage", 3, M["floor"][3])], xp=5.0, kamas=5, level=25),
        step("L'heure retrouvée", "Maître Pivot fait sonner son horloge, pour la première fois depuis trois siècles.", [ob_back("horloger", M["floor"][3])], xp=3.0, kamas=4, items=[("rouage_ring", 1)], level=26)])
    quest("x5", "Pages perdues", "libraire", M["floor"][4], 33, [
        step("Les pages dispersées", "Madame Quire cherche des pages mouillées et un index effacé pour reconstituer un livre.",
             [ob_bring("libraire", "res_page", 3, M["floor"][4]), ob_bring("libraire", "res_index", 1, M["floor"][4])], xp=6.0, kamas=6, level=35),
        step("Le livre reconstitué", "Madame Quire relie ce que vous lui avez rapporté, et vous prête un volume précieux.", [ob_back("libraire", M["floor"][4])], xp=3.5, kamas=5, items=[("maree_ring", 1)], level=36)])
    quest("x6", "Ce qui garde la porte", "aure", M["floor"][5], 43, [
        step("La tâche d'un Auré", "L'Auré égaré ne se rappelle plus ce qu'il gardait, mais il sent que les Gardiens de Voûte l'oublient aussi. Abattez-en trois.",
             [ob_kill(mob_id("gardien_voute"), 3, "Gardien de Voûte", M["floor"][5])], xp=6.0, kamas=7, level=47),
        step("Un souvenir", "L'Auré égaré se rappelle, un instant, la porte qu'il gardait.", [ob_back("aure", M["floor"][5])], xp=4.0, kamas=5, items=[("aurore_ring", 1), ("potion5", 2)], level=48)])

    # lore / collection (the four fragments of a floor, read by L'Écho) --------------
    rewards = {1: [("potion2", 2)], 2: [("potion3", 2)], 3: [("potion3", 3)], 4: [("potion4", 3)], 5: [("potion5", 3)]}
    for f in range(1, 6):
        objs = [ob_bring("echo", "frag_%d_%d" % (f, i), 1, h) for i in range(1, 5)]
        quest("l%d" % f, "Mémoire des %s" % lore.FLOORS[f]["name"].replace("Le ", "").replace("La ", "").replace("Les ", ""), "echo", h, lore.FLOORS[f]["lv"][0], [
            step("Les quatre fragments", "L'Écho veut les quatre fragments de mémoire de cet étage pour les lire à voix haute. Ils sont cachés : fouillez les recoins, les salles secrètes, les coffres, les cadavres.",
                 objs, xp=2.0 + f, kamas=3 + f, level=lore.FLOORS[f]["lv"][0]),
            step("Ce que disent les murs", "L'Écho a lu. Écoutez-le, à votre tour.", [ob_back("echo", h)], xp=2.0 + f, kamas=3 + f, items=rewards[f], level=lore.FLOORS[f]["lv"][0] + 3)])
