## What the mouse points at on the map, out of fight (like the Dofus client): the sprite of
## a resource, a door, the zaap or the phoenix lights up with a tooltip (what it is, what a
## click does, where a door leads), the cursor turns into an arrow over an exit cell or past
## the edge of a side that leads out (MapFrame then blurs the outside a little) and a hand
## over what can be used. Holding the "highlight" key lights every one of them at once.
class_name MapHover
extends RefCounted

## sprite colour of a lit element (times its own tint)
const LIT := Color(1.35, 1.35, 1.35, 1.0)
const LIT_DEPLETED := Color(1.15, 1.15, 1.15, 1.0)

var _s: ClientSession
var _tip: PanelContainer
var _tip_key := ""
var _lit := {} # CanvasItem -> its own modulate
## tools (client_shot hoverat / highlight): a map point instead of the mouse, the key held
var force_point: Variant = null
var force_all := false


func _init(session: ClientSession) -> void:
	_s = session


## Each frame; `hovering` = out of fight and not over a window.
func update(hovering: bool) -> void:
	var map := _s.map
	var p: Vector2 = force_point if force_point != null else _s.get_global_mouse_position()
	var t := {}
	var over_actor := false
	if hovering and map != null:
		over_actor = _s.clicks.group_at(p) >= 0 or _s.clicks.npc_at(p) >= 0 or _s.clicks.swords_at(p) != null
		if not over_actor and _s._others.player_at(p) < 0:
			t = target(map, _s._map_view, MapGeometry.screen_to_cell(p), p)
	var held := Input.is_key_pressed(Shortcuts.key("highlight")) and not _s.get_viewport().gui_get_focus_owner() is LineEdit
	var all := hovering and map != null and (held or force_all)
	_light(t, all)
	_s._map_view.show_passages = all
	var kind := str(t.get("kind", ""))
	if _s.frame != null:
		_s.frame.shown = kind == "exit" # the edge of the map shows while an exit arrow does
	MapCursor.show(cursor_kind(t, hovering and _s.clicks.npc_at(p) >= 0, _s._depleted))
	var tipped := t if kind != "exit" else {}
	var npc := _s.clicks.npc_at(p) if hovering and map != null else -1
	if npc >= 0 and _s.views.has(npc):
		var v: Node2D = _s.views[npc]
		tipped = {"kind": "npc", "name": UiStyle.plain_text(DofusI18n.text(int(v.get_meta("name_id", 0)), "PNJ")),
				"quest": v.get_node_or_null("QuestMark") != null}
	_update_tip(tipped, _s.get_viewport().get_canvas_transform() * p)


## The mouse cursor kind (MapCursor) over target `t`: the harvest cursor of a resource that has grown back.
static func cursor_kind(t: Dictionary, over_npc: bool, depleted: Dictionary) -> String:
	var kind := str(t.get("kind", ""))
	if kind == "exit":
		return str(t["dir"])
	if kind == "element" and not depleted.has(int(t["e"])):
		return MapCursor.kind_for_skill(int(t["skill"]))
	return "use" if kind != "" or over_npc else ""


## What a click on `cell` (point `p`) would use: {kind: element | door | zaap | phoenix | exit,
## cell, ...} ({} = a plain cell). Same order as MapClick.click.
static func target(map: MapData, view: MapView, cell: int, p: Vector2) -> Dictionary:
	if cell < 0:
		return edge_exit(map, p)
	var el := map.interactive_near(cell)
	if not el.is_empty():
		return {"kind": "element", "cell": int(el["cell"]), "e": int(el["e"]), "gfx": int(el.get("gfx", 0)), "skill": int(el["skill"])}
	var door := map.door_near(cell)
	if door >= 0:
		return {"kind": "door", "cell": door, "trigger": map.trigger_at(door)}
	if view.is_phoenix(cell):
		return {"kind": "phoenix", "cell": map.phoenix}
	if view.is_zaap(cell):
		return {"kind": "zaap", "cell": map.zaap}
	if map.is_walkable(cell):
		var dir := PendingAction.exit_for(map, cell, p)
		if dir != "":
			return {"kind": "exit", "cell": cell, "dir": dir}
	return {}


## The mouse past the map's cells, on a side that leads to another map: that side's exit cell
## closest to the mouse ({kind: exit, cell, dir}; {} = no exit on that side), however far along
## the side the mouse is. The side = the edge of the map the mouse is the furthest past.
static func edge_exit(map: MapData, p: Vector2) -> Dictionary:
	var b := MapGeometry.screen_bounds()
	var past := {"left": b.position.x - p.x, "right": p.x - b.end.x, "top": b.position.y - p.y, "bottom": p.y - b.end.y}
	var side := "left"
	for dir: String in past:
		if past[dir] > past[side]:
			side = dir
	var best := -1
	var best_d := INF
	for c in map.exit_cells(side):
		var d := MapGeometry.to_screen(c).distance_squared_to(p)
		if d < best_d:
			best = c
			best_d = d
	return {"kind": "exit", "cell": best, "dir": side} if best >= 0 else {}


## The tooltip of a target: [title, what a click does (or why not)].
static func tip_lines(map: MapData, t: Dictionary, depleted := false) -> Array[String]:
	match str(t.get("kind", "")):
		"element":
			var skill := Jobs.skill(int(t["skill"]))
			var verb := DofusI18n.text(int(skill.get("nameId", 0)), "Utiliser")
			var job := DofusI18n.text(int(Jobs.job(int(skill.get("parentJobId", 0))).get("nameId", 0)), "")
			var title := UiTooltips.item_name(Jobs.item_of(int(t["skill"]))) if Jobs.is_gathering(int(t["skill"])) else verb
			if depleted:
				return [title, "Repousse bientôt"]
			return [title, "%s%s · niveau %d" % [verb, " (%s)" % job if job != "" else "", Jobs.required_level(int(t["skill"]))]]
		"door":
			return [door_name(map, t["trigger"]), "Clic : y aller"]
		"npc":
			return [str(t["name"]), "Clic : parler (quête)" if bool(t.get("quest", false)) else "Clic : parler"]
		"zaap":
			return ["Zaap", "Clic : voyager"]
		"phoenix":
			return ["Statue du Phénix", "Clic : ressusciter (fantôme)"]
	return []


## Where a door leads: the area's name when it leaves this area (Incarnam -> Astrub), else the subarea's.
static func door_name(map: MapData, trigger: Dictionary) -> String:
	var area := int(trigger.get("to_area_name_id", 0))
	if area != 0 and area != map.area_name_id:
		var a := DofusI18n.text(area, "")
		if a != "":
			return a
	var sub := DofusI18n.text(int(trigger.get("to_name_id", 0)), "")
	return sub if sub != "" and int(trigger.get("to_name_id", 0)) != map.name_id else "Entrée"


## Lights the sprites of `t` (or of every target of the map when `all`), puts back the others.
func _light(t: Dictionary, all: bool) -> void:
	var want := {} # CanvasItem -> lit colour
	var targets: Array = []
	if all:
		for el: Dictionary in _s.map.interactives:
			targets.append({"kind": "element", "cell": int(el["cell"]), "e": int(el["e"]), "gfx": int(el.get("gfx", 0))})
		for c: int in _s.map.triggers:
			targets.append({"kind": "door", "cell": c})
		for c: int in [_s.map.zaap, _s.map.phoenix]:
			if c >= 0:
				targets.append({"kind": "use", "cell": c})
	elif not t.is_empty() and str(t["kind"]) != "exit":
		targets.append(t)
	for x: Dictionary in targets:
		var dim := str(x["kind"]) == "element" and _s._depleted.has(int(x["e"]))
		for item: CanvasItem in _s._dofus_map.elements_at(int(x["cell"]), int(x.get("gfx", 0))):
			want[item] = LIT_DEPLETED if dim else LIT
	for item: Variant in _lit.keys(): # Variant: the map change frees them
		if not want.has(item):
			if is_instance_valid(item):
				item.modulate = _lit[item]
			_lit.erase(item)
	var pulse := 0.5 + 0.5 * sin(Time.get_ticks_msec() * 0.008) # the pointed sprite breathes
	for item: CanvasItem in want:
		if not _lit.has(item):
			_lit[item] = item.modulate
		var lit: Color = want[item]
		item.modulate = _lit[item] * (lit if all else Color(1, 1, 1).lerp(lit, pulse))
	var cells: Array[int] = []
	for x: Dictionary in targets:
		if str(x["kind"]) != "use" or not all:
			cells.append(int(x["cell"]))
	_s._map_view.lit_cells = cells


func _update_tip(t: Dictionary, at := Vector2.ZERO) -> void:
	var depleted := str(t.get("kind", "")) == "element" and _s._depleted.has(int(t["e"]))
	var lines := tip_lines(_s.map, t, depleted) if not t.is_empty() else ([] as Array[String])
	var key := "|".join(lines)
	if key != _tip_key:
		_tip_key = key
		if is_instance_valid(_tip):
			_tip.queue_free()
		_tip = null
		if not lines.is_empty():
			_tip = MapTip.build(lines[0], lines[1], depleted)
			_s._hud_layer.add_child(_tip)
	if _tip != null:
		MapTip.place(_tip, at, _s.get_viewport_rect().size)


## The map changes or a fight starts: nothing stays lit.
func clear() -> void:
	_light({}, false)
	_update_tip({})
	MapCursor.show("")
	if _s.frame != null:
		_s.frame.shown = false
