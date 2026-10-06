## Data-driven bridge from gameplay states to Dofus animation base names.
## One resource per entity family (player, monster, NPC…) lets designers remap
## animations without touching gameplay code.
class_name AnimMap
extends Resource

## GameEntity.State name -> animation base ("" = the bone's default idle)
@export var bases: Dictionary = {
	"IDLE": "",
	"MOVE": "AnimMarche",
	"RUN": "AnimCourse",
	"ATTACK": "AnimAttaque0",
	"HIT": "AnimHit",
	"DIE": "AnimMort",
}
## states whose animation plays once (then the view reports `action_done`)
@export var one_shot: PackedStringArray = PackedStringArray(["ATTACK", "HIT", "DIE"])


func base_for(state: GameEntity.State) -> String:
	return base_for_name(GameEntity.State.keys()[state])


## Same, keyed by state name ("IDLE", "MOVE"…), for callers without a GameEntity.
func base_for_name(state: String) -> String:
	return bases.get(state, "")


func is_one_shot(state: GameEntity.State) -> bool:
	return one_shot.has(GameEntity.State.keys()[state])
