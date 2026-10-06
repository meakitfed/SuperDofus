## Jobs (P2.05): the rules of gathering, shared by the sim and the client.
##
## Data: `skills` (a skill = one verb of a job: parentJobId, gatheredRessourceItem,
## levelMin, range, useAnimation, cursor) and `jobs` (names, icons), light copies in
## data/tables (`gamedata.py interactives <world>`). Which element offers which
## skill is world data (worlds/<id>/interactives.json).
##
## What the client does not give (no formula in `luaformulas`, nothing in the tables)
## is marked APPROX(P2.05) below.
class_name Jobs
extends RefCounted

const MAX_LEVEL := 200
## APPROX(P2.05): every job is known from the start at level 1 (Dofus 3 has no job to learn
## first, to be checked); queststeprewards.jobsReward is not given yet
const START_LEVEL := 1
## APPROX(P2.05): time a harvest takes (the animation `skills.useAnimation` lasts about that long)
const HARVEST_MS := 3000
## APPROX(P2.05): time a harvested resource takes to grow back
const RESPAWN_MS := 300000
## APPROX(P2.05): XP of one harvest = BASE + the level the resource needs
const XP_BASE := 10


static func skill(skill_id: int) -> Dictionary:
	return GameData.row("skills", skill_id)


static func job(job_id: int) -> Dictionary:
	return GameData.row("jobs", job_id)


## A skill that harvests a resource (skills.gatheredRessourceItem = an items.id).
static func is_gathering(skill_id: int) -> bool:
	return int(skill(skill_id).get("gatheredRessourceItem", -1)) > 0


static func job_of(skill_id: int) -> int:
	return int(skill(skill_id).get("parentJobId", 0))


## items.id of what the skill harvests.
static func item_of(skill_id: int) -> int:
	return int(skill(skill_id).get("gatheredRessourceItem", -1))


## Job level the skill needs (skills.levelMin).
static func required_level(skill_id: int) -> int:
	return int(skill(skill_id).get("levelMin", 1))


## "" or Protocol.E_JOB_LEVEL.
static func check(skill_id: int, job_level: int) -> String:
	return "" if job_level >= required_level(skill_id) else Protocol.E_JOB_LEVEL


# ── levels ─────────────────────────────────────────────────────────────────────

## Job level of a total XP. APPROX(P2.05): the job XP table is not in the client data:
## the character's table (characterxpmappings) is used, up to MAX_LEVEL.
static func level_for_xp(xp: int) -> int:
	return clampi(GameData.level_for_xp(xp), START_LEVEL, MAX_LEVEL)


static func xp_floor(level: int) -> int:
	return GameData.xp_floor(level)


static func xp_next(level: int) -> int:
	return GameData.xp_floor(mini(level + 1, MAX_LEVEL))


## XP of one harvest. APPROX(P2.05): not in the data.
static func xp_gain(skill_id: int) -> int:
	return XP_BASE + required_level(skill_id)


## Quantity of one harvest as [min, max]. APPROX(P2.05): 1-2 at the level the resource needs,
## the minimum +1 every 50 levels above it and the maximum +1 every 20.
static func quantity_range(skill_id: int, job_level: int) -> Vector2i:
	var over := maxi(0, job_level - required_level(skill_id))
	return Vector2i(1 + over / 50, 2 + over / 20)


static func roll_quantity(skill_id: int, job_level: int, rng: RandomNumberGenerator) -> int:
	var r := quantity_range(skill_id, job_level)
	return rng.randi_range(r.x, r.y)
