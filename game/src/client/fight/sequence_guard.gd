## Bookkeeping of the visual sequences of a fight (FightView): the events that follow an animated one
## wait for it. If it never ends (an error in an `await` chain, a tween that never finishes), every
## later event is blocked and the enemies seem to stop playing: `expired` gives up on it after
## TIMEOUT_MS, and the token of the abandoned sequence is then ignored by `finish`.
class_name SequenceGuard
extends RefCounted

const TIMEOUT_MS := 15000

var running := 0
var epoch := 0
var _started_ms := 0


## A sequence starts; returns its token.
func begin(ticks_ms: int) -> int:
	running += 1
	_started_ms = ticks_ms
	return epoch


## The sequence of `token` ends. False if it was already given up on (do not signal it again).
func finish(token: int) -> bool:
	if token != epoch:
		return false
	running = maxi(0, running - 1)
	return true


## True (once) when the running sequence lasted too long: it is declared over.
func expired(ticks_ms: int) -> bool:
	if running <= 0 or ticks_ms - _started_ms < TIMEOUT_MS:
		return false
	epoch += 1
	running = 0
	return true
