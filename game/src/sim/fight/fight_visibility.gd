## What each team may know of a fight (roadmap P1.13c): the server sends every
## recipient its own view of an event, the standalone host does the same.
##   invisible (effect 150 "Rend la cible invisible": state 250 "Invisible", flag
##   `invisible`): the other team does not get its position: its walks come with an
##   empty path, the moves of spells too, its fighter dict with cell -1. When it
##   stops being invisible (effect 202 "Dévoile les entités invisibles", or the end
##   of the state) everyone gets a `reveal` effect with its cell (FightEffects).
##   APPROX(P1.13c): a spell it casts shows the other team the cell it casts from
##   (`from`); it stays invisible.
##   traps: a hidden mark (P1.13a) is not sent to the other team (mark_add dropped);
##   when it goes off, everyone sees its effects.
## Hidden things are judged when the event goes out (after the action).
class_name FightVisibility
extends RefCounted


## `id` is hidden from `team`.
static func hidden(fight: Fight, id: int, team: int) -> bool:
	var f: Fighter = fight.fighters.get(id)
	return f != null and f.team != team and f.alive and f.has_flag("invisible")


## `ev` as `team` may see it (a copy; the same dict for events that can hide nothing).
static func view(ev: Dictionary, fight: Fight, team: int) -> Dictionary:
	if not ev.has("effects") and not ev.has("triggered") and not ev.has("fighters") 			and str(ev.get("t", "")) not in [Protocol.FIGHTER_MOVE, Protocol.SPELL_CAST]:
		return ev
	var d := ev.duplicate(true)
	match str(d.get("t", "")):
		Protocol.FIGHTER_MOVE:
			if hidden(fight, int(d["id"]), team):
				d["path"] = []
		Protocol.SPELL_CAST:
			if hidden(fight, int(d["caster"]), team):
				d["from"] = (fight.fighters[int(d["caster"])] as Fighter).cell
	if d.has("fighters"):
		d["fighters"] = (d["fighters"] as Array).map(func(f: Dictionary) -> Dictionary: return _fighter(fight, f, team))
	for key: String in ["effects", "triggered"]:
		if d.has(key):
			d[key] = _effects(fight, d[key], team)
	return d


static func _effects(fight: Fight, effects: Array, team: int) -> Array:
	var out: Array = []
	for e: Dictionary in effects:
		match str(e.get("kind", "")):
			"mark_add":
				if bool(e["mark"].get("hidden", false)) and int(e["mark"]["team"]) != team:
					continue
			"move":
				if hidden(fight, int(e["target"]), team):
					e["path"] = []
			"summon":
				e["fighter"] = _fighter(fight, e["fighter"], team)
		out.append(e)
	return out


static func _fighter(fight: Fight, f: Dictionary, team: int) -> Dictionary:
	if hidden(fight, int(f["id"]), team):
		f["cell"] = -1
	return f
