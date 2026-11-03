class_name JsonTextPatch
extends RefCounted
## Changes one value inside JSON text while keeping the rest of the text as
## it was written: the layout, key order, comment keys and number style of a
## hand-edited data file stay, so a saved change diffs as one line.
##
##   var r := JsonTextPatch.set_value(text, ["actions", "heavy_strike", "recovery"], 60)
##   if r.error.is_empty(): text = r.text
##
## A key missing from the innermost object is added at its end; every other
## key on the path must exist. Values are written on one line in the files'
## style ({"a": 1, "b": [2, 3]}); a whole float keeps its ".0".

const WHITESPACE := " \t\r\n"


## `text` with the value at `path` (object keys, outermost first) replaced by
## `value`. Returns {"text": String, "error": String}; on an error the text is
## unchanged.
static func set_value(text: String, path: Array, value: Variant) -> Dictionary:
	var fail := func(why: String) -> Dictionary: return {"text": text, "error": why}
	if path.is_empty():
		return fail.call("an empty path")
	if JSON.parse_string(text) == null:
		return fail.call("the text is not JSON")
	var start := _skip(text, 0)
	var end := _scan_value(text, start)
	for depth in path.size():
		var key := str(path[depth])
		if start >= text.length() or text[start] != "{":
			return fail.call("%s is not an object" % _path_text(path.slice(0, depth)))
		var members := _members(text, start)
		var found: Dictionary = {}
		for m: Dictionary in members:
			if m.key == key:
				found = m
		if found.is_empty():
			if depth < path.size() - 1:
				return fail.call("no %s" % _path_text(path.slice(0, depth + 1)))
			return _checked(_insert(text, start, end, members, key, value), path, value, text)
		start = int(found.value_start)
		end = int(found.value_end)
	var out := text.substr(0, start) + format(value) + text.substr(end)
	return _checked(out, path, value, text)


## The value at `path` in the parsed `text`, or `missing` when a key on the
## path is absent.
static func get_value(text: String, path: Array, missing: Variant = null) -> Variant:
	var v: Variant = JSON.parse_string(text)
	for key: Variant in path:
		if typeof(v) != TYPE_DICTIONARY or not (v as Dictionary).has(str(key)):
			return missing
		v = v[str(key)]
	return v


## `value` as one line of JSON in the data files' style.
static func format(value: Variant) -> String:
	match typeof(value):
		TYPE_NIL:
			return "null"
		TYPE_BOOL:
			return "true" if value else "false"
		TYPE_INT:
			return str(value)
		TYPE_FLOAT:
			var f: float = value
			if is_finite(f) and f == floorf(f) and absf(f) < 1e15:
				return "%d.0" % int(f)
			return String.num(f)
		TYPE_STRING, TYPE_STRING_NAME:
			return JSON.stringify(str(value))
		TYPE_ARRAY, TYPE_PACKED_STRING_ARRAY, TYPE_PACKED_INT32_ARRAY, TYPE_PACKED_FLOAT32_ARRAY, \
				TYPE_PACKED_INT64_ARRAY, TYPE_PACKED_FLOAT64_ARRAY:
			var parts := PackedStringArray()
			for item: Variant in value:
				parts.append(format(item))
			return "[%s]" % ", ".join(parts)
		TYPE_DICTIONARY:
			var parts := PackedStringArray()
			for k: Variant in value:
				parts.append("%s: %s" % [JSON.stringify(str(k)), format(value[k])])
			return "{%s}" % ", ".join(parts)
	return JSON.stringify(value)


## True when two parsed JSON values are the same (JSON numbers parse as
## floats, so 4 and 4.0 match).
static func same(a: Variant, b: Variant) -> bool:
	var numbers := [TYPE_INT, TYPE_FLOAT]
	if typeof(a) in numbers and typeof(b) in numbers:
		return is_equal_approx(float(a), float(b))
	if typeof(a) in [TYPE_STRING, TYPE_STRING_NAME] and typeof(b) in [TYPE_STRING, TYPE_STRING_NAME]:
		return str(a) == str(b)
	if typeof(a) == TYPE_ARRAY and typeof(b) == TYPE_ARRAY:
		if (a as Array).size() != (b as Array).size():
			return false
		for i in (a as Array).size():
			if not same(a[i], b[i]):
				return false
		return true
	if typeof(a) == TYPE_DICTIONARY and typeof(b) == TYPE_DICTIONARY:
		if (a as Dictionary).size() != (b as Dictionary).size():
			return false
		for k: Variant in a:
			if not (b as Dictionary).has(k) or not same(a[k], b[k]):
				return false
		return true
	return typeof(a) == typeof(b) and a == b


static func _checked(out: Dictionary, path: Array, value: Variant, original: String) -> Dictionary:
	if not str(out.get("error", "")).is_empty():
		return out
	var text: String = out.text
	if JSON.parse_string(text) == null:
		return {"text": original, "error": "the change would break the JSON"}
	if not same(get_value(text, path), JSON.parse_string(format(value))):
		return {"text": original, "error": "the change did not land at %s" % _path_text(path)}
	return {"text": text, "error": ""}


## Adds `"key": value` at the end of the object at [obj_start, obj_end).
static func _insert(text: String, obj_start: int, obj_end: int, members: Array, key: String, value: Variant) -> Dictionary:
	var entry := "%s: %s" % [JSON.stringify(key), format(value)]
	var close := obj_end - 1
	if members.is_empty():
		return {"text": text.substr(0, obj_start + 1) + entry + text.substr(close), "error": ""}
	var last: Dictionary = members[-1]
	var at := int(last.value_end)
	var body := text.substr(obj_start, obj_end - obj_start)
	if body.contains("\n"):
		# A multi-line object: the new key goes on its own line, indented as
		# the last key is.
		var line_start := text.rfind("\n", int(last.key_start)) + 1
		var indent := text.substr(line_start, int(last.key_start) - line_start)
		return {"text": text.substr(0, at) + ",\n" + indent + entry + text.substr(at), "error": ""}
	return {"text": text.substr(0, at) + ", " + entry + text.substr(at), "error": ""}


## The members of the object starting at `start` ("{"): each one's key and
## where its key and value sit in the text.
static func _members(text: String, start: int) -> Array:
	var out := []
	var i := _skip(text, start + 1)
	if i < text.length() and text[i] == "}":
		return out
	while i < text.length():
		var key_start := i
		var key_end := _scan_string(text, i)
		var key: String = JSON.parse_string(text.substr(key_start, key_end - key_start))
		i = _skip(text, key_end)
		i = _skip(text, i + 1)  # past ":"
		var value_start := i
		var value_end := _scan_value(text, i)
		out.append({"key": key, "key_start": key_start, "value_start": value_start, "value_end": value_end})
		i = _skip(text, value_end)
		if i < text.length() and text[i] == ",":
			i = _skip(text, i + 1)
			continue
		break
	return out


## The index just past the value starting at `i`.
static func _scan_value(text: String, i: int) -> int:
	if i >= text.length():
		return i
	var c := text[i]
	if c == "\"":
		return _scan_string(text, i)
	if c == "{" or c == "[":
		var closing := "}" if c == "{" else "]"
		i = _skip(text, i + 1)
		if i < text.length() and text[i] == closing:
			return i + 1
		while i < text.length():
			if c == "{":
				i = _skip(text, _scan_string(text, i))
				i = _skip(text, i + 1)
			i = _skip(text, _scan_value(text, i))
			if i < text.length() and text[i] == ",":
				i = _skip(text, i + 1)
				continue
			return i + 1
		return i
	while i < text.length() and not text[i] in ",}]" and not WHITESPACE.contains(text[i]):
		i += 1
	return i


## The index just past the string starting at `i` (a "\"").
static func _scan_string(text: String, i: int) -> int:
	i += 1
	while i < text.length():
		var c := text[i]
		if c == "\\":
			i += 2
			continue
		if c == "\"":
			return i + 1
		i += 1
	return i


static func _skip(text: String, i: int) -> int:
	while i < text.length() and WHITESPACE.contains(text[i]):
		i += 1
	return i


static func _path_text(path: Array) -> String:
	if path.is_empty():
		return "the top level"
	return ".".join(PackedStringArray(path.map(func(k: Variant) -> String: return str(k))))
