## The characters of an account in a world (the character selection screen):
## list, create, delete, and whether one may be played. Pure rules over the
## world's Persistence; GameSession calls them before a character is chosen.
class_name CharacterRoster
extends RefCounted

## APPROX(P1.01): the real per-server slot count (subscription, bonus slots) is server-side, not in the client data.
const MAX_PER_WORLD := 5
const DEFAULT_BREED := 12


## Protocol character summary: {name, level, breed, sex, look}, sorted by name.
static func summaries(sim: WorldSim, account: String) -> Array:
	var out: Array = []
	for name in sim.persistence.list_characters(sim.world_id()):
		var d := sim.persistence.load_character(sim.world_id(), name)
		if _owned(d, account):
			out.append({"name": name, "level": int(d.get("level", 1)), "breed": int(d.get("breed", DEFAULT_BREED)),
					"sex": int(d.get("sex", 0)), "look": str(d.get("worn_look", d.get("look", "")))}) # as it is dressed (P1.06b)
	return out


## breeds.id that can be created: the classes of the breeds table that have a
## spell book (spellvariants; its breed 19 has spell pairs but no breeds row).
static func playable_breeds() -> Array:
	var out: Array = []
	for b: Dictionary in LookBuilder.breeds():
		if SpellBook.pairs(DEFAULT_BREED).is_empty() or not SpellBook.pairs(int(b["id"])).is_empty():
			out.append(int(b["id"]))
	return out


static func characters_event(sim: WorldSim, account: String) -> Dictionary:
	return Protocol.characters(summaries(sim, account), MAX_PER_WORLD,
			{"id": sim.world_id(), "name": str(sim.info.get("name", ""))}, playable_breeds())


## The stored name matching `name` ignoring case, "" if none: names are unique
## per world whatever the case. APPROX(P1.01): Dofus also refuses reserved or
## insulting names (server-side list, not in the client data).
static func find(sim: WorldSim, name: String) -> String:
	for n in sim.persistence.list_characters(sim.world_id()):
		if n.to_lower() == name.to_lower():
			return n
	return ""


## "" or an E_* code. `look` = the creation choices {breed, sex, body, head,
## colors} (create_character fields; missing = the breed's defaults), checked
## and turned into the look string by the shared LookBuilder.
static func create(sim: WorldSim, account: String, name: String, look := {}) -> String:
	var breed := int(look.get("breed", DEFAULT_BREED))
	var sex := int(look.get("sex", 0))
	var body := int(look.get("body", 0))
	var face := int(look.get("head", 0))
	var colors: Array = look.get("colors", [])
	if account != "" and Sanctions.is_banned(sim.persistence, account): # A1.01
		return ProtocolAdmin.E_BANNED
	if not NameRules.is_valid(name): # namingrules via servercommunities.namingRulePlayerNameId
		return Protocol.E_BAD_NAME
	if find(sim, name) != "":
		return Protocol.E_NAME_TAKEN
	if not breed in playable_breeds():
		return Protocol.E_UNKNOWN_BREED
	var bad_look := LookBuilder.check(breed, sex, body, face, colors)
	if bad_look != "":
		return bad_look
	if summaries(sim, account).size() >= MAX_PER_WORLD:
		return Protocol.E_TOO_MANY_CHARACTERS
	var c := Character.new()
	c.name = name
	c.account = account
	c.breed = breed
	c.sex = sex
	c.body = body
	c.head = face
	c.colors = colors.map(func(v: Variant) -> int: return int(v))
	c.look = LookBuilder.build(breed, sex, body, face, colors)
	var data := c.to_dict(sim.now)
	data["saved_at"] = sim.clock.now_unix_ms()
	sim.persistence.save_character(sim.world_id(), name, data)
	return ""


## Deleting is final. A character being played cannot be deleted.
static func delete(sim: WorldSim, account: String, name: String) -> String:
	var err := can_select(sim, account, name)
	if err != "":
		return err
	for p: PlayerActor in sim.players.values():
		if p.name == name:
			return Protocol.E_CHARACTER_IN_USE
	sim.persistence.delete_character(sim.world_id(), name)
	return ""


static func can_select(sim: WorldSim, account: String, name: String) -> String:
	if account != "" and Sanctions.is_banned(sim.persistence, account): # A1.01
		return ProtocolAdmin.E_BANNED
	var d := sim.persistence.load_character(sim.world_id(), name) if name != "" else {}
	return "" if not d.is_empty() and _owned(d, account) else Protocol.E_UNKNOWN_CHARACTER


## Standalone saves from before accounts (account "") belong to whoever plays
## them first (WorldSim.connect_player then records the account).
static func _owned(d: Dictionary, account: String) -> bool:
	var owner := str(d.get("account", ""))
	return owner == "" or owner == account
