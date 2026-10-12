class_name UiGlossary
extends RefCounted
## Keywords that descriptions highlight, from data/ui/glossary.json, like
## Slay the Spire keywords. highlight() colors and underlines each keyword as
## a link ([url=kw:Pierce]); wire() makes a RichTextLabel's links show the
## keyword's box on hover and pin it on click (KeywordPopup).
##
##   var r := UiGlossary.rich("Deal 9. Pierce 20%.", PixelTheme.font_size("small"))

const PATH := "res://data/ui/glossary.json"
## Meta prefix of a keyword link.
const LINK := "kw:"
## Label meta holding its plain text, for restyle().
const TEXT_META := &"ui_keyword_text"

static var _forms := {}
static var _re: RegEx


static func keywords() -> Dictionary:
	return FeelData.table(PATH).get("keywords", {})


## The keyword as the glossary spells it, for the keyword itself or any of its
## aliases, ignoring case; "" when `word` is none.
static func keyword(word: String) -> String:
	return _form_table().get(word.to_lower(), "")


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


## `text` as BBCode with each keyword a colored link to its box, with a
## dotted underline that follows wrapped lines (RichTextLabel draws [hint]
## dashed; the empty hint shows no tooltip of its own):
##   [url=kw:Pierce][hint=][color=#ffe08a]Piercing[/color][/hint][/url]
## Keywords in `active` (hovered or pinned) get the active look: bright text
## on a highlight. Brackets in `text` are escaped.
static func highlight(text: String, color: Color, active: Array = []) -> String:
	var escaped := text.replace("[", "[lb]")
	var out := ""
	var at := 0
	for m in _regex().search_all(escaped):
		var k := keyword(m.get_string(1))
		if k.is_empty():
			continue
		out += escaped.substr(at, m.get_start(1) - at)
		if k in active:
			out += "[url=%s%s][hint=][bgcolor=#%s][color=#%s]%s[/color][/bgcolor][/hint][/url]" % [
				LINK, k, active_back().to_html(false), FeelData.color("text_bright").to_html(false), m.get_string(1)]
		else:
			out += "[url=%s%s][hint=][color=#%s]%s[/color][/hint][/url]" % [LINK, k, color.to_html(false), m.get_string(1)]
		at = m.get_end(1)
	return out + escaped.substr(at)


## The keyword a link's meta names, or "" for any other meta.
static func link_keyword(meta: Variant) -> String:
	var s := str(meta)
	return keyword(s.trim_prefix(LINK)) if s.begins_with(LINK) else ""


## The kit's keyword color (ui_kit.json tooltip.keyword_color).
static func color() -> Color:
	return FeelData.color(str(UiIcons.kit("tooltip.keyword_color", "preview")))


## The highlight behind a hovered or pinned keyword.
static func active_back() -> Color:
	return FeelData.color(str(UiIcons.kit("tooltip.keyword_active_back", "panel_border_light")))


## Shows `text` in a wired `label` with its keywords highlighted, and keeps
## the plain text so the label can restyle when a keyword is hovered or pinned.
static func set_text(label: RichTextLabel, text: String) -> void:
	label.set_meta(TEXT_META, text)
	restyle(label, KeywordPopup.shown())


## Redraws `label`'s keywords with those in `active` in the active look.
static func restyle(label: RichTextLabel, active: Array) -> void:
	if label.has_meta(TEXT_META):
		label.text = highlight(str(label.get_meta(TEXT_META)), color(), active)


## Makes `label`'s keyword links live: hover shows the keyword's box, click
## pins it. The label passes other clicks on to what is under it.
static func wire(label: RichTextLabel) -> void:
	if label.meta_hover_started.is_connected(KeywordPopup.hover):
		return
	label.meta_underlined = false
	label.hint_underlined = true
	# PASS: the label sees its links, other clicks reach the card or button under it.
	label.mouse_filter = Control.MOUSE_FILTER_PASS
	label.meta_hover_started.connect(KeywordPopup.hover.bind(label))
	label.meta_hover_ended.connect(KeywordPopup.unhover.bind(label))
	label.meta_clicked.connect(KeywordPopup.click.bind(label))


## A wired RichTextLabel showing `text` with its keywords highlighted.
static func rich(text: String, font_size: int, text_color := Color(0, 0, 0, 0), width := 0.0) -> RichTextLabel:
	var r := RichTextLabel.new()
	r.bbcode_enabled = true
	r.fit_content = true
	r.scroll_active = false
	r.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	if width > 0.0:
		r.custom_minimum_size.x = width
	r.add_theme_font_size_override("normal_font_size", font_size)
	r.add_theme_color_override("default_color", text_color if text_color.a > 0.0 else FeelData.color("text"))
	wire(r)
	set_text(r, text)
	return r


## Drops cached lookups, so an edited glossary is read again.
static func reload() -> void:
	_forms = {}
	_re = null


static func _form_table() -> Dictionary:
	if _forms.is_empty():
		for k: String in keywords():
			_forms[k.to_lower()] = k
			for a in (keywords()[k] as Dictionary).get("aliases", []):
				_forms[str(a).to_lower()] = k
	return _forms


static func _regex() -> RegEx:
	if _re == null:
		var forms: Array = _form_table().keys()
		# Longest first, so "Low Energy" wins over "Energy".
		forms.sort_custom(func(a: String, b: String) -> bool: return a.length() > b.length())
		var escaped: Array[String] = []
		for f: String in forms:
			escaped.append(_escape(f))
		_re = RegEx.new()
		_re.compile("(?i)\\b(%s)\\b" % "|".join(escaped) if not escaped.is_empty() else "(?!)")
	return _re


static func _escape(s: String) -> String:
	var out := ""
	for c in s:
		out += ("\\" + c) if c in ".^$*+?()[]{}|\\" else c
	return out
