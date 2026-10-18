## When a window asks "are you sure?" before sending a message (U.07): never for a small purchase
## (it would only slow the player down), always for what is expensive, hard to undo or unlikely to work.
## Pure rules, no node: the windows call UiConfirm when these say so.
class_name ConfirmPolicy
extends RefCounted

## a spend of at least this many kamas is always confirmed
const BIG_SPEND := 10000
## below this, even half the purse is not worth a question
const SMALL_SPEND := 1000
## a forgemagic try under this chance (%) is confirmed
const RISKY_FORGE := 50


static func spend(total: int, kamas: int) -> bool:
	if total >= BIG_SPEND:
		return true
	return total >= SMALL_SPEND and total * 2 > kamas


static func forge(chance: int) -> bool:
	return chance < RISKY_FORGE


## "5 x Pain pour 1 250 K ?" : the question of a purchase.
static func buy_text(what: String, total: int, kamas: int) -> String:
	return "%s pour %s K ? Il vous restera %s K." % [what, UiStyle.thousands(total), UiStyle.thousands(maxi(0, kamas - total))]


## Putting a lot on sale at this price is confirmed (the tax is not refunded).
static func listing(price: int) -> bool:
	return price >= BIG_SPEND
