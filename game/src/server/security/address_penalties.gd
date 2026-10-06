## Automatic sanction of an address (roadmap S.05c): every time the host has to cut a connection
## of an address (rate limit, too many bad passwords) it calls `cut`; an address cut `max_cuts`
## times within `window_ms` is banned for `ban_ms` (the host then refuses its connections).
## Time is given by the caller (ms of the host clock), so tests drive it without waiting.
## APPROX(S.05c): 3 cuts in 10 min = 10 min of ban, values without a source. Nothing here
## knows which game a world runs.
class_name AddressPenalties
extends RefCounted

var max_cuts := 3
var window_ms := 10 * 60 * 1000
var ban_ms := 10 * 60 * 1000
## 0 = never ban (tools, tests that cut on purpose)
var enabled := true

var _cuts := {}   # address -> Array of cut times (ms)
var _banned := {} # address -> end of the ban (ms)
## addresses banned since the start, for logs and tests
var bans := 0


## The address was cut at `now_ms`; true if that bans it.
func cut(address: String, now_ms: int) -> bool:
	if not enabled or max_cuts <= 0:
		return false
	if _cuts.size() > 4096: # forget what is old
		_forget(now_ms)
	var times: Array = _cuts.get(address, [])
	times = times.filter(func(t: int) -> bool: return now_ms - t < window_ms)
	times.append(now_ms)
	_cuts[address] = times
	if times.size() < max_cuts:
		return false
	_cuts.erase(address)
	_banned[address] = now_ms + ban_ms
	bans += 1
	return true


func is_banned(address: String, now_ms: int) -> bool:
	if not _banned.has(address):
		return false
	if now_ms >= int(_banned[address]):
		_banned.erase(address)
		return false
	return true


## Lifts the ban and the count of an address (a GM, a test).
func clear(address: String) -> void:
	_banned.erase(address)
	_cuts.erase(address)


## Addresses banned right now, sorted.
func banned(now_ms: int) -> PackedStringArray:
	var out := PackedStringArray()
	for a: String in _banned.keys():
		if is_banned(a, now_ms):
			out.append(a)
	out.sort()
	return out


func _forget(now_ms: int) -> void:
	for a: String in _cuts.keys():
		var times: Array = _cuts[a]
		if times.is_empty() or now_ms - int(times[-1]) >= window_ms:
			_cuts.erase(a)
