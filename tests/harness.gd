class_name TestHarness
extends RefCounted

## A tiny assertion harness for the headless test runner.
##
## GDScript's `assert` is stripped from release builds and stops the run on the
## first failure, neither of which suits a test suite — so failures are collected
## and reported as a list.

var suite := ""
var passed := 0
var failures: PackedStringArray = []
var _current := ""


func describe(name: String) -> void:
	suite = name


func it(name: String) -> void:
	_current = name


func _fail(detail: String) -> void:
	failures.append("%s › %s\n      %s" % [suite, _current, detail])


func check(condition: bool, detail: String) -> void:
	if condition:
		passed += 1
	else:
		_fail(detail)


func equal(actual: Variant, expected: Variant, what := "") -> void:
	var label := what if what != "" else "value"
	if _deep_equal(actual, expected):
		passed += 1
	else:
		_fail("%s: expected %s, got %s" % [label, _show(expected), _show(actual)])


func not_equal(actual: Variant, unexpected: Variant, what := "") -> void:
	var label := what if what != "" else "value"
	if not _deep_equal(actual, unexpected):
		passed += 1
	else:
		_fail("%s: expected anything but %s" % [label, _show(unexpected)])


func contains(haystack: Variant, needle: Variant, what := "") -> void:
	var label := what if what != "" else "collection"
	var found := false
	if haystack is Array or haystack is PackedStringArray:
		for item in haystack:
			if _deep_equal(item, needle):
				found = true
				break
	elif haystack is String:
		found = (haystack as String).contains(String(needle))
	if found:
		passed += 1
	else:
		_fail("%s: expected to contain %s, got %s" % [label, _show(needle), _show(haystack)])


func not_contains(haystack: Variant, needle: Variant, what := "") -> void:
	var label := what if what != "" else "collection"
	var found := false
	if haystack is Array or haystack is PackedStringArray:
		for item in haystack:
			if _deep_equal(item, needle):
				found = true
				break
	if not found:
		passed += 1
	else:
		_fail("%s: expected not to contain %s" % [label, _show(needle)])


## Structural equality, so a Dictionary compares by contents and an int 5
## matches a float 5.0 the way JSON round-trips make it.
static func _deep_equal(a: Variant, b: Variant) -> bool:
	if a is Dictionary and b is Dictionary:
		var da: Dictionary = a
		var db: Dictionary = b
		if da.size() != db.size():
			return false
		for key in da:
			if not db.has(key):
				return false
			if not _deep_equal(da[key], db[key]):
				return false
		return true
	if (a is Array or a is PackedInt32Array or a is PackedStringArray) and (
		b is Array or b is PackedInt32Array or b is PackedStringArray
	):
		if a.size() != b.size():
			return false
		for index in a.size():
			if not _deep_equal(a[index], b[index]):
				return false
		return true
	if (a is int or a is float) and (b is int or b is float):
		return is_equal_approx(float(a), float(b))
	return a == b


static func _show(value: Variant) -> String:
	var text := str(value)
	return text if text.length() <= 220 else text.substr(0, 220) + "…"


func report() -> bool:
	if failures.is_empty():
		print("  ✓ %s — %d checks" % [suite, passed])
		return true
	print("  ✗ %s — %d passed, %d failed" % [suite, passed, failures.size()])
	for failure in failures:
		print("      " + failure)
	return false
