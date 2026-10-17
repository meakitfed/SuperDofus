## The family of a monster (H.04): how its spells make it play (FightAI.profile), or "passive" when it
## has none. Each family has its own expectation in the monster matrix (MonsterMatrix.family_errors).
class_name MonsterFamily
extends RefCounted

const PASSIVE := "passive" # no spell at all: it only walks
const MELEE := FightAI.AGGRESSIVE # hits from where it reaches (corps a corps)
const SHOOTER := FightAI.CAUTIOUS # tireur: only ranged hits, keeps its distance
const HEALER := FightAI.HEALER
const SUMMONER := FightAI.SUMMONER # invocateur
const BOMB := FightAI.KAMIKAZE # bombe: its spell kills itself
const ALL := [PASSIVE, MELEE, SHOOTER, HEALER, SUMMONER, BOMB]


static func of(f: Fighter) -> String:
	if f.spells.is_empty():
		return PASSIVE
	return FightAI.profile(f)
