## Message checking against the protocol: Protocol.SCHEMA plus the SCHEMA of every
## domain extension (protocol_<domain>.gd). Protocol.validate() delegates here.
class_name ProtocolSchema
extends RefCounted

## The domain extensions (C2S, S2C, SCHEMA, ERROR_CODES each). A new domain goes here
## and into Protocol.ERROR_CODES; test_protocol checks both lists.
const EXTENSIONS := [preload("protocol_party.gd"), preload("protocol_watch.gd"), preload("protocol_resume.gd"),
		preload("protocol_admin.gd"), preload("protocol_cluster.gd"), preload("protocol_trade.gd"),
		preload("protocol_contacts.gd"), preload("protocol_dungeon.gd"), preload("protocol_market.gd")]

static var _all := {}


## type -> [direction, meaning, {field: type}] for every message (Protocol.SCHEMA wins on a clash).
static func all() -> Dictionary:
	if _all.is_empty():
		var merged: Dictionary = Protocol.SCHEMA.duplicate()
		for ext: Script in EXTENSIONS:
			merged.merge(constant(ext, "SCHEMA"))
		_all = merged
	return _all


## A constant of an extension script (EXTENSIONS holds scripts, not instances).
static func constant(ext: Script, name: String) -> Variant:
	return ext.get_script_constant_map()[name]


## "" when `msg` matches the schema (in the expected direction, if given), else a
## short English reason. Numbers that came back from JSON as integral floats
## count as ints.
static func validate(msg: Dictionary, direction := "") -> String:
	var type := str(msg.get("t", ""))
	var entry: Array = all().get(type, [])
	if entry.is_empty():
		return "unknown message type '%s'" % type
	if direction != "" and entry[0] != direction:
		return "'%s' is not a %s message" % [type, direction]
	var fields: Dictionary = entry[2]
	if msg.has("seq") and not is_type(msg["seq"], "int"):
		return "seq must be an int"
	for f: String in fields:
		var kind: String = fields[f]
		var optional := kind.ends_with("?")
		kind = kind.trim_suffix("?")
		if not msg.has(f):
			if optional:
				continue
			return "%s: missing field '%s'" % [type, f]
		if not is_type(msg[f], kind):
			return "%s: field '%s' must be %s" % [type, f, kind]
	return ""


static func is_type(v: Variant, kind: String) -> bool:
	match kind:
		"int":
			return typeof(v) == TYPE_INT or (typeof(v) == TYPE_FLOAT and v == floorf(v) and is_finite(v))
		"bool":
			return typeof(v) == TYPE_BOOL
		"str":
			return typeof(v) == TYPE_STRING
		"dict":
			return typeof(v) == TYPE_DICTIONARY
		"array":
			return typeof(v) == TYPE_ARRAY
	return false
