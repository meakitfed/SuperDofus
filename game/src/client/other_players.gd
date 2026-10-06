## The other players on the map (P3.01): the name above their head, the tooltip under
## the mouse (name, level, class) and the right-click menu. It only shows what the sim
## sent in `actor_add` (name, level, breed): the rest of a character is never sent.
class_name OtherPlayers
extends RefCounted

const BOX := Rect2(Vector2(-35, -110), Vector2(70, 120))

var _session: ClientSession
var _tip: PanelContainer
var _tip_id := -1


func _init(session: ClientSession) -> void:
	_session = session


## A name above a sprite (NPCs, players), drawn over the sprite with an outline.
static func add_tag(view: Node2D, text: String, color: Color, y := -135.0) -> void:
	var tag := UiStyle.label(text, color, 13)
	tag.add_theme_color_override("font_outline_color", Color.BLACK)
	tag.add_theme_constant_override("outline_size", 6)
	tag.position = Vector2(-tag.get_minimum_size().x / 2.0, y)
	view.add_child(tag)


## Called for every actor_add / map_enter actor of kind "player" other than us.
static func decorate(view: ActorView, a: Dictionary) -> void:
	view.set_meta("player", int(a["id"]))
	view.set_meta("player_name", str(a.get("name", "")))
	view.set_meta("level", int(a.get("level", 1)))
	view.set_meta("breed", int(a.get("breed", 0)))
	add_tag(view, str(a.get("name", "")), UiStyle.TEXT)


## "Niveau 12 · Iop"
static func summary(level: int, breed: int) -> String:
	return "Niveau %d · %s" % [level, CharacterSelectScreen.breed_name(breed)]


## The player under the mouse (its sprite box), -1 if none.
func player_at(p: Vector2) -> int:
	for id: int in _session.views:
		var v: Node2D = _session.views[id]
		if v.has_meta("player") and Rect2(v.position + BOX.position, BOX.size).has_point(p):
			return id
	return -1


## Right click: the menu of a player. Only "Informations" exists yet; the others are
## greyed until their lot (duel later; group invitation P3.03b, exchange P3.11b).
func menu(id: int, at: Vector2) -> void:
	var v: Node2D = _session.views[id]
	var name := str(v.get_meta("player_name"))
	var info := "%s : %s" % [name, summary(int(v.get_meta("level")), int(v.get_meta("breed")))]
	ContextMenu.popup(_session, at, name, [
		["Informations", func() -> void: _session.toast.show_text(info)],
		["Message privé", func() -> void: _session.chat.whisper(name)],
		["Inviter dans le groupe", func() -> void: _session.player_hud.party.invite(name)],
		["Ajouter en ami", func() -> void: _session.backend.send(ProtocolContacts.add(Contacts.FRIEND, name))],
		["Ignorer", func() -> void: _session.backend.send(ProtocolContacts.add(Contacts.IGNORED, name))],
		["Défier", func() -> void: pass, false],
		["Échanger", func() -> void: _session.backend.send(ProtocolTrade.invite(name))]])


## Each frame: the tooltip of the player under the mouse (not over a window).
func update(hud_layer: CanvasLayer, hovering: bool) -> void:
	var id := player_at(_session.get_global_mouse_position()) if hovering else -1
	if id != _tip_id:
		_tip_id = id
		if is_instance_valid(_tip):
			_tip.queue_free()
		_tip = null
		if id >= 0:
			var v: Node2D = _session.views[id]
			_tip = PanelContainer.new()
			_tip.theme = ClientTheme.get_theme()
			_tip.add_theme_stylebox_override("panel", ClientTheme.get_theme().get_stylebox("panel", "TooltipPanel"))
			_tip.mouse_filter = Control.MOUSE_FILTER_IGNORE
			var box := VBoxContainer.new()
			box.add_child(UiStyle.label(str(v.get_meta("player_name")), UiStyle.GOLD, 14))
			box.add_child(UiStyle.label(summary(int(v.get_meta("level")), int(v.get_meta("breed"))), UiStyle.TEXT, 12))
			_tip.add_child(box)
			hud_layer.add_child(_tip)
	if _tip != null:
		var vp := _session.get_viewport_rect().size
		_tip.position = (_session.get_viewport().get_mouse_position() + Vector2(18, 18)).clamp(Vector2.ZERO, vp - _tip.size)


## The tooltip goes with the fight / the map change.
func clear() -> void:
	_tip_id = -1
	if is_instance_valid(_tip):
		_tip.queue_free()
	_tip = null
