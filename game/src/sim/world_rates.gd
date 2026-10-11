## The rates of a server (S.06), set when it starts (--xp-rate=3 ...) or in standalone
## (same options on the client's command line): multipliers on the fight XP, the drop
## chances, the kamas and the job XP, and the bonus drops of Temporis-like servers
## (BonusDrops: equipment of the sets tied to the monsters fought, or without a set
## around their level). One object shared by every world of a LocalServer. The defaults
## change nothing: same rolls, same rewards.
class_name WorldRates
extends RefCounted

const MAX_RATE := 100.0
## the command-line options (--xp-rate=3 --bonus-drops ...), on the server and in standalone
const OPTIONS := ["xp-rate", "drop-rate", "kamas-rate", "job-xp-rate", "bonus-drops", "bonus-drop-rate", "bonus-drop-range"]

var xp := 1.0
var drop := 1.0
var kamas := 1.0
var job_xp := 1.0
## bonus drops (BonusDrops): off by default, their own rolls, not touched by `drop`
var bonus_drops := false
## % chance per monster killed and per player (× prospecting / 100)
var bonus_rate := 3.0
## the equipment without a set: levels within ± this of the group's highest monster
var bonus_range := 15
## share of the draws taken in the tied sets when the fight has some
var bonus_set_share := 0.5


## From the command-line options (key -> value, a flag has any value):
## xp-rate, drop-rate, kamas-rate, job-xp-rate, bonus-drops, bonus-drop-rate, bonus-drop-range.
static func from_options(opts: Dictionary) -> WorldRates:
	var r := WorldRates.new()
	r.xp = _rate(opts.get("xp-rate", 1.0))
	r.drop = _rate(opts.get("drop-rate", 1.0))
	r.kamas = _rate(opts.get("kamas-rate", 1.0))
	r.job_xp = _rate(opts.get("job-xp-rate", 1.0))
	r.bonus_drops = opts.has("bonus-drops") and str(opts["bonus-drops"]) not in ["0", "false", "no"]
	r.bonus_rate = clampf(float(opts.get("bonus-drop-rate", r.bonus_rate)), 0.0, 100.0)
	r.bonus_range = clampi(int(opts.get("bonus-drop-range", r.bonus_range)), 0, 200)
	return r


## The invalid options ("" when all are valid): --check refuses them.
static func check_options(opts: Dictionary) -> String:
	for k: String in OPTIONS:
		if not opts.has(k) or k == "bonus-drops":
			continue
		var v := str(opts[k])
		var top := 200.0 if k == "bonus-drop-range" else MAX_RATE
		if not v.is_valid_float() or float(v) < 0.0 or float(v) > top:
			return "%s=%s (attendu : un nombre entre 0 et %d)" % [k, v, int(top)]
	return ""


static func _rate(v: Variant) -> float:
	return clampf(float(v), 0.0, MAX_RATE)


## A job XP gain × job_xp (harvest, craft; not the job XP potions: a fixed value).
func job_xp_of(gained: int) -> int:
	return gained if job_xp == 1.0 else int(floor(gained * job_xp))


func is_default() -> bool:
	return xp == 1.0 and drop == 1.0 and kamas == 1.0 and job_xp == 1.0 and not bonus_drops


## JSON-safe view (welcome.world.rates, admin).
func to_dict() -> Dictionary:
	var d := {"xp": xp, "drop": drop, "kamas": kamas, "job_xp": job_xp, "bonus_drops": bonus_drops}
	if bonus_drops:
		d["bonus_rate"] = bonus_rate
		d["bonus_range"] = bonus_range
	return d


## One line for the server's log.
func summary() -> String:
	var s := "taux XP x%s, drop x%s, kamas x%s, metiers x%s" % [_num(xp), _num(drop), _num(kamas), _num(job_xp)]
	return s + (", drops bonus %s %% (+-%d niveaux)" % [_num(bonus_rate), bonus_range] if bonus_drops else ", drops bonus non")


static func _num(v: float) -> String:
	return str(int(v)) if v == floorf(v) else str(v)
