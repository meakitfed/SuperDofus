## The spells whose effect shows only over several steps or turns, written as data (SpellCaseRunner
## documents the format). Each case says what the spell's description promises, played in the
## SpellArena (see its layout) with the caster's rolls at their maximum unless `rolls` says otherwise:
## a number comes from the spell's own dice, never from a run of the engine.
class_name SpellCases
extends RefCounted

const CASES := [
	# ── Féca ──
	{"name": "Silbo pushes away from the centre, not the centre itself",
		"source": "Silbo: « repousse les cibles depuis le centre en zone. N'affecte pas le lanceur »",
		"breed": 1, "steps": [
			["cast", 1041124, "foe"],
			["expect", {"foe": {"lost": 15, "moved": false}, "foe_n": {"lost": 13, "cell": Vector2i(2, 2)},
					"ally_t": {"lost": 0, "cell": Vector2i(2, -2)}, "me": {"moved": false}}]]},
	{"name": "Manœuvre swaps the caster with its target",
		"source": "Manœuvre: « occasionne des dommages Air aux ennemis et échange de position avec la cible »",
		"breed": 1, "steps": [
			["cast", 1041125, "foe"],
			["expect", {"foe": {"lost": 37, "cell": "me"}, "me": {"cell": "foe"}}]]},
	{"name": "Terre Brûlée's glyph burns an enemy starting its turn in it",
		"source": "Terre Brûlée: « Pose un glyphe de début de tour qui occasionne des dommages Feu aux ennemis »",
		"breed": 1, "steps": [
			["cast", 1041054, "foe"],
			["expect", {"foe": {"lost": 0}, "marks": {"glyph_start": 1}}],
			["turn", "foe"],
			["expect", {"foe": {"lost": 25}}]]},
	# ── Osamodas ──
	{"name": "Saute-granouille jumps over its target",
		"source": "Saute-granouille: « Téléporte le lanceur symétriquement par rapport à la cible et occasionne des dommages Eau »",
		"breed": 2, "setup": {"foe_2": {"at": Vector2i(4, 3)}}, "steps": [
			["cast", 1082237, "foe"],
			["expect", {"me": {"cell": Vector2i(4, 0)}, "foe": {"lost": 18, "moved": false}}]]},
	{"name": "Fouet hits in the caster's best element and pushes 2",
		"source": "Fouet: « dommages dans le meilleur élément du lanceur aux ennemis et repousse la cible »",
		"breed": 2, "setup": {"me": {"stats": {"chance": 100}}, "foe": {"stats": {"res_water": 50}}, "foe_2": {"at": Vector2i(4, 3)}},
		"steps": [
			["cast", 1082230, "foe"],
			["expect", {"foe": {"lost": 10, "cell": Vector2i(4, 0)}}]]}, # 10 x 200% water, -50 %
	{"name": "Tofu summons a Tofu on the cell",
		"source": "Tofu: « Invoque un Tofu maîtrisable »",
		"breed": 2, "steps": [
			["cast", 1082231, "free"],
			["expect", {"summons": 1}]]},
	# ── Enutrof ──
	{"name": "Retraite Anticipée roots everyone else now and the caster on its next turn",
		"source": "Retraite Anticipée: « Immobilise les cibles et applique l'état Pesanteur sur tout le monde sauf le lanceur. Immobilise le lanceur au tour suivant »",
		"breed": 3, "steps": [
			["cast", 1041751, "me"],
			["expect", {"foe": {"mp": 0, "states": [7]}, "ally": {"mp": 0, "states": [7]}, "far": {"mp": 0}, "me": {"mp": 3, "no_states": [7]}}],
			["turn", "me"],
			["expect", {"me": {"mp": 0}}]]},
	{"name": "Souterrain swaps with its target and hits it",
		"source": "Souterrain: « Échange de position avec la cible et occasionne des dommages Terre aux ennemis »",
		"breed": 3, "steps": [
			["cast", 1041770, "foe"],
			["expect", {"foe": {"lost": 22, "cell": "me"}, "me": {"cell": "foe"}}]]},
	{"name": "Tunnel de Fortune makes the caster invisible",
		"source": "Tunnel de Fortune: « Rend le lanceur invisible »",
		"breed": 3, "steps": [
			["cast", 1043676, "me"],
			["expect", {"me": {"invisible": true}}]]},
	{"name": "Sac Animé takes the hits of the allies around it",
		"source": "Sac Animé: « intercepte les dommages des alliés situés dans sa zone d'invocation »",
		"breed": 3, "setup": {"ally": {"at": Vector2i(1, 2)}}, "steps": [
			["cast", 1041688, "free"],
			["hit", "foe", "ally", 100],
			["expect", {"summons": 1, "ally": {"lost": 0}}]]},
	# ── Sram ──
	{"name": "Arsenic poisons at the start of the target's turn",
		"source": "Arsenic: « Retire de la Portée et applique un poison Air de début de tour sur la cible »",
		"breed": 4, "steps": [
			["cast", 1040898, "foe"],
			["expect", {"foe": {"lost": 0, "stat": {"range": -2}}}],
			["turn", "foe"],
			["expect", {"foe": {"lost": 11}}]]},
	{"name": "Toxines poisons at the end of the target's turn, and grows with each cast",
		"source": "Toxines: « Applique un poison Air de fin de tour sur l'ennemi ciblé. Les dommages du sort sont augmentés (cumulable 5 fois) »",
		"breed": 4, "steps": [
			["cast", 1040970, "foe"],
			["turn", "foe"],
			["expect", {"foe": {"lost": 0}}],
			["turn", "me"],
			["expect", {"foe": {"lost": 7}}]]},
	{"name": "Piège Sournois hurts and pulls who walks into it",
		"source": "Piège Sournois: « Pose un piège qui occasionne des dommages Feu aux ennemis et attire les entités vers son centre en zone »",
		"breed": 4, "steps": [
			["cast", 1040895, Vector2i(2, 3)],
			["expect", {"marks": {"trap": 1}}],
			["walk", "foe_n", Vector2i(2, 3)],
			["expect", {"foe_n": {"lost": 12}, "marks": {"trap": 0}}]]},
	{"name": "Invisibilité hides an ally and gives it MP",
		"source": "Invisibilité: « Rend la cible invisible. Augmente également ses PM si c'est un allié »",
		"breed": 4, "steps": [
			["cast", 1040916, "ally"],
			["expect", {"ally": {"invisible": true, "mp": 4}}]]},
	{"name": "Extorsion steals Strength first, then life with it",
		"source": "Extorsion: « Vole de la Force et de la vie dans l'élément Terre » (effects in order: the stolen Strength counts)",
		"breed": 4, "setup": {"me": {"hp": 5000}}, "steps": [
			["cast", 1040975, "foe"],
			["expect", {"foe": {"lost": 26, "stat": {"strength": -40}}, "me": {"lost": -13, "stat": {"strength": 40}}}]]},
	# ── Xélor ──
	{"name": "Frappe de Xélor sends its target to the other side of the caster",
		"source": "Frappe de Xélor: « Téléporte la cible symétriquement par rapport au lanceur et occasionne des dommages Terre »",
		"breed": 5, "steps": [
			["cast", 1041556, "foe"],
			["expect", {"foe": {"cell": Vector2i(-2, 0), "lost": 15}, "me": {"moved": false}}]]},
	{"name": "Frappe de Xélor onto an ally is a Téléfrag: both swap and get Téléfrag, the caster gains 2 AP",
		"source": "Frappe de Xélor: « Peut générer un Téléfrag » (Téléfrag: état 3622, Téléfrag allié 244 / ennemi 251)",
		"breed": 5, "setup": {"ally": {"at": Vector2i(-2, 0)}}, "steps": [
			["cast", 1041556, "foe"],
			["expect", {"foe": {"cell": "ally", "states": [3622, 251]}, "ally": {"cell": "foe", "states": [3622, 244]}, "me": {"ap": 8}}]]},
	{"name": "Gelure sends its target back where it was before its last move",
		"source": "Gelure: « Téléporte la cible à sa position précédente et occasionne des dommages Eau »",
		"breed": 5, "steps": [
			["walk", "foe", Vector2i(3, 0)],
			["cast", 1041535, Vector2i(3, 0)],
			["expect", {"foe": {"cell": "foe", "lost": 8}}]]},
	{"name": "Momification gives the caster MP and AP removal",
		"source": "Momification: « Applique l'état Téléfrag sur le lanceur, le rend Intaclable et augmente ses PM et son Retrait PA »",
		"breed": 5, "steps": [
			["cast", 1041578, "me"],
			["expect", {"me": {"mp": 5, "stat": {"ap_attack": 30}, "states": [3622]}}]]},
	# ── Ecaflip ──
	{"name": "Bond du Félin teleports onto a free cell",
		"source": "Bond du Félin: « Augmente les PM de l'allié ciblé ou téléporte le lanceur sur la case ciblée »",
		"breed": 6, "steps": [
			["cast", 1040770, Vector2i(0, 1)],
			["expect", {"me": {"cell": Vector2i(0, 1)}}]]},
	{"name": "Bond du Félin on an ally gives MP and does not move anyone",
		"source": "Bond du Félin: « Augmente les PM de l'allié ciblé ou téléporte le lanceur »",
		"breed": 6, "setup": {"ally": {"at": Vector2i(0, 1)}}, "steps": [
			["cast", 1040770, "ally"],
			["expect", {"ally": {"mp": 4, "moved": false}, "me": {"moved": false}}]]},
	{"name": "Prédation erodes the enemies around",
		"source": "Prédation: « Érode l'ennemi ciblé et dévoile les invisibles en zone »",
		"breed": 6, "steps": [
			["cast", 1040834, "foe"],
			["expect", {"foe": {"stat": {"erosion": 10}}, "foe_n": {"stat": {"erosion": 10}}, "ally_t": {"stat": {"erosion": 0}}}]]},
	# ── Eniripsa ──
	{"name": "Mot Vampirique gives an ally part of the caster's life",
		"source": "Mot Vampirique: « transfère une partie de la vie du lanceur à l'allié ciblé » (8 % in the spell and 8 % in its sub-spell)",
		"breed": 7, "setup": {"ally": {"hp": 5000}}, "steps": [
			["cast", 1065828, "ally"],
			["expect", {"me": {"lost": [800, 1600]}, "ally": {"lost": [-1600, -800]}, "foe": {"lost": 0}}]]},
	{"name": "Mot d'Envol swaps with an ally",
		"source": "Mot d'Envol: « Échange de position avec l'allié ciblé »",
		"breed": 7, "steps": [
			["cast", 1041431, "ally"],
			["expect", {"me": {"cell": "ally"}, "ally": {"cell": "me"}}]]},
	{"name": "Mot Farceur sends its target back at the end of its turn",
		"source": "Mot Farceur: « applique l'état Farce sur la cible : téléporte la cible à sa position précédente à la fin de son tour »",
		"breed": 7, "steps": [
			["walk", "foe", Vector2i(3, 0)],
			["cast", 1065837, Vector2i(3, 0)],
			["expect", {"foe": {"lost": 17, "states": [4206], "cell": Vector2i(3, 0)}}],
			["turn", "me"],
			["expect", {"foe": {"cell": "foe"}}]]},
	# ── Iop ──
	{"name": "Bond teleports the caster onto the free cell",
		"source": "Bond: « Téléporte le lanceur sur la case ciblée et augmente les dommages subis par les ennemis en zone »",
		"breed": 8, "steps": [
			["cast", 1041277, "free"],
			["expect", {"me": {"cell": "free"}}]]},
	{"name": "Précipitation gives AP now and takes 3 back on the ally's next turn",
		"source": "Précipitation: « Augmente les PA de l'allié ciblé et lui applique l'état Affaibli. Retire des PA non esquivables à cet allié au tour suivant »",
		"breed": 8, "steps": [
			["cast", 1041298, "ally"],
			["expect", {"ally": {"ap": 11, "states": [42]}}],
			["turn", "me"],
			["turn", "ally"],
			["expect", {"ally": {"ap": 3}}]]},
	{"name": "Violence pushes everyone around the caster 4 cells away",
		"source": "Violence: « Repousse les cibles en zone » (cercle 1 à 2 autour du lanceur)",
		"breed": 8, "steps": [
			["cast", 1041347, "me"],
			["expect", {"ally": {"cell": Vector2i(-5, 0), "lost": 0}, "foe": {"cell": Vector2i(3, 0), "lost": [1, 9999]}, "me": {"moved": false}}]]},
	# ── Crâ ──
	{"name": "Pas Chassé teleports the caster and gives it 1 MP on its next turn",
		"source": "Pas Chassé: « Téléporte le lanceur sur la case ciblée. Augmente les PM du lanceur au tour suivant »",
		"breed": 9, "steps": [
			["cast", 1085272, Vector2i(1, 0)],
			["expect", {"me": {"cell": Vector2i(1, 0)}}],
			["turn", "me"],
			["expect", {"me": {"mp": 4}}]]},
	{"name": "Flèche de Recul hits and pushes 2",
		"source": "Flèche de Recul: « Occasionne des dommages Air aux ennemis et repousse la cible »",
		"breed": 9, "setup": {"foe_2": {"at": Vector2i(4, 3)}}, "steps": [
			["cast", 1085234, "foe"],
			["expect", {"foe": {"lost": 17, "cell": Vector2i(4, 0)}}]]},
	{"name": "Tirs Puissants trades range for power",
		"source": "Tirs Puissants: « Sacrifie la Portée du lanceur pour augmenter sa Puissance, ses Dommages Poussée et ses Critiques »",
		"breed": 9, "steps": [
			["cast", 1085274, "me"],
			["expect", {"me": {"stat": {"range": -1, "power": 150, "push_damage": 50, "crit": 10}}}]]},
	# ── Sacrieur ──
	{"name": "Assaut swaps with its target, then hits it",
		"source": "Assaut: « Échange de position avec la cible et occasionne des dommages Air aux ennemis »",
		"breed": 11, "steps": [
			["cast", 1040565, "foe"],
			["expect", {"foe": {"lost": 11, "cell": "me"}, "me": {"cell": "foe"}}]]},
	{"name": "Attirance pulls its target next to the caster",
		"source": "Attirance: « Attire la cible »",
		"breed": 11, "setup": {"foe": {"at": Vector2i(5, 0)}, "foe_2": {"at": Vector2i(4, 3)}}, "steps": [
			["cast", 1040571, "foe"],
			["expect", {"foe": {"cell": Vector2i(1, 0), "lost": 0}}]]},
	{"name": "Sacrifice takes the allies' hits on the caster",
		"source": "Sacrifice: « Intercepte les dommages subis par les alliés en zone »",
		"breed": 11, "steps": [
			["cast", 1040583, "me"],
			["hit", "foe", "ally", 100],
			["expect", {"ally": {"lost": 0}, "me": {"lost": 100}}]]},
	{"name": "Fulgurance lands next to its target and hits it",
		"source": "Fulgurance: « Téléporte le lanceur sur la première case disponible entre la cible et lui et occasionne des dommages Air aux ennemis en zone »",
		"breed": 11, "setup": {"foe": {"at": Vector2i(4, 0)}, "foe_2": {"at": Vector2i(4, 3)}}, "steps": [
			["cast", 1040536, "foe"],
			["expect", {"me": {"cell": Vector2i(3, 0)}, "foe": {"lost": 23}}]]},
	{"name": "Projection jumps over its target",
		"source": "Projection: « Téléporte le lanceur symétriquement par rapport à la cible et occasionne des dommages Eau »",
		"breed": 11, "setup": {"foe_2": {"at": Vector2i(4, 3)}}, "steps": [
			["cast", 1040544, "foe"],
			["expect", {"me": {"cell": Vector2i(4, 0)}, "foe": {"lost": 17}}]]},
	# ── Sadida ──
	{"name": "La Folle Transmutée becomes a Tree 3 turns after",
		"source": "La Folle Transmutée: « Invoque une Poupée maîtrisable [...] La Poupée est remplacée par un Arbre 3 tours après son invocation »",
		"breed": 10, "steps": [
			["cast", 1042083, "free"],
			["expect", {"monsters": {5896: 1, 5894: 0}}],
			["turn", "me"], ["turn", "me"],
			["expect", {"monsters": {5896: 1}}],
			["turn", "me"],
			["expect", {"monsters": {5896: 0, 5894: 1}}]]},
	# ── Pandawa ──
	{"name": "Karcham carries its target, then throws it",
		"source": "Karcham: « Porte ou jette la cible »",
		"breed": 12, "setup": {"ally": {"at": Vector2i(1, 0)}}, "steps": [
			["cast", 1040662, "ally"],
			["expect", {"ally": {"carried_by": "me", "cell": "me"}}],
			["cast", 1040662, Vector2i(0, 1)],
			["expect", {"ally": {"cell": Vector2i(0, 1)}}]]},
	{"name": "Paume Explosive changes once cast by a sober Pandawa: its next cast hits around",
		"source": "Paume Explosive: « Occasionne des dommages Feu. Modifie le sort selon l'état du lanceur après un lancer »",
		"breed": 12, "setup": {"me": {"states": [3531]}}, "steps": [
			["cast", 1040644, "foe"],
			["expect", {"foe": {"lost": 14}, "foe_n": {"lost": 0}, "me": {"states": [3532]}}],
			["cast", 1040644, "foe"],
			["expect", {"foe": {"lost": 28}, "foe_n": {"lost": 12}}]]},
	{"name": "Fermentation shields an ally now and on the next turn",
		"source": "Fermentation: « Applique un bouclier sur l'allié ciblé immédiatement et au tour suivant »",
		"breed": 12, "steps": [
			["cast", 1040724, "ally"],
			["expect", {"ally": {"buff": {"shield": 1}}}],
			["turn", "me"],
			["expect", {"ally": {"buff": {"shield": 1}}}]]},
	# ── Roublard ──
	{"name": "Détonateur sets the Explobombe off and gives AP back",
		"source": "Explobombe: « Pose une Bombe qui peut occasionner des dommages Feu en zone à son explosion » ; Détonateur: « déclenche son explosion. Rend 1 PA au lanceur » (on a bomb its data gives 1 AP twice: 120, and 120 in sub-spell 1061089)",
		"breed": 13, "steps": [
			["cast", 1041922, Vector2i(1, 1)],
			["expect", {"monsters": {3112: 1}}],
			["cast", 1041886, Vector2i(1, 1)],
			["expect", {"monsters": {3112: 0}, "foe": {"lost": [1, 9999]}, "me": {"ap": 8}}]]},
	# ── Zobal ──
	{"name": "Masque de l'Intrépide: AP for the caster and its allies, pulls who stands 2 cells away",
		"source": "Masque de l'Intrépide: « Applique l'état Intrépide sur le lanceur. Augmente les PA du lanceur et de ses alliés »",
		"breed": 14, "steps": [
			["cast", 1041793, "me"],
			["expect", {"me": {"states": [98], "ap": 7}, "ally": {"ap": 7}, "foe": {"cell": Vector2i(1, 0)}}]]},
	{"name": "Débandade teleports next to the caster and gives MP",
		"source": "Débandade: « Téléporte le lanceur sur la case ciblée et augmente ses PM »",
		"breed": 14, "steps": [
			["cast", 1041808, Vector2i(1, 0)],
			["expect", {"me": {"cell": Vector2i(1, 0), "mp": 4}}]]},
	{"name": "Pivot jumps over the adjacent target",
		"source": "Pivot: « Téléporte le lanceur symétriquement par rapport à la cible »",
		"breed": 14, "setup": {"foe": {"at": Vector2i(1, 0)}}, "steps": [
			["cast", 1041855, "foe"],
			["expect", {"me": {"cell": Vector2i(2, 0)}, "foe": {"moved": false}}]]},
	# ── Steamer ──
	{"name": "Marée swaps with its target and hits it",
		"source": "Marée: « Échange de position avec la cible et occasionne des dommages Eau aux ennemis »",
		"breed": 15, "steps": [
			["cast", 1042725, "foe"],
			["expect", {"foe": {"lost": 24, "cell": "me"}, "me": {"cell": "foe"}}]]},
	{"name": "Torpille hits and pushes 2",
		"source": "Torpille: « Occasionne des dommages Air aux ennemis et repousse la cible »",
		"breed": 15, "setup": {"foe_2": {"at": Vector2i(4, 3)}}, "steps": [
			["cast", 1042845, "foe"],
			["expect", {"foe": {"lost": 17, "cell": Vector2i(4, 0)}}]]},
	# ── Éliotrope ──
	{"name": "Portail lays a portal and raises the caster's final damage",
		"source": "Portail: « Pose un portail »",
		"breed": 16, "steps": [
			["cast", 1044339, "free"],
			["expect", {"marks": {"portal": 1}, "me": {"stat": {"final_damage": 2}}}]]},
	# ── monsters ──
	{"name": "Bave Affaiblissante: the target takes 20 % more for the turn",
		"source": "Bave Affaiblissante (monstre): « Dommages subis x120% » (1163, sans déclencheur)",
		"steps": [
			["cast", 1036076, "me", {"by": "foe"}],
			["expect", {"me": {"lost": [15, 20]}}],
			["hit", "foe_n", "me", 100],
			["expect", {"me": {"lost": [135, 140]}}]]},
	# ── Huppermage ──
	{"name": "Lance Solaire swaps with its target and hits it",
		"source": "Lance Solaire: « Échange de position avec la cible et occasionne des dommages Feu aux ennemis »",
		"breed": 17, "steps": [
			["cast", 1042536, "foe"],
			["expect", {"foe": {"lost": 20, "cell": "me"}, "me": {"cell": "foe"}}]]},
	# ── Ouginak ──
	{"name": "Proie: who hits the prey is healed of part of the damage",
		"source": "Proie: « Applique l'état Proie sur l'ennemi ciblé. Les entités qui attaquent la cible sont soignées d'une partie des dommages occasionnés » (15 %)",
		"breed": 18, "setup": {"ally": {"hp": 5000}}, "steps": [
			["cast", 1042580, "foe"],
			["hit", "ally", "foe", 100],
			["expect", {"foe": {"states": [516], "lost": 100}, "ally": {"lost": -15}}]]},
	{"name": "Charogne erodes before it hits: the hit already erodes more",
		"source": "Charogne: « Érode la cible et occasionne des dommages Air » (érosion de base 10 % + 10 %)",
		"breed": 18, "steps": [
			["cast", 1042628, "foe"],
			["expect", {"foe": {"lost": 20, "max_hp": 9996, "stat": {"erosion": 10}}}]]},
	{"name": "Radius swaps with its target and hits it",
		"source": "Radius: « Échange de position avec la cible et occasionne des dommages Eau aux ennemis »",
		"breed": 18, "steps": [
			["cast", 1042701, "foe"],
			["expect", {"foe": {"lost": 29, "cell": "me"}, "me": {"cell": "foe"}}]]},
	# ── Forgelance ──
	{"name": "Estoc Brûlant pushes everyone in the cone away from the caster, twice",
		"source": "Estoc Brûlant (i18n 1140213): « repousse les cibles depuis le lanceur en zone » ; APPROX(P1.18b): le sort pose l'état 6032, lance 1079237 (pousse de 2 ceux qui l'ont) puis pousse de 2 lui-même : 4 cases au total, comme les donnees",
		"breed": 20, "setup": {"foe_2": {"at": Vector2i(8, 3)}}, "steps": [
			["cast", 1060590, "foe"],
			["expect", {"foe": {"lost": 19, "cell": Vector2i(6, 0), "no_states": [6032]},
					"foe_d": {"lost": 17, "cell": Vector2i(7, 1)}, "foe_n": {"moved": false, "lost": 0}}]]},
	{"name": "Estoc Brûlant stops at an obstacle and hurts",
		"source": "Estoc Brûlant: une poussée arrêtée par un combattant occasionne des dommages de poussée (FightDisplace.push)",
		"breed": 20, "steps": [
			["cast", 1060590, "foe"],
			["expect", {"foe": {"cell": Vector2i(3, 0)}, "foe_2": {"moved": false}}]]},
	# ── Huppermage ──
	{"name": "Runification triggers a rune, steals each element and raises the characteristics",
		"source": "Runification (i18n 1179245): « déclenche une rune pour voler de la vie à l'ennemi qui l'occupe, et augmenter les caractéristiques du lanceur » ; 64 = 17 (la pose d'Éther) + 4 vols de 9 + la rune d'Éther ; l'agilité vaut 60 : +30 du sort et +30 de la rune d'air",
		"breed": 17, "steps": [
			["cast", 1042413, "foe"],
			["cast", 1042414, "foe"],
			["expect", {"foe": {"lost": 64, "states": [290, 291, 292, 293]}, "me": {"stat": {"strength": 30, "intelligence": 30, "chance": 30, "agility": 60}}}]]},
	# ── H.03 : mécaniques sensibles des classes les moins couvertes (valeurs = dés des données, lanceur sans caractéristique) ──
	{"name": "Arbre summons a tree on the free cell",
		"source": "Arbre (spells 1042093): effets summon 5894 (+ etat 256 apres 1 tour) ; le sort pose une invocation, sans toucher personne",
		"breed": 10, "steps": [
			["cast", 1042093, "free"],
			["expect", {"summons": 1, "monsters": {5894: 1}, "foe": {"lost": 0}}]]},
	{"name": "Vent Empoisonne poisons its target at each of its turns, twice",
		"source": "Vent Empoisonne (1042115): damage dur2 11-13 Air on=TB (debut de tour de la cible) ; le maximum dés vaut 13",
		"breed": 10, "steps": [
			["cast", 1042115, "foe"],
			["expect", {"foe": {"lost": 0}}],
			["turn", "foe"],
			["expect", {"foe": {"lost": 13}}],
			["turn", "foe"],
			["expect", {"foe": {"lost": 26}}],
			["turn", "foe"],
			["expect", {"foe": {"lost": 26}}]]},
	{"name": "Chardons Ardents burns the target at the end of its turn",
		"source": "Chardons Ardents (1042087): state dur2 5399 puis damage dur1 8-8 Feu on=TE ; 8 fixes",
		"breed": 10, "steps": [
			["cast", 1042087, "foe"],
			["turn", "me"],
			["expect", {"foe": {"lost": [8, 100]}}]]},
	{"name": "Explobombe summons a bomb",
		"source": "Explobombe (1041922): summon 3112 ; une bombe n'explose pas toute seule",
		"breed": 13, "steps": [
			["cast", 1041922, "free"],
			["expect", {"summons": 1, "monsters": {3112: 1}, "foe": {"lost": 0}}]]},
	{"name": "Roublabot summons a robot",
		"source": "Roublabot (1041879): summon 3120",
		"breed": 13, "steps": [
			["cast", 1041879, "free"],
			["expect", {"summons": 1, "monsters": {3120: 1}}]]},
	{"name": "Pulsar hits and pushes 2",
		"source": "Pulsar (1041916): damage 17-19 Feu + push 2 ; le maximum dés vaut 19",
		"breed": 13, "setup": {"foe_2": {"at": Vector2i(8, 3)}}, "steps": [
			["cast", 1041916, "foe"],
			["expect", {"foe": {"lost": 19, "cell": Vector2i(4, 0)}}]]},
	{"name": "Piege Magnetique lays a trap",
		"source": "Piege Magnetique (1042023): trap 1042024 ; un piege est une marque, personne n'est touche tant que nul n'y marche",
		"breed": 13, "steps": [
			["cast", 1042023, "free"],
			["expect", {"marks": {"trap": 1}, "foe": {"lost": 0}, "me": {"lost": 0}}]]},
	{"name": "Harponneuse summons a steam turret",
		"source": "Harponneuse (1042734): summon 5836",
		"breed": 15, "steps": [
			["cast", 1042734, "free"],
			["expect", {"summons": 1, "monsters": {5836: 1}}]]},
	{"name": "Foene hits and pushes 2",
		"source": "Foene (1042785): damage 18-20 Air + push 2 ; le maximum dés vaut 20",
		"breed": 15, "setup": {"foe_2": {"at": Vector2i(8, 3)}}, "steps": [
			["cast", 1042785, "foe"],
			["expect", {"foe": {"lost": 20, "cell": Vector2i(4, 0)}}]]},
	{"name": "Portail lays a portal that lasts and its bonus ends after 3 turns",
		"source": "Portail (1044339): portal dur-1 + stat dur3 final_damage 2 et final_heals 2 sur le lanceur",
		"breed": 16, "steps": [
			["cast", 1044339, Vector2i(1, 0)],
			["expect", {"marks": {"portal": 1}, "me": {"stat": {"final_damage": 2}}}],
			["turn", "me"],
			["turn", "me"],
			["turn", "me"],
			["expect", {"marks": {"portal": 1}, "me": {"stat": {"final_damage": 0}}}]]},
	{"name": "Extinction hits once: its delayed hit needs a portal",
		"source": "Extinction (1044399): damage 26-28 Feu ; le second coup (on=TE, cond portal vrai) n'a lieu que dans un portail : sans portail, 28 une seule fois",
		"breed": 16, "steps": [
			["cast", 1044399, "foe"],
			["expect", {"foe": {"lost": 28}}],
			["turn", "me"],
			["expect", {"foe": {"lost": 28}}]]},
	{"name": "Tison lays a fire rune and marks the target with the fire state",
		"source": "Tison (1042525): rune dur2 1042409, damage 10-12 Feu, state dur-1 290 ; le maximum dés vaut 12",
		"breed": 17, "steps": [
			["cast", 1042525, "foe"],
			["expect", {"foe": {"lost": 12, "states": [290]}, "marks": {"rune": 1}}]]},
	{"name": "Ether lays an air rune and marks the target with the air state",
		"source": "Ether (1042413): rune dur2 1042435, damage 15-17 Air, state dur-1 293 ; le maximum dés vaut 17",
		"breed": 17, "steps": [
			["cast", 1042413, "foe"],
			["expect", {"foe": {"lost": 17, "states": [293]}, "marks": {"rune": 1}}]]},
	{"name": "Maelstrom swaps with its target and hits it",
		"source": "Maelstrom (1060581): swap + damage 26-29 Feu en zone autour de la case visee : la cible, revenue 2 cases du centre, perd 29 - 20 % = 23 (la chute par distance de la zone, comme les donnees)",
		"breed": 20, "steps": [
			["cast", 1060581, "foe"],
			["expect", {"foe": {"lost": 23, "cell": "me"}, "me": {"cell": "foe", "lost": 0}}]]},
	{"name": "Volee d'Airain hits and pushes 4 in all (its sub-spell pushes 2 too)",
		"source": "Volee d'Airain (1060570): damage 14-16 Air, sous-sort 1062626 (push 2) puis push 2 : 4 cases ; le maximum des dés vaut 16",
		"breed": 20, "setup": {"foe_2": {"at": Vector2i(8, 3)}}, "steps": [
			["cast", 1060570, "foe"],
			["expect", {"foe": {"lost": 16, "cell": Vector2i(6, 0)}}]]},
]
