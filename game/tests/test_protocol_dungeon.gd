## Dungeon messages (roadmap P4.01): schema, directions, JSON round trip, error texts.
extends TestCase


func test_messages_are_in_the_schema() -> void:
	eq(ProtocolDungeon.C2S, Protocol.C2S)
	eq(ProtocolDungeon.S2C, Protocol.S2C)
	eq(Protocol.validate(ProtocolDungeon.enter(3), Protocol.C2S), "")
	eq(Protocol.validate(ProtocolDungeon.leave(), Protocol.C2S), "")
	eq(Protocol.validate(ProtocolDungeon.room(3, 0, 4, false, "Entrée"), Protocol.S2C), "")
	eq(Protocol.validate(ProtocolDungeon.end(3, ProtocolDungeon.REASON_WON), Protocol.S2C), "")
	check(Protocol.validate({"t": ProtocolDungeon.ENTER}, Protocol.C2S).contains("dungeon"), "a dungeon is required")
	check(Protocol.validate(ProtocolDungeon.room(3, 0, 4, false, "x"), Protocol.C2S) != "", "an event is no command")


func test_json_roundtrip_gives_ints_back() -> void:
	for msg: Dictionary in [ProtocolDungeon.enter(7), ProtocolDungeon.room(7, 2, 5, true, "Boss"), ProtocolDungeon.end(7, "left")]:
		var back := Protocol.roundtrip(msg)
		check(Protocol.is_json_safe(back))
		eq(Protocol.validate(back), "", "still valid after JSON")
	var r := Protocol.roundtrip(ProtocolDungeon.room(7, 2, 5, true, "Boss"))
	eq([int(r["dungeon"]), int(r["room"]), int(r["total"]), bool(r["boss"]), str(r["name"])], [7, 2, 5, true, "Boss"])


func test_error_codes_have_texts() -> void:
	eq(ProtocolDungeon.ERROR_CODES.size(), 5)
	for code: String in ProtocolDungeon.ERROR_CODES:
		check(Protocol.ERROR_CODES.has(code) and ErrorTexts.TEXTS.has(code), "%s is listed and has its text" % code)
