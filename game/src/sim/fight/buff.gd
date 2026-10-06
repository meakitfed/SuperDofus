## A lasting effect on a fighter: characteristic bonus, AP/MP bonus or loss,
## state, shield, poison, trigger (FightTriggers). `turns` counts down at the start
## of the caster's turns (Dofus); -1 = until the end of the fight (or of its aura).
class_name Buff
extends RefCounted

var id := 0
var kind := "" # "stat" | "ap" | "mp" | "state" | "shield" | "poison" | "trigger" | "delay"
var stat := "" # kind "stat"
var state := 0 # kind "state"
var state_name_id := 0
var flags: Array = [] # state flags: cant_be_pushed, invulnerable, no_cast...
var value := 0 # bonus (negative = malus), shield points left, poison effect below
var effect := {} # kind "poison": the damage effect applied each turn; "trigger": the effect it
		# fires; "delay": the effect that lands when the buff runs out
var on: Array = [] # kind "trigger": its codes (FightTriggers)
var aura := 0 # given by this aura mark (FightMarks.auras), 0 = none
var busy := false # kind "trigger": firing now (FightTriggers.fire)
## spelllevels effect `dispellable` (P1.13m): 1 a dispel (132) removes it, 2 only death, 3 never
var dispellable := 1
var turns := 1
var caster := 0
var spell := 0


func to_dict() -> Dictionary:
	var d := {"id": id, "kind": kind, "value": value, "turns": turns, "caster": caster, "spell": spell}
	if kind == "stat":
		d["stat"] = stat
	if kind == "state":
		d["state"] = state
		d["state_name_id"] = state_name_id
		if not flags.is_empty():
			d["flags"] = flags
	if kind == "trigger":
		d["on"] = on
	if kind == "trigger" or kind == "delay":
		d["effect"] = str(effect.get("kind", ""))
	return d
