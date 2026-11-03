class_name CsvFile
extends RefCounted
## Appends rows to a comma-separated file, writing the header first when the
## file is new. Values are quoted when they hold a comma, quote or newline.


## Appends `rows` (each an Array of values) to `path`. Creates the folder and,
## for a new or empty file, writes `header` first. Returns the error, or OK.
static func append(path: String, header: Array, rows: Array) -> Error:
	var dir := path.get_base_dir()
	if not DirAccess.dir_exists_absolute(dir):
		var made := DirAccess.make_dir_recursive_absolute(dir)
		if made != OK:
			return made
	var is_new := not FileAccess.file_exists(path)
	var f := FileAccess.open(path, FileAccess.READ_WRITE if not is_new else FileAccess.WRITE)
	if f == null:
		return FileAccess.get_open_error()
	if not is_new and f.get_length() == 0:
		is_new = true
	f.seek_end()
	if is_new:
		f.store_string(line(header) + "\n")
	for row: Array in rows:
		f.store_string(line(row) + "\n")
	f.close()
	return OK


## One CSV line for `values`.
static func line(values: Array) -> String:
	var parts := PackedStringArray()
	for v: Variant in values:
		parts.append(cell(v))
	return ",".join(parts)


static func cell(v: Variant) -> String:
	var s := str(v)
	if s.contains(",") or s.contains("\"") or s.contains("\n"):
		return "\"%s\"" % s.replace("\"", "\"\"")
	return s
