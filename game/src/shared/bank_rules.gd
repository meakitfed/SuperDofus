## The bank (roadmap P2.08): rules shared by the sim and the client.
##
## One chest per account, kept by any banker NPC (npcs templates listed in the
## world's bank.json) and shared by every character and world of the account.
## It holds kamas and item stacks, no weight limit.
##
## Sources:
##  - one chest per account, paid access that depends on how many objects it
##    holds, deposit of kamas and objects: the banker's own text (i18n 913012,
##    the `npcs` 6394 dialog message).
##  - cost: APPROX(P2.08) 1 kama per stack stored. The text only says "depends on
##    the number of objects"; the real price is server data (not in the client
##    tables, not in luaformulas).
##  - APPROX(P2.08) no object is refused for being bound or a quest item
##    (items.m_flags tradability is not read yet); worn items are always refused.
class_name BankRules
extends RefCounted

## the largest quantity of one move
const MAX_QTY := 100000
const IN := "in"
const OUT := "out"
## i18n of the banker's "Consulter son coffre personnel." (npcs 6394 dialogReplies)
const OPEN_TEXT_ID := 913010


## What opening the chest costs: 1 kama per stack stored.
static func access_cost(stacks: int) -> int:
	return maxi(0, stacks)
