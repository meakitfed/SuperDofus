## Client side of a fight: fighters, team discs, cell overlays (placement cells,
## reachable cells, spell range/area), input, and the visual sequences (moves,
## spells, start-of-turn effects). It only reads events and sends Protocol
## commands; rules used for previews come from shared/FightRules, the same code
## the sim validates with.
class_name FightView
extends Node2D

## a visual sequence (spell, move) is over: the session resumes event processing
signal sequence_done

const TEAM_COLORS := [Color(0.25, 0.55, 1.0), Color(1.0, 0.3, 0.25)]
## placement cells: your team red, the other blue (Dofus)
const PLACEMENT_COLORS := [Color(0.95, 0.2, 0.15, 0.45), Color(0.2, 0.45, 1.0, 0.45)]
const COL_REACH := Color(0.3, 0.85, 0.35, 0.3)
const COL_PATH := Color(0.45, 1.0, 0.5, 0.6)
const COL_RANGE := Color(0.3, 0.5, 1.0, 0.3)
const COL_AREA := Color(1.0, 0.55, 0.2, 0.65)
const COL_NO_TARGET := Color(0.6, 0.6, 0.6, 0.25)
const COL_PORTAL := Color(0.25, 0.65, 1.0, 0.6)
const COL_PORTAL_OFF := Color(0.45, 0.5, 0.6, 0.35)
const HEAD := Vector2(0, -45) # where FX hit a fighter
const ELEMENT_COLORS := {"neutral": Color(0.95, 0.35, 0.3), "earth": Color(0.85, 0.55, 0.25),
		"fire": Color(1.0, 0.3, 0.2), "water": Color(0.35, 0.65, 1.0), "air": Color(0.45, 0.9, 0.45),
		"push": Color(0.95, 0.35, 0.3)}

var backend: GameBackend
var map: MapData
var map_view: MapView
var hud: FightHud
## your spell bar (player_stats.bar: castable id or 0 per slot)
var bar: Array = []
var you := -1
## watching (P3.04b): no fighter of ours, nothing can be sent but the leave
var spectator := false
var fighters := {} # id -> fighter dict (state as known from events)
var views := {} # id -> ActorView
var looks := {} # id -> the fighter's own look (a carrier shows its carried fighter in it, P1.12)
## traps and glyphs (P1.13a): mark id -> mark dict; a hidden trap of the other team is not drawn
var marks := {}
var order: Array = []
var current := -1
var turn_end := 0
var selected_spell := 0
var phase := "placement"
var placement := {0: [], 1: []} # team -> cells
var placement_end := 0
## length of the running timer (placement or turn) for the chrono bar: its remaining time when it was received
var timer_total := 30000
## your spells: id -> turns before castable / casts this turn (display only, the sim decides)
var cooldowns := {}
var casts := {}
## challenges [{id, name_id, desc_id, state, target, bonus}] (P1.15) and the fight options, as the sim sent them
var challenges: Array = []
var options := {"locked": false, "party_only": false, "secret": false, "help": false}

var _container: Node2D
var _seq := SequenceGuard.new()
var _waiting_reply := false
var _hover := -1


## `sort_parent`: the y-sorted node shared with the map's sortable elements.
func setup(p_backend: GameBackend, p_map: MapData, p_map_view: MapView, hud_layer: CanvasLayer, sort_parent: Node2D, ev: Dictionary) -> void:
	backend = p_backend
	map = p_map
	map_view = p_map_view
	you = int(ev["you"])
	order = _ints(ev["order"])
	phase = str(ev.get("phase", "fight"))
	placement_end = int(ev.get("end", 0))
	timer_total = maxi(1, placement_end - backend.time_ms())
	var pl: Dictionary = ev.get("placement", {})
	placement = {0: _ints(pl.get("0", [])), 1: _ints(pl.get("1", []))}
	_container = Node2D.new()
	_container.y_sort_enabled = true
	sort_parent.add_child(_container)
	for f: Dictionary in ev["fighters"]:
		_add_fighter(f, false)
	hud = FightHud.new()
	hud_layer.add_child(hud)
	hud.setup(self)
	_refresh()


## A fighter's sprite; a summon (P1.11) fades in.
func _add_fighter(f: Dictionary, fade_in: bool) -> void:
	var id := int(f["id"])
	fighters[id] = f
	var v := ActorView.new()
	_container.add_child(v)
	v.idle_candidates = ["AnimStatiqueCombat0", ""]
	looks[id] = str(f["looks"][0]) if not f["looks"].is_empty() else ""
	v.setup(looks[id], maxi(0, int(f["cell"])), int(f["dir"]))
	views[id] = v
	v.visible = int(f["cell"]) >= 0 # an invisible enemy (P1.13c): cell -1
	if fade_in:
		v.modulate.a = 0.0
		v.create_tween().tween_property(v, "modulate:a", 1.0, 0.4)


## fighter_joined: someone joined during the placement (its sprite appears on its cell).
func on_joined(f: Dictionary, p_order: Array) -> void:
	if fighters.has(int(f["id"])):
		return
	_add_fighter(f, true)
	order = _ints(p_order)
	if hud != null:
		hud.rebuild_timeline()
	_refresh()


## fighter_left: a runaway the others go on without (its sprite goes, the timeline closes up).
func on_left(id: int, p_order: Array) -> void:
	if fighters.has(id):
		fighters[id]["alive"] = false
		views[id].visible = false
	order = _ints(p_order)
	if hud != null:
		hud.rebuild_timeline()
	_refresh()


func close() -> void:
	map_view.overlays = {}
	map_view.queue_redraw()
	if hud != null:
		hud.queue_free()
	_container.queue_free()
	queue_free()


## Display name: the localized monster name when known.
func fighter_name(id: int) -> String:
	var f: Dictionary = fighters.get(id, {})
	if id == you:
		return "Vous"
	return DofusI18n.text(int(f.get("name_id", 0)), str(f.get("name", "?")))


func me() -> Dictionary:
	return fighters.get(you, {})


func my_team() -> int:
	return int(me().get("team", 0))


func is_my_turn() -> bool:
	return not spectator and phase == "fight" and current == you and _seq.running == 0 and not _waiting_reply


## One of my active portals is on `cell` (P1.13f).
func _my_portal(cell: int) -> bool:
	return marks.values().any(func(m: Dictionary) -> bool:
		return m["kind"] == "portal" and int(m["caster"]) == you and int(m["cell"]) == cell and bool(m.get("active", true)))


func occupied(except_id := -1) -> Dictionary:
	var out := {}
	for id: int in fighters:
		if fighters[id]["alive"] and id != except_id:
			out[int(fighters[id]["cell"])] = true
	return out


func time_left_ms() -> int:
	return maxi(0, (placement_end if phase == "placement" else turn_end) - backend.time_ms())


## Sum of a fighter's buffs of `kind` (and `stat`), from the events.
func buff_total(id: int, kind: String, stat := "") -> int:
	var v := 0
	for b: Dictionary in fighters.get(id, {}).get("buffs", []):
		if str(b["kind"]) == kind and (stat == "" or str(b.get("stat", "")) == stat):
			v += int(b["value"])
	return v


func state_ids(id: int) -> Array:
	var out: Array = []
	for b: Dictionary in fighters.get(id, {}).get("buffs", []):
		if str(b["kind"]) == "state":
			out.append(int(b["state"]))
	return out


## Why you cannot use `id` now ("" = you can pick it), for the spell bar.
func spell_block(id: int) -> String:
	var spell := spell_of(id)
	if spell.is_empty():
		return "?"
	if (spell.get("effects", []) as Array).is_empty():
		return "sim" # the game refuses it (spell_not_simulated)
	if _cast_forbidden(spell):
		return "état"
	if int(cooldowns.get(id, 0)) > 0:
		return "%d" % int(cooldowns[id])
	if int(spell.get("ap", 0)) > int(me().get("ap", 0)):
		return "PA"
	if int(casts.get(id, 0)) >= int(spell.get("per_turn", 99)):
		return "max"
	if not FightRules.criterion_ok(str(spell.get("criterion", "")), state_ids(you)):
		return "état"
	return ""


## A no_cast state of yours blocks `spell`, unless the spell needs it (the throws
## of a Porteur, P1.12): the same rule as the sim's Fighter.cast_forbidden.
func _cast_forbidden(spell: Dictionary) -> bool:
	for b: Dictionary in me().get("buffs", []):
		if str(b["kind"]) == "state" and (b.get("flags", []) as Array).has("no_cast") and not FightRules.needs_state(spell, int(b["state"])):
			return true
	return false


## `spell` as you cast it now (a carrier throws farther, on a free cell).
func your_spell(id: int) -> Dictionary:
	return FightRules.for_caster(spell_of(id), state_ids(you))


# ── events (called by ClientSession; true = a visual sequence started) ────────

func handle(ev: Dictionary) -> bool:
	match str(ev["t"]):
		Protocol.FIGHTER_PLACED:
			var id := int(ev["id"])
			fighters[id]["cell"] = int(ev["cell"])
			(views[id] as ActorView).place(int(ev["cell"]))
			_refresh()
		Protocol.FIGHTER_READY:
			fighters[int(ev["id"])]["ready"] = bool(ev["ready"])
			_refresh()
		Protocol.CHALLENGE_LIST:
			challenges = ev["challenges"]
			hud.set_challenges()
		Protocol.CHALLENGE_UPDATE:
			for c: Dictionary in challenges:
				if int(c["id"]) == int(ev["id"]) and c["state"] != ev["state"]:
					c["state"] = ev["state"]
					if ev["state"] == "failed" and phase == "fight":
						hud.show_message("Challenge raté : %s" % DofusI18n.text(int(c["name_id"]), "?"))
			hud.set_challenges()
		Protocol.FIGHT_OPTIONS:
			options = ev["options"]
			hud.refresh_options()
		Protocol.FIGHT_BEGIN:
			phase = "fight"
			order = _ints(ev["order"])
			hud.rebuild_timeline()
			_refresh()
		Protocol.FIGHT_TURN:
			current = int(ev["id"])
			turn_end = int(ev["end"])
			timer_total = maxi(1, turn_end - backend.time_ms())
			var f: Dictionary = fighters[current]
			f["ap"] = int(ev["ap"])
			f["mp"] = int(ev["mp"])
			selected_spell = 0
			if current == you:
				casts.clear()
				for sid: int in cooldowns.keys():
					cooldowns[sid] = int(cooldowns[sid]) - 1
					if int(cooldowns[sid]) <= 0:
						cooldowns.erase(sid)
			_refresh()
			if not (ev.get("effects", []) as Array).is_empty():
				_play_effects(ev["effects"])
				return true
		Protocol.FIGHTER_MOVE:
			var id := int(ev["id"])
			var path := _ints(ev["path"])
			fighters[id]["mp"] = int(ev["mp"])
			var lost: Dictionary = ev.get("lost", {})
			fighters[id]["ap"] = int(fighters[id]["ap"]) - int(lost.get("ap", 0))
			if id == you:
				_waiting_reply = false
			_play_move(id, path, lost, ev.get("effects", []), ev.get("triggered", []))
			return true
		Protocol.SPELL_CAST:
			var caster := int(ev["caster"])
			fighters[caster]["ap"] = int(ev["ap"])
			# hp / deaths are applied at impact time by _play_spell: later events wait
			# for the sequence anyway, so the rules previews never see stale data
			if caster == you:
				_waiting_reply = false
				var sid := int(ev["spell"])
				selected_spell = 0
				casts[sid] = int(casts.get(sid, 0)) + 1
				if int(spell_of(sid).get("cooldown", 0)) > 0:
					cooldowns[sid] = int(spell_of(sid)["cooldown"])
			_play_spell(ev)
			return true
		Protocol.ERROR:
			_waiting_reply = false
			hud.show_message(ErrorTexts.text(ev))
			_refresh()
	return false


func update(now: int) -> void:
	watchdog(Time.get_ticks_msec())
	for v: ActorView in views.values():
		v.update(now)
	queue_redraw() # team discs follow the fighters


# ── input ──────────────────────────────────────────────────────────────────────

func set_bar(p_bar: Array) -> void:
	bar = p_bar
	if hud != null:
		hud.set_bar()


## A spell a fighter casts: its own (the weapon hit, fighter dict own_spells) or SpellBook's.
func spell_of(id: int, fighter_id := -1) -> Dictionary:
	var own: Dictionary = fighters.get(you if fighter_id < 0 else fighter_id, {}).get("own_spells", {})
	if own.has(id):
		return own[id]
	if own.has(str(id)): # after a JSON round trip (network)
		return own[str(id)]
	return SpellBook.get_spell(id)


func select_spell(id: int) -> void:
	if not is_my_turn():
		return
	var why := spell_block(id)
	if why != "":
		hud.show_message({"PA": "Pas assez de PA", "max": "Plus de lancers ce tour", "état": "Condition du sort non remplie",
				"sim": ErrorTexts.TEXTS[Protocol.E_SPELL_NOT_SIMULATED]}.get(why, "Sort en recharge (%s tours)" % why))
		id = 0
	selected_spell = 0 if selected_spell == id else id
	_refresh()


func end_turn() -> void:
	if spectator:
		return
	if phase == "placement":
		set_ready(not bool(me().get("ready", false)))
	elif current == you:
		selected_spell = 0
		backend.send(Protocol.fight_end_turn())


func set_ready(ready: bool) -> void:
	backend.send(Protocol.fight_ready(ready))


func leave() -> void:
	backend.send(Protocol.fight_leave())


func set_option(option: String, value: bool) -> void:
	backend.send(Protocol.fight_option(option, value))


func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventMouseMotion:
		var c := MapGeometry.screen_to_cell(get_global_mouse_position())
		if c != _hover:
			_hover = c
			_refresh_overlays()
	elif event is InputEventMouseButton and event.pressed:
		var mb := event as InputEventMouseButton
		if mb.button_index == MOUSE_BUTTON_RIGHT:
			selected_spell = 0
			_refresh()
			get_viewport().set_input_as_handled()
		elif mb.button_index == MOUSE_BUTTON_LEFT:
			_click(MapGeometry.screen_to_cell(get_global_mouse_position()))
			get_viewport().set_input_as_handled()
	elif event is InputEventKey and event.pressed and not event.echo:
		var key := event as InputEventKey
		if key.keycode == Shortcuts.key("end_turn"):
			end_turn()
		elif key.keycode == Shortcuts.key("close"):
			selected_spell = 0
			_refresh()
		else:
			var id := hud.spell_bar.spell_for_key(event)
			if id != 0:
				select_spell(id)
		get_viewport().set_input_as_handled()


func _click(cell: int) -> void:
	if cell < 0 or spectator:
		return
	if phase == "placement":
		if (placement[my_team()] as Array).has(cell):
			backend.send(Protocol.fight_place(cell))
		return
	if not is_my_turn():
		return
	var m := me()
	if selected_spell != 0:
		var spell := your_spell(selected_spell)
		var err := FightRules.cast_error(map, occupied(you), spell, int(m["cell"]), cell, int(m["ap"]), buff_total(you, "stat", "range"))
		if err == Protocol.E_NEEDS_TARGET and _my_portal(cell): # the sim decides if it is projected (P1.13f)
			err = ""
		if err == "":
			_waiting_reply = true
			backend.send(Protocol.fight_cast(selected_spell, cell))
		else:
			selected_spell = 0
		_refresh()
		return
	if FightRules.path_to(map, occupied(you), int(m["cell"]), cell, int(m["mp"])).size() >= 2:
		_waiting_reply = true
		backend.send(Protocol.fight_move(cell))
		_refresh()


# ── visuals ────────────────────────────────────────────────────────────────────

func _refresh() -> void:
	_refresh_overlays()
	if hud != null:
		hud.refresh()


func _refresh_overlays() -> void:
	var o := {}
	var mk := {} # the marks, over the reach and range cells
	for m: Dictionary in marks.values():
		if not bool(m.get("hidden", false)) or int(m["team"]) == my_team():
			var col := Color(str(m["color"]), 0.45)
			if m["kind"] == "portal": # P1.13f
				col = COL_PORTAL if bool(m.get("active", true)) else COL_PORTAL_OFF
			for c: Variant in m["cells"]:
				mk[int(c)] = col
	o = mk.duplicate()
	if phase == "placement":
		for team in 2:
			for c: int in placement[team]:
				o[c] = PLACEMENT_COLORS[0 if team == my_team() else 1]
		if (placement[my_team()] as Array).has(_hover):
			o[_hover] = Color(1, 0.85, 0.3, 0.6)
	elif is_my_turn():
		var m := me()
		var from := int(m["cell"])
		var occ := occupied(you)
		if selected_spell != 0:
			var spell := your_spell(selected_spell)
			var bonus := buff_total(you, "stat", "range")
			var targets := FightRules.targetable(map, occ, spell, from, bonus)
			var r: Array = spell["range"]
			for c in FightRules.reachable(MapData.new(), {}, from, FightRules.max_range(spell, bonus)):
				if FightRules.distance(from, c) >= int(r[0]) and map.is_fight_walkable(c):
					o[c] = COL_NO_TARGET
			for c in targets:
				o[c] = COL_RANGE
			if targets.has(_hover):
				for c in FightRules.area(spell, _hover, from, map, occ):
					o[c] = COL_AREA
		else:
			for c: int in FightRules.reachable(map, occ, from, int(m["mp"])):
				if c != from:
					o[c] = COL_REACH
			for c: int in FightRules.path_to(map, occ, from, _hover, int(m["mp"])):
				if c != from:
					o[c] = COL_PATH
	for c: int in mk:
		if o[c] in [COL_REACH, COL_RANGE, COL_NO_TARGET]:
			o[c] = mk[c]
	map_view.overlays = o
	map_view.queue_redraw()


func _draw() -> void:
	for id: int in views:
		if not fighters[id]["alive"] or not views[id].visible: # dead, or carried (P1.12)
			continue
		var p: Vector2 = views[id].position
		var col: Color = TEAM_COLORS[int(fighters[id]["team"])]
		var pts := PackedVector2Array()
		for i in 24:
			var a := TAU * i / 24.0
			pts.append(p + Vector2(cos(a) * 26.0, sin(a) * 13.0))
		draw_colored_polygon(pts, Color(col, 0.35))
		pts.append(pts[0])
		draw_polyline(pts, Color(col, 0.95 if id == current else 0.6), 3.0 if id == current else 2.0)


func _play_move(id: int, path: Array, lost: Dictionary, effects: Array, triggered: Array) -> void:
	var seq := _begin_sequence()
	if not effects.is_empty(): # a carried fighter gets off its carrier first
		await _apply_effects(effects, null)
	if path.is_empty(): # an invisible enemy walked somewhere (P1.13c)
		if not triggered.is_empty():
			await get_tree().create_timer(await _apply_effects(triggered, null)).timeout
		_end_sequence(seq)
		return
	_set_cell(id, path[-1])
	_refresh()
	var v: ActorView = views[id]
	if int(lost.get("mp", 0)) > 0 or int(lost.get("ap", 0)) > 0:
		SpellFx.floating_text(self, v.position + Vector2(0, -95), "Tacle !", Color(1, 0.8, 0.3), 22)
		var parts: Array = []
		if int(lost.get("mp", 0)) > 0:
			parts.append("-%d PM" % int(lost["mp"]))
		if int(lost.get("ap", 0)) > 0:
			parts.append("-%d PA" % int(lost["ap"]))
		SpellFx.floating_text(self, v.position + Vector2(0, -70), " ".join(parts), Color(0.5, 0.9, 0.5), 20)
		await get_tree().create_timer(0.5).timeout
	if path.size() >= 2:
		# animate from now: the move may have been queued behind another sequence
		var now := backend.time_ms()
		v.set_move(path, now, path.size() > 3)
		await get_tree().create_timer(Movement.duration_ms(path, path.size() > 3) / 1000.0 + 0.05).timeout
	if not triggered.is_empty(): # a trap went off on arrival
		await get_tree().create_timer(await _apply_effects(triggered, null)).timeout
	_end_sequence(seq)


func _play_spell(ev: Dictionary) -> void:
	var seq := _begin_sequence()
	_refresh()
	await get_tree().process_frame
	var caster: ActorView = views[int(ev["caster"])]
	if ev.has("from"): # an invisible enemy casts: where from (P1.13c)
		caster.place(int(ev["from"]))
		SpellFx.floating_text(self, caster.position + Vector2(0, -80), "?", Color(1, 0.85, 0.3), 30)
	var spell := spell_of(int(ev["spell"]), int(ev["caster"]))
	var target := int(ev["cell"])
	var fx: Dictionary = spell.get("fx", {})
	var color := Color(str(fx.get("color", "#ffffff")))
	if bool(ev.get("crit", false)):
		SpellFx.floating_text(self, caster.position + Vector2(0, -120), "Coup critique !", Color(1, 0.85, 0.2), 24)
	# 1. caster animation, until its SHOT label (the frame the spell leaves)
	var st := {"shot": false}
	var on_label := func(label: String) -> void:
		if label == "SHOT":
			st["shot"] = true
	caster.label_reached.connect(on_label)
	var played := caster.play_action(spell.get("anim", []), int(ev["dir"]))
	var t0 := Time.get_ticks_msec()
	while played and not st["shot"] and caster.is_acting() and Time.get_ticks_msec() - t0 < 1500:
		await get_tree().process_frame
	caster.label_reached.disconnect(on_label)
	if not played:
		await get_tree().create_timer(0.25).timeout
	# 2. spell FX: the real Dofus FX bones when the spell has some, else procedural ones
	var to := MapGeometry.to_screen(target) + HEAD
	if fx.has("target") or fx.has("target2") or fx.has("missile") or fx.has("caster"):
		await FightVisuals.dofus_fx(self, fx, caster, target, int(ev["dir"]))
	else:
		await FightVisuals.procedural_fx(self, fx, spell, caster, target, to, color)
	# 3. effects on targets
	var wait := await _apply_effects(ev["effects"], caster)
	await get_tree().create_timer(wait).timeout
	_end_sequence(seq)


## Start-of-turn effects (poisons, buffs running out).
func _play_effects(effects: Array) -> void:
	var seq := _begin_sequence()
	var wait := await _apply_effects(effects, null)
	if wait > 0.36:
		await get_tree().create_timer(wait).timeout
	_end_sequence(seq)


## Applies the effects to the known fighters and shows them (numbers, slides,
## hits, deaths); returns how long to let them play.
func _apply_effects(effects: Array, caster: ActorView) -> float:
	var fx := {"wait": 0.35} # how long to let the effects play (the helpers raise it)
	var lines := {} # target -> texts shown so far (stacked)
	for e: Dictionary in effects:
		var id := int(e["target"])
		if str(e["kind"]) == "summon": # a new fighter, and the new turn order
			_add_fighter(e["fighter"], true)
			order = _ints(e["order"])
			hud.rebuild_timeline()
			fx["wait"] = maxf(fx["wait"], 0.6)
			continue
		if not fighters.has(id):
			continue
		var shown: Array = await _apply_effect(e, id, caster, fx)
		if shown[0] != "":
			var n := int(lines.get(id, 0))
			lines[id] = n + 1
			SpellFx.floating_text(self, views[id].position + Vector2(0, -95 - 26 * n), shown[0], shown[1], 26 if n == 0 else 20)
	hud.refresh()
	return fx["wait"]


## One effect on a known fighter: updates the fight's copy of it and plays the effect.
## Returns [text, color] to float above the fighter ("" = none).
func _apply_effect(e: Dictionary, id: int, caster: ActorView, fx: Dictionary) -> Array:
	var t: Dictionary = fighters[id]
	var tv: ActorView = views[id]
	match str(e["kind"]):
		"damage", "heal", "ap", "mp":
			return _effect_vitals(e, t, tv, caster, fx)
		"buff", "buff_end", "projected", "portal", "reflected", "explode":
			return _effect_status(e, id, t)
		"move":
			if not (e["path"] as Array).is_empty(): # an empty one: an invisible enemy (P1.13c)
				var path := _ints(e["path"])
				_set_cell(id, path[-1])
				await _slide(tv, path, str(e.get("how", "push")))
		"carry", "throw", "drop":
			fx["wait"] = maxf(fx["wait"], await FightVisuals.carry(self, e))
		_:
			_effect_world(e, id, t, tv)
	return ["", Color.WHITE]


## damage, heal, AP / MP: the life or the points shown.
func _effect_vitals(e: Dictionary, t: Dictionary, tv: ActorView, caster: ActorView, fx: Dictionary) -> Array:
	var text := ""
	var color := Color.WHITE
	match str(e["kind"]):
		"damage":
			t["hp"] = int(e["hp"])
			t["alive"] = not bool(e["died"])
			text = "-%d" % int(e["amount"])
			color = ELEMENT_COLORS.get(str(e.get("element", "neutral")), Color(1, 0.35, 0.3))
			if int(e.get("shield", 0)) > 0:
				text += "  (-%d bouclier)" % int(e["shield"])
			if bool(e["died"]):
				tv.dead = true
				tv.play_action(["AnimMort"])
				_fade_out(tv)
				fx["wait"] = 1.2
			elif tv != caster and int(e["amount"]) > 0:
				tv.play_action(["AnimHit"])
		"heal":
			t["hp"] = int(e["hp"])
			text = "+%d" % int(e["amount"])
			color = Color(0.4, 1.0, 0.45)
		"ap", "mp":
			var v := int(e["value"])
			t[str(e["kind"])] = int(e["left"])
			text = "%+d %s" % [v, "PA" if e["kind"] == "ap" else "PM"]
			if int(e.get("dodged", 0)) > 0:
				text += " (%d esquivé)" % int(e["dodged"])
			color = Color(0.4, 0.7, 1.0) if e["kind"] == "ap" else Color(0.45, 0.9, 0.45)
			if e.has("buff"):
				_add_buff(t, e["buff"])
	return [text, color]


## buffs, portals, reflections, bombs: the status texts.
func _effect_status(e: Dictionary, id: int, t: Dictionary) -> Array:
	var text := ""
	var color := Color.WHITE
	match str(e["kind"]):
		"buff":
			var b: Dictionary = e["buff"]
			_add_buff(t, b)
			text = FightTexts.buff_text(b)
			color = Color(0.85, 0.75, 1.0)
			_show_invisibility(id)
		"buff_end":
			t["buffs"] = (t.get("buffs", []) as Array).filter(func(b: Dictionary) -> bool: return int(b["id"]) != int(e["buff"]))
			_show_invisibility(id)
		"projected": # through portals (P1.13f); the effects follow on the exit
			text = "Portail +%d %%" % int(e["bonus"])
			color = Color(0.4, 0.75, 1.0)
		"portal": # disabled / back on
			if marks.has(int(e["mark"])):
				marks[int(e["mark"])]["active"] = bool(e["active"])
				_refresh_overlays()
		"reflected": # spell reflector (P1.13r): the spell goes back to its caster
			text = "Sort renvoyé !"
			color = Color(0.7, 0.9, 1.0)
		"explode": # a bomb goes off (P1.13d); its spell's effects follow
			text = "Boum !"
			color = Color(1.0, 0.55, 0.2)
	return [text, color]


## cooldowns, reveals, marks: changes without a text.
func _effect_world(e: Dictionary, id: int, t: Dictionary, tv: ActorView) -> void:
	match str(e["kind"]):
		"cooldown": # P1.17b: a spell's cooldown changed (the bar's badge)
			if id == you:
				if int(e["turns"]) > 0:
					cooldowns[int(e["spell"])] = int(e["turns"])
				else:
					cooldowns.erase(int(e["spell"]))
				_refresh()
		"reveal": # no longer invisible: where it is
			t["cell"] = int(e["cell"])
			tv.place(int(e["cell"]))
			tv.visible = t["alive"] and int(t.get("carried_by", -1)) < 0
			_show_invisibility(id)
		"mark_add":
			marks[int(e["mark"]["id"])] = e["mark"]
			_refresh_overlays()
		"mark_remove":
			marks.erase(int(e["mark"]))
			_refresh_overlays()


## Invisibility (P1.13c, a state with the flag `invisible`): see-through for its team,
## gone for the other one (which does not know its cell any more).
func _show_invisibility(id: int) -> void:
	var inv := (fighters[id].get("buffs", []) as Array).any(func(b: Dictionary) -> bool:
		return (b.get("flags", []) as Array).has("invisible"))
	var v: ActorView = views[id]
	if int(fighters[id]["team"]) == my_team():
		v.modulate.a = 0.5 if inv else 1.0
	elif inv:
		v.visible = false
		fighters[id]["cell"] = -1


## Pushes / pulls slide cell by cell; teleports blink.
func _slide(v: ActorView, path: Array, how: String) -> void:
	if path.size() < 2: # a tween with no step never finishes
		return
	if how in ["teleport", "swap", "portal"]:
		var tw := v.create_tween()
		tw.tween_property(v, "modulate:a", 0.0, 0.12)
		await tw.finished
		v.place(path[-1])
		var tw2 := v.create_tween()
		tw2.tween_property(v, "modulate:a", 1.0, 0.15)
		return
	var tw := v.create_tween()
	for c: int in path.slice(1):
		tw.tween_property(v, "position", MapGeometry.to_screen(c), 0.09)
	await tw.finished
	v.place(path[-1])


## A fighter's new cell; the fighter it carries comes along (P1.12).
func _set_cell(id: int, cell: int) -> void:
	fighters[id]["cell"] = cell
	var carried := int(fighters[id].get("carrying", -1))
	if fighters.has(carried):
		fighters[carried]["cell"] = cell



func _add_buff(t: Dictionary, b: Dictionary) -> void:
	var buffs: Array = t.get("buffs", [])
	buffs.append(b)
	t["buffs"] = buffs



## Buff lines for the fighter tooltip.
func buff_lines(id: int) -> Array:
	var out: Array = []
	for b: Dictionary in fighters.get(id, {}).get("buffs", []):
		var s := FightTexts.buff_text(b)
		if s == "":
			continue
		var turns := int(b.get("turns", 1))
		out.append(s + ("" if turns < 0 else " (%d tour%s)" % [turns, "s" if turns > 1 else ""]))
	return out


func _fade_out(v: ActorView) -> void:
	var t0 := Time.get_ticks_msec()
	while v.is_acting() and Time.get_ticks_msec() - t0 < 2500:
		await get_tree().process_frame
	var tw := v.create_tween()
	tw.tween_property(v, "modulate:a", 0.0, 0.6)


func _begin_sequence() -> int:
	return _seq.begin(Time.get_ticks_msec())


func _end_sequence(token: int) -> void:
	if _seq.finish(token):
		if hud != null:
			_refresh()
		sequence_done.emit()


## Safety net (SequenceGuard): a sequence that never ends is declared over, the queue goes on.
func watchdog(ticks_ms: int) -> bool:
	if not _seq.expired(ticks_ms):
		return false
	push_warning("FightView: a sequence lasted more than %d ms, forced done (you %d, turn of %d)" % [SequenceGuard.TIMEOUT_MS, you, current])
	if hud != null:
		_refresh()
	sequence_done.emit()
	return true


static func _ints(a: Array) -> Array:
	return a.map(func(x: Variant) -> int: return int(x))
