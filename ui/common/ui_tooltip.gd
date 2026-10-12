class_name UiTooltip
extends VBoxContainer
## The standard tooltip: a bold name, one or two plain lines, the numbers, and
## a small box per glossary keyword the lines use.
##
##   UiTooltip.attach(control, "Guard", "Blocks part of the next hits.", "40%", "status_guard")
##
## attach() works on any Control: hovering it for the kit delay shows the
## tooltip by the mouse. Call it again to change the lines; it connects once.

const META := &"ui_tip"

static var _hovered: Control
static var _layer: CanvasLayer

var title: String
var body: String
var numbers: String
var icon_id: String


## A tooltip panel, built now. Shown by attach(); tests build it directly.
static func build(p_title: String, p_body: String, p_numbers := "", p_icon_id := "") -> UiTooltip:
	var tip := UiTooltip.new()
	tip.title = p_title
	tip.body = p_body
	tip.numbers = p_numbers
	tip.icon_id = p_icon_id
	tip._compose()
	return tip


## Gives `control` this tooltip on hover.
static func attach(control: Control, p_title: String, p_body: String, p_numbers := "", p_icon_id := "") -> void:
	var first := not control.has_meta(META)
	control.set_meta(META, {"title": p_title, "body": p_body, "numbers": p_numbers, "icon": p_icon_id})
	if not first:
		return
	if control.mouse_filter == Control.MOUSE_FILTER_IGNORE:
		control.mouse_filter = Control.MOUSE_FILTER_PASS
	control.mouse_entered.connect(_on_enter.bind(control))
	control.mouse_exited.connect(_on_exit.bind(control))
	control.tree_exiting.connect(_on_exit.bind(control))


## What attach() stored on `control`: title, body, numbers, icon.
static func spec(control: Control) -> Dictionary:
	return control.get_meta(META, {})


## Glossary keywords this tooltip explains, in order of first use.
func keywords() -> Array[String]:
	return UiGlossary.find_keywords(body + " " + numbers)


func _compose() -> void:
	name = "UiTooltip"
	theme = PixelTheme.theme()
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_theme_constant_override("separation", 4)
	var width := float(UiIcons.kit("tooltip.width", 260))
	var main := _box("Main")
	var head := HBoxContainer.new()
	head.add_theme_constant_override("separation", 6)
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
	for k in keywords():
		var box := _box("Keyword_%s" % k)
		var row := HBoxContainer.new()
		row.add_theme_constant_override("separation", 6)
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
	v.add_theme_constant_override("separation", 2)
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
	r.mouse_filter = Control.MOUSE_FILTER_IGNORE
	r.add_theme_font_size_override("normal_font_size", PixelTheme.font_size("small"))
	r.add_theme_color_override("default_color", FeelData.color("text"))
	r.text = UiGlossary.highlight(text, _keyword_color())
	return r


## The pixel font has no bold face: an outline in the text's own color
## thickens each glyph by a pixel.
static func _bold(label: Label, color: Color) -> void:
	label.add_theme_color_override("font_color", color)
	label.add_theme_color_override("font_outline_color", color)
	label.add_theme_constant_override("outline_size", 2)
	label.mouse_filter = Control.MOUSE_FILTER_IGNORE


static func _keyword_color() -> Color:
	return FeelData.color(str(UiIcons.kit("tooltip.keyword_color", "preview")))


static func _on_enter(control: Control) -> void:
	_hovered = control
	if not control.is_inside_tree():
		return
	await control.get_tree().create_timer(float(UiIcons.kit("tooltip.delay_seconds", 0.35))).timeout
	if _hovered != control or not is_instance_valid(control) or not control.is_inside_tree():
		return
	_show(control)


static func _on_exit(control: Control) -> void:
	if _hovered == control:
		_hovered = null
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
	var tip := build(s["title"], s["body"], s["numbers"], s["icon"])
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
