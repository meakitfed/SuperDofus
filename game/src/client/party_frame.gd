## The group frame (P3.03b), top left under the map name: one row per member (class symbol, name,
## level, HP bar, "chef" star), the invitations received (accept / refuse) and a "leave" button.
## It only shows what the sim sends (party_update, party_invited, party_left, party_declined):
## every action goes back as a ProtocolParty message. Members on the current map also get a
## marker over their sprite (sync_marks); the others show their map coordinates.
class_name PartyFrame
extends VBoxContainer

const WIDTH := 250
const INVITE_MS := 60000 # same as the sim (APPROX(P3.03a)): an older invitation is dropped
const MARK := "party_mark"

var backend: GameBackend
var party := {}               # last party_update.party, {} = no group
var invites: Array = []       # [{from, at (ms)}], oldest first
var you := -1                 # our actor id
var _list: VBoxContainer
var _invites_box: VBoxContainer
var _title: Label
var _box: PanelContainer


func setup(p_backend: GameBackend) -> void:
	backend = p_backend
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_theme_constant_override("separation", 4)
	_box = PanelContainer.new()
	_box.add_theme_stylebox_override("panel", UiStyle.panel(Color(UiStyle.BG, 0.8), UiStyle.BORDER, 6, 8))
	_box.custom_minimum_size = Vector2(WIDTH, 0)
	add_child(_box)
	var v := VBoxContainer.new()
	v.add_theme_constant_override("separation", 3)
	_box.add_child(v)
	var head := HBoxContainer.new()
	v.add_child(head)
	_title = UiStyle.label("", UiStyle.GOLD, 13)
	_title.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	head.add_child(_title)
	var leave := Button.new()
	leave.text = "Quitter"
	leave.tooltip_text = "Quitter le groupe"
	leave.pressed.connect(func() -> void: backend.send(ProtocolParty.leave()))
	head.add_child(leave)
	_list = VBoxContainer.new()
	_list.add_theme_constant_override("separation", 3)
	v.add_child(_list)
	_invites_box = VBoxContainer.new()
	_invites_box.add_theme_constant_override("separation", 4)
	add_child(_invites_box)
	refresh()


## The party events, routed here by ClientSession (the sim decides everything).
func on_event(t: String, ev: Dictionary, toast: Toast, views: Dictionary, p_you: int) -> void:
	you = p_you
	match t:
		ProtocolParty.INVITED:
			var from := str(ev["from"])
			invites = invites.filter(func(i: Dictionary) -> bool: return i["from"] != from)
			invites.append({"from": from, "at": Time.get_ticks_msec()})
			_say(toast, "%s vous invite dans son groupe" % from)
		ProtocolParty.UPDATE:
			party = ev["party"]
			invites.clear() # joined: the other invitations are moot
		ProtocolParty.LEFT:
			party = {}
			_say(toast, left_text(str(ev["reason"])))
		ProtocolParty.DECLINED:
			_say(toast, "%s a refusé votre invitation" % str(ev["name"]))
	refresh()
	sync_marks(views)


## Toast, unless there is none (tests).
static func _say(toast: Toast, text: String) -> void:
	if toast != null:
		toast.show_text(text)


static func left_text(reason: String) -> String:
	match reason:
		ProtocolParty.REASON_KICKED:
			return "Vous avez été exclu du groupe"
		ProtocolParty.REASON_DISSOLVED:
			return "Le groupe est dissous"
	return "Vous avez quitté le groupe"


func members() -> Array:
	return party.get("members", [])


func is_leader() -> bool:
	for m: Dictionary in members():
		if int(m["id"]) == you:
			return str(m["name"]) == str(party.get("leader", ""))
	return false


func accept(from: String) -> void:
	invites = invites.filter(func(i: Dictionary) -> bool: return i["from"] != from)
	backend.send(ProtocolParty.accept(from))
	refresh()


func decline(from: String) -> void:
	invites = invites.filter(func(i: Dictionary) -> bool: return i["from"] != from)
	backend.send(ProtocolParty.decline(from))
	refresh()


func invite(player: String) -> void:
	backend.send(ProtocolParty.invite(player))


## The menu of a member row: follow, hand over the lead, exclude (the leader).
func member_menu(m: Dictionary, at: Vector2) -> void:
	var name := str(m["name"])
	if int(m["id"]) == you:
		return
	var following := str(party.get("follow", "")) == name
	var entries: Array = [[
		"Ne plus suivre" if following else "Suivre",
		func() -> void: backend.send(ProtocolParty.follow("" if following else name))]]
	if is_leader():
		entries.append(["Passer le commandement", func() -> void: backend.send(ProtocolParty.leader(name))])
		entries.append(["Exclure du groupe", func() -> void: backend.send(ProtocolParty.kick(name))])
	ContextMenu.popup(self, at, name, entries)


func refresh() -> void:
	_box.visible = not party.is_empty()
	for c: Node in _list.get_children():
		_list.remove_child(c)
		c.queue_free()
	_title.text = "Groupe (%d)" % members().size()
	for m: Dictionary in members():
		_list.add_child(_row(m))
	for c: Node in _invites_box.get_children():
		_invites_box.remove_child(c)
		c.queue_free()
	for i: Dictionary in invites:
		_invites_box.add_child(_invite_row(str(i["from"])))
	reset_size.call_deferred()


func _row(m: Dictionary) -> Control:
	var row := PanelContainer.new()
	var leader := str(m["name"]) == str(party.get("leader", ""))
	var followed := str(m["name"]) == str(party.get("follow", ""))
	row.add_theme_stylebox_override("panel", UiStyle.panel(Color(UiStyle.BG_INSET, 0.9), UiStyle.GOLD if leader else UiStyle.BORDER, 4, 4))
	row.gui_input.connect(func(e: InputEvent) -> void:
		if e is InputEventMouseButton and e.pressed:
			member_menu(m, get_viewport().get_mouse_position() if is_inside_tree() else Vector2.ZERO))
	var h := HBoxContainer.new()
	h.add_theme_constant_override("separation", 6)
	h.mouse_filter = Control.MOUSE_FILTER_IGNORE
	row.add_child(h)
	h.add_child(UiStyle.icon(CharacterSelectScreen.symbol_texture(int(m["breed"])), 28, Color.WHITE))
	var col := VBoxContainer.new()
	col.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	col.mouse_filter = Control.MOUSE_FILTER_IGNORE
	col.add_theme_constant_override("separation", 1)
	h.add_child(col)
	var line := "%s%s · niv. %d" % ["★ " if leader else "", str(m["name"]), int(m["level"])]
	if followed:
		line += " (suivi)"
	col.add_child(UiStyle.label(line, UiStyle.GOLD if leader else UiStyle.TEXT, 12))
	var hp := UiBar.new(UiStyle.HP, 10)
	hp.custom_minimum_size = Vector2(120, 10)
	hp.set_values(int(m["hp"]), int(m["max_hp"]), "%d / %d" % [int(m["hp"]), int(m["max_hp"])])
	col.add_child(hp)
	var where := location_text(m, party_map())
	if where != "":
		col.add_child(UiStyle.label(where, UiStyle.TEXT_MUTED, 11))
	return row


## Where a member is when not on our map: "[x, y]", or "en combat".
static func location_text(m: Dictionary, my_map: int) -> String:
	if bool(m.get("fight", false)):
		return "en combat"
	if int(m["map"]) == my_map:
		return ""
	var c: Array = m.get("coords", [])
	return "[%d, %d]" % [int(c[0]), int(c[1])] if c.size() >= 2 else "autre carte"


## Our own map, read from our entry of the party.
func party_map() -> int:
	for m: Dictionary in members():
		if int(m["id"]) == you:
			return int(m["map"])
	return -1


func _invite_row(from: String) -> Control:
	var p := PanelContainer.new()
	p.add_theme_stylebox_override("panel", UiStyle.panel(Color(UiStyle.BG, 0.9), UiStyle.GOLD, 6, 8))
	p.custom_minimum_size = Vector2(WIDTH, 0)
	var v := VBoxContainer.new()
	p.add_child(v)
	var l := UiStyle.label("%s vous invite dans son groupe" % from, UiStyle.TEXT, 13)
	l.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	l.custom_minimum_size = Vector2(WIDTH - 20, 0)
	v.add_child(l)
	var h := HBoxContainer.new()
	h.alignment = BoxContainer.ALIGNMENT_END
	v.add_child(h)
	var no := Button.new()
	no.text = "Refuser"
	no.pressed.connect(func() -> void: decline(from))
	h.add_child(no)
	var yes := Button.new()
	yes.text = "Accepter"
	yes.pressed.connect(func() -> void: accept(from))
	h.add_child(yes)
	return p


## Each frame: an invitation unanswered for a minute disappears (the sim forgot it too).
func _process(_delta: float) -> void:
	var now := Time.get_ticks_msec()
	var kept := invites.filter(func(i: Dictionary) -> bool: return now - int(i["at"]) < INVITE_MS)
	if kept.size() != invites.size():
		invites = kept
		refresh()


## A marker over the sprite of every member on the map (gold for the leader, blue otherwise),
## removed from the others. `views` = ClientSession.views (actor id -> node).
func sync_marks(views: Dictionary) -> void:
	var wanted := {}
	for m: Dictionary in members():
		if int(m["id"]) != you:
			wanted[int(m["id"])] = str(m["name"]) == str(party.get("leader", ""))
	for id: int in views:
		var v: Node = views[id]
		var mark := v.get_node_or_null(MARK)
		if not wanted.has(id):
			if mark != null:
				v.remove_child(mark)
				mark.queue_free()
			continue
		if mark == null:
			mark = Panel.new() # a dot (Polygon2D children are not drawn over an ActorView)
			mark.name = MARK
			mark.position = Vector2(-9, -172)
			mark.custom_minimum_size = Vector2(18, 18)
			mark.size = Vector2(18, 18)
			mark.mouse_filter = Control.MOUSE_FILTER_IGNORE
			v.add_child(mark)
		var color: Color = UiStyle.GOLD if wanted[id] else UiStyle.AP
		var dot := UiStyle.panel(color, Color(0.1, 0.08, 0.05), 9, 0)
		dot.set_border_width_all(3)
		mark.add_theme_stylebox_override("panel", dot)
		mark.set_meta("leader", wanted[id])
