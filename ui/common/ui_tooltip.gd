class_name UiTooltip
extends VBoxContainer
## The standard tooltip: a bold name, one or two plain lines, the numbers, and
## a small box per glossary keyword the lines use.
##
##   UiTooltip.attach(control, "Guard", "Blocks part of the next hits.", "40%", "status_guard")
##
## A tooltip can also explain its math: formula lines built from the real
## values (UiFormula), shown under the numbers:
##
##   UiTooltip.set_math(badge, [UiFormula.parse("{ATK} − {DEF}", {"ATK": 12, "DEF": 8}, 4)])
##
## attach() works on any Control: hovering it for the kit delay shows the
## tooltip by the mouse. Call it again to change the lines; it connects once.

const META := &"ui_tip"

static var _hovered: Control
static var _layer: CanvasLayer

var title: String
var body: String
## The control whose hover shows this tooltip (when shown by hover).
var _source: Control
var _away := 0.0
var numbers: String
var icon_id: String
## Formula lines as bbcode (see math_lines()).
var math: Array[String] = []


## A tooltip panel, built now. Shown by attach(); tests build it directly.
static func build(p_title: String, p_body: String, p_numbers := "", p_icon_id := "", p_math: Array = []) -> UiTooltip:
	var tip := UiTooltip.new()
	tip.title = p_title
	tip.body = p_body
	tip.numbers = p_numbers
	tip.icon_id = p_icon_id
	tip.math = math_lines(p_math)
	tip._compose()
	return tip


## Gives `control` this tooltip on hover.
static func attach(control: Control, p_title: String, p_body: String, p_numbers := "", p_icon_id := "", p_math: Array = []) -> void:
	var first := not control.has_meta(META)
	control.set_meta(META, {"title": p_title, "body": p_body, "numbers": p_numbers, "icon": p_icon_id, "math": math_lines(p_math)})
	if not first:
		return
	if control.mouse_filter == Control.MOUSE_FILTER_IGNORE:
		control.mouse_filter = Control.MOUSE_FILTER_PASS
	control.mouse_entered.connect(_on_enter.bind(control))
	control.mouse_exited.connect(_on_exit.bind(control))
	control.tree_exiting.connect(_on_exit.bind(control))


## What attach() stored on `control`: title, body, numbers, icon, math.
static func spec(control: Control) -> Dictionary:
	return control.get_meta(META, {})


## Sets the formula lines of `control`'s tooltip (after attach()).
static func set_math(control: Control, lines: Array) -> void:
	if not control.has_meta(META):
		attach(control, "", "")
	var s: Dictionary = control.get_meta(META)
	s["math"] = math_lines(lines)
	control.set_meta(META, s)


## Formula lines as bbcode: a UiFormula renders colored, a String shows as
## plain text.
static func math_lines(lines: Array) -> Array[String]:
	var out: Array[String] = []
	for line: Variant in lines:
		if line is UiFormula:
			out.append((line as UiFormula).bbcode())
		elif line is String and not (line as String).is_empty():
			out.append((line as String).replace("[", "[lb]"))
	return out


func _process(delta: float) -> void:
	if _source == null:
		return
	var mouse := get_global_mouse_position()
	var over := get_global_rect().grow(4).has_point(mouse) or \
		(is_instance_valid(_source) and _source.is_visible_in_tree() and _source.get_global_rect().has_point(mouse))
	_away = 0.0 if over else _away + delta
	if _away > float(UiIcons.kit("tooltip.grace_seconds", 0.25)):
		UiTooltip._hide()


## Glossary keywords this tooltip explains, in order of first use.
func keywords() -> Array[String]:
	return UiGlossary.find_keywords(body + " " + numbers)


func _compose() -> void:
	name = "UiTooltip"
	theme = PixelTheme.theme()
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_theme_constant_override("separation", UiStyle.space("xs"))
	process_mode = Node.PROCESS_MODE_ALWAYS
	var width := float(UiIcons.kit("tooltip.width", 260))
	var main := _box("Main")
	var head := HBoxContainer.new()
	head.add_theme_constant_override("separation", UiStyle.space("s"))
	head.mouse_filter = Control.MOUSE_FILTER_IGNORE
	main.add_child(head)
	if not icon_id.is_empty():
		head.add_child(UiIcons.rect(icon_id))
	var name_label := Label.new()
	name_label.name = "Title"
	name_label.text = title
	_bold(name_label, FeelData.color("text_bright"))
	head.add_child(name_label)
	if not body.is_empty():
		main.add_child(_rich("Body", body, width))
	if not numbers.is_empty():
		var n := _rich("Numbers", numbers, width)
		n.add_theme_color_override("default_color", FeelData.color(str(UiIcons.kit("tooltip.number_color", "text_bright"))))
		main.add_child(n)
	if not math.is_empty():
		var rule := HSeparator.new()
		rule.mouse_filter = Control.MOUSE_FILTER_IGNORE
		rule.add_theme_constant_override("separation", UiStyle.space("xs"))
		main.add_child(rule)
		var m := RichTextLabel.new()
		m.name = "Math"
		m.bbcode_enabled = true
		m.fit_content = true
		m.scroll_active = false
		m.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		# A formula reads best on one line: widen for it, up to the kit's limit.
		var longest := 0
		for line in math:
			longest = maxi(longest, _plain(line).length())
		var advance := PixelTheme.font().get_string_size("0", HORIZONTAL_ALIGNMENT_LEFT, -1, text_size()).x
		m.custom_minimum_size = Vector2(clampf(longest * advance + 8.0, width, float(UiIcons.kit("math.max_width", 600))), 0)
		m.mouse_filter = Control.MOUSE_FILTER_IGNORE
		m.add_theme_font_size_override("normal_font_size", text_size())
		m.add_theme_color_override("default_color", FeelData.color("text"))
		m.text = "\n".join(math)
		main.add_child(m)
	for k in keywords():
		var box := _box("Keyword_%s" % k)
		var row := HBoxContainer.new()
		row.add_theme_constant_override("separation", UiStyle.space("s"))
		row.mouse_filter = Control.MOUSE_FILTER_IGNORE
		box.add_child(row)
		var e := UiGlossary.entry(k)
		if e.has("icon"):
			row.add_child(UiIcons.rect(str(e["icon"])))
		var kl := Label.new()
		kl.text = k
		_bold(kl, _keyword_color())
		row.add_child(kl)
		box.add_child(_rich("Text", str(e.get("text", "")), width))


func _box(box_name: String) -> VBoxContainer:
	var panel := PanelContainer.new()
	panel.name = box_name
	panel.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(panel)
	var v := VBoxContainer.new()
	v.add_theme_constant_override("separation", UiStyle.space("xs"))
	v.mouse_filter = Control.MOUSE_FILTER_IGNORE
	panel.add_child(v)
	return v


func _rich(label_name: String, text: String, width: float) -> RichTextLabel:
	var r := RichTextLabel.new()
	r.name = label_name
	r.bbcode_enabled = true
	r.fit_content = true
	r.scroll_active = false
	r.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	r.custom_minimum_size = Vector2(width, 0)
	r.add_theme_font_size_override("normal_font_size", text_size())
	r.add_theme_color_override("default_color", FeelData.color("text"))
	# Keywords are links: hover shows their box, click pins it.
	UiGlossary.wire(r)
	UiGlossary.set_text(r, text)
	return r


## The pixel font has no bold face: an outline in the text's own color
## thickens each glyph by a pixel.
static func _bold(label: Label, color: Color) -> void:
	label.add_theme_color_override("font_color", color)
	label.add_theme_color_override("font_outline_color", color)
	label.add_theme_constant_override("outline_size", 2)
	label.mouse_filter = Control.MOUSE_FILTER_IGNORE


static func _plain(bbcode: String) -> String:
	var re := RegEx.create_from_string("\\[[^\\]]*\\]")
	return re.sub(bbcode, "", true)


## The size of tooltip text: body size, so nothing the player reads is tiny.
static func text_size() -> int:
	return PixelTheme.font_size(str(UiIcons.kit("tooltip.font_size", "body")))


static func _keyword_color() -> Color:
	return UiGlossary.color()


static func _on_enter(control: Control) -> void:
	_hovered = control
	if not control.is_inside_tree():
		return
	await control.get_tree().create_timer(float(UiIcons.kit("tooltip.delay_seconds", 0.35))).timeout
	if _hovered != control or not is_instance_valid(control) or not control.is_inside_tree():
		return
	_show(control)


## Leaving the control does not close its tooltip at once: the pointer may
## cross to the tooltip to reach its keywords. _process closes it once the
## pointer is over neither for the grace time.
static func _on_exit(control: Control) -> void:
	if _hovered == control:
		_hovered = null
	if not is_instance_valid(control) or not control.is_inside_tree():
		_hide()


static func _show(control: Control) -> void:
	show_at(control, control.get_global_mouse_position() + UiIcons.kit_vector("tooltip.offset", Vector2(16, 16)))


## Shows `control`'s tooltip now with its corner at `at`, kept on screen.
## Hover calls it; demos and screenshots call it directly.
static func show_at(control: Control, at: Vector2) -> void:
	_hide()
	var s := spec(control)
	if s.is_empty():
		return
	_layer = CanvasLayer.new()
	_layer.name = "UiTooltipLayer"
	_layer.layer = 100
	control.get_tree().root.add_child(_layer)
	var tip := UiTooltip.new()
	tip.title = s["title"]
	tip.body = s["body"]
	tip.numbers = s["numbers"]
	tip.icon_id = s["icon"]
	tip.math.assign(s.get("math", []))
	tip._compose()
	tip._source = control
	_layer.add_child(tip)
	tip.reset_size()
	var view := control.get_viewport().get_visible_rect().size
	tip.position = Vector2(clampf(at.x, 0, maxf(0, view.x - tip.size.x)), clampf(at.y, 0, maxf(0, view.y - tip.size.y)))


static func hide_tooltip() -> void:
	_hide()


static func _hide() -> void:
	if _layer != null and is_instance_valid(_layer):
		_layer.queue_free()
	_layer = null
