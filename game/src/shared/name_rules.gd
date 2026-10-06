## Dofus name rules (characters, later guilds, alliances, mounts…), read from
## the game data: servercommunities.namingRule<Kind>Id -> namingrules
## {minLength, maxLength, regexp}. Shared so the client can check a name as
## it is typed; the sim checks it again (it never trusts the client).
class_name NameRules
extends RefCounted

## servercommunities id 0 = "fr" (the community whose rules we follow)
const COMMUNITY := 0
## namingrules 1 (servercommunities[0].namingRulePlayerNameId), used when the
## tables are not available (test fixtures)
const FALLBACK_PLAYER := {"minLength": 2, "maxLength": 20, "regexp": "^([A-Z][a-z]+(\\-[a-zA-Z][a-z]*){0,2})$"}

static var _regex := {} # pattern -> RegEx


## The rule row for a kind of name: "Player", "Guild", "Alliance", "AllianceTag", "Party", "Mount"…
static func rule(kind := "Player") -> Dictionary:
	var community := GameData.row("servercommunities", COMMUNITY)
	var r := GameData.row("namingrules", int(community.get("namingRule%sNameId" % kind, community.get("namingRule%sId" % kind, -1))))
	if r.is_empty() and kind == "Player":
		return FALLBACK_PLAYER
	return r


## True if `name` follows the rule (length and pattern).
static func is_valid(name: String, kind := "Player") -> bool:
	var r := rule(kind)
	if r.is_empty():
		return false
	if name.length() < int(r["minLength"]) or name.length() > int(r["maxLength"]):
		return false
	var pattern := str(r["regexp"])
	if not _regex.has(pattern):
		var re := RegEx.new()
		re.compile(pattern)
		_regex[pattern] = re
	return (_regex[pattern] as RegEx).search(name) != null
