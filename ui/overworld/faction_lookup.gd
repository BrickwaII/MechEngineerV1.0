class_name FactionLookup
extends RefCounted
## Which enemy faction holds a region, for the territory panel. The answer
## comes from P4's FactionTable (fight/faction_table.gd over
## data/combat/factions.json) when that script exists; without it, or when
## the table names no faction for the region, the panel shows nothing.
##
## TODO(decision: faction-table-api): FactionTable is not merged yet. The
## agreed calls are FactionTable.faction_for_region(region_id) (region ids are
## unique across acts) and FactionTable.faction_of(act_id, region_id); either
## may return a Dictionary or an object with a name (or display_name) and a
## color, and optionally an icon (a Texture2D or a res:// path). This reader
## accepts any of those.

const TABLE_PATH := "res://fight/faction_table.gd"

## Callable(map_id: String, act: int, region_id: String) -> Variant: what the
## table says about a region, or null.
var source := Callable()
## Data set in place of the table (tests, demos), as
##     {"factions": {"<id>": {"name", "color", "icon"}},
##      "by_region": {"<region set id>": {"<region id>": "<faction id>"}},
##      "by_act": {"<act index from 0>": "<faction id>"}}
var _data := {}


## The lookup over FactionTable, or an empty one when it is not there.
static func load_default() -> FactionLookup:
	var lookup := FactionLookup.new()
	if not ResourceLoader.exists(TABLE_PATH):
		return lookup
	var script := load(TABLE_PATH) as GDScript
	if script == null or not script.can_instantiate():
		return lookup
	lookup.source = func(_map_id: String, act: int, region_id: String) -> Variant:
		return _ask_table(script, act, region_id)
	return lookup


## Uses `data` (the shape above) instead of the table.
func read(data: Dictionary) -> void:
	_data = data
	source = _from_data


## The faction holding `region_id` on map `map_id` in act `act` (0-based):
## {"id", "name", "color": Color or null, "icon": Texture2D or null}, or {}.
func faction_for(map_id: String, act: int, region_id: String) -> Dictionary:
	if not source.is_valid():
		return {}
	return normalize(source.call(map_id, act, region_id))


## A faction as the table gave it, in the panel's shape, or {}.
static func normalize(faction: Variant) -> Dictionary:
	var get_field := func(key: String) -> Variant: return null
	if faction is Dictionary:
		get_field = func(key: String) -> Variant: return faction.get(key)
	elif faction is Object and faction != null:
		get_field = func(key: String) -> Variant: return faction.get(key) if key in faction else null
	else:
		return {}
	var name: Variant = get_field.call("name")
	if not (name is String) or (name as String).is_empty():
		name = get_field.call("display_name")
	if not (name is String) or (name as String).is_empty():
		return {}
	var color: Variant = get_field.call("color")
	if color is String:
		color = Color(color) if Color.html_is_valid(color) else null
	elif not (color is Color):
		color = null
	var icon: Variant = get_field.call("icon")
	if icon is String:
		icon = load(icon) as Texture2D if ResourceLoader.exists(icon) else null
	elif not (icon is Texture2D):
		icon = null
	var id: Variant = get_field.call("id")
	return {"id": str(id) if id != null else name, "name": name, "color": color, "icon": icon}


static func _ask_table(script: GDScript, act: int, region_id: String) -> Variant:
	var statics := {}
	for method in script.get_script_method_list():
		statics[method["name"]] = (int(method["flags"]) & METHOD_FLAG_STATIC) != 0
	var target: Object = script
	if (statics.has("faction_for_region") and not statics["faction_for_region"]) \
			or (statics.has("faction_of") and not statics["faction_of"]):
		target = script.new()
	if statics.has("faction_for_region"):
		var found: Variant = target.call("faction_for_region", region_id)
		if found != null:
			return found
	if statics.has("faction_of"):
		return target.call("faction_of", act, region_id)
	return null


func _from_data(map_id: String, act: int, region_id: String) -> Variant:
	var factions: Dictionary = _data.get("factions", {}) if _data.get("factions") is Dictionary else {}
	var id: Variant = null
	var regions: Variant = (_data.get("by_region", {}) as Dictionary).get(map_id) if _data.get("by_region") is Dictionary else null
	if regions is Dictionary and regions.get(region_id) is String:
		id = regions[region_id]
	elif _data.get("by_act") is Dictionary and _data["by_act"].get(str(act)) is String:
		id = _data["by_act"][str(act)]
	if id == null or not (factions.get(id) is Dictionary):
		return null
	var def: Dictionary = factions[id].duplicate()
	def["id"] = id
	return def
