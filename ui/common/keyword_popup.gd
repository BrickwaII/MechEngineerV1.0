class_name KeywordPopup
extends Control
## The keyword box a highlighted keyword pops up (UiGlossary links). Hovering
## a keyword shows its box by the cursor; clicking pins the box until a click
## elsewhere or Esc. A pinned box's own keywords are links too: hover shows
## theirs beside it, click pins theirs instead.
##
## The state is static, so every screen shares one popup:
##   KeywordPopup.hovered, KeywordPopup.pinned, KeywordPopup.shown()

## The keyword under the pointer, or "".
static var hovered := ""
## The pinned keyword, or "".
static var pinned := ""
static var _source: Control
static var _popup: KeywordPopup
## Labels whose keywords took part in a hover or pin, restyled on each change
## so the hovered and pinned keywords show in the active look.
static var _labels: Array[RichTextLabel] = []

var _hover_box: Control
var _pin_box: Control
var _pin_box_keyword := ""


## Keywords whose boxes show now: the pinned one, then the hovered one.
static func shown() -> Array[String]:
	var out: Array[String] = []
	for k in [pinned, hovered]:
		if not k.is_empty() and not k in out:
			out.append(k)
	return out


static func hover(meta: Variant, label: Control = null) -> void:
	var k := UiGlossary.link_keyword(meta)
	# Restyling the label resets its text, which can report the same hover
	# again: nothing changes then.
	if k.is_empty() or (k == hovered and label == _source):
		return
	hovered = k
	_source = label
	_track(label)
	_render(label, true)


static func unhover(meta: Variant, label: Control = null) -> void:
	if UiGlossary.link_keyword(meta) == hovered:
		hovered = ""
		_restyle_all()
		_render(label, false)


static func click(meta: Variant, label: Control = null) -> void:
	var k := UiGlossary.link_keyword(meta)
	if k.is_empty():
		return
	pinned = k
	hovered = ""
	_track(label)
	# The click is the keyword's, not the card's or button's under it.
	if label != null and label.is_inside_tree():
		label.accept_event()
	_render(label, true)


## Closes every box.
static func dismiss() -> void:
	pinned = ""
	hovered = ""
	_restyle_all()
	if _popup != null and is_instance_valid(_popup):
		_popup._refresh(false)


## True while `label` takes part in a hover or pin (its keywords restyle).
static func is_tracked(label: Control) -> bool:
	return label in _labels


static func _track(label: Control) -> void:
	if label is RichTextLabel and not label in _labels:
		_labels.append(label)
	_restyle_all()


static func _restyle_all() -> void:
	var active := shown()
	var keep: Array[RichTextLabel] = []
	for l in _labels:
		if is_instance_valid(l):
			UiGlossary.restyle(l, active)
			if not active.is_empty():
				keep.append(l)
	# With nothing active, every label is back to normal: forget them.
	_labels = keep


## A keyword's box: icon, the keyword, its lines (whose keywords link too).
static func box(k: String) -> PanelContainer:
	var panel := PanelContainer.new()
	panel.name = "KeywordBox_%s" % k
	panel.theme = PixelTheme.theme()
	panel.mouse_filter = Control.MOUSE_FILTER_STOP
	var col := VBoxContainer.new()
	col.add_theme_constant_override("separation", 2)
	col.mouse_filter = Control.MOUSE_FILTER_IGNORE
	panel.add_child(col)
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 6)
	row.mouse_filter = Control.MOUSE_FILTER_IGNORE
	col.add_child(row)
	var e := UiGlossary.entry(k)
	if e.has("icon"):
		row.add_child(UiIcons.rect(str(e["icon"])))
	var title := Label.new()
	title.name = "Title"
	title.text = k
	UiTooltip._bold(title, UiGlossary.color())
	row.add_child(title)
	var text := UiGlossary.rich(str(e.get("text", "")), PixelTheme.font_size("small"), Color(0, 0, 0, 0),
		float(UiIcons.kit("tooltip.width", 260)))
	text.name = "Text"
	col.add_child(text)
	return panel


static func _render(label: Control, at_mouse: bool) -> void:
	if label == null or not label.is_inside_tree():
		return
	if _popup == null or not is_instance_valid(_popup):
		var layer := CanvasLayer.new()
		layer.name = "KeywordPopupLayer"
		layer.layer = 110
		label.get_tree().root.add_child(layer)
		_popup = KeywordPopup.new()
		_popup.name = "KeywordPopup"
		_popup.mouse_filter = Control.MOUSE_FILTER_IGNORE
		_popup.set_anchors_preset(Control.PRESET_FULL_RECT)
		layer.add_child(_popup)
	_popup._refresh(at_mouse)


func _refresh(at_mouse: bool) -> void:
	var mouse := get_global_mouse_position() + UiIcons.kit_vector("tooltip.offset", Vector2(16, 16))
	if _pin_box != null and _pin_box_keyword != pinned:
		_drop(_pin_box)
		_pin_box = null
	if _pin_box == null and not pinned.is_empty():
		_pin_box = box(pinned)
		_pin_box_keyword = pinned
		add_child(_pin_box)
		_place(_pin_box, mouse)
	if _hover_box != null:
		_drop(_hover_box)
		_hover_box = null
	if not hovered.is_empty() and hovered != pinned:
		_hover_box = box(hovered)
		_hover_box.mouse_filter = Control.MOUSE_FILTER_IGNORE
		add_child(_hover_box)
		var at := mouse
		# Beside a pinned box, not over it, when hovering a link inside it.
		if _pin_box != null and _source != null and is_instance_valid(_source) and _pin_box.is_ancestor_of(_source):
			at = Vector2(_pin_box.position.x + _pin_box.size.x + 6.0, _pin_box.position.y)
		_place(_hover_box, at)


## Takes a box out at once (its name is free for the next box), then frees it.
func _drop(b: Control) -> void:
	remove_child(b)
	b.queue_free()


func _place(b: Control, at: Vector2) -> void:
	b.reset_size()
	var view := get_viewport_rect().size
	b.position = Vector2(clampf(at.x, 0, maxf(0, view.x - b.size.x)), clampf(at.y, 0, maxf(0, view.y - b.size.y)))


func _process(_delta: float) -> void:
	# A hovered keyword whose label went away (its tooltip closed) closes too.
	if not hovered.is_empty() and (_source == null or not is_instance_valid(_source) or not _source.is_visible_in_tree()):
		hovered = ""
		_refresh(false)


func _input(event: InputEvent) -> void:
	if pinned.is_empty():
		return
	if event.is_action_pressed("ui_cancel"):
		dismiss()
		get_viewport().set_input_as_handled()
		return
	var click := event as InputEventMouseButton
	if click != null and click.pressed and (_pin_box == null or not _pin_box.get_global_rect().has_point(click.position)):
		# A click on another keyword pins that one right after (meta_clicked).
		dismiss()
