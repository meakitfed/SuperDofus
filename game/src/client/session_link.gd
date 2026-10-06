## The connection side of a ClientSession (S.02c, split from client_session.gd): the events that
## are about the link to the server, not about the game. net_reconnecting (NetBackend lost the
## connection and tries again) shows the banner; resume_ok (the server gave the session back) removes
## it and clears what the client believed (fight, windows) because the server replays the state
## as for a fresh connection; a refused token or the end of the link (kick, replaced) goes back to the
## launch screen with the reason when the session was started from it (`back_to_launch`).
class_name SessionLink
extends RefCounted

var banner := ReconnectBanner.new()
## zones on demand of a big world (C.02d), null for a world that is complete (solo, small worlds)
var zones: ZoneGate
var _s: ClientSession


func _init(session: ClientSession) -> void:
	_s = session
	zones = session.zone_gate
	if zones != null:
		session._hud_layer.add_child(zones)
		zones.zone_ready.connect(session._on_sequence_done)
		zones.class_installed.connect(_on_class_installed)
		zones.equipment_installed.connect(_on_equipment_installed)


## C.02e: the files of a class arrived after its players were drawn: their views start again.
func _on_class_installed(breed: int) -> void:
	for v: Variant in _s.views.values():
		if v is ActorView and int((v as ActorView).get_meta("breed", 0)) == breed:
			(v as ActorView).set_look((v as ActorView).sprite.look_string)


## C.02g: the skins of the items arrived after the players wearing them were drawn: their views start again.
func _on_equipment_installed() -> void:
	for v: Variant in _s.views.values():
		if v is ActorView and int((v as ActorView).get_meta("breed", 0)) > 0:
			(v as ActorView).set_look((v as ActorView).sprite.look_string)


## Applies the event if it is about the link; true when it was.
func handle(t: String, ev: Dictionary) -> bool:
	if zones != null and (t == Protocol.ACTOR_ADD or t == Protocol.ACTOR_LOOK or t == Protocol.MAP_ENTER):
		zones.observe(ev)
	if (t == Protocol.MAP_ENTER or t == Protocol.CHARACTERS) and zones != null and not zones.admit(ev):
		_s._queue.push_front(ev) # the zone is downloading: the same event is shown when it is there
		_s._blocked = true
		return true
	match t:
		ProtocolResume.NET_RECONNECTING:
			banner.wait(int(ev["attempt"]), int(ev["delay_ms"]))
			return true
		ProtocolResume.RESUME_OK:
			banner.clear()
			_forget_state()
			_s.toast.show_text("Reconnecté", UiStyle.GOOD)
			return true
		Protocol.LOGIN_ERROR:
			_leave(ErrorTexts.text(ev))
			return true
		Protocol.ERROR:
			if str(ev.get("code", "")) != Protocol.E_NETWORK:
				return false
			banner.clear()
			_leave(ErrorTexts.text(ev))
			return true
	return false


## What the server is about to replay: the current fight, the open windows.
func _forget_state() -> void:
	if _s.fight != null:
		_s.fight.close()
		_s.fight = null
		_s._actors.visible = true
	_s._pending.clear()
	var hud := _s.player_hud
	hud.dialog.end_dialog()
	hud.shop.end_shop()
	hud.bank.end_bank()
	hud.craft.end_craft()


func _leave(text: String) -> void:
	if not _s.back_to_launch:
		_s.toast.show_text(text, UiStyle.BAD)
		return
	var launch: LaunchScreen = (load("res://scenes/client/launch.tscn") as PackedScene).instantiate()
	launch.notice = text
	_s.get_parent().add_child(launch)
	_s.queue_free()
