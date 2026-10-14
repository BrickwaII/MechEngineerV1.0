class_name DataReader
extends RefCounted
## Checked reading of hand-edited data: each problem is added to an errors
## list, worded for the person editing the file, and a safe value comes back
## so loading goes on and every problem is reported at once.
##
##   var r := DataReader.new(errors, "tuning")
##   points_per_day = int(r.num(d, "time.points_per_day"))
##   # missing: "tuning is missing 'time.points_per_day'"
##
## The static helpers check one key of one object, for files whose entries
## are named in messages (`where`, such as "region 'seattle'").

## Where problems go; the caller's list, filled in place.
var errors: Array[String]
## The file's name in messages: "<label> is missing 'a.b'".
var label: String


func _init(p_errors: Array[String], p_label: String) -> void:
	errors = p_errors
	label = p_label


## The value at a dotted `path` ("view.globe.size"), or null (with an
## error) when any step is missing.
func lookup(d: Dictionary, path: String) -> Variant:
	var v: Variant = d
	for key in path.split("."):
		if not v is Dictionary or not (v as Dictionary).has(key):
			errors.append("%s is missing '%s'" % [label, path])
			return null
		v = v[key]
	return v


## The number at `path`, or 0 (with an error) when it is missing or not one.
func num(d: Dictionary, path: String) -> float:
	var v: Variant = lookup(d, path)
	if v == null:
		return 0.0
	if not (v is float or v is int):
		errors.append("%s '%s' must be a number" % [label, path])
		return 0.0
	return float(v)


## The list at `path`, or [] (with an error) when it is missing or not one.
func list(d: Dictionary, path: String) -> Array:
	var v: Variant = lookup(d, path)
	if v == null:
		return []
	if not v is Array:
		errors.append("%s '%s' must be a list" % [label, path])
		return []
	return v


## d[key] when it is a non-empty string, else "" with an error naming `where`.
static func non_empty_string(d: Dictionary, key: String, where: String, errors: Array[String]) -> String:
	var v: Variant = d.get(key)
	if not v is String or (v as String).is_empty():
		errors.append("%s needs a non-empty '%s'" % [where, key])
		return ""
	return v


## d[key] as a number, `fallback` when the key is absent; `fallback` with an
## error naming `where` when it is there but not a number.
static func number_or(d: Dictionary, key: String, fallback: float, where: String, errors: Array[String]) -> float:
	var v: Variant = d.get(key, fallback)
	if not (v is float or v is int):
		errors.append("%s %s must be a number" % [where, key])
		return fallback
	return float(v)
