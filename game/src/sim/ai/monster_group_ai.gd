## Roleplay wandering of monster groups, Dofus-like: now and then the group
## walks a few cells away, staying near its spawn and away from map exits.
## Deterministic for a given RNG seed (tests and replays rely on it).
class_name MonsterGroupAI
extends RefCounted

const RADIUS := 4
const MAX_PATH := 7
const LEASH := 6 # max distance from home cell


static func think(group: MonsterGroup, map: MapInstance, now: int, rng: RandomNumberGenerator, wander_ms: Vector2i) -> void:
	if now < group.next_think or group.is_moving(now):
		return
	group.next_think = now + rng.randi_range(wander_ms.x, wander_ms.y)
	var origin := MapGeometry.to_iso(group.cell)
	for attempt in 10:
		var off := Vector2i(rng.randi_range(-RADIUS, RADIUS), rng.randi_range(-RADIUS, RADIUS))
		var target := MapGeometry.from_iso(origin + off)
		if target < 0 or target == group.cell or MapGeometry.is_edge(target) or not map.data.is_walkable(target):
			continue
		if MapGeometry.distance(target, group.home_cell) > LEASH:
			continue
		var p := map.pathfinder.find_path(group.cell, target)
		if p.size() < 2 or p.size() > MAX_PATH:
			continue
		map.move_actor(group, p, now, false)
		group.next_think += Movement.duration_ms(p, false)
		return
