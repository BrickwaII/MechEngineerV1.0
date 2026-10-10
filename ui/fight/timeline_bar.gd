extends Control
## The upcoming actions, left to right, as Fight.upcoming() gives them. The
## first chip is the unit acting now. When the order changes, chips slide to
## their new places (feel tween "ui_slow"), new chips fade in and dropped ones
## fade out, so a change in the order is seen, not just redrawn.

const CHIP_HEIGHT := 28
const GAP := 6
const TITLE_WIDTH := 60

## Combatant ids in the order shown, for tests and the intent hookup.
var shown_ids: Array[String] = []
var settings: GameSettings

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


func refresh(entries: Array[TimelineEntry]) -> void:
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
		_style_chip(chip, entries[i], i == 0)
		var label: Label = chip.get_child(0)
		label.text = entries[i].display_name + (" (wait)" if entries[i].ends_wait else "")
		chip.tooltip_text = "acts at tick %d" % entries[i].tick
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


func _chip(entry: TimelineEntry) -> PanelContainer:
	var chip := PanelContainer.new()
	chip.mouse_filter = Control.MOUSE_FILTER_PASS
	var label := Label.new()
	label.theme_type_variation = &"SmallLabel"
	label.add_theme_color_override("font_color", FeelData.color("text_bright"))
	label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	chip.add_child(label)
	return chip


func _style_chip(chip: PanelContainer, entry: TimelineEntry, is_now: bool) -> void:
	var style := StyleBoxFlat.new()
	var side_color := FeelData.color("enemy" if entry.side == Combatant.Side.ENEMY else "ally")
	style.bg_color = side_color.darkened(0.6)
	style.border_color = FeelData.color("active") if is_now else side_color.darkened(0.15)
	style.set_border_width_all(2 if is_now else 1)
	# Enemies get a notched left edge, bots a square one: side reads by shape too.
	style.border_width_left = 4 if entry.side == Combatant.Side.ENEMY else (2 if is_now else 1)
	style.content_margin_left = 8
	style.content_margin_right = 8
	style.content_margin_top = 6
	style.content_margin_bottom = 6
	style.anti_aliasing = false
	chip.add_theme_stylebox_override("panel", style)


func _settings() -> GameSettings:
	return settings if settings else GameSettings.shared()
