class_name FightStatsLog
extends RefCounted
## Appends one JSON object per fight to a log file (JSON lines), to tune
## balance from. See SimulatedFight.record() for the fields.


static func append(path: String, record: Dictionary) -> Error:
	return append_all(path, [record])


## Appends every record in one write. Creates the file and its folder if needed.
static func append_all(path: String, records: Array) -> Error:
	var made := DirAccess.make_dir_recursive_absolute(path.get_base_dir())
	if made != OK:
		return made
	var file := FileAccess.open(path, FileAccess.READ_WRITE if FileAccess.file_exists(path) else FileAccess.WRITE)
	if file == null:
		return FileAccess.get_open_error()
	file.seek_end()
	for record: Dictionary in records:
		file.store_line(JSON.stringify(record, "", false))
	file.close()
	return OK


## Every record in the log, oldest first. Lines that are not JSON objects are skipped.
static func read_all(path: String) -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	if not FileAccess.file_exists(path):
		return out
	for line in FileAccess.get_file_as_string(path).split("\n", false):
		var parsed: Variant = JSON.parse_string(line)
		if parsed is Dictionary:
			out.append(parsed)
	return out
