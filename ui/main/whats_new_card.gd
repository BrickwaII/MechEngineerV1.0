class_name WhatsNewCard
extends RefCounted
## The one-time "What's new" card after an update: what changed, as icons and
## short lines, and how to send feedback (F8 in a run). It shows once per id
## in data/ui/whats_new.json; closing it remembers the id in GameSettings.

const DATA_PATH := "res://data/ui/whats_new.json"


static func data() -> Dictionary:
	return FeelData.table(DATA_PATH)


## True when the card for the current id has not been closed yet.
static func is_due(settings: GameSettings = null) -> bool:
	var s := settings if settings != null else GameSettings.shared()
	var id := str(data().get("id", ""))
	return not id.is_empty() and s.whats_new_seen != id


## Opens the card over `host` and marks it seen when it closes.
static func open(host: Node, settings: GameSettings = null) -> DetailModal:
	var s := settings if settings != null else GameSettings.shared()
	var d := data()
	var col := UiStyle.column("m")
	col.name = "WhatsNew"
	for line: Dictionary in d.get("lines", []):
		var row := UiStyle.row("m")
		var icon := EntryTile.icon_art(str(line.get("icon", "new")), 2)
		row.add_child(icon)
		var text := DetailModal.prose(str(line.get("text", "")))
		text.size_flags_vertical = Control.SIZE_SHRINK_CENTER
		row.add_child(text)
		col.add_child(row)
	var feedback := DetailModal.prose(str(d.get("feedback", "")))
	feedback.name = "Feedback"
	feedback.add_theme_color_override("default_color", UiStyle.role("hint"))
	col.add_child(feedback)
	var m := DetailModal.open(host, {"title": str(d.get("title", "What's new")), "icon": "new",
		"flags": [Flag.of("new")], "sections": [{"id": "new", "title": "New", "content": col}]})
	var id := str(d.get("id", ""))
	m.closed.connect(func() -> void: s.set_value("whats_new_seen", id))
	return m
