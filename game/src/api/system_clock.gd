## The computer's real clock (standalone game, server).
class_name SystemClock
extends Clock


func now_unix_ms() -> int:
	return int(Time.get_unix_time_from_system() * 1000.0)


func advance(_delta_ms: int) -> void:
	pass
