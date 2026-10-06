## Minimal test base (no addon needed). Methods named `test_*` are run by tests/run_tests.gd.
class_name TestCase
extends RefCounted

var failures: PackedStringArray = PackedStringArray()
var _current := ""


func _set_current(name: String) -> void:
	_current = name


func check(condition: bool, message := "") -> void:
	if not condition:
		failures.append("%s: %s" % [_current, message if message != "" else "assertion failed"])


func eq(actual: Variant, expected: Variant, message := "") -> void:
	if typeof(actual) != typeof(expected) and not (_is_num(actual) and _is_num(expected)):
		failures.append("%s: %s expected %s (%s), got %s (%s)" % [_current, message, expected, type_string(typeof(expected)), actual, type_string(typeof(actual))])
	elif actual != expected:
		failures.append("%s: %s expected %s, got %s" % [_current, message, expected, actual])


func near(actual: float, expected: float, eps := 0.0005, message := "") -> void:
	if absf(actual - expected) > eps:
		failures.append("%s: %s expected ~%s, got %s" % [_current, message, expected, actual])


## Skip marker: return early from a test when optional content is missing.
func skip(reason: String) -> void:
	print("    - skipped %s (%s)" % [_current, reason])


static func _is_num(v: Variant) -> bool:
	return typeof(v) == TYPE_INT or typeof(v) == TYPE_FLOAT
