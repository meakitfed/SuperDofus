## Local / network parity of the matrix (H.06): the same fight played by a LocalBackend (standalone) and
## by a real ServerHost + NetBackend on 127.0.0.1 (WebSocket, JSON), reduced to what the rules decide.
## The world holds one group (a monster of the matrix, as its data gives it), the player is a character
## of a class that casts one of its spells every turn and ends the turn; the monsters play with the AI.
class_name ParityRig
extends RefCounted

const STEP := 0.05
const WORLD := "parity"
const LOOK := "{1|120,2195||56}"
const SECONDS := 25.0
const ATTACK_MS := 1000 # when the player attacks the group (the fight seed reads the world clock at that moment)
## The attack of the network side leaves this much earlier than the local one, to reach the sim at the same world time
## (same fight seed, same rolls). Measured: 0 (a command sent before a poll is read by the next host poll on both sides);
## a different value makes the rolls differ and the test fail.
const NET_LEAD_MS := 0
## What the digest keeps of an event: the fields that are game rules (not the clock, not the animation).
const KEPT := [Protocol.FIGHT_START, Protocol.FIGHT_BEGIN, Protocol.FIGHTER_MOVE, Protocol.SPELL_CAST, Protocol.FIGHT_END, Protocol.ERROR]


## A server and one NetBackend pumped together on a virtual clock, behind the GameBackend API.
class NetRig extends GameBackend:
	var host := ServerHost.new()
	var net := NetBackend.new()
	var virtual_ms := 0

	func _init(source: WorldSource) -> void:
		host.gm_accounts = PackedStringArray(["ip-127.0.0.1"])
		host.server.sources[ParityRig.WORLD] = source
		host.rate_burst = 1.0e9 # the rate limit is S.05's business; a fight fast-forwarded must not trip it
		host.rate_per_sec = 1.0e9
		host.listen(0, "127.0.0.1")
		net.validate_events = true
		net.ticks = func() -> int: return virtual_ms
		net.event.connect(func(ev: Dictionary) -> void: event.emit(ev))
		net.connect_to("127.0.0.1:%d" % host.local_port())

	func prepare_scenario(header: Dictionary) -> void:
		host.server.seed = int(header.get("seed", 1))
		if header.has("character"):
			var ch: Dictionary = (header["character"] as Dictionary).duplicate(true)
			ch["name"] = str(header.get("player", "Tester"))
			host.server.persistence.save_character(str(header["world"]), ch["name"], ch)

	func send(cmd: Dictionary) -> void:
		net.send(cmd)

	func poll(delta: float) -> void:
		virtual_ms += int(delta * 1000.0)
		host.poll(delta)
		net.poll(delta)

	func time_ms() -> int:
		return virtual_ms

	func close() -> void:
		net.close()
		for i in 4:
			host.poll(ParityRig.STEP)
		host.shutdown()


## A one-map world with one group of `members` (grade dictionaries of the data).
static func world(members: Array) -> WorldSource:
	return WorldSource.from_dicts(
		{"id": WORLD, "name": "Parity", "start_map": 1, "start_cell": 300, "wander_ms": [600000, 600000]},
		[{"id": 1, "coords": [0, 0], "groups": [{"name": "Groupe", "members": members}]}])


static func scenario(breed: int, level: int, variants := []) -> Scenario:
	var s := Scenario.new()
	s.header = {"scenario": "parity", "world": WORLD, "seed": 1, "seconds": SECONDS, "step_ms": 50, "player": "Cli", "look": LOOK,
			"character": {"breed": breed, "level": level, "variants": variants}}
	return s


## The fight driver: attack the group, ready, then each own turn cast `spell` at the first enemy's cell
## (where it stood or last moved to), move toward it, end the turn.
static func driver(spell: int, attack_at: int) -> Callable:
	var st := {"you": -1, "target": -1, "cell": {}, "group": -1, "turn_seen": -1, "step": 0, "attacked": false}
	return func(backend: GameBackend, events: Array, sent: Array) -> void:
		if not st["attacked"] and int(st["group"]) != -1 and backend.time_ms() >= attack_at:
			st["attacked"] = true
			sent.append(Protocol.fight_attack(int(st["group"])))
		elif st["attacked"] and not st.has("ready"):
			st["ready"] = true
			sent.append(Protocol.fight_ready())
		for i in range(int(st["step"]), events.size()):
			var ev: Dictionary = events[i]["ev"]
			match str(ev["t"]):
				Protocol.WELCOME:
					st["you"] = int(ev["you"])
				Protocol.MAP_ENTER:
					for a: Dictionary in ev.get("actors", []):
						if str(a.get("kind", "")) == "monster_group" and st["group"] == -1:
							st["group"] = int(a["id"])
				Protocol.FIGHT_START:
					for f: Dictionary in ev.get("fighters", []):
						st["cell"][int(f["id"])] = int(f["cell"])
						if int(f["id"]) != st["you"] and int(f.get("team", 1)) != 0 and st["target"] == -1:
							st["target"] = int(f["id"])
				Protocol.FIGHTER_MOVE:
					var path: Array = ev.get("path", [])
					if not path.is_empty():
						st["cell"][int(ev["id"])] = int(path[-1])
				Protocol.FIGHT_TURN:
					if int(ev["id"]) == int(st["you"]) and int(st["target"]) != -1:
						var at := int(st["cell"].get(st["target"], -1))
						var mine := int(st["cell"].get(st["you"], -1))
						if MapGeometry.distance(mine, at) > 1: # walk next to the enemy first (one turn), cast from the next
							var delta := MapGeometry.to_iso(at) - MapGeometry.to_iso(mine)
							var left := 3 # MP of a level-100 character
							if absi(delta.x) + absi(delta.y) <= left: # do not walk onto the enemy: stop one short
								if absi(delta.x) >= absi(delta.y):
									delta.x -= signi(delta.x)
								else:
									delta.y -= signi(delta.y)
							var dx := clampi(delta.x, -left, left)
							left -= absi(dx)
							var dy := clampi(delta.y, -left, left)
							var best := MapGeometry.from_iso(MapGeometry.to_iso(mine) + Vector2i(dx, dy))
							sent.append(Protocol.fight_move(best))
						else:
							sent.append(Protocol.fight_cast(spell, at))
						sent.append(Protocol.fight_end_turn())
		st["step"] = events.size()


## Plays `s` on a backend, returns the digest: the rule-bearing events as canonical strings.
static func digest(events: Array) -> Array:
	var out := []
	for e: Dictionary in events:
		var ev: Dictionary = e["ev"]
		var t := str(ev["t"])
		if t in KEPT:
			out.append(JSON.stringify(Scenario._intify(Scenario._pick(ev, Scenario.RECORDED.get(t, ["t"]))), "", true))
		elif t == Protocol.FIGHT_TURN:
			out.append(JSON.stringify({"t": t, "id": int(ev["id"]), "effects": Scenario._intify(ev.get("effects", []))}, "", true))
	return out


static func play_local(source: WorldSource, s: Scenario, spell: int) -> Array:
	var b := LocalBackend.new()
	b.sources[WORLD] = source
	return s.run(b, driver(spell, ATTACK_MS))


## Returns {events, schema_errors}.
static func play_net(source: WorldSource, s: Scenario, spell: int) -> Dictionary:
	var rig := NetRig.new(source)
	var events := s.run(rig, driver(spell, ATTACK_MS - NET_LEAD_MS))
	return {"events": events, "schema_errors": rig.net.schema_errors}
