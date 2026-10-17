## The challenges received (P3.10), under the group frame: one card per challenger with
## Accepter / Refuser, like TradeInvites. A challenge unanswered for a minute disappears (the sim
## forgot it too). Accepting starts the fight: the sim sends fight_start.
class_name DuelInvites
extends VBoxContainer

const WIDTH := 250

var backend: GameBackend
var model := DuelModel.new()


func setup(p_backend: GameBackend) -> void:
	backend = p_backend
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_theme_constant_override("separation", 4)


## duel_requested (a card appears) / duel_end (our own challenge was declined or expired).
func on_event(t: String, ev: Dictionary, toast: Toast) -> void:
	match t:
		ProtocolDuel.REQUESTED:
			model.apply_requested(str(ev["from"]), Time.get_ticks_msec())
			toast.show_text("%s vous défie" % str(ev["from"]), UiStyle.GOLD)
			refresh()
		ProtocolDuel.END:
			toast.show_text(DuelModel.end_text(str(ev["reason"])), UiStyle.TEXT_MUTED)


## Sent by the card buttons.
func accept(from: String) -> void:
	model.forget(from)
	backend.send(ProtocolDuel.accept(from))
	refresh()


func decline(from: String) -> void:
	model.forget(from)
	backend.send(ProtocolDuel.decline(from))
	refresh()


## A fight (any) starts: the pending cards are moot for now.
func clear() -> void:
	model.invites.clear()
	refresh()


func refresh() -> void:
	for c: Node in get_children():
		remove_child(c)
		c.queue_free()
	for i: Dictionary in model.invites:
		add_child(_card(str(i["from"])))
	reset_size.call_deferred()


func _card(from: String) -> Control:
	var p := PanelContainer.new()
	p.add_theme_stylebox_override("panel", UiStyle.panel(Color(UiStyle.BG, 0.9), UiStyle.BAD, 6, 8))
	p.custom_minimum_size = Vector2(WIDTH, 0)
	var v := VBoxContainer.new()
	p.add_child(v)
	var l := UiStyle.label("%s vous défie en duel" % from, UiStyle.TEXT, 13)
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
	if model.expire(Time.get_ticks_msec()):
		refresh()
