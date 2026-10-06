## A fight on the map (P3.04): the swords the players of the map see, and click to join or watch.
## It stands on the cell of the group that was attacked. Public information only: how many
## fighters each team has, the phase and the options (nothing of the fighters themselves).
class_name FightActor
extends SimActor

var fight: Fight


func kind() -> String:
	return "fight"


## The part of the dict that changes with the fight (WorldFightWatch re-sends the actor when it does).
func state() -> Dictionary:
	return {"teams": [fight.team_size(0), fight.team_size(1)], "phase": fight.phase, "options": fight.options.duplicate()}


func to_dict(now: int) -> Dictionary:
	var d := super.to_dict(now)
	d.merge(state())
	return d
