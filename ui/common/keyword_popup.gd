class_name KeywordPopup
extends Control
## The keyword box a highlighted keyword pops up (UiGlossary links). Hovering
## a keyword shows its box by the cursor; clicking pins the box until a click
## elsewhere or Esc. A pinned box's own keywords are links too: hover shows
## theirs beside it, click pins theirs instead.
##
## The state is static, so every screen shares one popup:
##   KeywordPopup.hovered, KeywordPopup.pinned, KeywordPopup.shown()

## Space between a box and what it sits beside.
const GAP := 6.0

## The keyword under the pointer, or "".
static var hovered := ""
## The pinned keyword, or "".
static var pinned := ""
static var _source: Control
## The label whose keyword was clicked, to place the pinned box by.
static var _pin_source: Control
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
	_pin_source = label
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
	col.add_theme_constant_override("separation", UiStyle.space("xs"))
	col.mouse_filter = Control.MOUSE_FILTER_IGNORE
	panel.add_child(col)
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", UiStyle.space("s"))
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
	var text := UiGlossary.rich(str(e.get("text", "")), UiTooltip.text_size(), Color(0, 0, 0, 0),
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


func _refresh(_at_mouse: bool) -> void:
	if _pin_box != null and _pin_box_keyword != pinned:
		_drop(_pin_box)
		_pin_box = null
	if _pin_box == null and not pinned.is_empty():
		_pin_box = box(pinned)
		_pin_box_keyword = pinned
		add_child(_pin_box)
		_place_by(_pin_box, _pin_source, [])
	if _hover_box != null:
		_drop(_hover_box)
		_hover_box = null
	if not hovered.is_empty() and hovered != pinned:
		_hover_box = box(hovered)
		_hover_box.mouse_filter = Control.MOUSE_FILTER_IGNORE
		add_child(_hover_box)
		var keep_clear: Array[Rect2] = []
		if _pin_box != null:
			# Beside the pinned box, clear of it and of the cards it belongs to.
			keep_clear.append(_pin_box.get_global_rect())
			if _pin_source != null and is_instance_valid(_pin_source) and _pin_source.is_inside_tree():
				var pin_anchor := anchor_of(_pin_source)
				keep_clear.append(pin_anchor.get_global_rect())
				keep_clear.append_array(_neighbours(pin_anchor, _hover_box))
		_place_by(_hover_box, _source, keep_clear)


## Places box `b` by the card, tooltip or box holding `label` (its anchor):
## beside it where there is room, never over the anchor's neighbours (the
## other cards in a row) or `keep_clear`, kept on screen. A box chained from a
## pinned box's keyword sits beside that box.
func _place_by(b: Control, label: Control, keep_clear: Array[Rect2]) -> void:
	b.reset_size()
	var view := get_viewport_rect()
	if label == null or not is_instance_valid(label) or not label.is_inside_tree():
		b.position = clamp_to(get_global_mouse_position() + UiIcons.kit_vector("tooltip.offset", Vector2(16, 16)), b.size, view)
		return
	var anchor := anchor_of(label)
	var avoid: Array[Rect2] = keep_clear.duplicate()
	avoid.append_array(_neighbours(anchor, b))
	b.position = place_beside(b.size, anchor.get_global_rect(), avoid, view, GAP)


## The screen rects of `anchor`'s visible siblings (the other cards in its
## row), leaving out `skip`.
static func _neighbours(anchor: Control, skip: Control) -> Array[Rect2]:
	var out: Array[Rect2] = []
	var parent := anchor.get_parent()
	if parent == null:
		return out
	for sibling in parent.get_children():
		if sibling != anchor and sibling != skip and sibling is Control and (sibling as Control).is_visible_in_tree():
			out.append((sibling as Control).get_global_rect())
	return out


## Where a label's box goes: next to the card (a button), tooltip panel or
## keyword box holding it, else next to the label itself.
static func anchor_of(label: Control) -> Control:
	var node: Node = label
	while node != null:
		if node is BaseButton or (node is PanelContainer and node != label):
			return node
		node = node.get_parent()
	return label


## The spot for a box of `box_size` beside `anchor`: right, left, above, then
## below it, each kept inside `view`; the first that overlaps neither the
## anchor nor any of `avoid` wins, else the one that overlaps least.
static func place_beside(box_size: Vector2, anchor: Rect2, avoid: Array[Rect2], view: Rect2, gap: float) -> Vector2:
	var spots: Array[Vector2] = [
		Vector2(anchor.end.x + gap, anchor.position.y),
		Vector2(anchor.position.x - gap - box_size.x, anchor.position.y),
		Vector2(anchor.position.x, anchor.position.y - gap - box_size.y),
		Vector2(anchor.position.x, anchor.end.y + gap),
	]
	var best := Vector2.ZERO
	var best_cost := INF
	for spot in spots:
		var at := clamp_to(spot, box_size, view)
		var r := Rect2(at, box_size)
		# Covering the anchor itself (the card or word you are reading) costs most.
		var cost := _overlap(r, anchor) * 4.0
		for a in avoid:
			cost += _overlap(r, a)
		if cost < best_cost:
			best_cost = cost
			best = at
		if cost <= 0.0:
			break
	return best


static func clamp_to(at: Vector2, box_size: Vector2, view: Rect2) -> Vector2:
	return Vector2(clampf(at.x, view.position.x, maxf(view.position.x, view.end.x - box_size.x)),
		clampf(at.y, view.position.y, maxf(view.position.y, view.end.y - box_size.y)))


static func _overlap(a: Rect2, b: Rect2) -> float:
	var i := a.intersection(b)
	return i.get_area() if a.intersects(b) else 0.0


## Takes a box out at once (its name is free for the next box), then frees it.
func _drop(b: Control) -> void:
	remove_child(b)
	b.queue_free()


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
