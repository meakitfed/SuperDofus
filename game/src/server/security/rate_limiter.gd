## A token bucket (roadmap S.05): `capacity` tokens at most, `rate` tokens per second. `take`
## spends one and says whether there was one. Time is given by the caller (ms of the host clock),
## so the tests drive it without waiting. Not used by sim/, shared/ or client/.
class_name RateLimiter
extends RefCounted

var capacity := 1.0
var rate := 1.0
var _tokens := 1.0
var _last_ms := -1


func _init(p_capacity: float, p_rate: float) -> void:
	capacity = p_capacity
	rate = p_rate
	_tokens = p_capacity


func take(now_ms: int, cost := 1.0) -> bool:
	if _last_ms >= 0 and now_ms > _last_ms:
		_tokens = minf(capacity, _tokens + float(now_ms - _last_ms) * rate / 1000.0)
	_last_ms = now_ms
	if _tokens < cost:
		return false
	_tokens -= cost
	return true


func tokens() -> float:
	return _tokens
