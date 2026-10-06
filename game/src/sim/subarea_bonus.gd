## The stars of the monster groups (roadmap P1.09): an XP and loot bonus shared
## by a whole subarea since Dofus 2.51 ("les étoiles sont désormais générées au
## niveau d'une zone/d'un donjon entier"), from −50 % (too much activity) to
## +100 %; Incarnam and Astrub have none.
## Source: https://dofus.jeuxonline.info/actualite/56075 (Anomalies temporelles).
## The bonus is the fight's rewardRate (luaformulas 99: 1 + bonus / 100).
## Kept in Persistence ("worlds", "<world>/stars") and aged with the real
## clock, so the stars grow while nobody plays, like on a server.
class_name SubareaBonus
extends RefCounted

const MAX := 100
const MIN := -50
## areas.id: Astrub (18) and Incarnam (45), "zones débutantes"
const NO_STARS_AREAS := [18, 45]
## APPROX(P1.09): the 2.51 system balances zones of the same level from the
## players' activity, with unpublished rates. Growth kept from the per-group
## Dofus 2 rule (20 % per hour, "Les groupes de monstres gagnent 20% de bonus
## d'XP et de butin par heure", https://blog-zaapsufokien.ek.la/etoiles-des-groupes-de-monstres-edit-1-a4023709;
## other community pages say 2 %), a defeated group takes one star (20 %) from its subarea.
const PER_HOUR := 20.0
const PER_DEFEAT := 20.0

var persistence: Persistence
var key := ""
## subarea id (String) -> {bonus: float, at: unix ms}
var _state := {}


func _init(p_persistence: Persistence = null, world_id := "") -> void:
	persistence = p_persistence
	key = world_id + "/stars"
	if persistence != null:
		_state = persistence.load_doc("worlds", key).get("subareas", {})


## The subarea's bonus in % at this date (0 for Incarnam / Astrub).
func bonus(subarea: int, area: int, now_unix: int) -> int:
	if NO_STARS_AREAS.has(area):
		return 0
	return int(floor(_value(subarea, now_unix)))


## A group of the subarea was beaten: its bonus goes down.
func on_defeat(subarea: int, area: int, now_unix: int) -> void:
	if NO_STARS_AREAS.has(area):
		return
	_store(subarea, _value(subarea, now_unix) - PER_DEFEAT, now_unix)


## Tool / test shortcut.
func set_bonus(subarea: int, value: float, now_unix: int) -> void:
	_store(subarea, value, now_unix)


func _value(subarea: int, now_unix: int) -> float:
	var s: Dictionary = _state.get(str(subarea), {})
	if s.is_empty():
		return 0.0
	var hours := maxf(0.0, float(now_unix - int(s["at"])) / 3_600_000.0)
	return minf(MAX, float(s["bonus"]) + hours * PER_HOUR)


func _store(subarea: int, value: float, now_unix: int) -> void:
	_state[str(subarea)] = {"bonus": clampf(value, MIN, MAX), "at": now_unix}
	if persistence != null:
		persistence.save_doc("worlds", key, {"subareas": _state})
