## Hosts the game in-process: one WorldSim per world, sharing one Persistence
## and one Clock. It is what the network server (roadmap S.01) will wrap with
## a transport, accounts and a database; standalone and tests use it directly.
## Several LocalBackends can share one LocalServer (multiplayer tests, bots):
## then the owner of the server ticks it, not each backend.
class_name LocalServer
extends RefCounted

var seed := 1
var persistence := Persistence.new()
var clock := Clock.new()
## world id -> WorldSource override (tests, generated worlds); default: worlds/<id>
var sources := {}
var worlds := {} # world id -> WorldSim
## instance id -> {content, name}: a world that reads the content of another (S.04b); its saves and
## lists are its own (they key on the instance id), `info.content` says which data it reads
var instances := {}
## where the GM audit trail goes (A1.01, WorldAdmin.audit_sink): set by the host, given to every world
var audit_sink := Callable():
	set(value):
		audit_sink = value
		for sim: WorldSim in worlds.values():
			sim.admin.audit_sink = value


## The running world, started on first use. null if the world does not exist.
func world(id: String) -> WorldSim:
	if worlds.has(id):
		return worlds[id]
	var source := source_of(id)
	if source == null:
		return null
	var sim := WorldSim.new(source, seed, persistence, clock)
	sim.admin.audit_sink = audit_sink
	worlds[id] = sim
	return sim


## The data source of a world or of an instance; null when it does not exist.
func source_of(id: String) -> WorldSource:
	var inst: Variant = instances.get(id)
	if inst is Dictionary:
		var base := source_of(str(inst["content"]))
		return base.instance(id, str(inst.get("name", id))) if base != null and not instances.has(str(inst["content"])) else null
	var source: WorldSource = sources.get(id, null)
	if source == null:
		source = JsonWorldSource.for_world(id)
	return source if not source.get_info().is_empty() else null


## Saves every connected character now (periodic save of a server, S.03); returns how many.
func save_all() -> int:
	var n := 0
	for sim: WorldSim in worlds.values():
		for p: PlayerActor in sim.players.values():
			sim.save_player(p)
			n += 1
	return n


func tick(delta_ms: int) -> void:
	clock.advance(delta_ms)
	for sim: WorldSim in worlds.values():
		sim.tick(delta_ms)
