## Server metrics (roadmap A1.01b): what `GET /admin/metrics` reports. `record_tick` is fed by
## ServerHost.poll with the duration of each poll; `snapshot` reads the sims. Plain numbers and
## strings only (JSON-safe). Knows nothing about the game being hosted. Not used by sim/,
## shared/ or client/.
class_name ServerMetrics
extends RefCounted

## tick durations kept for the average and the maximum (30 fps: about 20 s)
const WINDOW := 600

## server version reported to the admin
var version := str(ProjectSettings.get_setting("application/config/version", "dev"))
var _start_ms := Time.get_ticks_msec()
var _ring := PackedInt32Array() # microseconds, circular
var _next := 0
var _ticks := 0


func record_tick(usec: int) -> void:
	if _ring.size() < WINDOW:
		_ring.append(usec)
	else:
		_ring[_next] = usec
		_next = (_next + 1) % WINDOW
	_ticks += 1


## {ticks, avg_ms, max_ms, window} over the last WINDOW ticks (zeros before the first).
func tick_stats() -> Dictionary:
	var total := 0
	var worst := 0
	for u in _ring:
		total += u
		worst = maxi(worst, u)
	var n := _ring.size()
	return {"count": _ticks, "window": n, "avg_ms": snappedf(total / 1000.0 / maxi(n, 1), 0.001),
			"max_ms": snappedf(worst / 1000.0, 0.001)}


## `host` is a ServerHost. Active map = a map with at least one player; fight = a running Fight.
func snapshot(host: ServerHost) -> Dictionary:
	var worlds := {}
	var players := 0
	var maps := 0
	var fights := 0
	var ids := host.server.worlds.keys()
	ids.sort()
	for id: String in ids:
		var sim: WorldSim = host.server.worlds[id]
		var on_map := {}
		for p: PlayerActor in sim.players.values():
			on_map[p.map_id] = true
		worlds[id] = {"players": sim.players.size(), "maps_loaded": sim.maps.size(),
				"maps_active": on_map.size(), "fights": sim.fights.size()}
		players += sim.players.size()
		maps += on_map.size()
		fights += sim.fights.size()
	return {"version": version, "protocol": Protocol.VERSION,
			"uptime_s": (Time.get_ticks_msec() - _start_ms) / 1000,
			"connections": host.connections, "players": players, "maps_active": maps,
			"fights": fights, "worlds": worlds, "tick": tick_stats(),
			"memory_bytes": OS.get_static_memory_usage()}
