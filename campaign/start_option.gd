class_name StartOption
extends RefCounted
## One starting location from a region file's "starts" list: which regions the
## run begins holding, and the traits that come with them. Plain data.
##
## Traits:
## - income_bonus: extra per-day income for the whole run, keyed like
##   MapRegion.provides. Carries across the act zoom.
## - pressure_rate_factor: factor on the pressure rate of the start regions in
##   this act. Below 1 builds pressure more slowly.
## - energy, material: extra stock at the start of the run.

const MIN_RATE_FACTOR := 0.0
const MAX_RATE_FACTOR := 10.0

var id: String
var name: String
var description: String
var regions: PackedStringArray = []
var income_bonus: Dictionary[String, int] = {}
var pressure_rate_factor := 1.0
var energy := 0.0
var material := 0.0


## The start a region file has without a "starts" list: its starts_owned
## regions and no traits.
static func default_for(map: RegionMap) -> StartOption:
	var start := StartOption.new()
	start.name = map.name
	start.regions = map.starting_ids()
	for key in MapRegion.RESOURCE_KEYS:
		start.income_bonus[key] = 0
	return start


## Builds a start from one entry of a region file's "starts" list. Appends a
## message to `errors` for each problem and returns null if there were any.
## Region ids are checked by RegionMap once every region is read.
static func from_dict(data: Variant, errors: Array[String]) -> StartOption:
	if not data is Dictionary:
		errors.append("a start entry is not an object")
		return null
	var d: Dictionary = data
	var before := errors.size()
	var start := StartOption.new()
	start.id = DataReader.non_empty_string(d, "id", "a start", errors)
	var where := "start '%s'" % start.id
	start.name = DataReader.non_empty_string(d, "name", where, errors)
	start.description = DataReader.non_empty_string(d, "description", where, errors)
	var list: Variant = d.get("regions")
	if not list is Array or (list as Array).is_empty():
		errors.append("%s needs a non-empty 'regions' list" % where)
	else:
		for region_id: Variant in list:
			if region_id is String:
				start.regions.append(region_id)
			else:
				errors.append("%s has a non-string region id" % where)
	var bonus: Variant = d.get("income_bonus", {})
	if not bonus is Dictionary:
		errors.append("%s income_bonus must be an object" % where)
	else:
		for key in MapRegion.RESOURCE_KEYS:
			var v: Variant = (bonus as Dictionary).get(key, 0)
			if not (v is float or v is int) or float(v) != floorf(float(v)) or float(v) < 0.0:
				errors.append("%s income_bonus.%s must be a whole number 0 or more" % [where, key])
			else:
				start.income_bonus[key] = int(v)
	start.pressure_rate_factor = DataReader.number_or(d, "pressure_rate_factor", 1.0, where, errors)
	if start.pressure_rate_factor < MIN_RATE_FACTOR or start.pressure_rate_factor > MAX_RATE_FACTOR:
		errors.append("%s pressure_rate_factor must be %s to %s" % [where, MIN_RATE_FACTOR, MAX_RATE_FACTOR])
	start.energy = DataReader.number_or(d, "energy", 0.0, where, errors)
	start.material = DataReader.number_or(d, "material", 0.0, where, errors)
	if start.energy < 0.0 or start.material < 0.0:
		errors.append("%s energy and material must be 0 or more" % where)
	return start if errors.size() == before else null
