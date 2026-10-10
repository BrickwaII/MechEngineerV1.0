class_name FactionLookup
extends RefCounted
## Which enemy faction holds a region, for the territory panel, read from the
## faction table in data/combat/ (P4's). Missing file, missing entry or a
## faction with no name: no faction, and the panel shows nothing.
##
## TODO(decision: faction-table-format): P4's table is not in yet. Default
## shape, read from FACTIONS_PATH:
##     {"factions": {"<id>": {"name": "...", "color": "#rrggbb", "icon": "res://..."}},
##      "by_region": {"<region set id>": {"<region id>": "<faction id>"}},
##      "by_act": {"<act index from 0>": "<faction id>"}}
## by_region wins over by_act. color and icon are optional.

const FACTIONS_PATH := "res://data/combat/factions.json"

var factions := {}
var by_region := {}
var by_act := {}


static func load_default() -> FactionLookup:
	return load_file(FACTIONS_PATH)


## Reads `path`; a missing or unreadable file gives an empty lookup.
static func load_file(path: String) -> FactionLookup:
	var lookup := FactionLookup.new()
	if not FileAccess.file_exists(path):
		return lookup
	var parsed: Variant = JSON.parse_string(FileAccess.get_file_as_string(path))
	if parsed is Dictionary:
		lookup.read(parsed)
	return lookup


func read(data: Dictionary) -> void:
	factions = data.get("factions", {}) if data.get("factions") is Dictionary else {}
	by_region = data.get("by_region", {}) if data.get("by_region") is Dictionary else {}
	by_act = data.get("by_act", {}) if data.get("by_act") is Dictionary else {}


## The faction holding `region_id` on map `map_id` in act `act` (0-based):
## {"id", "name", "color": Color or null, "icon": Texture2D or null}, or {}.
func faction_for(map_id: String, act: int, region_id: String) -> Dictionary:
	var id := ""
	var regions: Variant = by_region.get(map_id)
	if regions is Dictionary and regions.get(region_id) is String:
		id = regions[region_id]
	elif by_act.get(str(act)) is String:
		id = by_act[str(act)]
	var def: Variant = factions.get(id)
	if id.is_empty() or not (def is Dictionary) or not (def.get("name") is String):
		return {}
	var color: Variant = null
	if def.get("color") is String and Color.html_is_valid(def["color"]):
		color = Color(def["color"])
	var icon: Texture2D = null
	if def.get("icon") is String and ResourceLoader.exists(def["icon"]):
		icon = load(def["icon"]) as Texture2D
	return {"id": id, "name": def["name"], "color": color, "icon": icon}
