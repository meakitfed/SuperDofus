## What the effects do to life (split from FightEffects): damage, steals, heals, kills, poisons.
##   damage = base x (100 + element stat + power) / 100 + damage + element damage, minus the
##            target's fixed element resistance, then x (100 - res%) / 100,
##            absorbed by shields first. Element stats: Fighter.ELEMENT_STAT.
##            Then x (100 + final_damage + combo) / 100 (1171 / 1172 "Dommages finaux", 1027
##            "Dommages Combo" of the bombs, P1.13d). APPROX(P1.13d): applied last, after the
##            resistances; the combo counts like final damage of the fighter holding it.
##            Then x (100 + melee|ranged + spell damage %) x (100 - melee|ranged resistance %), + the
##            target's `dmg_taken` (265, negative), and + `crit_damage` on the base of a critical hit.
##            APPROX(P1.18): the client enum names and i18n texts only, applied multiplicatively after
##            final damage (Dofus 2 order); melee = adjacent.
##   heal   = base x (100 + element stat) / 100 + heals, x (100 + final_heals) / 100 (2971); element
##            "best" (3002) = the caster's highest.
##            A spell projected through portals (P1.13f, FightMarks): both x (100 + bonus) / 100,
##            APPROX(P1.13f): after everything else (the text only says "augmentés").
##            steal = damage, caster heals half.
##   damage `hp_pct` / `per_ap` (P1.17, 1071 / 1132): see `base`.
##   reflect (P1.13o, 107 / 220): fired by a hit, sends a flat damage back to its attacker (APPROX).
## Erosion: `hurt`. Not simulated: chain pushes.
class_name FightLife
extends RefCounted


## Effects that hurt, heal or give back life.
static func apply(fight: Fight, caster: Fighter, t: Fighter, e: Dictionary, kind: String, spell_id: int) -> Array:
	match kind:
		"damage":
			var duration := int(e.get("duration", 0))
			if duration > 0:
				var b := FightBuffs.make(fight, caster, spell_id, "poison", duration)
				b.effect = e
				return [FightBuffs.attach(t, b)]
			return _dealt(fight, damage(fight, caster, t, str(e.get("element", "neutral")), base(fight, e, t, caster), int(e.get("zone_pct", 0))))
		"steal":
			var before := fight.cast_dealt
			var out := damage(fight, caster, t, str(e.get("element", "neutral")), roll(fight, e, caster), int(e.get("zone_pct", 0)))
			_dealt(fight, out)
			var dealt := fight.cast_dealt - before
			if caster.alive:
				var healed := heal_raw(caster, dealt / 2)
				if int(healed["amount"]) > 0: # V / VA, never H (P1.13m, gzp.bmzy; gzj.bmvy)
					FightTriggers.event(fight, caster, FightTriggers.LIFE, caster.id, int(healed["amount"]))
				out.append(healed)
			return out
		"heal_attackers": # 786 (P1.13e): fired by a hit, the attacker heals pct % of it
			var attacker: Fighter = fight.fighters.get(fight.trigger_from)
			if attacker == null or not attacker.alive:
				return []
			return [receive_heal(fight, attacker, fight.trigger_amount * int(e.get("pct", 0)) / 100, caster, false)]
		"reflect": # 107 / 220 (P1.13o): fired by a hit, the attacker takes a flat amount back
			var from: Fighter = fight.fighters.get(fight.trigger_from)
			if from == null or not from.alive or from == t or fight.trigger_amount <= 0:
				return []
			# APPROX(P1.13o): no formula found (luaformulas, client enums, JondoEmu): the amount is
			# the effect's roll (diceNum), plus the holder's `reflect` stat for 107 (boosted), never
			# reduced by the attacker's resistances; it triggers nothing
			var back := roll(fight, e) + (t.stat("reflect") if bool(e.get("boosted", false)) else 0)
			return [hurt(from, back, "neutral")]
		"heal":
			return [heal(fight, caster, t, str(e.get("element", "fire")), roll(fight, e, caster), int(e.get("zone_pct", 0)))]
		"heal_pct":
			return [receive_heal(fight, t, t.max_hp * roll(fight, e) / 100, caster)]
		"transfer_hp": # P1.17b (11), 90 "Transfere #1 a #2% des PV": the caster gives that % of its life
			# APPROX(P1.17b): i18n text only; the caster's current life, the receiver is healed as by any heal
			if t == caster or not caster.alive:
				return []
			var give := mini(caster.hp - 1, caster.hp * roll(fight, e) / 100)
			if give <= 0:
				return []
			caster.hp -= give
			return [{"kind": "damage", "target": caster.id, "element": "neutral", "amount": give, "shield": 0,
					"hp": caster.hp, "died": false}, receive_heal(fight, t, give, caster, false)]
		"heal_dealt": # 2973 "Soin : #1 a #2% des dommages occasionnes": a % of what the caster dealt in this cast
			return [receive_heal(fight, t, fight.cast_dealt * roll(fight, e) / 100, caster, false)]
		"splash_taken": # 1223 "Dommages : #1 a #2% des dommages finaux subis": a % of the hit that fired the trigger
			if fight.trigger_amount <= 0 or t == null or not t.alive:
				return []
			return [hurt(t, fight.trigger_amount * roll(fight, e) / 100, "neutral")]
		"splash_heal": # 2020 (P1.17b 13) "Soin : #1 a #2% des dommages subis". APPROX(P1.17b): i18n text only
			if fight.trigger_amount <= 0 or t == null or not t.alive:
				return []
			return [receive_heal(fight, t, fight.trigger_amount * roll(fight, e) / 100, caster, false)]
	return []


## Adds the damage in `out` to what the caster dealt in this cast (Fight.cast_dealt); returns `out`.
static func _dealt(fight: Fight, out: Array) -> Array:
	for h: Dictionary in out:
		if str(h.get("kind", "")) == "damage":
			fight.cast_dealt += int(h["amount"])
	return out


## The base of a damage effect: its dice, or (P1.17) `hp_pct` % of the target's current life (1071,
## APPROX(P1.17): only the i18n text "#1% PV de la cible", current life, then the usual formula) or
## `per_ap` [ap, damage] (1132 "#2 dommages Eau pour #1 PA utilisé": the target's AP spent this turn).
## `caster_hp_pct` (P1.17b, 8; 89 "#1 à #2% PV du lanceur", APPROX: the caster's current life, dice = the %).
static func base(fight: Fight, e: Dictionary, t: Fighter, caster: Fighter = null) -> int:
	if e.has("caster_hp_pct") and caster != null:
		return caster.hp * roll(fight, e) / 100
	if e.has("caster_missing_pct") and caster != null: # P1.17b (9), 279 "#1 a #2% PV manquants du lanceur"
		return maxi(0, caster.max_hp - caster.hp) * roll(fight, e) / 100
	if e.has("eroded_pct"): # P1.18, 1118 / 1092 "#1 à #2% PV érodés du lanceur / de la cible"
		var who := caster if str(e["eroded_pct"]) == "caster" and caster != null else t
		return who.eroded * roll(fight, e) / 100
	if e.has("mp_left"): # P1.17b (10), 1012-1016 "(% PM restants)": APPROX, the dice x the target's MP left / max
		return roll(fight, e) * t.mp / maxi(1, t.max_mp)
	if e.has("hp_pct"):
		return t.hp * int(e["hp_pct"]) / 100
	if e.has("per_ap"):
		var p: Array = e["per_ap"]
		return int(p[1]) * (t.ap_spent / maxi(1, int(p[0])))
	return roll(fight, e, caster)


## Tirage d'un effet. 782 (`roll_max`) force le maximum, 781 (`roll_min`) le minimum, pour les dommages et soins
## du porteur (P1.17b, APPROX : d'apres les noms de l'enum ActionId seulement ; le maximum l'emporte).
static func roll(fight: Fight, e: Dictionary, bearer: Fighter = null) -> int:
	var lo := int(e.get("min", 0))
	var hi := maxi(lo, int(e.get("max", lo)))
	if bearer != null and bearer.stat("roll_max") > 0:
		return hi
	if bearer != null and bearer.stat("roll_min") > 0:
		return lo
	return fight.rng.randi_range(lo, hi)


## "Meilleur élément" (P1.17b, 2822 / 2828): the element of the caster's highest characteristic
## (strength = earth, intelligence = fire, chance = water, agility = air). APPROX(P1.17b): only the
## i18n text; ties go to earth, fire, water, air; neutral is never chosen.
static func best_element(caster: Fighter) -> String:
	var best := "earth"
	var top := -999999
	for el: String in ["earth", "fire", "water", "air"]:
		var v := caster.stat(Fighter.ELEMENT_STAT[el])
		if v > top:
			top = v
			best = el
	return best


## "Pire element" (P1.17b 9, 2832 "dommages du pire element"): the lowest of the four, same tie order
## as `best_element`. APPROX(P1.17b 9): only the i18n text.
static func worst_element(caster: Fighter) -> String:
	var worst := "earth"
	var low := 999999
	for el: String in ["earth", "fire", "water", "air"]:
		var v := caster.stat(Fighter.ELEMENT_STAT[el])
		if v < low:
			low = v
			worst = el
	return worst


## The hits of `caster` on `t`: `t`'s, or its interceptor's, and its sharers' (P1.13e).
## `zone_pct`: the area decrease (P1.13j), on the caster's side (ra.fay: floor), before resistances.
static func damage(fight: Fight, caster: Fighter, t: Fighter, element: String, base: int, zone_pct := 0) -> Array:
	if element == "best":
		element = best_element(caster)
	elif element == "worst":
		element = worst_element(caster)
	var power := caster.stat(Fighter.ELEMENT_STAT.get(element, "strength")) + caster.stat("power")
	var dmg := base * maxi(0, 100 + power) / 100 + caster.stat("damage") + caster.stat("damage_" + element)
	if fight.cast_crit: # 418 "Dommages Critiques": flat, on a critical hit (P1.18)
		dmg += caster.stat("crit_damage")
	if zone_pct != 0:
		dmg = floori(dmg * (100 - zone_pct) / 100.0)
	dmg = maxi(0, dmg - t.stat("res_fixed_" + element))
	if fight.cast_crit: # P1.17b, 420 "Résistance Critiques": flat, on a critical hit (APPROX, see the header)
		dmg = maxi(0, dmg - t.stat("crit_res"))
	var res := clampi(t.stat("res_" + element), -100, 100)
	dmg = maxi(0, dmg * (100 - res) / 100)
	dmg = maxi(0, dmg * (100 + caster.stat("final_damage") + caster.stat("combo")) / 100)
	dmg = maxi(0, dmg * (100 + dealt_pct(fight, caster, t)) / 100 * (100 - received_pct(caster, t)) / 100)
	dmg = maxi(0, dmg + t.stat("dmg_taken")) # 265 "-#1 dommages reçus" (a negative stat)
	if caster.projecting >= 0:
		dmg = dmg * (100 + caster.projecting) / 100
	if t.has_flag("invulnerable") or caster.has_flag("no_damage"):
		dmg = 0
	dmg = roundi(dmg * FightTriggers.multiplier(t, "taken"))
	# redirections (P1.13e, FightTriggers): an interceptor takes it, sharers split it
	var codes := FightTriggers.codes(caster, t, element)
	t = FightTriggers.interceptor(fight, t, codes)
	var group := FightTriggers.sharers(fight, t, FightTriggers.codes(caster, t, element))
	var out: Array = []
	var part := dmg / group.size()
	for g: Fighter in group:
		var amount := part + (dmg - part * group.size() if g == t else 0)
		FightTriggers.hit(fight, caster, g, element, amount)
		out.append(hurt(g, amount, element))
	return out


## % more damage `caster` deals to `t` (P1.18, 2800 / 2804 / 2812 "#1% Dommages mêlée / distance / aux sorts":
## a spell's, not a weapon's). Melee = next to it (as the trigger code DM).
static func dealt_pct(fight: Fight, caster: Fighter, t: Fighter) -> int:
	var melee := FightRules.distance(caster.cell, t.cell) <= 1
	return caster.stat("melee_damage" if melee else "ranged_damage") + (0 if fight.cast_weapon else caster.stat("spell_damage"))


## % less damage `t` takes from `caster` (P1.18, 2803 / 2807 "#1% Résistance mêlée / distance", 2802 / 2806 the maluses).
static func received_pct(caster: Fighter, t: Fighter) -> int:
	return clampi(t.stat("melee_res" if FightRules.distance(caster.cell, t.cell) <= 1 else "ranged_res"), -100, 100)


## `t` dies at once (a summon replaced, or dying with its summoner).
static func kill(t: Fighter) -> Dictionary:
	var amount := t.hp
	t.hp = 0
	t.alive = false
	return {"kind": "damage", "target": t.id, "element": "neutral", "amount": amount, "shield": 0, "hp": 0, "died": true}


## Takes `dmg` HP from `t` (shields first).
static func hurt(t: Fighter, dmg: int, element: String) -> Dictionary:
	var absorbed := 0
	for b: Buff in t.buffs:
		if b.kind == "shield" and dmg > 0:
			var a := mini(b.value, dmg)
			b.value -= a
			dmg -= a
			absorbed += a
	t.buffs = t.buffs.filter(func(b: Buff) -> bool: return b.kind != "shield" or b.value > 0)
	dmg = mini(dmg, t.hp)
	t.hp -= dmg
	# Erosion (P1.14): a share of the HP lost (not the shield) also lowers max HP until the fight ends.
	# APPROX(P1.14): base 10 % + stat `erosion` (776), capped at 50 %: community values; no formula in
	# luaformulas or the client tables (documented, pinned by tests/test_formulas.gd EROSION_CASES).
	var eroded := 0
	if dmg > 0 and t.hp > 0:
		var pct := clampi(10 + t.stat("erosion"), 0, 50)
		eroded = mini(dmg * pct / 100, t.max_hp - 1)
		t.max_hp -= eroded
		t.eroded += eroded
		t.hp = mini(t.hp, t.max_hp)
	if t.hp <= 0:
		t.alive = false
	return {"kind": "damage", "target": t.id, "element": element, "amount": dmg, "shield": absorbed,
			"hp": t.hp, "died": not t.alive, "max_hp": t.max_hp, "eroded": eroded}


static func heal(fight: Fight, caster: Fighter, t: Fighter, element: String, base: int, zone_pct := 0) -> Dictionary:
	if element == "best": # 3002 (P1.17b 7)
		element = best_element(caster)
	var stat := caster.stat(Fighter.ELEMENT_STAT.get(element, "intelligence"))
	var amount := base * maxi(0, 100 + stat) / 100 + caster.stat("heals")
	if zone_pct != 0: # P1.13j, as for damage
		amount = floori(amount * (100 - zone_pct) / 100.0)
	amount = maxi(0, amount * (100 + caster.stat("final_heals")) / 100)
	if caster.projecting >= 0:
		amount = amount * (100 + caster.projecting) / 100
	return receive_heal(fight, t, amount, caster)


## `t` receives a heal of `amount` from `healer`: incurable, heal multipliers, H triggers (CH on
## the healer unless `ch` is false).
static func receive_heal(fight: Fight, t: Fighter, amount: int, healer: Fighter = null, ch := true) -> Dictionary:
	if t.has_flag("incurable"):
		amount = 0
	var out := heal_raw(t, roundi(amount * FightTriggers.multiplier(t, "healed")))
	FightTriggers.healed(fight, t, int(out["amount"]), healer, ch)
	return out


static func heal_raw(t: Fighter, amount: int) -> Dictionary:
	amount = clampi(amount, 0, t.max_hp - t.hp)
	t.hp += amount
	return {"kind": "heal", "target": t.id, "amount": amount, "hp": t.hp}


## A poison ticking at the start of its target's turn.
static func poison(fight: Fight, t: Fighter, b: Buff) -> Array:
	var caster: Fighter = fight.fighters.get(b.caster, t)
	fight.hit_source = "poison"
	var out := damage(fight, caster, t, str(b.effect.get("element", "neutral")), roll(fight, b.effect))
	fight.hit_source = ""
	return out
