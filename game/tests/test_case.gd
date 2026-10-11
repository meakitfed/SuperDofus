## Minimal test base (no addon needed). Methods named `test_*` are run by tests/run_tests.gd.
class_name TestCase
extends RefCounted

var failures: PackedStringArray = PackedStringArray()
var _current := ""
var _sub := ""
## TEST_CASE=<text>: parameterized tests only run the cases whose label contains it.
var _case_filter := OS.get_environment("TEST_CASE")


func _set_current(name: String) -> void:
	_current = name


## Parameterized tests: the case `label` prefixes the next failures; false when TEST_CASE filters it out.
func sub(label: String) -> bool:
	_sub = label
	return _case_filter == "" or _case_filter in label


func check(condition: bool, message := "") -> void:
	if not condition:
		fail(message if message != "" else "assertion failed")


func eq(actual: Variant, expected: Variant, message := "") -> void:
	if typeof(actual) != typeof(expected) and not (_is_num(actual) and _is_num(expected)):
		fail("%s expected %s (%s), got %s (%s)" % [message, expected, type_string(typeof(expected)), actual, type_string(typeof(actual))])
	elif actual != expected:
		fail("%s expected %s, got %s" % [message, expected, actual])


func near(actual: float, expected: float, eps := 0.0005, message := "") -> void:
	if absf(actual - expected) > eps:
		fail("%s expected ~%s, got %s" % [message, expected, actual])


func fail(message: String) -> void:
	failures.append("%s: %s%s" % [_current, _sub + " / " if _sub != "" else "", message])


## Skip marker: return early from a test when optional content is missing.
func skip(reason: String) -> void:
	print("    - skipped %s (%s)" % [_current, reason])


static func _is_num(v: Variant) -> bool:
	return typeof(v) == TYPE_INT or typeof(v) == TYPE_FLOAT
