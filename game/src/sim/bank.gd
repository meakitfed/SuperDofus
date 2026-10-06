## The account's chest (roadmap P2.08): kamas and item stacks, stored in the
## "accounts" collection of Persistence under the key "bank" of the account
## document, so that every character of the account (and every world sharing
## the store) sees the same chest. Rules: BankRules (shared with the client).
##
## Always loaded fresh and written together with the character
## (Persistence.commit), so that an item is never in both places or in neither.
class_name Bank
extends RefCounted

var kamas := 0
var inventory := Inventory.new()


## Standalone saves from before accounts have account "": they share one chest.
static func account_key(account: String) -> String:
	return account if account != "" else "_local"


static func load_for(persistence: Persistence, account: String) -> Bank:
	var d: Dictionary = persistence.load_account(account_key(account)).get("bank", {})
	var b := Bank.new()
	b.kamas = int(d.get("kamas", 0))
	b.inventory = Inventory.from_array(d.get("items", []))
	return b


## The write of this chest for Persistence.commit (the rest of the account document is kept).
func write_for(persistence: Persistence, account: String) -> Dictionary:
	var key := account_key(account)
	var doc := persistence.load_account(key)
	doc["bank"] = {"kamas": kamas, "items": inventory.to_array()}
	return {"collection": Persistence.ACCOUNTS, "key": key, "data": doc}


func access_cost() -> int:
	return BankRules.access_cost(inventory.items.size())
