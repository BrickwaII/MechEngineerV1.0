class_name JsonFile
extends RefCounted
## Reads and writes JSON files. Every layer reads its tuning this way.
##
##   var d: Variant = JsonFile.read_object(path)    # Dictionary, or null
##   if d == null:
##       push_error("cannot read %s" % path)
##
## read_object_cached() reads a file once per path and hands out deep copies,
## for the shipped data files that simulations load over and over.

static var _cache: Dictionary = {}


## The parsed contents of `path`, or null when it is missing or not JSON.
static func read(path: String) -> Variant:
	return JSON.parse_string(FileAccess.get_file_as_string(path))


## The JSON object in `path`, or null when the file is missing, is not JSON
## or holds something other than an object.
static func read_object(path: String) -> Variant:
	var parsed: Variant = read(path)
	return parsed if parsed is Dictionary else null


## The JSON object in `path`, or {} when there is none.
static func read_dict(path: String) -> Dictionary:
	var parsed: Variant = read(path)
	return parsed if parsed is Dictionary else {}


## read_object(), but the file is read only the first time; later calls get
## a deep copy of what was read, so a caller may change what it gets. For
## shipped data files only: a change to the file on disk is not seen.
static func read_object_cached(path: String) -> Variant:
	if not _cache.has(path):
		var parsed: Variant = read_object(path)
		if parsed == null:
			return null
		_cache[path] = parsed
	return (_cache[path] as Dictionary).duplicate(true)


## Forgets every file read_object_cached() has read.
static func clear_cache() -> void:
	_cache.clear()


## Writes `text` to `path`, replacing it. Returns the open error, or OK.
static func write_text(path: String, text: String) -> Error:
	var file := FileAccess.open(path, FileAccess.WRITE)
	if file == null:
		return FileAccess.get_open_error()
	file.store_string(text)
	file.close()
	return OK


## Writes `value` to `path` as JSON (JSON.stringify's arguments), replacing it.
static func write(path: String, value: Variant, indent := "", sort_keys := true, full_precision := false) -> Error:
	return write_text(path, JSON.stringify(value, indent, sort_keys, full_precision))
