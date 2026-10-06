## Real-world date for rules that depend on it (marketplace expiry, almanax,
## events, "saved_at"). The sim's own game time is WorldSim.now, advanced by
## tick(); this clock only answers "what date is it". This base class is a
## manual clock (tests, replays: deterministic); SystemClock (api/) reads the
## computer's clock. The sim must never read Time/OS directly.
class_name Clock
extends RefCounted

var unix_ms := 0


func _init(p_unix_ms := 0) -> void:
	unix_ms = p_unix_ms


func now_unix_ms() -> int:
	return unix_ms


## Called by the host (LocalServer.tick) so that a manual clock follows game time.
func advance(delta_ms: int) -> void:
	unix_ms += delta_ms
