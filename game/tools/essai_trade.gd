## The trade part of the server trial (P3.11, tools/essai_serveur.gd): two accounts trade an
## item and kamas through the real server, then a cancelled trade and an absent partner.
## `e` is the trial script: its two peers (`_a` is the game master), `_pump` and `_ok`.
class_name EssaiTrade
extends RefCounted

const POTION := 683

var e: Object


func _init(p_trial: Object) -> void:
	e = p_trial


func run() -> void:
	e._a.clear()
	e._b.clear()
	e._a.send(Protocol.admin_cmd("give", [POTION, 3]))
	e._a.send(Protocol.admin_cmd("kamas", [500]))
	await e._pump(2.0)
	var uid: int = e._a.item_of(POTION)
	var kamas_a: int = e._a.kamas
	var kamas_b: int = e._b.kamas
	e._a.clear()
	e._b.clear()
	e._a.send(ProtocolTrade.invite(e._b.name))
	await e._pump(3.0, func() -> bool: return e._b.has(ProtocolTrade.INVITED))
	e._ok("échange : invitation reçue", e._b.has(ProtocolTrade.INVITED), "erreurs A %s" % [e._a.errors()])
	e._b.send(ProtocolTrade.accept(e._a.name))
	await e._pump(3.0, func() -> bool: return e._a.has(ProtocolTrade.OPEN) and e._b.has(ProtocolTrade.OPEN))
	e._ok("échange : fenêtre ouverte chez les deux", e._a.has(ProtocolTrade.OPEN) and e._b.has(ProtocolTrade.OPEN), "erreurs B %s" % [e._b.errors()])
	e._a.send(ProtocolTrade.set_offer([{"uid": uid, "qty": 2}], 100))
	await e._pump(3.0, func() -> bool: return e._b.of(ProtocolTrade.UPDATE).any(func(u: Dictionary) -> bool: return int(u["theirs"]["kamas"]) == 100))
	var theirs: Dictionary = e._b.last(ProtocolTrade.UPDATE).get("theirs", {})
	e._ok("échange : l'offre est vue par l'autre", int(theirs.get("kamas", -1)) == 100 and (theirs.get("items", []) as Array).size() == 1,
			"vu %s ; erreurs A %s" % [theirs, e._a.errors()])
	e._a.send(ProtocolTrade.ready())
	await e._pump(1.0)
	e._b.send(ProtocolTrade.ready())
	await e._pump(3.0, func() -> bool: return e._a.has(ProtocolTrade.END) and e._b.has(ProtocolTrade.END))
	var done := str(e._a.last(ProtocolTrade.END).get("reason", "")) == "done" and str(e._b.last(ProtocolTrade.END).get("reason", "")) == "done"
	await e._pump(1.0)
	e._ok("échange : double validation, objets et kamas échangés", done and e._b.item_of(POTION) > 0 and e._a.kamas == kamas_a - 100 and e._b.kamas == kamas_b + 100,
			"fin %s ; kamas A %d->%d B %d->%d ; erreurs %s %s" % [done, kamas_a, e._a.kamas, kamas_b, e._b.kamas, e._a.errors(), e._b.errors()])
	e._a.clear()
	e._b.clear()
	e._a.send(ProtocolTrade.invite(e._b.name))
	await e._pump(2.0, func() -> bool: return e._b.has(ProtocolTrade.INVITED))
	e._b.send(ProtocolTrade.accept(e._a.name))
	await e._pump(2.0, func() -> bool: return e._a.has(ProtocolTrade.OPEN))
	e._b.send(ProtocolTrade.cancel())
	await e._pump(3.0, func() -> bool: return e._a.has(ProtocolTrade.END))
	e._ok("échange : annulation par l'un des deux", str(e._a.last(ProtocolTrade.END).get("reason", "")) == "cancelled", "erreurs %s" % [e._a.errors()])
	e._a.clear()
	e._a.send(ProtocolTrade.invite("personne_xyz"))
	await e._pump(2.0, func() -> bool: return e._a.has(Protocol.ERROR))
	e._ok("échange : inviter un absent refusé", e._a.has_error("player_offline"), "erreurs %s" % [e._a.errors()])

