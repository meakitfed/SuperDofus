## Energy and death (roadmap P1.10). Rules of the Dofus 3 client tutorial
## (notifications 12-14): a character that dies loses energy and goes back to
## its save point; at 0 energy it turns into a ghost, which comes back to life
## by reaching a resurrection phoenix (shown on the map); energy comes back
## with consumables (items effect 139) and while logged out, twice as fast in a
## class temple, a house or a tavern (map capability ALLOW_TAVERN_REGEN).
## Life states = GameRolePlayPlayerLifeStatus (notification 14 trigger "0:2":
## alive -> phantom, no tombstone in Dofus 3).
## Amounts (not in the client data), Dofus wiki (https://dofuswiki.fandom.com/wiki/Death,
## https://dofuswiki.fandom.com/wiki/Characteristic; read through search results,
## the pages refuse direct access): 10 000 energy at most, a
## defeat against monsters costs 10 per level, a phoenix gives 1 000 back,
## 1 point per minute logged out (2 in a tavern).
class_name Energy
extends RefCounted

const MAX := 10000
const PER_LEVEL := 10
const PHOENIX := 1000
const MINUTE_MS := 60000
## GameRolePlayPlayerLifeStatus values
const ALIVE := 0
const GHOST := 2
## "Votre énergie est dangereusement basse" (i18n 4840) below this.
## APPROX(P1.10): the threshold is server-side, not in the sources
const LOW := 2000


## Energy a defeat against monsters costs.
## APPROX(P1.10): capped at level 200 (omega levels are not in the sources)
static func defeat_loss(level: int) -> int:
	return PER_LEVEL * clampi(level, 1, 200)


## Energy regained after `ms` logged out (`tavern`: logged out where it doubles).
static func offline_gain(ms: int, tavern: bool) -> int:
	return maxi(0, ms) / MINUTE_MS * (2 if tavern else 1)
