extends PanelContainer
## One unit on the battle screen: its animated sprite on a stage (tier plate,
## glow, target reticle), name and personality tag, its stats as icon chips
## (ATK, DEF, SPD, BAT), health and energy meters (GhostBars that show every
## change and the choice preview: the hp slice a hit would take, the energy a
## skill would cost), and status icons. Resting the pointer on the card shows
## the full readout (UnitDetail). Emits clicked with the mouse button and
## hovered when the pointer enters or leaves; the battle screen turns those
## into FightCommands and previews.
##
## Enemy intents and preview numbers are drawn on the arrows (IntentArrows),
## not under the sprite: the intent and preview labels still hold their words
## (for the detail card and tests) but stay hidden.

const UnitView := preload("res://ui/fight/unit_view.gd")
const PreviewBar := preload("res://ui/fight/preview_bar.gd")
const StatusRow := preload("res://ui/fight/status_row.gd")
const UnitDetail := preload("res://ui/fight/unit_detail.gd")

enum Highlight { NONE, ACTIVE, SELECTED, TARGETABLE }

const INTENT_ICONS := {
	"attack": preload("res://assets/fight/icons/intent_attack.png"),
	"heal": preload("res://assets/fight/icons/intent_heal.png"),
	"wait": preload("res://assets/fight/icons/intent_charge.png"),
	"guard": preload("res://assets/fight/icons/intent_guard.png"),
}
const CARD_WIDTH := 320
## Stat id -> icon, in chip order.
const STAT_ICONS := {
	"atk": preload("res://assets/fight/icons/stat_attack.png"),
	"def": preload("res://assets/fight/icons/stat_defense.png"),
	"spd": preload("res://assets/fight/icons/stat_speed.png"),
	"bat": preload("res://assets/fight/icons/stat_battery.png"),
}

signal clicked(unit_id: String, button_index: MouseButton)
signal hovered(unit_id: String, inside: bool)

var unit_id := ""
var is_enemy := false
var highlight := Highlight.NONE
var view: UnitView
var name_label: Label
var hp_bar: PreviewBar
var energy_bar: PreviewBar
var status_row: StatusRow
## READY / click to target prompts.
var status_label: Label
## Personality tag, for example "aggressive".
var tag_label: Label
## Enemy intent telegraph: "Intent: Strike -> Ace (6)". Enemies only.
var intent_label: Label
## The intent's kind as an icon (attack, heal, wait). Enemies only.
var intent_icon: TextureRect
## "changed: <why>" while the intent is marked as revised. Enemies only.
var change_label: Label
## What the previewed choice would do to this unit, or empty.
var preview_label: Label
## True while the intent is marked as revised.
var intent_changed := false
## The telegraphed intent's kind: "attack", "heal", "wait", or "".
var intent_kind := ""
## True while the previewed choice would change this enemy's intent.
var intent_would_change := false
## Stat id ("atk", "def", "spd", "bat") -> its number label.
var stat_labels: Dictionary[String, Label] = {}
## The row holding the intent icon and words. Hidden: arrows carry intents.
var intent_row: HBoxContainer
## The enemy's intent in words, for the detail card.
var intent_text := ""

var _style := StyleBoxFlat.new()
var _unit: Combatant
var _bars_ready := false


func setup(unit: Combatant, look: Dictionary = {}) -> void:
	unit_id = unit.id
	_unit = unit
	is_enemy = unit.side == Combatant.Side.ENEMY
	name = "Unit_%s" % unit.id.validate_node_name()
	mouse_filter = Control.MOUSE_FILTER_STOP
	custom_minimum_size = Vector2(CARD_WIDTH, 0)
	_style.bg_color = FeelData.color("panel")
	_style.set_border_width_all(2)
	_style.set_content_margin_all(4)
	_style.anti_aliasing = false
	add_theme_stylebox_override("panel", _style)

	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 4)
	row.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(row)
	view = UnitView.new()
	view.name = "View"
	row.add_child(view)
	if look.is_empty():
		look = BattleArt.look_for(unit, 0, BattleTierRule.defaults())
	view.setup(look, is_enemy)
	var col := VBoxContainer.new()
	col.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	col.add_theme_constant_override("separation", 3)
	col.mouse_filter = Control.MOUSE_FILTER_IGNORE
	row.add_child(col)
	var name_row := HBoxContainer.new()
	name_row.add_theme_constant_override("separation", 6)
	name_row.mouse_filter = Control.MOUSE_FILTER_IGNORE
	col.add_child(name_row)
	name_label = _label(name_row, unit.display_name.to_upper(), "")
	name_label.add_theme_color_override("font_color", FeelData.color("text_bright"))
	name_label.clip_text = true
	name_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	var stat_row := HBoxContainer.new()
	stat_row.name = "StatRow"
	stat_row.add_theme_constant_override("separation", int(ReadoutStyle.number("stats.gap_px", 6)))
	stat_row.mouse_filter = Control.MOUSE_FILTER_IGNORE
	col.add_child(stat_row)
	for id: String in STAT_ICONS:
		var icon := TextureRect.new()
		icon.texture = STAT_ICONS[id]
		icon.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
		icon.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
		var icon_px := ReadoutStyle.number("stats.icon_px", 12)
		icon.custom_minimum_size = Vector2(icon_px, icon_px)
		icon.mouse_filter = Control.MOUSE_FILTER_IGNORE
		icon.size_flags_vertical = Control.SIZE_SHRINK_CENTER
		stat_row.add_child(icon)
		var value := _label(stat_row, "", "SmallLabel")
		value.name = "Stat_%s" % id
		value.size_flags_vertical = Control.SIZE_SHRINK_CENTER
		value.add_theme_color_override("font_color", ReadoutStyle.color("stats.text"))
		stat_labels[id] = value
	hp_bar = PreviewBar.new()
	hp_bar.name = "HpBar"
	hp_bar.kind = "hp"
	hp_bar.custom_minimum_size = Vector2(0, 12)
	col.add_child(hp_bar)
	energy_bar = PreviewBar.new()
	energy_bar.name = "EnergyBar"
	energy_bar.kind = "energy"
	energy_bar.custom_minimum_size = Vector2(0, 12)
	col.add_child(energy_bar)
	var status_line := HBoxContainer.new()
	status_line.add_theme_constant_override("separation", 6)
	status_line.custom_minimum_size = Vector2(0, 24)
	status_line.mouse_filter = Control.MOUSE_FILTER_IGNORE
	col.add_child(status_line)
	status_row = StatusRow.new()
	status_row.name = "StatusRow"
	status_line.add_child(status_row)
	status_label = _label(status_line, "", "SmallLabel")
	status_label.name = "StatusLabel"
	status_label.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	status_label.add_theme_color_override("font_color", FeelData.color("active"))
	# The personality tag closes the status line, so long names keep their room.
	var spacer := Control.new()
	spacer.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	spacer.mouse_filter = Control.MOUSE_FILTER_IGNORE
	status_line.add_child(spacer)
	tag_label = _label(status_line, "", "SmallLabel")
	tag_label.name = "TagLabel"
	tag_label.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	if is_enemy:
		intent_row = HBoxContainer.new()
		intent_row.name = "IntentRow"
		intent_row.visible = false
		intent_row.add_theme_constant_override("separation", 4)
		intent_row.mouse_filter = Control.MOUSE_FILTER_IGNORE
		col.add_child(intent_row)
		intent_icon = TextureRect.new()
		intent_icon.name = "IntentIcon"
		intent_icon.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
		intent_icon.custom_minimum_size = Vector2(24, 24)
		intent_icon.mouse_filter = Control.MOUSE_FILTER_IGNORE
		intent_row.add_child(intent_icon)
		intent_label = _label(intent_row, "Intent: ?", "SmallLabel")
		intent_label.name = "IntentLabel"
		intent_label.size_flags_vertical = Control.SIZE_SHRINK_CENTER
		intent_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		intent_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		change_label = _label(col, "", "SmallLabel")
		change_label.name = "ChangeLabel"
		change_label.add_theme_color_override("font_color", FeelData.color("changed"))
		change_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		change_label.visible = false
	preview_label = _label(col, "", "SmallLabel")
	preview_label.name = "PreviewLabel"
	preview_label.add_theme_color_override("font_color", FeelData.color("preview"))
	preview_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	preview_label.visible = false
	tooltip_text = " "
	mouse_entered.connect(func() -> void: hovered.emit(unit_id, true))
	mouse_exited.connect(func() -> void: hovered.emit(unit_id, false))
	refresh(unit, Highlight.NONE)


## Shows `unit` as it stands, with `hp` and `energy` as the meters should read
## now (the presenter holds them back until an animation lands; -1 reads the
## unit). The first call sets the meters without animating.
func refresh(unit: Combatant, p_highlight: Highlight, hp := -1, energy := -1) -> void:
	_unit = unit
	highlight = p_highlight
	set_meters(unit.hp if hp < 0 else hp, unit.energy() if energy < 0 else energy)
	view.set_state(unit.guard_percent > 0, not unit.is_alive())
	view.set_targeted(p_highlight == Highlight.TARGETABLE, FeelData.color("enemy" if is_enemy else "ally"))
	status_label.text = _prompt(unit, p_highlight)
	_update_stats(unit)
	_update_statuses()
	_apply_style()
	modulate = Color(1, 1, 1, BattleArt.number("downed_alpha", 0.55)) if not unit.is_alive() else Color.WHITE


## Moves the meters to `hp` and `energy`, animating after the first call.
func set_meters(hp: int, energy: int) -> void:
	@warning_ignore("integer_division")
	var max_energy := _unit.max_energy_milli / Combatant.MILLI
	hp_bar.caption = "HP %d/%d" % [hp, _unit.max_hp]
	energy_bar.caption = "EN %d/%d" % [energy, max_energy]
	if not _bars_ready:
		hp_bar.reset(hp, _unit.max_hp)
		energy_bar.reset(energy, maxi(1, max_energy))
		_bars_ready = true
		return
	hp_bar.max_value = _unit.max_hp
	hp_bar.set_value(hp)
	energy_bar.set_value(energy)
	hp_bar.queue_redraw()
	energy_bar.queue_redraw()


## Shows the personality tag and, for an enemy, its intent in words and as an
## icon. `change` is "changed: <why>" while the intent is marked, else "".
## `kind` is the intent's kind ("attack", "heal", "wait") or "".
func show_intent(tag: String, intent: String, change: String, kind := "") -> void:
	tag_label.text = tag
	tag_label.visible = not tag.is_empty()
	intent_changed = not change.is_empty()
	intent_kind = kind if not intent.is_empty() else ""
	intent_text = intent
	if intent_label != null:
		intent_label.text = "Intent: %s" % (intent if not intent.is_empty() else "-")
		intent_label.add_theme_color_override(
			"font_color", FeelData.color("changed") if intent_changed else FeelData.color("text"))
		intent_icon.texture = INTENT_ICONS.get(intent_kind)
		intent_icon.visible = intent_icon.texture != null
		change_label.text = change
		# The reason shows in the detail card; the status row says CHANGED.
		change_label.visible = false
	_update_statuses()
	_apply_style()


## Holds what the previewed choice would do to this unit in words ("" for
## nothing). Not drawn under the sprite: the arrows and meters show it.
func show_preview(text: String) -> void:
	preview_label.text = text
	preview_label.visible = false
	_apply_style()


## True while a previewed choice touches this unit.
func has_preview() -> bool:
	return not preview_label.text.is_empty()


## Draws the previewed choice on the meters: the hp it would leave (blinking),
## or a hatch when the amount is unknown. `effect` null clears it. `would_change`
## marks an enemy whose intent the choice would change.
func show_meter_preview(effect: UnitEffect, would_change := false) -> void:
	intent_would_change = would_change
	if effect == null:
		hp_bar.clear_preview()
	else:
		hp_bar.show_preview(effect.hp_after.value if effect.hp_after.known else 0.0, effect.hp_after.known)
	_update_statuses()


## Draws the energy the unit would have after the selected skill: the cost
## blinks on the energy bar. -1 clears it.
func show_energy_preview(energy_after: int) -> void:
	if energy_after < 0:
		energy_bar.clear_preview()
	else:
		energy_bar.show_preview(energy_after)


## The full readout, as the detail card shows it.
func detail_text() -> String:
	if _unit == null:
		return ""
	return "\n".join(UnitDetail.lines(_unit, status_text(), intent_text, change_label.text if change_label != null else "", tag_label.text))


func _make_custom_tooltip(_for_text: String) -> Object:
	if _unit == null:
		return null
	return UnitDetail.card(_unit, status_text(), intent_text, change_label.text if change_label != null else "", tag_label.text)


## The statuses shown, as words: "GUARD 40% · CHARGE >6".
func status_text() -> String:
	return status_row.text()


func _update_statuses() -> void:
	if _unit == null:
		return
	var s := {}
	if not _unit.is_alive():
		s["down"] = "DOWN"
	else:
		if _unit.guard_percent > 0:
			s["guard"] = "GUARD %d%%" % _unit.guard_percent
		if _unit.is_waiting():
			if _unit.wait_length > 0:
				s["waiting"] = "WAIT %d" % (_unit.wait_length - _unit.wait_ticks)
			else:
				@warning_ignore("integer_division")
				s["charging"] = "CHARGE >%d" % (_unit.wait_target_milli / Combatant.MILLI)
		elif intent_kind == "wait":
			s["waiting"] = "WAIT"
		if is_low_energy(_unit):
			s["low_energy"] = "LOW EN"
		if intent_changed or intent_would_change:
			s["intent_changed"] = "CHANGED" if intent_changed else "WOULD CHANGE"
	status_row.show_statuses(s)


## True when `unit` cannot afford its cheapest skill that costs energy.
static func is_low_energy(unit: Combatant) -> bool:
	var cheapest := -1
	for skill in unit.skills():
		if skill.energy_cost > 0 and (cheapest < 0 or skill.energy_cost < cheapest):
			cheapest = skill.energy_cost
	return cheapest > 0 and unit.energy() < cheapest


func _apply_style() -> void:
	match highlight:
		Highlight.ACTIVE:
			_style.border_color = FeelData.color("active")
		Highlight.SELECTED:
			_style.border_color = FeelData.color("selected")
		Highlight.TARGETABLE:
			_style.border_color = FeelData.color("enemy" if is_enemy else "ally")
		_ when intent_changed:
			_style.border_color = FeelData.color("changed")
		_:
			_style.border_color = FeelData.color("panel_border")
	_style.bg_color = FeelData.color("panel_raised") if highlight != Highlight.NONE else FeelData.color("panel")
	if preview_label != null and has_preview():
		_style.bg_color = FeelData.color("panel_raised")


## The stat chips: ATK, DEF (with the guard on top, while guarded), SPD, BAT.
func _update_stats(unit: Combatant) -> void:
	var s := unit.stats
	stat_labels["atk"].text = str(s.attack)
	stat_labels["def"].text = str(s.defense) if unit.guard_percent <= 0 else "%d+%d%%" % [s.defense, unit.guard_percent]
	stat_labels["def"].add_theme_color_override("font_color",
		ReadoutStyle.color("stats.guarded_text" if unit.guard_percent > 0 else "stats.text"))
	stat_labels["spd"].text = str(s.speed)
	stat_labels["bat"].text = str(s.battery_capacity)


## The stat chips as words: "ATK 8 DEF 3 SPD 7 BAT 10".
func stats_text() -> String:
	return "ATK %s DEF %s SPD %s BAT %s" % [
		stat_labels["atk"].text, stat_labels["def"].text, stat_labels["spd"].text, stat_labels["bat"].text]


func _prompt(unit: Combatant, p_highlight: Highlight) -> String:
	if not unit.is_alive():
		return ""
	if p_highlight == Highlight.ACTIVE:
		return "READY"
	if p_highlight == Highlight.TARGETABLE:
		return "click to target"
	return ""


func _gui_input(event: InputEvent) -> void:
	var mouse := event as InputEventMouseButton
	if mouse != null and mouse.pressed:
		clicked.emit(unit_id, mouse.button_index)
		accept_event()


static func _label(parent: Node, text: String, variation: String) -> Label:
	var label := Label.new()
	label.text = text
	if not variation.is_empty():
		label.theme_type_variation = StringName(variation)
	label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	parent.add_child(label)
	return label
