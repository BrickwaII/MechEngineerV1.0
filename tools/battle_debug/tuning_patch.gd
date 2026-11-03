class_name TuningPatch
extends RefCounted
## What the battle debugger's Save to data would write (S9b): for each data
## file touched, its text now, its text with the chosen changes, and the line
## diff between them. Nothing is written until write() is called, so the diff
## can be shown first.
##
## Each change is written into the file's existing text (JsonTextPatch), so
## the file keeps its layout and the diff is one line per changed entry.

## One entry per file, in the order first changed: {"file": data file key,
## "path": res:// path, "before": text, "after": text, "diff": LineDiff text,
## "seqs": the DebugChange seqs written}.
var files: Array[Dictionary] = []
## Changes left out because the file already holds their value.
var unchanged: Array[DebugChange] = []
var problems: Array[String] = []

## Marks a key a data file lacks, for JsonTextPatch.get_value().
const MISSING := "\u0000missing"


## The patch for `changes` (data changes only; later ones win on the same
## key) against the files at `paths` (data file key -> path).
static func build(changes: Array[DebugChange], paths: Dictionary) -> TuningPatch:
	var patch := TuningPatch.new()
	var texts := {}
	var by_file := {}
	for ch in changes:
		if not ch.is_data():
			continue
		if not paths.has(ch.file):
			patch.problems.append("no data file for %s changes" % ch.file)
			continue
		var path := String(paths[ch.file])
		if not texts.has(ch.file):
			if not FileAccess.file_exists(path):
				patch.problems.append("cannot read %s" % path)
				continue
			texts[ch.file] = FileAccess.get_file_as_string(path)
			by_file[ch.file] = {"file": ch.file, "path": path, "before": texts[ch.file], "seqs": []}
		var text: String = texts[ch.file]
		var held: Variant = JsonTextPatch.get_value(text, ch.data_path, MISSING)
		var absent: bool = typeof(held) == TYPE_STRING and String(held) == MISSING
		var after: Variant = JSON.parse_string(JsonTextPatch.format(ch.after))
		if (absent and ch.has_default and JsonTextPatch.same(after, ch.default_value)) or \
				(not absent and JsonTextPatch.same(held, after)):
			patch.unchanged.append(ch)
			continue
		var r := JsonTextPatch.set_value(text, ch.data_path, ch.after)
		if not String(r.error).is_empty():
			patch.problems.append("%s: %s" % [ch.text(), r.error])
			continue
		texts[ch.file] = r.text
		(by_file[ch.file].seqs as Array).append(ch.seq)
	for key: String in by_file:
		var f: Dictionary = by_file[key]
		f["after"] = texts[key]
		if f.after == f.before:
			continue
		f["diff"] = LineDiff.unified(f.before, f.after, String(f.path).trim_prefix("res://"))
		patch.files.append(f)
	return patch


func is_empty() -> bool:
	return files.is_empty()


## Every file's diff, one after another.
func diff_text() -> String:
	var parts := PackedStringArray()
	for f in files:
		parts.append(f.diff)
	return "\n".join(parts)


## The seqs of every change the patch writes.
func seqs() -> Array[int]:
	var out: Array[int] = []
	for f in files:
		for s: Variant in f.seqs:
			out.append(int(s))
	return out


## Writes every file. Returns the problems; empty when all were written.
func write() -> Array[String]:
	var out: Array[String] = []
	for f in files:
		var err := JsonFile.write_text(String(f.path), String(f.after))
		if err != OK:
			out.append("cannot write %s (error %d)" % [f.path, err])
	JsonFile.clear_cache()
	return out
