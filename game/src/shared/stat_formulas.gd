## Characteristics rules (roadmap P1.04), the one source used by the persistent
## Character (out of fight, characteristics window) and by the Fighter (fight):
## capital cost of the characteristics by tier (breeds.statsPointsFor*), HP, AP,
## MP and the derived characteristics (initiative, prospecting, pods, tackle,
## escape, AP/MP dodge and removal).
## `s` is a Callable (stat name -> int) giving the characteristics to use: the
## character's base ones, or a fighter's with its buffs.
class_name StatFormulas
extends RefCounted

## the characteristics the capital can raise (breeds.statsPointsFor<Stat>)
const BOOSTABLE := ["vitality", "wisdom", "strength", "intelligence", "chance", "agility"]
const BASE_HP := 50
const HP_PER_LEVEL := 5
## APPROX(P1.04): base pods, strength bonus and base summons/crit are the
## community-known Dofus values, not in the client data
const BASE_PODS := 1000
const PODS_PER_STRENGTH := 5
const BASE_SUMMONS := 1
const BASE_PROSPECTING := 100


## [[from base value, capital per point], ...] of a breed (breeds.statsPointsFor<Stat>:
## all classes: 1 per point up to 99, then 2, 3, 4 from 100 / 200 / 300; vitality 1; wisdom 3).
static func tiers(breed: int, stat: String) -> Array:
	var row := GameData.row("breeds", breed)
	var raw: Array = row.get("statsPointsFor" + stat.capitalize(), [])
	var out: Array = raw.map(func(t: Dictionary) -> Array: return [int(t["values"][0]), int(t["values"][1])])
	if out.is_empty(): # no table (hand-made tests): the Dofus defaults
		out = [[0, 3]] if stat == "wisdom" else [[0, 1]]
	return out


## Capital needed for the next point when the base value is `base`.
static func point_cost(breed: int, stat: String, base: int) -> int:
	var cost := 1
	for t: Array in tiers(breed, stat):
		if base >= int(t[0]):
			cost = int(t[1])
	return cost


## Spending at most `capital` on `stat` from `base`: [points gained, capital spent]
## (points are bought one by one at their tier's cost, the rest is kept).
static func boost(breed: int, stat: String, base: int, capital: int) -> Array:
	var points := 0
	var spent := 0
	while spent + point_cost(breed, stat, base + points) <= capital:
		spent += point_cost(breed, stat, base + points)
		points += 1
	return [points, spent]


## Capital spent to raise `stat` from 0 to `base` (what a reset gives back).
static func capital_for(breed: int, stat: String, base: int) -> int:
	var total := 0
	for v in maxi(0, base):
		total += point_cost(breed, stat, v)
	return total


## HP = 50 + 5 × level + vitality (Dofus 2/3: 55 HP at level 1).
static func max_hp(level: int, vitality: int) -> int:
	return BASE_HP + HP_PER_LEVEL * level + vitality


## 6 AP, 7 from level 100 (Dofus); 3 MP.
static func max_ap(level: int) -> int:
	return 6 if level < 100 else 7


static func max_mp(_level: int) -> int:
	return 3


## Initiative: the four element characteristics + initiative bonus, weighted by
## the HP left (Dofus). APPROX(P1.04): community formula, not in the client data.
static func initiative(s: Callable, hp: int, hp_max: int) -> int:
	var base := 100 + int(s.call("strength")) + int(s.call("intelligence")) \
			+ int(s.call("chance")) + int(s.call("agility")) + int(s.call("initiative"))
	return int(base * float(hp) / maxf(1.0, hp_max))


## Tackle (blocks the adjacent enemies) and escape: agility / 10 + bonus.
## APPROX(P1.04): community formula
static func tackle(s: Callable) -> int:
	return maxi(0, int(s.call("agility")) / 10 + int(s.call("tackle")))


static func escape(s: Callable) -> int:
	return maxi(0, int(s.call("agility")) / 10 + int(s.call("escape")))


## AP / MP removal and dodge: wisdom / 10 + bonus. APPROX(P1.04): community formula
static func ap_attack(s: Callable) -> int:
	return maxi(0, int(s.call("wisdom")) / 10 + int(s.call("ap_attack")))


static func mp_attack(s: Callable) -> int:
	return maxi(0, int(s.call("wisdom")) / 10 + int(s.call("mp_attack")))


static func ap_dodge(s: Callable) -> int:
	return maxi(0, int(s.call("wisdom")) / 10 + int(s.call("ap_dodge")))


static func mp_dodge(s: Callable) -> int:
	return maxi(0, int(s.call("wisdom")) / 10 + int(s.call("mp_dodge")))


## Prospecting: 100 + chance / 10 + bonus. APPROX(P1.04): community formula
static func prospecting(s: Callable) -> int:
	return BASE_PROSPECTING + maxi(0, int(s.call("chance"))) / 10 + int(s.call("prospecting"))


## Pods: base + 5 × strength + the jobs' part (luaformulas 46: 12 pods per job
## level earned, one less every 200 levels) + bonus.
static func pods(s: Callable, job_levels := 0) -> int:
	return BASE_PODS + PODS_PER_STRENGTH * maxi(0, int(s.call("strength"))) + job_pods(job_levels) + int(s.call("pods"))


## luaformulas 46 (sum_of_jobs_earned_levels -> weight).
static func job_pods(levels: int) -> int:
	var cw := 0
	var per := 12
	for i in range(1, levels + 1):
		cw += per
		if i % 200 == 0 and per > 1:
			per -= 1
	return cw


## Everything the characteristics window shows besides the six characteristics
## (keys = Fighter stat names).
static func derived(s: Callable, hp: int, hp_max: int) -> Dictionary:
	return {"initiative": initiative(s, hp, hp_max), "prospecting": prospecting(s), "pods": pods(s),
			"tackle": tackle(s), "escape": escape(s), "ap_attack": ap_attack(s), "mp_attack": mp_attack(s),
			"ap_dodge": ap_dodge(s), "mp_dodge": mp_dodge(s), "summons": BASE_SUMMONS + int(s.call("summons")),
			"range": int(s.call("range")), "crit": int(s.call("crit")), "power": int(s.call("power")),
			"damage": int(s.call("damage")), "heals": int(s.call("heals"))}
