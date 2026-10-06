## A turn-based fight on a map's cells (Dofus rules, simplified). Pure logic;
## events go out through `emit` (WorldSim fans them out to the fight's players).
##   placement: each team on its placement cells, players swap places and get
##              ready (or PLACEMENT_MS runs out);
##   fight:     turns by initiative, alternating teams; AP/MP reset each turn
##              (+ buffs); 4-direction moves, tackle; spells (FightEffects) with
##              crits, cooldowns and cast limits; buffs count down on their
##              caster's turns, poisons tick on their target's turns;
##   end:       `result` = "win" / "lose" / "abandon" (players' side); WorldSim
##              hands out the rewards (FightRewards).
class_name Fight
extends RefCounted

## constants 162 = "30s" (one turn); constants 163 = "5s" is not identified (APPROX(P1.15): no extra time kept)
const TURN_MS := 30000
const PLACEMENT_MS := 30000
const AI_THINK_MS := 900
## a disconnected player's fighter passes its turns this long, then the AI plays for it
## (S.02b). APPROX(S.02b): 60 s, not in the sources
const ABSENT_GRACE_MS := 60000
const AI_MAX_ACTIONS := 12

var id := 0
var map: MapData
var fighters := {} # id -> Fighter
var order: Array = [] # fighter ids, turn order
var turn := -1 # index in `order`
var turn_start := 0
var turn_end := 0
var phase := "placement" # "placement" | "fight"
## team -> placement cells
var placement := {0: [], 1: []}
var placement_end := 0
var started_at := 0
## "" while running, then "win" / "lose" / "abandon" (from the players' side);
## summons do not keep their team in the fight
var result := ""
## luaformulas 99 rewardRate: 1 + the monster group's stars (SubareaBonus) / 100
var reward_rate := 1.0
var rng := RandomNumberGenerator.new()
## challenges (P1.15, FightChallenges): [{id, name_id, desc_id, icon, state, target, bonus}] and their
## bookkeeping (empty without challenges)
var challenges: Array = []
var chal := {}
## fight options (P1.15): locked = nobody else may join, party_only = only the leader's party,
## secret = no spectators, help = a call for help is posted. Changed by the leader (fight_option).
var options := {"locked": false, "party_only": false, "secret": false, "help": false}
## the players watching (PlayerActor ids, P3.04): they get every event, as a team that sees no
## invisible fighter, and cannot act
var spectators: Array = []
var _seed := 0

var _emit: Callable
var _ai_next := 0
var _ai_actions := 0
var _casts := {} # spell id -> casts this turn
var _casts_on := {} # "spell:target" -> casts this turn
var _buff_id := 0
var _dead := {} # fighter ids whose death has been handled
var _summon_id := -100 # summons: -101, -102... (-1 = Fighter.summoner of a non-summon)
## traps and glyphs on the ground (FightMarks, P1.13a)
var marks: Array = []
var _mark_id := 0
## triggers (FightTriggers, P1.13b): hits waiting for their triggers, chain depths,
## the aura mark whose buffs are being given
var hits: Array = []
var trigger_depth := 0
var chain_depth := 0
var aura_tag := 0
## what happened to each fighter during the cast being resolved (P1.13k, TargetMask T / W / U / K):
## fighter id -> {"moved": true, "telefrag": true (P1.13n), "thrower": id, "summoned": true}. The client keeps the same per
## fighter list in its preview state (FightState.bmjp: movement events gzw, summon events haa);
## it starts empty with each outermost FightEffects.apply_spell (a sub-spell shares its caster's).
var cast_log := {}
var cast_depth := 0
## damage the caster dealt in the cast being resolved (P1.17b 11, 2973 heals a % of it)
var cast_dealt := 0
## the hit a trigger is firing for (P1.13e, 786 heals the attacker): who struck (-1 = no one), how much
var trigger_from := -1
var trigger_amount := 0
## where the damage being dealt comes from (P1.13i, FightTriggers DS / DT / DG): "" a spell,
## "trap", "glyph", "poison"
var hit_source := ""
## the cast being resolved (P1.13m, FightTriggers): a critical hit (DCCBA / DCCBE...), a weapon's hit
## (DCAC / CDCAC / KWW); the dispellable of the effect making buffs (FightEffects.apply, Buff)
var cast_crit := false
var cast_weapon := false
var dispellable := 1
## portals (P1.13f): the fight's round (1 = everyone's first turn), the portal a projected spell
## comes out of while it lands (-1 = none)
var fight_round := 1
var cast_from := -1
var _turned := false


func _init(p_id: int, p_map: MapData, seed: int, emit: Callable) -> void:
	id = p_id
	map = p_map
	rng.seed = seed
	_seed = seed
	_emit = emit


## Draws the challenges (P1.15). Own generator: the fight's dice (crits, drops) stay the same.
func draw_challenges() -> void:
	var crng := RandomNumberGenerator.new()
	crng.seed = hash([_seed, "challenges"])
	challenges = FightChallenges.pick(self, crng)


## For FightChallenges: sends an event to the fight's players.
func emit_event(ev: Dictionary) -> void:
	_emit.call(ev)


func add_fighter(f: Fighter) -> void:
	fighters[f.id] = f


## Turn order by initiative, teams alternating (Dofus): the team with the best
## initiative starts; ties go to the players.
func prepare() -> void:
	var teams: Array = [[], []]
	for f: Fighter in fighters.values():
		if f.plays and not f.left:
			teams[f.team].append(f)
	for t in 2:
		teams[t].sort_custom(func(a: Fighter, b: Fighter) -> bool:
			return a.initiative() > b.initiative() or (a.initiative() == b.initiative() and a.id < b.id))
	var first := 0
	if not teams[1].is_empty() and (teams[0].is_empty() or teams[1][0].initiative() > teams[0][0].initiative()):
		first = 1
	order = []
	for i in maxi(teams[0].size(), teams[1].size()):
		for k in 2:
			var t: int = (first + k) % 2
			if i < teams[t].size():
				order.append(teams[t][i].id)
	turn = -1


## Placement phase: monsters are ready, players place themselves.
func start_placement(now: int) -> void:
	phase = "placement"
	started_at = now
	placement_end = now + PLACEMENT_MS
	for f: Fighter in fighters.values():
		f.ready = f.player_id < 0


## Ends the placement and starts the first turn.
func begin(now: int) -> void:
	if phase == "fight":
		return
	phase = "fight"
	prepare()
	if not challenges.is_empty():
		FightChallenges.begin(self)
	for f: Fighter in fighters.values():
		f.start_cell = f.cell
		f.prev_cell = -1
		f.turn_begin_cell = f.cell
		var foe := _nearest_enemy(f)
		if foe != null and foe.cell != f.cell:
			f.dir = MapGeometry.facing(f.cell, foe.cell)
		for sid: int in f.spells:
			var ic := int(f.spell(sid).get("initial_cooldown", 0))
			if ic > 0:
				f.cooldowns[sid] = ic
	_emit.call(Protocol.fight_begin(order))
	_next_turn(now)


func current() -> Fighter:
	return fighters.get(order[turn]) if turn >= 0 and phase == "fight" else null


func fighters_dicts() -> Array:
	return order.map(func(fid: int) -> Dictionary: return (fighters[fid] as Fighter).to_dict())


func placement_dict() -> Dictionary:
	return {"0": placement[0], "1": placement[1]}


## cellId -> true for every living fighter except `except_id`.
func occupied(except_id := -1) -> Dictionary:
	var out := {}
	for f: Fighter in fighters.values():
		if f.alive and f.id != except_id:
			out[f.cell] = true
	return out


## The fighter standing on `cell` (a carried one is on its carrier, not on the board).
func fighter_at(cell: int) -> Fighter:
	for f: Fighter in fighters.values():
		if f.alive and f.cell == cell and f.carried_by == -1:
			return f
	return null


## Summon fighter ids: negative, so they never meet player or monster ids.
func next_summon_id() -> int:
	_summon_id -= 1
	return _summon_id


## A summon joins the fight; if it plays, right after its summoner and the
## summoner's older summons (Summons).
func add_summon(f: Fighter, summoner: Fighter) -> void:
	fighters[f.id] = f
	f.start_cell = f.cell
	f.prev_cell = -1
	f.turn_begin_cell = f.cell
	if not f.plays:
		return
	var at := order.find(summoner.id) + 1
	while at < order.size() and _summoned_by(fighters[order[at]], summoner.id):
		at += 1
	order.insert(at, f.id)
	if at <= turn:
		turn += 1


## `f` is a summon of `summoner_id`, or a summon of one of its summons.
func _summoned_by(f: Fighter, summoner_id: int) -> bool:
	while f != null and f.summoner != -1:
		if f.summoner == summoner_id:
			return true
		f = fighters.get(f.summoner)
	return false


func next_mark_id() -> int:
	_mark_id += 1
	return _mark_id


func next_buff_id() -> int:
	_buff_id += 1
	return _buff_id


func tick(now: int) -> void:
	if result != "":
		return
	if phase == "placement":
		if now >= placement_end:
			begin(now)
		return
	var f := current()
	if f == null:
		return
	if f.absent_since >= 0 and not f.ai:
		if now - f.absent_since < ABSENT_GRACE_MS:
			end_turn(now) # the absent player passes
			return
		f.ai = true
		f.ai_takeover = true
		_ai_next = now
	if f.ai:
		if now < _ai_next:
			return
		_ai_actions += 1
		var wait: int = FightAI.act(self, f, now) if _ai_actions <= AI_MAX_ACTIONS else -1
		if result != "" or current() != f:
			return
		if wait < 0:
			end_turn(now)
		else:
			_ai_next = now + wait
	elif now >= turn_end:
		end_turn(now)


# ── actions (players via handle(), AI directly) ────────────────────────────────

## Returns "" on success, otherwise why the command was refused.
func handle(fighter_id: int, cmd: Dictionary, now: int) -> String:
	var f: Fighter = fighters.get(fighter_id)
	if f == null or result != "":
		return Protocol.E_NOT_IN_FIGHT
	var type := str(cmd.get("t", ""))
	match type:
		Protocol.FIGHT_LEAVE:
			leave(f, now)
			return ""
		Protocol.FIGHT_OPTION:
			return set_option(f, str(cmd.get("option", "")), bool(cmd.get("value", false)))
		Protocol.FIGHT_PLACE:
			return place(f, int(cmd.get("cell", -1)))
		Protocol.FIGHT_READY:
			return set_ready(f, bool(cmd.get("ready", true)), now)
	if phase != "fight":
		return Protocol.E_FIGHT_NOT_STARTED
	match type:
		Protocol.FIGHT_MOVE:
			return move(f, int(cmd.get("cell", -1)), now)
		Protocol.FIGHT_CAST:
			return cast(f, int(cmd.get("spell", 0)), int(cmd.get("cell", -1)), now)
		Protocol.FIGHT_END_TURN:
			if current() != f:
				return Protocol.E_NOT_YOUR_TURN
			end_turn(now)
			return ""
	return Protocol.E_UNKNOWN_COMMAND


## The player of `f` lost its connection (S.02b): it passes its turns, then the AI takes over
## (ABSENT_GRACE_MS); in the placement it is counted ready.
func set_absent(f: Fighter, now: int) -> void:
	if f.absent_since < 0:
		f.absent_since = now
		if phase == "placement":
			f.ready = true
			if result == "" and fighters.values().all(func(x: Fighter) -> bool: return x.ready):
				begin(now)


## The player is back: it plays its own turns again.
func set_present(f: Fighter) -> void:
	f.absent_since = -1
	if f.ai_takeover:
		f.ai_takeover = false
		f.ai = false


## `f` flees (placement) or abandons (fight). With other players still in it, only `f` leaves the
## fight (it counts as dead for the challenges); alone, the fight is lost for good ("abandon": no
## reward, FightRewards). Dofus 3 has no penalty here beyond the missed rewards.
func leave(f: Fighter, now: int) -> void:
	var others := fighters.values().filter(func(g: Fighter) -> bool: return g.team == f.team and g.alive and g.id != f.id and g.player_id >= 0)
	if f.team != 0 or others.is_empty() or f.player_id < 0:
		_finish("abandon")
		return
	f.alive = false
	f.hp = 0
	f.left = true
	f.ready = true # a fighter who left no longer holds the placement back
	var was_current := phase == "fight" and current() == f
	if phase == "placement":
		prepare()
	_emit.call(ProtocolWatch.left(f.id, order))
	if was_current:
		end_turn(now)
	_check_end()
	if phase == "placement" and result == "" and fighters.values().all(func(x: Fighter) -> bool: return x.ready):
		begin(now)


## The fight leader: the first player who is still in (lowest id).
func leader() -> Fighter:
	var best: Fighter = null
	for f: Fighter in fighters.values():
		if f.player_id >= 0 and f.alive and f.team == 0 and (best == null or f.id < best.id):
			best = f
	return best


## fight_option: the leader sets an option (`options`).
func set_option(f: Fighter, option: String, value: bool) -> String:
	if not options.has(option):
		return Protocol.E_UNKNOWN_OPTION
	if f != leader():
		return Protocol.E_NOT_LEADER
	if options[option] != value:
		options[option] = value
		_emit.call(Protocol.fight_options(options))
	return ""


## Whether somebody may join (or watch) the fight now: "" or the error code (options). `in_party` =
## belongs to the leader's party. Used by WorldFightWatch (P3.04).
func join_error(in_party: bool, spectator := false) -> String:
	if spectator:
		return Protocol.E_FIGHT_SECRET if options["secret"] else ""
	if options["locked"]:
		return Protocol.E_FIGHT_LOCKED
	if options["party_only"] and not in_party:
		return Protocol.E_FIGHT_PARTY_ONLY
	return ""


## Fighters of `team` in the fight (summons and the ones who left do not count).
func team_size(team: int) -> int:
	return fighters.values().filter(func(f: Fighter) -> bool: return f.team == team and f.summoner == -1 and not f.left).size()


## A player joins the fight during the placement (P3.04, Dofus: up to TEAM_MAX per team). `f` is the new
## fighter (id, stats and looks set), it takes the free placement cell closest to `near`. Only the
## players' team can be joined (monsters are the group's). Returns "" or the error code; the
## options (locked, party_only) are the caller's, see join_error. Emits nothing: the host tells.
func join(f: Fighter, team: int, near: int) -> String:
	if result != "":
		return ProtocolWatch.E_NO_FIGHT
	if phase != "placement":
		return ProtocolWatch.E_FIGHT_STARTED
	if team != 0:
		return ProtocolWatch.E_BAD_TEAM
	if team_size(team) >= ProtocolWatch.TEAM_MAX:
		return ProtocolWatch.E_FIGHT_FULL
	var best := -1
	for c: int in placement[team]:
		if fighter_at(c) == null and (best == -1 or FightRules.distance(c, near) < FightRules.distance(best, near)):
			best = c
	if best == -1:
		return ProtocolWatch.E_FIGHT_FULL
	f.team = team
	f.cell = best
	f.ready = false
	var foe := _nearest_enemy(f)
	if foe != null:
		f.dir = MapGeometry.facing(f.cell, foe.cell)
	add_fighter(f)
	prepare()
	return ""


## The state of the fight for somebody who starts watching it (ProtocolWatch.watch).
func watch_dict() -> Dictionary:
	var cur := current()
	return ProtocolWatch.watch(id, fighters_dicts(), order, phase, placement_dict(),
			placement_end if phase == "placement" else turn_end, cur.id if cur != null else -1, options, challenges)


## `who` (a player id) watches the fight: "" or why not (secret).
func spectate(who: int) -> String:
	if result != "":
		return ProtocolWatch.E_NO_FIGHT
	var err := join_error(false, true)
	if err == "" and not spectators.has(who):
		spectators.append(who)
	return err


## Time left in the current turn / placement, in ms (the client's chrono).
func time_left(now: int) -> int:
	return maxi(0, (placement_end if phase == "placement" else turn_end) - now)


## Notes in `cast_log` that `f` was moved (by `thrower` if it was thrown), or summoned.
func log_cast(f: Fighter, what: String, thrower := -1) -> void:
	var entry: Dictionary = cast_log.get(f.id, {})
	entry[what] = true
	if thrower != -1:
		entry["thrower"] = thrower
	cast_log[f.id] = entry


func place(f: Fighter, cell: int) -> String:
	if phase != "placement":
		return Protocol.E_PLACEMENT_OVER
	if not (placement[f.team] as Array).has(cell):
		return Protocol.E_BAD_CELL
	var other := fighter_at(cell)
	if other == f:
		return ""
	if other != null and other.team != f.team:
		return Protocol.E_CELL_NOT_FREE
	if other != null:
		other.cell = f.cell
		_emit.call(Protocol.fighter_placed(other.id, other.cell))
	f.cell = cell
	_emit.call(Protocol.fighter_placed(f.id, cell))
	return ""


func set_ready(f: Fighter, ready: bool, now: int) -> String:
	if phase != "placement":
		return Protocol.E_PLACEMENT_OVER
	f.ready = ready
	_emit.call(Protocol.fighter_ready(f.id, ready))
	if fighters.values().all(func(x: Fighter) -> bool: return x.ready):
		begin(now)
	return ""


## Moves along the shortest path. Leaving a cell next to enemies costs MP and AP
## (tackle): the share kept is (escape + 2) / (2 x (tackle of the adjacent enemies + 2)).
func move(f: Fighter, target: int, now: int) -> String:
	if current() != f:
		return Protocol.E_NOT_YOUR_TURN
	var path := FightRules.path_to(map, occupied(f.id), f.cell, target, f.mp)
	if path.size() < 2:
		return Protocol.E_UNREACHABLE
	var walked: Array = [path[0]]
	var lost := {"ap": 0, "mp": 0}
	for i in range(1, path.size()):
		var tck := _tackle_at(f, path[i - 1])
		if tck >= 0 and not f.has_flag("cant_be_tackled"):
			# APPROX(P1.14): community tackle formula (kept share = (escape + 2) / (2 x (tackle + 2)))
			var keep := clampf((f.escape() + 2.0) / (2.0 * (tck + 2.0)), 0.0, 1.0)
			if keep < 1.0:
				var mp_lost := f.mp - roundi(f.mp * keep)
				var ap_lost := f.ap - roundi(f.ap * keep)
				f.mp -= mp_lost
				f.ap -= ap_lost
				lost["mp"] += mp_lost
				lost["ap"] += ap_lost
		if f.mp <= 0:
			break
		walked.append(path[i])
		f.mp -= 1
		if not FightMarks.trap_at(self, f, path[i]).is_empty(): # a trap stops the walk
			break
		if not FightMarks.crossing(self, f, path[i], true).is_empty(): # so does a portal it crosses (P1.13f)
			break
	var effects: Array = []
	if walked.size() >= 2:
		if f.carried_by != -1: # walks off its carrier
			effects = Carry.release(self, f)
		f.cell = walked[-1]
		f.dir = MapGeometry.facing(walked[-2], walked[-1])
		Carry.follow(self, f)
		FightChallenges.on_walk(self, f, walked.size() - 1)
	var triggered := FightMarks.entered(self, f)
	for i in walked.size() - 1: # CCMPARR: once per MP used walking (P1.13e, FightTriggers)
		triggered.append_array(FightTriggers.fire(self, f, ["CCMPARR"]))
	if walked.size() >= 2:
		triggered.append_array(FightMarks.walked_in(self, f))
	triggered.append_array(handle_deaths())
	triggered.append_array(FightMarks.auras(self))
	FightChallenges.observe(self)
	_emit.call(Protocol.fighter_move(f.id, walked, now, f.mp, lost, effects, triggered))
	_check_end()
	if result == "" and (not f.alive or f.pass_turn):
		f.pass_turn = false
		end_turn(now)
	return ""


## Total tackle of the enemies next to `cell`, -1 if none.
func _tackle_at(f: Fighter, cell: int) -> int:
	var total := -1
	for n in FightRules.neighbors4(cell):
		var e := fighter_at(n)
		if e != null and e.team != f.team and e.tackles and not e.has_flag("cant_tackle"):
			total = maxi(total, 0) + e.tackle()
	return total


## "" if `f` may cast `spell_id` on `target` now, otherwise why not.
func cast_check(f: Fighter, spell_id: int, target: int) -> String:
	var err := spell_block(f, spell_id)
	if err != "":
		return err
	if target_limit_reached(f, spell_id, fighter_at(target)):
		return Protocol.E_CAST_LIMIT_TARGET
	var spell := f.spell(spell_id)
	err = Summons.cast_error(self, f, spell)
	if err != "":
		return err
	spell = FightRules.for_caster(spell, f.state_ids())
	err = FightRules.cast_error(map, occupied(f.id), spell, f.cell, target, f.ap, f.stat("range"))
	# APPROX(P1.13f): a spell needing a fighter may target a portal it would be projected through
	if err == Protocol.E_NEEDS_TARGET and not FightMarks.projection(self, f, spell, target).is_empty():
		return ""
	return err


## What prevents `f` from casting `spell_id` at all this turn ("" = nothing).
func spell_block(f: Fighter, spell_id: int) -> String:
	var spell := f.spell(spell_id)
	if not f.spells.has(spell_id) or spell.is_empty():
		return Protocol.E_UNKNOWN_SPELL
	if (spell.get("effects", []) as Array).is_empty():
		return Protocol.E_SPELL_NOT_SIMULATED # summons, glyphs... (spell.partial, roadmap P1.11-P1.14)
	if f.cast_forbidden(spell):
		return Protocol.E_SPELL_FORBIDDEN
	if int(f.cooldowns.get(spell_id, 0)) > 0:
		return Protocol.E_SPELL_COOLDOWN
	if int(_casts.get(spell_id, 0)) >= int(spell.get("per_turn", 99)):
		return Protocol.E_CAST_LIMIT
	if not FightRules.criterion_ok(str(spell.get("criterion", "")), f.state_ids()):
		return Protocol.E_SPELL_CONDITION
	return ""


func target_limit_reached(f: Fighter, spell_id: int, t: Fighter) -> bool:
	return t != null and int(_casts_on.get("%d:%d" % [spell_id, t.id], 0)) >= int(f.spell(spell_id).get("per_target", 99))


func cast(f: Fighter, spell_id: int, target: int, now: int) -> String:
	if current() != f:
		return Protocol.E_NOT_YOUR_TURN
	var err := cast_check(f, spell_id, target)
	if err != "":
		return err
	var spell := f.spell(spell_id)
	f.ap -= int(spell["ap"])
	f.ap_spent += int(spell["ap"])
	FightChallenges.on_cast(self, f, spell_id)
	_casts[spell_id] = int(_casts.get(spell_id, 0)) + 1
	var t := fighter_at(target)
	if t != null:
		var key := "%d:%d" % [spell_id, t.id]
		_casts_on[key] = int(_casts_on.get(key, 0)) + 1
	if int(spell.get("cooldown", 0)) > 0:
		f.cooldowns[spell_id] = int(spell["cooldown"])
	if target != f.cell:
		f.dir = MapGeometry.facing(f.cell, target)
	var crit_pct := int(spell.get("crit", 0))
	var crit := crit_pct > 0 and rng.randi_range(1, 100) <= crit_pct + f.stat("crit")
	# projected through its portals (P1.13f): lands on the exit portal, from the one before
	var proj := FightMarks.projection(self, f, spell, target)
	var effects: Array = []
	var center := target
	if not proj.is_empty():
		effects.append({"kind": "projected", "target": f.id, "path": proj["path"], "bonus": proj["bonus"]})
		f.projecting = int(proj["bonus"])
		cast_from = int(proj["from"])
		center = int(proj["exit"])
	effects.append_array(FightEffects.apply_spell(self, f, spell, center, crit))
	f.projecting = -1
	cast_from = -1
	if crit: # CC (P1.13i, gzp.bnaa): its caster made a critical hit
		FightTriggers.event(self, f, ["CC"])
	effects.append_array(FightTriggers.flush(self))
	effects.append_array(handle_deaths())
	effects.append_array(FightMarks.auras(self))
	FightChallenges.observe(self)
	_emit.call(Protocol.spell_cast(f.id, spell_id, target, f.dir, f.ap, effects, crit))
	_check_end()
	if result == "" and not f.alive:
		end_turn(now)
	return ""


## End-of-turn triggers (FightTriggers "TE") and glyphs (FightMarks) hit the fighter
## whose turn ends; their effects go out with the next fight_turn.
func end_turn(now: int) -> void:
	if result == "":
		FightChallenges.on_turn_end(self, current())
		var pre := FightTriggers.fire(self, current(), ["TE"])
		pre.append_array(FightMarks.glyphs(self, current(), "glyph_end"))
		pre.append_array(handle_deaths())
		_next_turn(now, pre)


func _next_turn(now: int, pre: Array = []) -> void:
	for guard in order.size() + 1:
		for i in order.size():
			turn = (turn + 1) % order.size()
			if turn == 0 and _turned:
				fight_round += 1
			_turned = true
			var cand := fighters[order[turn]] as Fighter
			if cand.alive and cand.pass_turn: # 1031 on someone else: its turn is skipped
				cand.pass_turn = false
				continue
			if cand.alive:
				break
		var f := current()
		f.turn_begin_cell = f.cell
		FightChallenges.on_turn_begin(self, f)
		var effects: Array = pre
		pre = []
		effects.append_array(FightMarks.countdown(self, f))
		# the buffs this fighter cast count down
		for g: Fighter in fighters.values():
			for b: Buff in g.buffs.duplicate():
				if b.caster == f.id and b.turns > 0 and g.buffs.has(b):
					b.turns -= 1
					if b.turns == 0:
						effects.append_array(FightEffects.expire(self, g, b))
		effects.append_array(FightTriggers.flush(self)) # EOFF of the states that ran out
		for sid: int in f.cooldowns.keys():
			f.cooldowns[sid] = int(f.cooldowns[sid]) - 1
			if int(f.cooldowns[sid]) <= 0:
				f.cooldowns.erase(sid)
		# poisons tick on their target
		for b: Buff in f.buffs.duplicate():
			if b.kind == "poison" and f.alive:
				effects.append_array(FightEffects.poison(self, f, b))
				effects.append_array(FightTriggers.flush(self))
		effects.append_array(FightTriggers.fire(self, f, ["TB"]))
		effects.append_array(FightMarks.glyphs(self, f, "glyph_start"))
		effects.append_array(FightMarks.glyphs(self, f, "wall"))
		effects.append_array(handle_deaths())
		effects.append_array(FightMarks.auras(self))
		FightChallenges.observe(self)
		f.start_turn()
		_casts.clear()
		_casts_on.clear()
		_ai_next = now + AI_THINK_MS
		_ai_actions = 0
		turn_start = now
		turn_end = now + TURN_MS
		_emit.call(Protocol.fight_turn(f.id, f.ap, f.mp, turn_end, effects))
		_check_end()
		if result != "" or f.alive:
			return


## Fighters that just died: their death triggers fire (FightTriggers "X"), their
## summons die with them, their buffs are dispelled (Dofus), a carried fighter is
## dropped (Carry).
func handle_deaths() -> Array:
	var out: Array = []
	var again := true
	while again:
		again = false
		for f: Fighter in fighters.values():
			if f.alive or _dead.has(f.id):
				continue
			_dead[f.id] = true
			var fired := FightTriggers.fire(self, f, ["X"])
			fired.append_array(FightTriggers.died(self, f)) # K on its killer, EK:<mask> (P1.13i)
			if not fired.is_empty():
				out.append_array(fired)
				again = true
			out.append_array(Carry.release(self, f))
			out.append_array(FightMarks.remove_of(self, f.id))
			for g: Fighter in fighters.values():
				if g.alive and g.summoner == f.id:
					out.append(FightEffects.kill(g))
					again = true
				for b: Buff in g.buffs.duplicate():
					if b.caster == f.id or g == f:
						out.append_array(FightEffects.remove_buff(g, b))
	return out


func _nearest_enemy(f: Fighter) -> Fighter:
	var best: Fighter = null
	for g: Fighter in fighters.values():
		if g.alive and g.team != f.team and (best == null or FightRules.distance(f.cell, g.cell) < FightRules.distance(f.cell, best.cell)):
			best = g
	return best


func _check_end() -> void:
	var alive := [0, 0]
	for f: Fighter in fighters.values():
		if f.alive and f.summoner == -1:
			alive[f.team] += 1
	if alive[1] == 0:
		_finish("win")
	elif alive[0] == 0:
		_finish("lose")


func _finish(r: String) -> void:
	if result == "":
		result = r
		FightChallenges.finish(self)
