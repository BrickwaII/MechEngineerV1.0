class_name DebugChange
extends RefCounted
## One tweak in the battle debugger's change log (S9b): what was changed,
## from what to what, at which decision. Changes to a definition in data/
## (an action, an AI weight) name the file and the key path Save to data
## writes; everything else (a unit's hp, a forced intent, a rewind) lives only
## in the session.

const KIND_ACTION := "action"
const KIND_AI := "ai"
const KIND_PERSONALITY := "personality"
const KIND_UNIT := "unit"
const KIND_STATUS := "status"
const KIND_TIMELINE := "timeline"
const KIND_INTENT := "intent"
const KIND_ROSTER := "roster"
const KIND_TIME := "time"

## Order in the log, from 1.
var seq := 0
## Fight.action_count when made.
var at_action := 0
var kind := ""
## What was changed: an action id, a unit id, a weight name.
var subject := ""
var field := ""
var before: Variant
var after: Variant
## BattleDebugSession.FILE_* of the data file the change belongs in; "" for
## a session-only change.
var file := ""
## Keys from the file's top level down to the value.
var data_path: Array = []
## The value a data file means when it leaves the key out (an action's
## recovery 0, say), so saving that value to a file without the key adds
## nothing. Only read when has_default.
var default_value: Variant
var has_default := false
## True once Save to data has written it.
var saved := false
## Rewinding past a change to fight state undoes it; it stays in the log, marked.
var undone := false


func is_data() -> bool:
	return not file.is_empty()


func text() -> String:
	var where := " [%s]" % file if is_data() else ""
	var marks := ""
	if saved:
		marks += " (saved)"
	if undone:
		marks += " (rewound)"
	var what := subject if field.is_empty() else "%s.%s" % [subject, field]
	if before == null and after == null:
		return "#%d @%d %s %s%s%s" % [seq, at_action, kind, what, where, marks]
	return "#%d @%d %s %s: %s -> %s%s%s" % [seq, at_action, kind, what, _show(before), _show(after), where, marks]


func to_dict() -> Dictionary:
	return {"seq": seq, "at_action": at_action, "kind": kind, "subject": subject, "field": field,
		"before": before, "after": after, "file": file, "data_path": data_path.duplicate(), "saved": saved,
		"undone": undone}


static func _show(v: Variant) -> String:
	if v == null:
		return "-"
	if typeof(v) == TYPE_STRING:
		return "\"%s\"" % v
	return str(v)
