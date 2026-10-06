## Security, second part (roadmap S.05b): the audit file gets the trades of two real clients
## (WebSockets on 127.0.0.1), and what an invisible fighter hides from the other side stays hidden
## in the snapshots (resume, spectator, joining), not only in the live events.
extends TestCase

const Resume := preload("res://tests/test_resume.gd")
const NetTests := preload("res://tests/test_net.gd")
const AUDIT := "user://test_security_audit/audit.jsonl"


func _init() -> void:
	GameData.roots = GameData.DEFAULT_ROOTS
	GameData.clear_cache()
	SpellBook.use_file("res://tests/fixtures/spells.json")


## An invisible state (250, flag `invisible`) on `f`, as effect 150 puts it.
static func _hide(fight: Fight, f: Fighter) -> void:
	FightEffects.add_state(fight, f, f, {"state": 250, "flags": ["invisible"]}, -1, 0)


static func _monster(fight: Fight) -> Fighter:
	return fight.fighters.values().filter(func(f: Fighter) -> bool: return f.team == 1)[0]


static func _cell_of(fighters: Array, id: int) -> int:
	for f: Dictionary in fighters:
		if int(f["id"]) == id:
			return int(f["cell"])
	return -99


func test_trades_reach_the_audit_file_over_websocket() -> void:
	DirAccess.remove_absolute(ProjectSettings.globalize_path(AUDIT))
	var rig := NetTests.Rig.new()
	rig.host.set_audit_log(AuditLog.new(AUDIT))
	var a := rig.client("tiny", "Alice")
	rig.run(2.0, func() -> bool: return a.has(Protocol.MAP_ENTER))
	var b := rig.client("tiny", "Bob")
	rig.run(2.0, func() -> bool: return b.has(Protocol.MAP_ENTER))
	var sim := rig.sim()
	sim.players[a.you].character.kamas = 300
	# a done trade (kamas only), then a cancelled one
	a.backend.send(ProtocolTrade.invite("Bob"))
	rig.run(0.5)
	b.backend.send(ProtocolTrade.accept("Alice"))
	rig.run(0.5)
	a.backend.send(ProtocolTrade.set_offer([], 120))
	rig.run(0.3)
	a.backend.send(ProtocolTrade.ready())
	rig.run(0.3)
	b.backend.send(ProtocolTrade.ready())
	check(rig.run(2.0, func() -> bool: return a.has(ProtocolTrade.END)), "the trade is done")
	a.take(ProtocolTrade.END)
	a.backend.send(ProtocolTrade.invite("Bob"))
	rig.run(0.5)
	b.backend.send(ProtocolTrade.accept("Alice"))
	rig.run(0.5)
	a.backend.send(ProtocolTrade.cancel())
	check(rig.run(2.0, func() -> bool: return a.has(ProtocolTrade.END)), "the second is cancelled")
	var entries := (rig.host.audit as AuditLog).read_all().filter(func(e: Dictionary) -> bool: return e["cmd"] == "trade")
	eq(entries.size(), 2, "both trades are in the file")
	eq([entries[0]["ok"], entries[0]["name"], entries[0]["with"]], [true, "Alice", "Bob"])
	eq(int(entries[0]["gave"]["Alice"]["kamas"]), 120, "what moved is recorded")
	eq([entries[1]["ok"], entries[1]["code"]], [false, "cancelled"])
	check(int(entries[0]["at"]) > 0 and str(entries[0]["world"]) == "tiny", "date and world")
	check(not str(entries).contains("password") and not str(entries).contains("token"), "no secret in the trail")
	rig.host.shutdown()


func test_a_resumed_fighter_does_not_get_the_cell_of_an_invisible_enemy() -> void:
	var rig := Resume.Rig.new()
	var a := rig.fighter()
	var token := a.backend.token
	var fight: Fight = rig.sim().fights.values()[0]
	var mob := _monster(fight)
	check(mob.cell >= 0, "the monster stands somewhere")
	_hide(fight, mob)
	rig.cut(a)
	var b := rig.client()
	rig.ask(b, ProtocolResume.resume(token), ProtocolResume.RESUME_OK)
	check(rig.run(2.0, func() -> bool: return b.has(Protocol.FIGHT_START)), "the snapshot comes")
	var start: Dictionary = b.take(Protocol.FIGHT_START)[0]
	eq(_cell_of(start["fighters"], mob.id), -1, "the invisible enemy has no cell in the resume snapshot")
	var hero := Resume._hero(rig.sim())
	check(_cell_of(start["fighters"], hero.id) >= 0, "the own team is intact")
	rig.shutdown()


func test_a_spectator_never_sees_an_invisible_fighter() -> void:
	var rig := Resume.Rig.new()
	var a := rig.fighter()
	var fight: Fight = rig.sim().fights.values()[0]
	var mob := _monster(fight)
	var hero := Resume._hero(rig.sim())
	_hide(fight, mob)
	_hide(fight, fight.fighters[hero.id]) # even the side of the fight does not matter: no seat
	var b := rig.client()
	rig.ask(b, Protocol.register("paul", "secret1"), Protocol.LOGIN_OK)
	rig.ask(b, Protocol.hello("duo", "Paul", Resume.LOOK), Protocol.MAP_ENTER)
	b.backend.send(ProtocolWatch.spectate(fight.id))
	check(rig.run(2.0, func() -> bool: return b.has(ProtocolWatch.WATCH)), "Paul watches")
	var w: Dictionary = b.take(ProtocolWatch.WATCH)[0]
	eq([_cell_of(w["fighters"], mob.id), _cell_of(w["fighters"], hero.id)], [-1, -1], "no cell for the invisible ones")
	check(a.backend.schema_errors.size() + b.backend.schema_errors.size() == 0, "valid messages")
	rig.shutdown()
