class_name ScenarioFiles
extends RefCounted
## Reads and writes scenario JSON files, and lists the ones in a folder.
## Files whose names start with "_" are settings, not scenarios, and are skipped.


## The scenario at `path`, or null when the file is missing or not a JSON object.
static func load_scenario(path: String) -> FightScenario:
	if not FileAccess.file_exists(path):
		return null
	var parsed: Variant = JsonFile.read_object(path)
	return FightScenario.from_dict(parsed) if parsed != null else null


static func save_scenario(scenario: FightScenario, path: String) -> Error:
	var made := DirAccess.make_dir_recursive_absolute(path.get_base_dir())
	if made != OK:
		return made
	return JsonFile.write_text(path, JSON.stringify(scenario.to_dict(), "\t", false) + "\n")


## Where a scenario called `scenario_name` is saved in `dir`.
static func path_for(dir: String, scenario_name: String) -> String:
	return dir.path_join("%s.json" % scenario_name.to_snake_case().validate_filename())


## Scenario files in each folder of `dirs`, sorted within each folder.
static func list(dirs: Array[String]) -> Array[String]:
	var out: Array[String] = []
	for dir in dirs:
		var access := DirAccess.open(dir)
		if access == null:
			continue
		var found: Array[String] = []
		for file in access.get_files():
			if file.get_extension() == "json" and not file.begins_with("_"):
				found.append(dir.path_join(file))
		found.sort()
		out.append_array(found)
	return out
