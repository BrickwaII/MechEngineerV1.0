class_name FeelData
extends RefCounted
## Reads the presentation tables in data/feel/ once and hands out values.
## Every timing, color and sound setting the feel kit uses comes from here.

const PALETTE_PATH := "res://data/feel/palette.json"
const FEEL_PATH := "res://data/feel/feel.json"
const AUDIO_PATH := "res://data/feel/audio.json"
const SETTINGS_PATH := "res://data/feel/settings.json"
const MANIFEST_PATH := "res://data/feel/sprite_manifest.json"

static var _tables := {}
static var _colors := {}


static func table(path: String) -> Dictionary:
	if not _tables.has(path):
		var parsed: Variant = JSON.parse_string(FileAccess.get_file_as_string(path))
		if parsed is Dictionary:
			_tables[path] = parsed
		else:
			push_error("FeelData: could not read %s" % path)
			_tables[path] = {}
	return _tables[path]


static func palette() -> Dictionary:
	return table(PALETTE_PATH)


static func feel() -> Dictionary:
	return table(FEEL_PATH)


static func audio() -> Dictionary:
	return table(AUDIO_PATH)


static func settings() -> Dictionary:
	return table(SETTINGS_PATH)


static func manifest() -> Dictionary:
	return table(MANIFEST_PATH)


## A named palette color. Unknown names come back magenta so they stand out.
static func color(name: String) -> Color:
	if not _colors.has(name):
		var hex: Variant = palette().get(name)
		if hex is String:
			_colors[name] = Color(hex)
		else:
			push_warning("FeelData: no palette color '%s'" % name)
			return Color.MAGENTA
	return _colors[name]


## A number from feel.json at a dotted path such as "hit_pause.light_ms".
static func number(path: String, fallback: float = 0.0) -> float:
	var node: Variant = feel()
	for key in path.split("."):
		if not (node is Dictionary) or not node.has(key):
			return fallback
		node = node[key]
	return float(node) if (node is float or node is int) else fallback


## Drops cached tables, so edited data files are read again.
static func reload() -> void:
	_tables.clear()
	_colors.clear()
