## A guild (P3.06a), pure rules on one document: name, emblem, members with a rank and
## rights. Kept by WorldGuild through Persistence (collection "guilds"); the client only
## reads its view. Nothing here is specific to Dofus except the ids of the tables
## guildranks / guildrights, which are data.
##
## Ranks (guildranks, ordered by `order`, a lower order is a higher rank):
##   1 Maitre de guilde (0) - 2 Officier (1) - 3 Initie (2) - 4 A l'essai (3)
## Rights (guildrights ids; the names are texts of the table, e.g. 26 "Attribuer des rangs
## inferieurs au mien"). Only the rights below are enforced; the others (chest, chest tabs,
## missions, raids) wait for the lots that bring those features.
## APPROX(P3.06a): the default rights of each rank (DEFAULT_RIGHTS) are ours, the data has none;
## the leader holds every right whatever its list says.
## APPROX(P3.06a): 200 members at most (Dofus 2); no guildalogemme item is consumed at creation.
class_name Guild
extends RefCounted

const RANK_LEADER := 1
const RANK_OFFICER := 2
const RANK_INITIATE := 3
const RANK_TRIAL := 4
const RANKS := [RANK_LEADER, RANK_OFFICER, RANK_INITIATE, RANK_TRIAL]

const R_MANAGE_RANKS := 1  # guildrights 1: manage the ranks and rights of lower members
const R_MESSAGE := 7       # 7: edit the guild message (enforced from P3.06b)
const R_INFO := 15         # 15: edit the guild information (emblem, name) (idem)
const R_NOTES := 14        # 14: member notes (idem)
const R_RECRUIT := 5       # 5: recruitment announcement (idem)
const R_INVITE := 6        # 6: manage applications and invitations
const R_KICK := 13         # 13: exclude a member
const R_ASSIGN := 26       # 26: assign ranks lower than mine
const ALL_RIGHTS := [R_MANAGE_RANKS, R_RECRUIT, R_INVITE, R_MESSAGE, R_KICK, R_NOTES, R_INFO, R_ASSIGN]
const DEFAULT_RIGHTS := {
	RANK_LEADER: ALL_RIGHTS,
	RANK_OFFICER: [R_INVITE, R_MESSAGE, R_KICK, R_ASSIGN],
	RANK_INITIATE: [],
	RANK_TRIAL: [],
}
const MAX_MEMBERS := 200
const INVITE_TTL_MS := 60000

var id := 0
var name := ""
## {symbol, symbol_color, bg, bg_color}: emblemsymbols / emblembackgrounds ids and RGB colours
var emblem := {}
## [{name, rank, rights: [int], joined (unix ms)}], the leader first
var members: Array = []
var created := 0


static func from_dict(d: Dictionary) -> Guild:
	var g := Guild.new()
	g.id = int(d.get("id", 0))
	g.name = str(d.get("name", ""))
	if d.get("emblem") is Dictionary:
		g.emblem = (d["emblem"] as Dictionary).duplicate()
	g.created = int(d.get("created", 0))
	if d.get("members") is Array:
		for m: Variant in d["members"]:
			if m is Dictionary and str(m.get("name", "")) != "":
				var rank := int(m.get("rank", RANK_TRIAL))
				g.members.append({"name": str(m["name"]), "rank": rank if rank in RANKS else RANK_TRIAL,
						"rights": _ints(m.get("rights", [])), "joined": int(m.get("joined", 0))})
	return g


func to_dict() -> Dictionary:
	return {"id": id, "name": name, "emblem": emblem.duplicate(), "created": created, "members": members.duplicate(true)}


static func _ints(a: Variant) -> Array:
	var out: Array = []
	if a is Array:
		for v: Variant in a:
			var i := int(v)
			if i in ALL_RIGHTS and not i in out:
				out.append(i)
	out.sort()
	return out


## guildranks.order of a rank (0 = highest); an unknown rank counts as the lowest.
static func order_of(rank: int) -> int:
	var row := GameData.row("guildranks", rank)
	if not row.is_empty():
		return int(row["order"])
	return RANKS.find(rank) if rank in RANKS else RANKS.size()


## Empty if `e` is a valid emblem, else bad_emblem. The tables are checked when loaded
## (symbol and background ids), colours are RGB integers.
static func emblem_error(e: Dictionary) -> String:
	for k: String in ["symbol", "symbol_color", "bg", "bg_color"]:
		if not e.has(k):
			return ProtocolGuild.E_BAD_EMBLEM
	for k: String in ["symbol_color", "bg_color"]:
		var c := int(e[k])
		if c < 0 or c > 0xFFFFFF:
			return ProtocolGuild.E_BAD_EMBLEM
	if GameData.has_table("emblemsymbols") and GameData.row("emblemsymbols", int(e["symbol"])).is_empty():
		return ProtocolGuild.E_BAD_EMBLEM
	if GameData.has_table("emblembackgrounds") and GameData.row("emblembackgrounds", int(e["bg"])).is_empty():
		return ProtocolGuild.E_BAD_EMBLEM
	return ""


## "" if `n` can name a guild (namingrules of the community), else bad_guild_name.
static func name_error(n: String) -> String:
	return "" if NameRules.is_valid(n, "Guild") else ProtocolGuild.E_BAD_GUILD_NAME


static func create(p_id: int, p_name: String, p_emblem: Dictionary, leader_name: String, now_unix_ms: int) -> Guild:
	var g := Guild.new()
	g.id = p_id
	g.name = p_name
	g.emblem = {"symbol": int(p_emblem["symbol"]), "symbol_color": int(p_emblem["symbol_color"]),
			"bg": int(p_emblem["bg"]), "bg_color": int(p_emblem["bg_color"])}
	g.created = now_unix_ms
	g.members = [{"name": leader_name, "rank": RANK_LEADER, "rights": ALL_RIGHTS.duplicate(), "joined": now_unix_ms}]
	return g


func index_of(who: String) -> int:
	for i in members.size():
		if str(members[i]["name"]) == who:
			return i
	return -1


func member(who: String) -> Dictionary:
	var i := index_of(who)
	return members[i] if i >= 0 else {}


func is_full() -> bool:
	return members.size() >= MAX_MEMBERS


func leader() -> String:
	for m: Dictionary in members:
		if int(m["rank"]) == RANK_LEADER:
			return str(m["name"])
	return ""


## True if the member holds the right (the leader holds them all).
func has_right(who: String, right: int) -> bool:
	var m := member(who)
	if m.is_empty():
		return false
	return int(m["rank"]) == RANK_LEADER or right in m["rights"]


## True if `actor` ranks strictly above `target` (both members).
func outranks(actor: String, target: String) -> bool:
	var a := member(actor)
	var t := member(target)
	return not a.is_empty() and not t.is_empty() and order_of(int(a["rank"])) < order_of(int(t["rank"]))


## guild_invite: needs R_INVITE.
func invite_error(actor: String) -> String:
	if not has_right(actor, R_INVITE):
		return ProtocolGuild.E_GUILD_NO_RIGHT
	return ProtocolGuild.E_GUILD_FULL if is_full() else ""


func add(who: String, now_unix_ms: int) -> String:
	if index_of(who) >= 0:
		return ProtocolGuild.E_ALREADY_IN_GUILD
	if is_full():
		return ProtocolGuild.E_GUILD_FULL
	members.append({"name": who, "rank": RANK_TRIAL, "rights": (DEFAULT_RIGHTS[RANK_TRIAL] as Array).duplicate(), "joined": now_unix_ms})
	return ""


func remove(who: String) -> void:
	var i := index_of(who)
	if i >= 0:
		members.remove_at(i)


## guild_kick: needs R_KICK and to outrank the target.
func kick_error(actor: String, target: String) -> String:
	if index_of(target) < 0:
		return ProtocolGuild.E_NOT_IN_GUILD
	if not has_right(actor, R_KICK) or not outranks(actor, target):
		return ProtocolGuild.E_GUILD_NO_RIGHT
	return ""


## guild_rank: needs R_ASSIGN and to outrank the target; a rank as high as one's own is
## only given by the leader (who cannot give its own: that is guild_leader).
func rank_error(actor: String, target: String, rank: int) -> String:
	if index_of(target) < 0:
		return ProtocolGuild.E_NOT_IN_GUILD
	if not rank in RANKS or rank == RANK_LEADER:
		return ProtocolGuild.E_BAD_RANK
	if not has_right(actor, R_ASSIGN) or not outranks(actor, target):
		return ProtocolGuild.E_GUILD_NO_RIGHT
	if order_of(rank) <= order_of(int(member(actor)["rank"])):
		return ProtocolGuild.E_GUILD_NO_RIGHT
	return ""


## guild_rights: needs R_MANAGE_RANKS, to outrank the target, and only rights the actor holds.
func rights_error(actor: String, target: String, rights: Array) -> String:
	if index_of(target) < 0:
		return ProtocolGuild.E_NOT_IN_GUILD
	for r: Variant in rights:
		if not int(r) in ALL_RIGHTS:
			return ProtocolGuild.E_BAD_RIGHT
	if not has_right(actor, R_MANAGE_RANKS) or not outranks(actor, target):
		return ProtocolGuild.E_GUILD_NO_RIGHT
	for r: Variant in rights:
		if not has_right(actor, int(r)):
			return ProtocolGuild.E_GUILD_NO_RIGHT
	return ""


func set_rank(target: String, rank: int) -> void:
	var m := member(target)
	m["rank"] = rank
	m["rights"] = (DEFAULT_RIGHTS[rank] as Array).duplicate() # a new rank brings its default rights


func set_rights(target: String, rights: Array) -> void:
	member(target)["rights"] = _ints(rights)


## The leader hands the guild to `target`; the former leader becomes an officer.
func hand_over(target: String) -> void:
	var old := leader()
	if old != "":
		set_rank(old, RANK_OFFICER)
	set_rank(target, RANK_LEADER)
	members.insert(0, members.pop_at(index_of(target))) # the leader first, as the list is shown
