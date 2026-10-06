## One open trade between two players (P3.11): who, their offers and their validations.
## Pure state (the rules are in shared/TradeRules, the flow and the messages in WorldTrade).
## Players are identified by character name. Any change of an offer cancels both validations.
class_name TradeSession
extends RefCounted

var a := ""
var b := ""
## name -> {items: {uid: qty}, kamas}
var offers := {}
## name -> bool
var ready := {}


static func create(p_a: String, p_b: String) -> TradeSession:
	var s := TradeSession.new()
	s.a = p_a
	s.b = p_b
	for n: String in [p_a, p_b]:
		s.offers[n] = {"items": {}, "kamas": 0}
		s.ready[n] = false
	return s


func other(name: String) -> String:
	return b if name == a else a


func set_offer(name: String, items: Dictionary, kamas: int) -> void:
	offers[name] = {"items": items.duplicate(), "kamas": kamas}
	ready[a] = false
	ready[b] = false


func items_of(name: String) -> Dictionary:
	return offers[name]["items"]


func kamas_of(name: String) -> int:
	return int(offers[name]["kamas"])


func both_ready() -> bool:
	return bool(ready[a]) and bool(ready[b])
