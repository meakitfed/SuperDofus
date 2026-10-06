## Dofus 3 localized texts (Content/I18n/<lang>.bin, copied as-is from the client).
## Format: [len u8][lang ascii][count i32] then count x (id i32, offset i32) sorted by id,
## strings at offset as .NET strings (7-bit varint length + UTF-8).
##   DofusI18n.text(6522) -> "Larve Bleue"
class_name DofusI18n
extends RefCounted

static var lang := "fr"
static var _bytes := PackedByteArray()
static var _table := 0
static var _count := 0
static var _cache := {}


static func text(id: int, fallback := "") -> String:
	if id <= 0 or not _ensure():
		return fallback
	if _cache.has(id):
		return _cache[id]
	var lo := 0
	var hi := _count - 1
	while lo <= hi:
		var mid := (lo + hi) >> 1
		var k := _bytes.decode_s32(_table + mid * 8)
		if k == id:
			var s := _read_string(_bytes.decode_s32(_table + mid * 8 + 4))
			_cache[id] = s
			return s
		if k < id:
			lo = mid + 1
		else:
			hi = mid - 1
	return fallback


static func is_available() -> bool:
	return _ensure()


static func _ensure() -> bool:
	if _count > 0:
		return true
	var path := "Content/I18n/%s.bin" % lang
	var provider := DofusContent.get_provider()
	if not provider.exists(path):
		return false
	_bytes = provider.read_bytes(path)
	var n := _bytes[0]
	_count = _bytes.decode_s32(1 + n)
	_table = 1 + n + 4
	return _count > 0


static func _read_string(off: int) -> String:
	var length := 0
	var shift := 0
	while true:
		var c := _bytes[off]
		off += 1
		length |= (c & 0x7f) << shift
		shift += 7
		if c < 0x80:
			break
	return _bytes.slice(off, off + length).get_string_from_utf8()
