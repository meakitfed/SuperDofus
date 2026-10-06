## Carry and throw (P1.12): effects 50 "Porte la cible" and 51 "Lance une entité"
## (effects table), the Pandawa's Karcham / Chamrak and its throws.
##   carry: the target (next to the caster: spell range 1) goes onto the caster's
##          cell; the caster gets state 3 "Porteur", the target state 8 "Porté"
##          (the effect's `states`, spellstates: Porteur preventsSpellCast, the
##          throws need it, statesCriterion HS=3). Not on a fighter that is
##          carrying or carried, stabilised (cant_be_moved) or rooted / heavy
##          (cant_switch: spellstates.cantSwitchPosition, Enraciné, Pesanteur).
##   the carried entity follows its carrier (moves, pushes, teleports: follow()).
##   throw: the carried entity lands on the target cell (FightRules.for_caster:
##          a free cell), both states end. The spell's effects marked `carried`
##          (targetMask K) touch it alone, the others the fighters around.
##   drop:  the carrier dies (or the carried entity dies): the other one is freed
##          on the cell. APPROX(P1.12): a carried fighter that walks away frees
##          itself (Dofus 2 behaviour, not in the client data).
## A carried fighter is not on the board for fighter_at (a spell's target cell, a
## free cell). Areas (P1.13l, FightEffects.targets): it is on its carrier's cell
## and touched only by zones with zoneDescr.includeCarried (every point, a few
## circles: client code gtz.nhs, FightRules.touches_carried).
class_name Carry
extends RefCounted


static func apply(fight: Fight, caster: Fighter, e: Dictionary, center: int, spell_id: int) -> Array:
	var t := fight.fighter_at(center)
	if t == null or t == caster or caster.carrying != -1 or t.carrying != -1 or t.carried_by != -1 \
			or t.has_flag("cant_be_moved") or t.has_flag("cant_switch"):
		return []
	var from := t.cell
	t.cell = caster.cell
	t.carried_by = caster.id
	caster.carrying = t.id
	var out: Array = [{"kind": "carry", "target": t.id, "carrier": caster.id, "from": from}]
	for s: Dictionary in e.get("states", []):
		var who := caster if str(s.get("who", "")) == "caster" else t
		out.append(FightEffects.add_state(fight, caster, who, s, -1, spell_id))
	return out


static func throw(fight: Fight, caster: Fighter, center: int) -> Array:
	var t: Fighter = fight.fighters.get(caster.carrying)
	if t == null or not fight.map.is_fight_walkable(center) or fight.fighter_at(center) != null:
		return []
	var out := _free(fight, caster, t)
	t.cell = center
	fight.log_cast(t, "moved", caster.id) # gzw.throwerEntityId (TargetMask K)
	out.push_front({"kind": "throw", "target": t.id, "carrier": caster.id, "from": caster.cell, "to": center})
	return out


## `f` walked, was pushed or teleported: its carried entity comes along.
static func follow(fight: Fight, f: Fighter) -> void:
	var t: Fighter = fight.fighters.get(f.carrying)
	if t != null:
		t.cell = f.cell


## Frees the carrier / carried pair `f` belongs to, if any (death, a carried
## fighter walking away). Returns the effects (drop, the states ending).
static func release(fight: Fight, f: Fighter) -> Array:
	var carrier: Fighter = f if f.carrying != -1 else fight.fighters.get(f.carried_by)
	if carrier == null or carrier.carrying == -1:
		return []
	var t: Fighter = fight.fighters[carrier.carrying]
	var out := _free(fight, carrier, t)
	out.push_front({"kind": "drop", "target": t.id, "carrier": carrier.id, "cell": t.cell})
	return out


static func _free(fight: Fight, carrier: Fighter, t: Fighter) -> Array:
	carrier.carrying = -1
	t.carried_by = -1
	t.cell = carrier.cell
	var out: Array = []
	for s in [FightRules.CARRIER_STATE, FightRules.CARRIED_STATE]:
		out.append_array(FightEffects.remove_state(carrier, s, fight))
		out.append_array(FightEffects.remove_state(t, s, fight))
	return out
