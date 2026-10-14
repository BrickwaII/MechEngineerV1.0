class_name HowToPlay
extends RefCounted
## The How to play guide: one illustrated page per topic (the run, the map,
## fights, growth), each line an icon and a short sentence whose keywords are
## glossary links. Text in data/ui/how_to_play.json; shown in a DetailModal
## with a tab per page.
##
##   DetailModal.open(self, HowToPlay.spec())

const DATA_PATH := "res://data/ui/how_to_play.json"


static func pages() -> Array:
	return FeelData.table(DATA_PATH).get("pages", [])


static func spec() -> Dictionary:
	var sections: Array = []
	for p: Dictionary in pages():
		sections.append({"id": str(p.get("id", "")), "title": str(p.get("title", "")),
			"icon": str(p.get("icon", "")), "content": page(p)})
	return {"title": "How to play", "icon": "guide", "sections": sections}


## One page: its lines as rows of a large icon and a sentence.
static func page(p: Dictionary) -> Control:
	var col := UiStyle.column("m")
	col.name = "Page_%s" % str(p.get("id", ""))
	for line: Dictionary in p.get("lines", []):
		var row := UiStyle.row("m")
		var icon := EntryTile.icon_art(str(line.get("icon", "unknown")), 3)
		icon.size_flags_vertical = Control.SIZE_SHRINK_BEGIN
		row.add_child(icon)
		var text := DetailModal.prose(str(line.get("text", "")))
		text.size_flags_vertical = Control.SIZE_SHRINK_CENTER
		row.add_child(text)
		col.add_child(row)
	return col
