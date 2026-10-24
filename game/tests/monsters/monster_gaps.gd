## The monsters whose family promise (MonsterMatrix.family_errors) still fails in the standard 6-turn game.
## H.04d studied the 62 that failed after H.04b: 56 left the list (start spells played, kills and blasts and cones
## aimed by the AI, monsters of support spells no longer promised to hit, see docs/DECOUVERTES.md H.04d). What
## stays has a cause that is not a bug of the sim: value = APPROX(H.04d) reason.
## test_monster_matrix checks that each one still fails, so a fixed monster must leave the list.
class_name MonsterGaps
extends RefCounted

const KROKILLE := "APPROX(H.04d): the bomb explodes (Koque Chok, 8 AP) once its allies' Krokille de neuf have given it the AP (ap>allies); the standard game has no ally and its grade has 2 AP"

const GAPS := {
	"dofus:3144": KROKILLE,
	"dofus:3165": KROKILLE,
	"dofus:3166": KROKILLE,
	"dofus:3167": KROKILLE,
	"dofus:3401": "APPROX(H.04d): its only attack (Spahunglif) costs 15 AP and the grade has 12; the other four spells are glyphs",
	"dofus:4394": "APPROX(H.04d): FightAI values removing MP at 6 points per MP, far above a 1 to 4 damage hit (Petits Dards): it keeps casting Dards de laine",
}
