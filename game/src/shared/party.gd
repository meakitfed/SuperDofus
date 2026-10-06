## A group of players (P3.03): the pure rules, no Node and nothing Dofus-specific beyond
## the numbers. Members are identified by character name (stable across a session, unlike
## an actor id); the first member is the leader. The sim (WorldParty) owns the instances,
## the invitations and the messages.
##   APPROX(P3.03): the limit of 8 players and the 60 s lifetime of an invitation are the
##   in-game values of Dofus; neither is in the client tables (FightXp.GROUP_BONUS has 12
##   entries because it also counts monsters of a fight).
class_name Party
extends RefCounted

const MAX_SIZE := 8
const INVITE_TTL_MS := 60000

var id := 0
## character names, the leader first
var members: Array = []


static func create(p_id: int, leader: String, other: String) -> Party:
	var p := Party.new()
	p.id = p_id
	p.members = [leader, other]
	return p


func leader() -> String:
	return members[0] if not members.is_empty() else ""


func has(name: String) -> bool:
	return members.has(name)


func is_full() -> bool:
	return members.size() >= MAX_SIZE


## A group of one is no group: it dissolves.
func is_dissolved() -> bool:
	return members.size() < 2


## "" if `name` joined, else Protocol's party_full / already_in_party.
func add(name: String) -> String:
	if has(name):
		return ProtocolParty.E_ALREADY_IN_PARTY
	if is_full():
		return ProtocolParty.E_PARTY_FULL
	members.append(name)
	return ""


## Leaves (or is excluded): when the leader goes the next member in line leads.
func remove(name: String) -> void:
	members.erase(name)


## "" if `by` may exclude `name`: the leader only, and a member other than itself.
func can_kick(by: String, name: String) -> String:
	if by != leader():
		return ProtocolParty.E_NOT_PARTY_LEADER
	if name == by or not has(name):
		return Protocol.E_NO_TARGET
	return ""


## The leader hands the lead to another member (it moves to the front).
func promote(by: String, name: String) -> String:
	if by != leader():
		return ProtocolParty.E_NOT_PARTY_LEADER
	if name == by or not has(name):
		return Protocol.E_NO_TARGET
	members.erase(name)
	members.push_front(name)
	return ""
