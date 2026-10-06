## Triggered effects (roadmap P1.13b). An effect with `on` (spelllevels effects
## `triggers` other than "I", spells.py) is not applied when the spell is cast: its
## target gets a "trigger" buff lasting `turns` (effectTriggerDuration; -1 = the whole
## fight, the summons' hooks) and the effect fires each time one of its codes happens
## to that fighter, cast by the buff's caster with the holder as its only target (a
## `cast` effect casts its spell on the holder's cell).
## Codes (P1.13i: read in the client's native code, its fight preview, class gzp, which says
## which event lights which code; Core.Features.Fight.Spells.Triggers keeps a spell effect's codes
## as bits (parser grr.blfl: the letters of each "|" part, an unknown one is ignored; EON<n>,
## EK:<mask> keep their number / mask in the string, Triggers.blgb / blfz)):
##   TB / TE: start / end of the holder's turn (JondoEmu docs/disparadores.md: measured on
##   game captures; not in the preview).
##   The holder is hit (gzp.bmzx): D any damage, DN / DE / DF / DW / DA of element 0..4
##   (neutral, earth, fire, water, air), DBA / DBE by a fighter of its team / the other team
##   (the holder itself included), DM / DR at melee range or not (gyp.bmrd; APPROX(P1.13b):
##   distance 1), DS by a spell (not a weapon) and not by a triggered effect (the hit context's
##   parent; APPROX(P1.13i): nor by a poison), DT / DG by a trap's / a glyph's spell (flags of
##   the cast spell). A push into an obstacle is not "D": only PD (gzp.bmzw).
##   The holder does it (gzp.bnaa / bmzz, on the author of the effect): CD, CDN / CDE / CDF /
##   CDW / CDA, CDBA / CDBE, CDM / CDR, CDS, CDT / CDG as above for the damage it deals
##   (APPROX(P1.13i): not for its push damage); CH it heals someone (not with 786 / 1164), CS
##   it gives a shield, CC one of its effects is a critical hit (APPROX(P1.13i): once per
##   critical cast), K it kills a fighter (KWS with a spell, KWW with a weapon: never here),
##   EK:<mask> a fighter the mask accepts (TargetMask, the holder as caster) dies (Triggers.blfz;
##   the spells' texts: "Lorsqu'un combattant allié meurt" for h,m,d).
##   Other events on the holder (gzp.bmzy): H healed (not by a life steal, gzj.bmvy: 82, 91-95,
##   2828, 2890), X death, P pushed / MA attracted (the move's kind, gzw.bnas / bnat), M moved by
##   an effect (P1.13m: the move output's newPosition passes the map's cell check, ezl slot 18 =
##   enq.babz, the one of the T mask: every move here lands on a fight cell; not a filter on the
##   kind), MS swapped (P1.13m: the output has a swappedEntityId), APA / MPA its AP / MP change
##   (characteristics 1 / 23), R its range goes down (19), LPU its vitality goes up (11), EON<n> /
##   EOFF<n> it gets / loses state n, ION / IOFF for the invisible state (250), DIS it is
##   dispelled (P1.13m: a dispel output gzv, effect 132).
##   Life (P1.13m, gzp.bmzy on a damage output gzt whose DamageRange gzd is not empty, before its
##   heal / collision flags are read): V and VA (not permanent) for any hit, push damage, heal or
##   shield it gets; VM / VE for permanent damage (gzt.isPermanentDamage: erosion, never here).
##   Hits (P1.13m, gzp.bmzx): DCAC by a weapon (hv.nhd; DS stays for spells), DCCBA / DCCBE by a
##   fighter of its team / the other one with a critical effect (APPROX(P1.13m): the effect
##   instance's flag hs+0x1c read as "critical" from the codes' names, CC = critical hit), PPD
##   with PD for push damage (PMD needs hs.nes, not read). The author (gzp.bnaa / bmzz): CDCAC
##   rather than CDS for a weapon, CDCCBA / CDCCBE, KWW rather than KWS (a weapon's kill), PO it
##   moves a fighter (any move output of its effect, itself included), CAPA / CMPA it steals AP /
##   MP (84 / 77, a stat output with isSteal), CION / CIOFF it makes someone invisible / visible
##   (APPROX(P1.13m): the client also lights the author's ION / IOFF there; not here).
##   CCMPARR (P1.13e): once per MP the holder uses walking (Fight.move; JondoEmu
##   docs/disparadores.md: measured on a capture; its spells say "pour chaque PM utilisé").
##   APPROX(P1.13e): only walking, not MP lost otherwise. The client does not know this code
##   (it knows CMPARR).
##   P1.13p: XD, XPD, XDM, XDTB, TP, CPD, CMPAS, CAPAS, DTB, DTE (ALIASES below, from the spell texts).
##   Not simulated (spells.py leaves them out, the spell stays partial): CI, CT, DV, CMPDEP,
##   CAP, TR, Y, iQ, il (no source for their meaning), and DI (a fighter flag gyp+0x38 not
##   identified), PMD, PST / PDT (FightState+0x38 in [0, 560)).
## Damage redirections (P1.13e, client enum Metadata.Effect.ActionId), trigger buffs that act on the
## hit itself, before it lands (FightEffects.damage), and never fire on their own:
##   intercept (765 CharacterSacrify): the hit goes to the interceptor instead (Buff.value = its
##            id: the fighter on the spell's target cell, else the caster: Sac Animé, Brise l'Âme's
##            turret, the Sacrieur). APPROX(P1.13e): the amount is not re-reduced by its resistances.
##   share (1061 CharacterShareDamages): the hit is split evenly between the living holders of the
##            same spell from the same caster. APPROX(P1.13e): even split, the remainder on the one hit.
##   heal_attackers (786 CharacterHealAttackers) fires normally: the attacker (Fight.trigger_from)
##            is healed of pct % of the damage (Fight.trigger_amount).
## Multipliers: 1163 "Dommages subis x#1%" and 1159 "Soins reçus x#1%" do not fire: they
## multiply what their holder suffers / receives, after the formula (JondoEmu
## Handlers/FightHandler.cs: "van al final, sobre el daño ya calculado"). APPROX(P1.13b):
## several multipliers multiply each other.
## Hits wait in Fight.hits until `flush` fires their triggers, so the effects come out
## after the hit that caused them. A trigger does not fire again from its own effects
## (APPROX(P1.13b): else "when hit, take 7 more" never ends), and chains stop at depth
## MAX_DEPTH (JondoEmu Managers/EffectEngine.cs HondoMaximo).
class_name FightTriggers
extends RefCounted

const MAX_DEPTH := 4
const PASSIVE := ["taken", "healed", "intercept", "share"]
const ELEMENT_CODE := {"air": "DA", "earth": "DE", "fire": "DF", "water": "DW", "neutral": "DN"}
const INVISIBLE_STATE := 250 # spellstates: the state of 150 "Invisibilité" (gzp.bmzy: ION / IOFF)
## P1.13p: the server's own codes, read from the i18n DESCRIPTION of the class spells that use them
## (the client's preview does not know them). A listener on the key fires when any of the values
## happens. APPROX(P1.13p): the meaning is deduced from the descriptions, not measured on a capture.
##   XD / XPD / XDM / XDTB: always beside D / PD / DM / DTB in the data (Pénitence "si elle subit des
##     dommages", Flibuste "si la cible subit des dommages de poussée", Couronne d'Épines "dommages subis
##     en mêlée"): same event as the code without X.
##   TP: Férocité "si [la cible] est attirée, poussée, transposée, téléportée" = it is moved (M:
##     every move here, push / pull / swap / teleport); the MP-removal attempt is not simulated.
##   CPD: Toupet "retire l'état si la cible attire, repousse, échange de position" = the holder moves
##     a fighter (PO).
##   CMPAS / CAPAS: Ronces Agressives "Vole des PM" = the holder steals MP / AP (CMPA / CAPA).
##   DTB: damage of a poison, which ticks at the start of its target's turn (Distillation "poison Eau
##     de début de tour"). DTE (end of turn) is known but never lit: no poison ticks at the end.
const ALIASES := {"XD": ["D"], "XPD": ["PD"], "XDM": ["DM"], "XDTB": ["DTB"], "TP": ["M"], "CPD": ["PO"],
		"CMPAS": ["CMPA"], "CAPAS": ["CAPA"], "CMPARR": ["CCMPARR"]}
const LIFE := ["V", "VA"] # P1.13m: a life output that is not permanent damage (gzp.bmzy)


## Gives `t` the trigger buff of effect `e` (cast by `caster`, castable `spell_id`). A spell
## stacks its triggers at most spelllevels.maxStack times on one fighter: the oldest goes.
static func add(fight: Fight, caster: Fighter, t: Fighter, e: Dictionary, spell_id: int, max_stack: int, center := -1) -> Array:
	var out: Array = []
	if max_stack > 0:
		var same := t.buffs.filter(func(b: Buff) -> bool: return b.kind == "trigger" and b.spell == spell_id and b.effect == e)
		while same.size() >= max_stack:
			out.append_array(FightEffects.remove_buff(t, same.pop_front()))
	var b := FightEffects._buff(fight, caster, spell_id, "trigger", int(e.get("turns", 1)))
	b.effect = e
	b.on = e.get("on", [])
	b.dispellable = int(e.get("dispellable", 1))
	b.value = int(e.get("pct", 0))
	if str(e.get("kind", "")) == "intercept":
		var on := fight.fighter_at(center) if center >= 0 else null
		b.value = on.id if on != null else caster.id
	out.append(FightEffects._add_buff(t, b))
	return out


## Product of `t`'s multipliers of `kind` ("taken" / "healed"), in %.
static func multiplier(t: Fighter, kind: String) -> float:
	var m := 1.0
	for b: Buff in t.buffs:
		if b.kind == "trigger" and str(b.effect.get("kind", "")) == kind:
			m *= b.value / 100.0
	return m


## The codes of a hit of `caster` (null: no one) on `t` (gzp.bmzx; `fight` null: without
## DS / DT / DG).
static func codes(caster: Fighter, t: Fighter, element: String, fight: Fight = null) -> Array:
	if element == "push":
		return ["PD", "PPD"] + LIFE
	var out: Array = ["D"] + LIFE
	if ELEMENT_CODE.has(element):
		out.append(ELEMENT_CODE[element])
	if caster != null:
		out.append("DBE" if caster.team != t.team else "DBA")
		if fight != null and fight.cast_crit:
			out.append("DCCBE" if caster.team != t.team else "DCCBA")
		out.append("DM" if FightRules.distance(caster.cell, t.cell) <= 1 else "DR")
	if fight != null:
		out.append_array(_source_codes(fight, ""))
		if fight.hit_source == "poison": # P1.13p, Distillation's "poison de début de tour"
			out.append("DTB")
	return out


## DS / DT / DG / DCAC (CDS / CDT / CDG / CDCAC with `prefix` "C"): where the hit comes from.
static func _source_codes(fight: Fight, prefix: String) -> Array:
	var out: Array = []
	if fight.hit_source == "trap":
		out.append(prefix + "DT")
	elif fight.hit_source == "glyph":
		out.append(prefix + "DG")
	if fight.cast_weapon and fight.hit_source == "": # P1.13m, gzp.bmzx / bnaa: hv.nhd, a weapon
		out.append(prefix + "DCAC")
	elif fight.trigger_depth == 0 and fight.hit_source != "poison":
		out.append(prefix + "DS")
	return out


## The codes of the author of a hit (gzp.bnaa / bmzz): CD, its element, CDBA / CDBE...
static func dealer_codes(fight: Fight, caster: Fighter, t: Fighter, element: String) -> Array:
	if element == "push":
		return []
	var out: Array = ["CD"]
	if ELEMENT_CODE.has(element):
		out.append("C" + ELEMENT_CODE[element])
	out.append("CDBE" if caster.team != t.team else "CDBA")
	if fight.cast_crit: # P1.13m, gzp.bmzz
		out.append("CDCCBE" if caster.team != t.team else "CDCCBA")
	out.append("CDM" if FightRules.distance(caster.cell, t.cell) <= 1 else "CDR")
	out.append_array(_source_codes(fight, "C"))
	return out


## `t` lost `amount` HP (before shields) to `caster` (null: no one): queued for `flush`, its
## author's codes too. `t` remembers who hit it last (K).
static func hit(fight: Fight, caster: Fighter, t: Fighter, element: String, amount: int) -> void:
	if caster != null and caster != t:
		t.last_hit_by = caster.id
		t.last_hit_weapon = fight.cast_weapon and fight.hit_source == ""
	if amount > 0:
		fight.hits.append([t, codes(caster, t, element, fight), caster.id if caster != null else -1, amount])
		if caster != null:
			event(fight, caster, dealer_codes(fight, caster, t, element), t.id, amount)


## Something other than a hit happened to `holder` (by fighter `from`): queued for `flush`
## when one of its trigger buffs may listen.
static func event(fight: Fight, holder: Fighter, event_codes: Array, from := -1, amount := 0) -> void:
	if holder != null and not event_codes.is_empty() and holder.buffs.any(func(b: Buff) -> bool: return b.kind == "trigger"):
		fight.hits.append([holder, event_codes, from, amount])


## `t` is being dispelled (P1.13m, 132): its DIS listeners, read before the dispel removes them
## (APPROX(P1.13m): Barricade / Bastion have dispellable 1 on their DIS trigger and say "s'il est
## ... désenvoûté", so the server must read them first). `queue_dispelled` fires them afterwards.
static func dis_listeners(t: Fighter) -> Array:
	return t.buffs.filter(func(b: Buff) -> bool: return b.kind == "trigger" and b.on.has("DIS"))


static func queue_dispelled(fight: Fight, t: Fighter, listeners: Array, from: int) -> void:
	if not listeners.is_empty():
		fight.hits.append([t, ["DIS"], from, 0, listeners])


## `t` got (`on`) or lost state `state`: EON<n> / EOFF<n>, ION / IOFF (invisible); CION on `by`,
## who made it invisible (P1.13m, gzp.bnaa).
static func state_changed(fight: Fight, t: Fighter, state: int, on: bool, by: Fighter = null) -> void:
	var out: Array = [("EON%d" if on else "EOFF%d") % state]
	if state == INVISIBLE_STATE:
		out.append("ION" if on else "IOFF")
		if by != null and on:
			event(fight, by, ["CION"], t.id)
	event(fight, t, out)


## `f` just died: K / KWS on who hit it last, EK:<mask> on everyone whose mask accepts it.
static func died(fight: Fight, f: Fighter) -> Array:
	var out: Array = []
	var killer: Fighter = fight.fighters.get(f.last_hit_by)
	if killer != null and killer.alive and killer != f: # KWW a weapon's hit (P1.13m, gzp.bnaa: hv.nhd)
		out.append_array(fire(fight, killer, ["K", "KWW" if f.last_hit_weapon else "KWS"], f.id))
	for g: Fighter in fight.fighters.values():
		if g.alive and g != f:
			out.append_array(fire(fight, g, ["EK"], f.id))
	return out


## `t`'s trigger buffs of `kind` matching one of `hit_codes`.
static func _redirects(t: Fighter, kind: String, hit_codes: Array) -> Array:
	return t.buffs.filter(func(b: Buff) -> bool:
		return b.kind == "trigger" and str(b.effect.get("kind", "")) == kind \
				and b.on.any(func(c: String) -> bool: return hit_codes.has(c)))


## Who takes a hit meant for `t` (765): its interceptor, or `t`.
static func interceptor(fight: Fight, t: Fighter, hit_codes: Array) -> Fighter:
	for b: Buff in _redirects(t, "intercept", hit_codes):
		var sac: Fighter = fight.fighters.get(b.value)
		if sac != null and sac != t and sac.alive:
			return sac
	return t


## Who shares a hit on `t` (1061): `t` first, then the other holders of the same share.
static func sharers(fight: Fight, t: Fighter, hit_codes: Array) -> Array:
	var out: Array = [t]
	for b: Buff in _redirects(t, "share", hit_codes):
		for f: Fighter in fight.fighters.values():
			if f != t and f.alive and not out.has(f) and f.buffs.any(func(x: Buff) -> bool:
					return x.kind == "trigger" and x.spell == b.spell and x.caster == b.caster \
							and str(x.effect.get("kind", "")) == "share"):
				out.append(f)
	return out


## `t` was healed of `amount` HP by `healer` (CH on it, unless the heal is 786's: `ch` false).
static func healed(fight: Fight, t: Fighter, amount: int, healer: Fighter = null, ch := true) -> void:
	if amount > 0:
		fight.hits.append([t, ["H"] + LIFE, healer.id if healer != null else -1, amount])
		if healer != null and ch:
			event(fight, healer, ["CH"], t.id, amount)


## Fires the triggers of the queued hits (and of the hits they cause).
static func flush(fight: Fight) -> Array:
	var out: Array = []
	while not fight.hits.is_empty():
		var h: Array = fight.hits.pop_front()
		out.append_array(fire(fight, h[0], h[1], int(h[2]), int(h[3]), h[4] if h.size() > 4 else null))
	return out


## A buff's code `c` answers the event `codes` (EK:<mask>: the fighter `from` who died passes the
## mask, the holder as its caster: Triggers.blfz -> gtz.blqi).
static func _matches(fight: Fight, holder: Fighter, c: String, event_codes: Array, from: int) -> bool:
	if c.begins_with("EK:"):
		var dead: Fighter = fight.fighters.get(from)
		return event_codes.has("EK") and dead != null and TargetMask.affects(fight, holder, dead, {"mask": c.substr(3)})
	if ALIASES.has(c):
		return ALIASES[c].any(func(a: String) -> bool: return event_codes.has(a))
	return event_codes.has(c)


## Fires `holder`'s triggers matching one of `codes` (a hit: by fighter `from`, of `amount`);
## `only`: these buffs, even if the holder lost them meanwhile (a dispel's listeners).
static func fire(fight: Fight, holder: Fighter, codes: Array, from := -1, amount := 0, only = null) -> Array:
	var out: Array = []
	if fight.trigger_depth >= MAX_DEPTH:
		fight.hits.clear()
		return out
	fight.trigger_depth += 1
	for b: Buff in (holder.buffs.duplicate() if only == null else only):
		if b.kind != "trigger" or b.busy or str(b.effect.get("kind", "")) in PASSIVE or (only == null and not holder.buffs.has(b)) \
				or not b.on.any(func(c: String) -> bool: return _matches(fight, holder, c, codes, from)):
			continue
		if not holder.alive and not codes.has("X"):
			break
		var caster: Fighter = fight.fighters.get(b.caster)
		if caster == null or not caster.alive:
			continue
		b.busy = true
		var ctx := [fight.trigger_from, fight.trigger_amount]
		fight.trigger_from = from
		fight.trigger_amount = amount
		out.append_array(FightEffects.apply(fight, caster, holder, b.effect, holder.cell, b.spell))
		fight.trigger_from = ctx[0]
		fight.trigger_amount = ctx[1]
		out.append_array(flush(fight))
		b.busy = false
	fight.trigger_depth -= 1
	return out
