extends RefCounted
## Checks the folder import rules stated in CLAUDE.md.
##
## A file "imports" another layer when it names a res:// or uid:// path inside
## that layer (preload, load, extends, a scene's ext_resource) or uses a
## class_name declared there. Comments do not count; for class names, string
## literals do not count either.

## The layers each layer may import. A layer may always use its own files.
## tests/ and addons/ are not layers and are not checked.
const ALLOWED := {
	"contracts": [],
	"bot_data": ["contracts"],
	"fight": ["contracts", "bot_data", "data"],
	"campaign": ["contracts"],
	"ui": ["contracts", "bot_data", "fight", "campaign", "tools"],
	"tools": ["contracts", "bot_data", "fight", "campaign"],
	"data": [],
}

## Folders that hold no code at all.
const CODE_FREE := ["data"]

const SCANNED_EXTENSIONS := ["gd", "tscn", "tres"]

var _path_regex := RegEx.create_from_string("res://([A-Za-z0-9_]+)/")
var _uid_regex := RegEx.create_from_string("uid://[a-z0-9]+")
var _class_name_regex := RegEx.create_from_string("(?m)^\\s*class_name\\s+([A-Za-z_][A-Za-z0-9_]*)")
var _identifier_regex := RegEx.create_from_string("\\b[A-Za-z_][A-Za-z0-9_]*\\b")


## The layer a res:// path belongs to, or "" when it is in no layer.
static func layer_of(path: String) -> String:
	if not path.begins_with("res://"):
		return ""
	var top := path.trim_prefix("res://").get_slice("/", 0)
	return top if ALLOWED.has(top) else ""


## Reads every scanned file inside a layer folder of the project.
func read_project_files() -> Dictionary:
	var files := {}
	for layer: String in ALLOWED:
		_collect("res://" + layer, files)
	return files


## Returns one message per broken rule in `files` (res:// path -> file text).
## `uid_to_path` turns a uid:// string into a res:// path, or "" if unknown.
func find_violations(files: Dictionary, uid_to_path: Callable = _resolve_uid) -> Array[String]:
	var class_layers := _class_layers(files)
	var violations: Array[String] = []
	for path: String in files:
		var layer := layer_of(path)
		if layer.is_empty():
			continue
		if layer in CODE_FREE and path.get_extension() == "gd":
			violations.append("%s: %s/ holds no code" % [path, layer])
			continue
		var text: String = files[path]
		var is_script := path.get_extension() == "gd"
		var without_comments := _strip(text, false) if is_script else text
		for target in _imported_layers(without_comments, class_layers if is_script else {}, uid_to_path, is_script):
			if target != layer and not target in ALLOWED[layer]:
				violations.append("%s: %s/ may not import %s/" % [path, layer, target])
	return violations


func _imported_layers(text: String, class_layers: Dictionary, uid_to_path: Callable, is_script: bool) -> Array[String]:
	var layers: Array[String] = []
	for m in _path_regex.search_all(text):
		_add_unique(layers, layer_of(m.get_string()))
	for m in _uid_regex.search_all(text):
		_add_unique(layers, layer_of(uid_to_path.call(m.get_string())))
	if is_script:
		for m in _identifier_regex.search_all(_strip(text, true)):
			_add_unique(layers, class_layers.get(m.get_string(), ""))
	return layers


func _class_layers(files: Dictionary) -> Dictionary:
	var result := {}
	for path: String in files:
		if path.get_extension() != "gd":
			continue
		for m in _class_name_regex.search_all(_strip(files[path], true)):
			result[m.get_string(1)] = layer_of(path)
	return result


## Removes comments, and string literals too when `strings` is true.
static func _strip(text: String, strings: bool) -> String:
	var out := PackedStringArray()
	var quote := ""
	var i := 0
	while i < text.length():
		var c := text[i]
		if quote.is_empty():
			if c == "#":
				while i < text.length() and text[i] != "\n":
					i += 1
				continue
			if c == "\"" or c == "'":
				quote = c
				if strings:
					i += 1
					continue
		else:
			if c == "\\":
				if not strings:
					out.append(text.substr(i, 2))
				i += 2
				continue
			if c == quote:
				quote = ""
				if strings:
					i += 1
					continue
			elif strings:
				i += 1
				continue
		out.append(c)
		i += 1
	return "".join(out)


static func _add_unique(layers: Array[String], layer: String) -> void:
	if not layer.is_empty() and not layer in layers:
		layers.append(layer)


static func _resolve_uid(uid: String) -> String:
	var id := ResourceUID.text_to_id(uid)
	if id == ResourceUID.INVALID_ID or not ResourceUID.has_id(id):
		return ""
	return ResourceUID.get_id_path(id)


func _collect(dir_path: String, files: Dictionary) -> void:
	var dir := DirAccess.open(dir_path)
	if dir == null:
		return
	for sub in dir.get_directories():
		_collect(dir_path.path_join(sub), files)
	for file in dir.get_files():
		if file.get_extension() in SCANNED_EXTENSIONS:
			var path := dir_path.path_join(file)
			files[path] = FileAccess.get_file_as_string(path)
