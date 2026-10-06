## THE boundary between the client and the game logic. The client only ever:
##   - sends commands:        backend.send(Protocol.move(cell))
##   - receives events:       backend.event signal (emitted from poll)
##   - reads the game clock:  backend.time_ms()  (to interpolate movements)
## Implementations: LocalBackend (standalone, sim embedded) and, later,
## a RemoteBackend (WebSocket + JSON, same messages). Nothing else may change.
class_name GameBackend
extends RefCounted

signal event(ev: Dictionary)

var _seq := 0


func send(_cmd: Dictionary) -> void:
	pass


## Call once per frame: advances / receives, then emits queued events.
func poll(_delta: float) -> void:
	pass


## Current game time in ms, on the same clock as the `t0` of movements.
func time_ms() -> int:
	return 0


func close() -> void:
	pass


## Numbers an outgoing command (Protocol envelope `seq`); errors it causes
## come back with `ref` = this number.
func _stamp(cmd: Dictionary) -> Dictionary:
	_seq += 1
	var out := cmd.duplicate()
	out["seq"] = _seq
	return out
