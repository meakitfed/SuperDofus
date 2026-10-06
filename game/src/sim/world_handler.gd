## Base of the domain handlers of WorldSim (R.01): a RefCounted without Node that
## holds the sim it works for and applies the commands of one domain. WorldSim stays
## the thin router (connection, tick, drain, dispatch) and keeps the public API.
class_name WorldHandler
extends RefCounted

var sim: WorldSim


func _init(p_sim: WorldSim) -> void:
	sim = p_sim
