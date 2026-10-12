## Data-driven bridge from actor states to Dofus animation base names.
## One resource per entity family (player, monster, NPC…) lets designers remap
## animations without touching gameplay code.
class_name AnimMap
extends Resource

## state name -> animation base ("" = the bone's default idle)
@export var bases: Dictionary = {
	"IDLE": "",
	"MOVE": "AnimMarche",
	"RUN": "AnimCourse",
	"ATTACK": "AnimAttaque0",
	"HIT": "AnimHit",
	"DIE": "AnimMort",
}


## The animation base of a state name ("IDLE", "MOVE"…).
func base_for_name(state: String) -> String:
	return bases.get(state, "")
