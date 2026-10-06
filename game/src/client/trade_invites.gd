## The trade invitations received (P3.11b), under the group frame: one card per inviter with
## Accepter / Refuser, like PartyFrame. The list lives in the TradeModel of the trade window; an
## invitation unanswered for a minute disappears (the sim forgot it too).
class_name TradeInvites
extends VBoxContainer

const WIDTH := 250

var backend: GameBackend
var window: TradeWindow


func setup(p_backend: GameBackend, p_window: TradeWindow) -> void:
	backend = p_backend
	window = p_window
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_theme_constant_override("separation", 4)


func accept(from: String) -> void:
	window.model.forget_invite(from)
	backend.send(ProtocolTrade.accept(from))
	refresh()


func decline(from: String) -> void:
	window.model.forget_invite(from)
	backend.send(ProtocolTrade.decline(from))
	refresh()


func refresh() -> void:
	for c: Node in get_children():
		remove_child(c)
		c.queue_free()
	for i: Dictionary in window.model.invites:
		add_child(_card(str(i["from"])))
	reset_size.call_deferred()


func _card(from: String) -> Control:
	var p := PanelContainer.new()
	p.add_theme_stylebox_override("panel", UiStyle.panel(Color(UiStyle.BG, 0.9), UiStyle.GOLD, 6, 8))
	p.custom_minimum_size = Vector2(WIDTH, 0)
	var v := VBoxContainer.new()
	p.add_child(v)
	var l := UiStyle.label("%s vous propose un échange" % from, UiStyle.TEXT, 13)
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


func _process(_delta: float) -> void:
	if window != null and window.model.expire(Time.get_ticks_msec()):
		refresh()
