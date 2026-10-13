extends Control
## The upcoming actions, left to right, as Fight.upcoming() gives them. The
## first chip is the unit acting now. When the order changes, chips slide to
## their new places (feel tween "ui_slow"), new chips fade in and dropped ones
## fade out, so a change in the order is seen, not just redrawn.
##
## Hovering a unit lights its upcoming slots and dims the rest
## (set_highlight). While a previewed choice would change the order, the bar
## shows the order it would leave, titled AFTER in the preview color, and the
## chips slide there; the order comes back when the preview ends.
## Hover and preview look: data/feel/battle_readout.json "timeline".

const CHIP_HEIGHT := 28
const GAP := 6
const TITLE_WIDTH := 60

## Combatant ids in the order shown, for tests and the intent hookup.
var shown_ids: Array[String] = []
var settings: GameSettings
## The unit whose slots are lit, or "".
var highlight_id := ""
## True while the bar shows the order a previewed choice would leave.
var showing_preview := false
## When a unit acts and why: unit id -> BattleMath.turn()'s dictionary, for
## each chip's tooltip. Unset: the tooltip names the tick only.
var turn_info: Callable

var _entries: Array[TimelineEntry] = []

## Chip key ("<id>#<n>", the n-th time the id appears) -> chip.
var _chips: Dictionary[String, PanelContainer] = {}
var _title: Label


func _init() -> void:
	custom_minimum_size = Vector2(0, CHIP_HEIGHT)
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	clip_contents = true
	_title = Label.new()
	_title.text = "NEXT"
	_title.theme_type_variation = &"DimLabel"
	_title.position = Vector2(0, 2)
	_title.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_title)


## Slot indexes lit by the highlight, for tests.
func lit_slots() -> Array[int]:
	var out: Array[int] = []
	if highlight_id.is_empty():
		return out
	for i in shown_ids.size():
		if shown_ids[i] == highlight_id:
			out.append(i)
	return out


## Lights the upcoming slots of `unit_id` and dims the others; "" clears.
func set_highlight(unit_id: String) -> void:
	if unit_id == highlight_id:
		return
	highlight_id = unit_id
	_restyle()


## Shows `entries`; `preview` marks them as the order a choice would leave.
func refresh(entries: Array[TimelineEntry], preview := false) -> void:
	_entries = entries
	showing_preview = preview
	_title.text = ReadoutStyle.text("timeline.preview_title", "AFTER") if preview else "NEXT"
	if preview:
		_title.add_theme_color_override("font_color", ReadoutStyle.color("timeline.preview_color"))
	else:
		_title.remove_theme_color_override("font_color")
	shown_ids.clear()
	var seen := {}
	var keys: Array[String] = []
	for entry in entries:
		shown_ids.append(entry.combatant_id)
		seen[entry.combatant_id] = int(seen.get(entry.combatant_id, 0)) + 1
		keys.append("%s#%d" % [entry.combatant_id, seen[entry.combatant_id]])
	var animate := is_inside_tree() and not _settings().skips_animations()
	# Drop chips no longer shown.
	for key: String in _chips.keys():
		if not key in keys:
			var gone: PanelContainer = _chips[key]
			_chips.erase(key)
			if animate:
				var fade := FeelTween.to(gone, "modulate:a", 0.0, "ui_fast", _settings())
				fade.tween_callback(gone.queue_free)
			else:
				gone.queue_free()
	var x := float(TITLE_WIDTH)
	for i in entries.size():
		var key := keys[i]
		var chip: PanelContainer = _chips.get(key)
		var fresh := chip == null
		if fresh:
			chip = _chip(entries[i])
			_chips[key] = chip
			add_child(chip)
		chip.set_meta("slot", i)
		_restyle_chip(chip)
		var label: Label = chip.get_child(0)
		label.text = entries[i].display_name + (" (wait)" if entries[i].ends_wait else "")
		var info: Dictionary = turn_info.call(entries[i].combatant_id) if turn_info.is_valid() else {}
		var when := "Acts now." if i == 0 else "Acts %s, at tick %d." % [BattleMath.ordinal(i + 1), entries[i].tick]
		UiTooltip.attach(chip, entries[i].display_name, when + (" Ends its wait." if entries[i].ends_wait else ""),
			"", "spd", info.get("math", []) if i == _first_slot(entries, i) else [])
		chip.reset_size()
		var target := Vector2(x, 0)
		if fresh:
			chip.position = target + (Vector2(12, 0) if animate else Vector2.ZERO)
			chip.modulate.a = 0.0 if animate else 1.0
			if animate:
				FeelTween.to(chip, "modulate:a", 1.0, "ui", _settings())
		if animate and chip.position != target:
			FeelTween.to(chip, "position", target, "ui_slow", _settings())
		elif not animate:
			chip.position = target
		x += chip.get_combined_minimum_size().x + GAP


## The first slot `entries[i]`'s unit holds: its next action, which the math
## explains (later slots repeat the same unit).
static func _first_slot(entries: Array[TimelineEntry], i: int) -> int:
	for j in entries.size():
		if entries[j].combatant_id == entries[i].combatant_id:
			return j
	return i


func _restyle() -> void:
	for key: String in _chips:
		_restyle_chip(_chips[key])


## Styles a chip for its slot: side, the unit acting now, the hover light.
func _restyle_chip(chip: PanelContainer) -> void:
	var i: int = chip.get_meta("slot", -1)
	if i < 0 or i >= _entries.size():
		return
	var entry := _entries[i]
	var lit := not highlight_id.is_empty() and entry.combatant_id == highlight_id
	_style_chip(chip, entry, i == 0, lit)
	var label: Label = chip.get_child(0)
	var dim := not highlight_id.is_empty() and not lit
	label.modulate.a = ReadoutStyle.number("timeline.dim_alpha", 0.35) if dim else 1.0


func _chip(entry: TimelineEntry) -> PanelContainer:
	var chip := PanelContainer.new()
	chip.mouse_filter = Control.MOUSE_FILTER_PASS
	var label := Label.new()
	label.theme_type_variation = &"SmallLabel"
	label.add_theme_color_override("font_color", FeelData.color("text_bright"))
	label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	chip.add_child(label)
	return chip


func _style_chip(chip: PanelContainer, entry: TimelineEntry, is_now: bool, lit := false) -> void:
	var style := StyleBoxFlat.new()
	var side_color := FeelData.color("enemy" if entry.side == Combatant.Side.ENEMY else "ally")
	style.bg_color = side_color.darkened(0.6)
	style.border_color = FeelData.color("active") if is_now else side_color.darkened(0.15)
	style.set_border_width_all(2 if is_now else 1)
	# Enemies get a notched left edge, bots a square one: side reads by shape too.
	style.border_width_left = 4 if entry.side == Combatant.Side.ENEMY else (2 if is_now else 1)
	if lit:
		style.border_color = ReadoutStyle.color("timeline.hover_color")
		style.set_border_width_all(int(ReadoutStyle.number("timeline.hover_border_px", 3)))
		style.bg_color = side_color.darkened(0.35)
	style.content_margin_left = 8
	style.content_margin_right = 8
	style.content_margin_top = 6
	style.content_margin_bottom = 6
	style.anti_aliasing = false
	chip.add_theme_stylebox_override("panel", style)


func _settings() -> GameSettings:
	return settings if settings else GameSettings.shared()
