class_name UiGlossary
extends RefCounted
## Keywords that tooltips and cards highlight, from data/ui/glossary.json.
## Each keyword found in a text gets its own small box under the tooltip,
## like Slay the Spire keywords.

const PATH := "res://data/ui/glossary.json"


static func keywords() -> Dictionary:
	return FeelData.table(PATH).get("keywords", {})


## The keyword as the glossary spells it, or "" when `word` is not one.
static func keyword(word: String) -> String:
	for k: String in keywords():
		if k.to_lower() == word.to_lower():
			return k
	return ""


static func entry(word: String) -> Dictionary:
	var k := keyword(word)
	return keywords()[k] if not k.is_empty() else {}


## Keywords in `text`, whole words, ignoring case, in order of first use.
static func find_keywords(text: String) -> Array[String]:
	var found: Array[String] = []
	for m in _regex().search_all(text):
		var k := keyword(m.get_string(1))
		if not k.is_empty() and not k in found:
			found.append(k)
	return found


## `text` as BBCode with each keyword colored. Brackets in `text` are escaped.
static func highlight(text: String, color: Color) -> String:
	var escaped := text.replace("[", "[lb]")
	var out := ""
	var at := 0
	for m in _regex().search_all(escaped):
		if keyword(m.get_string(1)).is_empty():
			continue
		out += escaped.substr(at, m.get_start(1) - at)
		out += "[color=#%s]%s[/color]" % [color.to_html(false), m.get_string(1)]
		at = m.get_end(1)
	return out + escaped.substr(at)


static func _regex() -> RegEx:
	var words: Array[String] = []
	for k: String in keywords():
		words.append(k)
	var re := RegEx.new()
	re.compile("(?i)\\b(%s)\\b" % "|".join(words) if not words.is_empty() else "(?!)")
	return re
