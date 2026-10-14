extends PanelContainer
## One unit on the battle screen, on the card anatomy (ui/README.md rule 8):
##
##   +--------+-----------------------------------+
##   |        | Name                  [intent] ⋮  |
##   | sprite | ▮▮▮▮▯ 38/50     / 12     >> 2nd   |   HP (Energy under it), ATK, next turn
##   |        | [Boss] [Guard 40%] [Low HP] [Aggr]|   flags on the edge
##   +--------+-----------------------------------+
##
## The sprite stage (tier plate, glow, target reticle) is never covered; only
## damage popups cross it. The meters are GhostBars that show every change and
## the choice preview (the hp slice a hit would take, the energy a skill would
## cost). ⋮, or a right-click while nothing is being chosen, opens the
## DetailModal with every stat, the skills with ranks, statuses, the
## personality and (enemies) the next move. Emits clicked with the mouse
## button and hovered when the pointer enters or leaves; the battle screen
## turns those into FightCommands and previews.
##
## Enemy intents and preview numbers are drawn on the arrows (IntentArrows),
## not under the sprite: the intent and preview labels still hold their words
## (for the detail card and tests) but stay hidden.

const UnitView := preload("res://ui/fight/unit_view.gd")
const PreviewBar := preload("res://ui/fight/preview_bar.gd")
const StatusRow := preload("res://ui/fight/status_row.gd")
const UnitDetail := preload("res://ui/fight/unit_detail.gd")

enum Highlight { NONE, ACTIVE, SELECTED, TARGETABLE }

const CARD_WIDTH := 352
## Stat id -> its icon id in data/ui/icons.json, in chip order.
const STAT_ICON_IDS := {"atk": "atk", "def": "def", "spd": "spd", "bat": "battery"}
## Intent kind -> its icon id in data/ui/icons.json.
const INTENT_ICON_IDS := {"attack": "intent_attack", "heal": "intent_heal", "wait": "intent_charge", "guard": "intent_guard"}

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
## The three headlines: HP (with Energy under it), ATK, next turn.
var strip: StatStrip
## The flags on the card's edge: unit flags, statuses, the trait.
var flags_row: HFlowContainer
## ⋮: opens the DetailModal.
var more_button: Button
## True for the fight's boss (show_boss()).
var is_boss := false
## When the unit acts next: BattleMath.turn()'s dictionary.
var turn_info := {}
## The bot's personality ends (Personality.ENDS order) for the detail card's
## hexagon; empty for enemies, which only have a tag.
var personality_ends: Array[float] = []
## Compact: flags show as icons, their names on hover.
var compact := false
## What the aimed skill would do to this unit ({} when it is not a target):
## {"text": "-13", "ko": bool}. Shown as the first flag.
var target_outcome := {}
## The personality tag as its trait icon; the tag word is in its tooltip.
var trait_icon: IconStat
## Enemies: the intent as an icon and its number at the top of the card
## (ui/README.md rule 4). Hidden while there is no intent.
var intent_chip: IconStat
## The row holding the intent icon and words. Hidden: arrows carry intents.
var intent_row: HBoxContainer
## The enemy's intent in words, for the detail card.
var intent_text := ""

## The name's font size before fitting, read once it is in the tree.
var _name_size := -1
var _style := StyleBoxFlat.new()
var _unit: Combatant
var _bars_ready := false
## The card's own flags (outcome, boss, elite, prompt, low HP) and its trait
## flag, all in flags_row with the statuses: one row that wraps as one.
var _unit_flags: Array[Flag] = []
var _trait_flag: Flag
var _flag_key := ""
var _trait_key := ""


func setup(unit: Combatant, look: Dictionary = {}) -> void:
	unit_id = unit.id
	_unit = unit
	is_enemy = unit.side == Combatant.Side.ENEMY
	name = "Unit_%s" % unit.id.validate_node_name()
	mouse_filter = Control.MOUSE_FILTER_STOP
	custom_minimum_size = Vector2(CARD_WIDTH, 0)
	_style.bg_color = FeelData.color("panel")
	_style.set_border_width_all(2)
	_style.set_content_margin_all(UiStyle.space("xs"))
	_style.anti_aliasing = false
	add_theme_stylebox_override("panel", _style)

	var row := UiStyle.row("s")
	row.name = "Body"
	add_child(row)
	view = UnitView.new()
	view.name = "View"
	row.add_child(view)
	if look.is_empty():
		look = BattleArt.look_for(unit, 0, BattleTierRule.defaults())
	view.setup(look, is_enemy)
	var col := UiStyle.column("xs")
	col.name = "Strip"
	col.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	col.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	row.add_child(col)
	# Title strip: the name, the enemy's intent, ⋮.
	var name_row := UiStyle.row("xs")
	name_row.name = "TitleRow"
	col.add_child(name_row)
	name_label = _label(name_row, unit.display_name, "")
	name_label.name = "Name"
	UiTooltip._bold(name_label, UiStyle.role("title"))
	name_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	name_label.tooltip_text = unit.display_name
	name_label.resized.connect(_fit_name)
	if is_enemy:
		intent_chip = IconStat.make("intent_attack")
		intent_chip.name = "IntentChip"
		intent_chip.visible = false
		intent_chip.size_flags_vertical = Control.SIZE_SHRINK_BEGIN
		name_row.add_child(intent_chip)
	more_button = DetailModal.more_button(detail_spec)
	more_button.size_flags_vertical = Control.SIZE_SHRINK_BEGIN
	name_row.add_child(more_button)
	# The three headlines: HP (Energy under it), ATK, next turn.
	hp_bar = PreviewBar.new()
	hp_bar.name = "HpBar"
	hp_bar.kind = "hp"
	hp_bar.draw_caption = false
	energy_bar = PreviewBar.new()
	energy_bar.name = "EnergyBar"
	energy_bar.kind = "energy"
	energy_bar.draw_caption = false
	strip = StatStrip.make([_hp_spec(unit, unit.hp, unit.energy()), _atk_spec(unit), _turn_spec()])
	strip.stacked = true
	col.add_child(strip)
	# Flags on the edge: boss, elite, the prompt, statuses, low HP, the trait.
	flags_row = Flag.row([])
	flags_row.name = "Flags"
	col.add_child(flags_row)
	status_row = StatusRow.new()
	status_row.name = "StatusRow"
	status_row.visible = false
	status_row.target = flags_row
	status_row.changed.connect(_order_flags)
	col.add_child(status_row)
	# Kept for their words (detail card, tests); flags show them.
	var hidden := Control.new()
	hidden.name = "Words"
	hidden.visible = false
	col.add_child(hidden)
	status_label = _label(hidden, "", "")
	status_label.name = "StatusLabel"
	tag_label = _label(hidden, "", "")
	tag_label.name = "TagLabel"
	trait_icon = IconStat.make("unknown")
	trait_icon.name = "TraitIcon"
	trait_icon.visible = false
	hidden.add_child(trait_icon)
	if is_enemy:
		intent_row = HBoxContainer.new()
		intent_row.name = "IntentRow"
		intent_row.visible = false
		hidden.add_child(intent_row)
		intent_icon = TextureRect.new()
		intent_icon.name = "IntentIcon"
		intent_row.add_child(intent_icon)
		intent_label = _label(intent_row, "Intent: ?", "")
		intent_label.name = "IntentLabel"
		change_label = _label(hidden, "", "")
		change_label.name = "ChangeLabel"
		change_label.visible = false
	preview_label = _label(hidden, "", "")
	preview_label.name = "PreviewLabel"
	preview_label.visible = false
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
	_update_flags()
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
	if strip != null:
		strip.set_stat(0, _hp_spec(_unit, hp, energy))
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
	_update_trait_flag(tag)
	# A known trait shows as its icon, the word in the tooltip; anything else
	# (a "balanced" bot, a mixed tag) keeps the word.
	var trait_id := "trait_%s" % tag.to_lower()
	var has_icon := UiIcons.has(trait_id)
	if has_icon and trait_icon.icon_id != trait_id:
		trait_icon.icon_id = trait_id
		trait_icon.icon_rect.texture = UiIcons.texture(trait_id)
		trait_icon.set_value(null)
	intent_changed = not change.is_empty()
	intent_kind = kind if not intent.is_empty() else ""
	intent_text = intent
	if intent_label != null:
		intent_label.text = "Intent: %s" % (intent if not intent.is_empty() else "-")
		intent_label.add_theme_color_override(
			"font_color", FeelData.color("changed") if intent_changed else FeelData.color("text"))
		intent_icon.texture = UiIcons.texture(INTENT_ICON_IDS[intent_kind]) if INTENT_ICON_IDS.has(intent_kind) else null
		intent_icon.visible = intent_icon.texture != null
		change_label.text = change
		# The reason shows in the detail card; the status row says CHANGED.
		change_label.visible = false
	_update_statuses()
	_apply_style()


## Shows the enemy's intent as an icon and its number at the top of the card:
## `kind` "attack" | "heal" | "wait" | "guard" | "" (hidden), `amount` the
## badge's number ("6", "+8", "40%", "?") or "".
func show_intent_chip(kind: String, amount: String) -> void:
	if intent_chip == null:
		return
	var icon_id: String = INTENT_ICON_IDS.get(kind, "")
	intent_chip.visible = not icon_id.is_empty()
	if icon_id.is_empty():
		return
	if intent_chip.icon_id != icon_id:
		intent_chip.icon_id = icon_id
		intent_chip.icon_rect.texture = UiIcons.texture(icon_id)
	intent_chip.value_label.add_theme_color_override("font_color", FeelData.color("changed") if intent_changed else UiIcons.color(icon_id))
	intent_chip.set_tip_text(intent_text if not intent_text.is_empty() else UiIcons.text(icon_id))
	intent_chip.set_value(amount if not amount.is_empty() else null)


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


## The full readout as a card (the detail modal's Stats page in words).
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


## The ATK and next-turn headlines as the unit stands.
func _update_stats(unit: Combatant) -> void:
	strip.set_stat(1, _atk_spec(unit))
	strip.set_stat(2, _turn_spec())


## The stats as words: "ATK 8 DEF 3 SPD 7 BAT 10" (DEF "3+40%" while guarded).
func stats_text() -> String:
	var s := _unit.stats
	var def := str(s.defense) if _unit.guard_percent <= 0 else "%d+%d%%" % [s.defense, _unit.guard_percent]
	return "ATK %d DEF %s SPD %d BAT %d" % [s.attack, def, s.speed, s.battery_capacity]


## Sets when the unit acts next (BattleMath.turn()) and shows it.
func set_turn(info: Dictionary) -> void:
	if info == turn_info:
		return
	turn_info = info
	if strip != null:
		strip.set_stat(2, _turn_spec())


## Marks the fight's boss: a Boss flag, and no Elite flag.
func set_boss(boss: bool) -> void:
	is_boss = boss
	_update_flags()


## True when the unit is drawn in the top tier and is not the boss.
func is_elite() -> bool:
	return is_enemy and not is_boss and view != null and view.tier == BattleArt.ELITE_TIER


func _hp_spec(unit: Combatant, hp: int, energy: int) -> Dictionary:
	@warning_ignore("integer_division")
	var max_energy := unit.max_energy_milli / Combatant.MILLI
	var spec := StatStrip.bar("hp", hp, unit.max_hp, UiIcons.text("hp"))
	spec["meter_node"] = hp_bar
	spec["sub_node"] = energy_bar
	spec["numbers"] = "HP %d/%d\nEnergy %d/%d" % [hp, unit.max_hp, energy, max_energy]
	spec["title"] = "HP and Energy"
	spec["show_icon"] = false
	spec["bar_size"] = Vector2(64, 10)
	return spec


func _atk_spec(unit: Combatant) -> Dictionary:
	var spec := StatStrip.number("atk", unit.stats.attack, UiIcons.text("atk"))
	spec["numbers"] = stats_text().replace(" DEF", "  DEF").replace(" SPD", "  SPD").replace(" BAT", "  BAT")
	return spec


func _turn_spec() -> Dictionary:
	var chip := str(turn_info.get("chip", "-"))
	var role := "hint" if chip == "Now" else "text_quiet"
	var spec := StatStrip.chip("spd", chip, str(turn_info.get("tip", "When it acts next.")), turn_info.get("math", []), role)
	spec["title"] = "Next turn"
	spec["numbers"] = "Speed %d" % _unit.stats.speed
	return spec


## The flags on the edge, rebuilt only when they change.
func _update_flags() -> void:
	if flags_row == null or _unit == null:
		return
	var ids: Array[String] = []
	if is_boss:
		ids.append("boss")
	elif is_elite():
		ids.append("elite")
	var prompt := status_label.text
	if prompt == "READY":
		ids.append("ready")
	elif prompt == "click to target":
		ids.append("target")
	if _unit.is_alive() and hp_bar.is_low():
		ids.append("low_hp")
	var outcome_key := "%s%s" % [target_outcome.get("text", ""), "ko" if target_outcome.get("ko", false) else ""]
	var key := ",".join(ids) + "|" + outcome_key + ("|c" if compact else "")
	if key == _flag_key:
		return
	_flag_key = key
	for f in _unit_flags:
		if is_instance_valid(f):
			flags_row.remove_child(f)
			f.queue_free()
	_unit_flags.clear()
	if not target_outcome.is_empty():
		_unit_flags.append(_outcome_flag())
	for id in ids:
		var f: Flag
		match id:
			"ready":
				f = Flag.make("Ready", "action_resume", "hint", "Its turn: choose a skill or Wait.", compact)
			"target":
				# The outcome flag says it all while a skill is aimed.
				if not target_outcome.is_empty():
					continue
				f = Flag.make("Target", "action_attack", "enemy" if is_enemy else "ally", "Click to aim the chosen skill here.", compact)
			_:
				f = Flag.of(id, compact)
		f.name = "Flag_%s" % id
		_unit_flags.append(f)
	for f in _unit_flags:
		flags_row.add_child(f)
	_order_flags()


## The card's flags in order: its own first, then statuses, the trait last.
func _order_flags() -> void:
	var i := 0
	for f in _unit_flags:
		if is_instance_valid(f) and f.get_parent() == flags_row:
			flags_row.move_child(f, i)
			i += 1
	if _trait_flag != null and is_instance_valid(_trait_flag):
		flags_row.move_child(_trait_flag, flags_row.get_child_count() - 1)


## The aimed skill's result on this unit as a flag: "-13", "KO -13", "+8".
## Never compact: it is the number the player is choosing by.
func _outcome_flag() -> Flag:
	var text := str(target_outcome.get("text", "?"))
	var ko: bool = target_outcome.get("ko", false)
	var heal := text.begins_with("+")
	var f: Flag
	if ko:
		f = Flag.make("KO %s" % text, "ko", "bad", "This hit would put it Down.")
	elif heal:
		f = Flag.make(text, "intent_heal", "good", "HP it would get back.")
	elif text.begins_with("Guard"):
		f = Flag.make(text, "status_guard", "info", "Guard it would gain.")
	else:
		f = Flag.make(text, "intent_attack", "bad", "HP it would lose.")
	f.name = "Flag_outcome"
	return f


## Shows what the aimed skill would do here ({} clears it).
func show_target_outcome(outcome: Dictionary) -> void:
	if outcome == target_outcome:
		return
	target_outcome = outcome
	_update_flags()


## Compact cards show their flags as icons (names on hover).
func set_compact(on: bool) -> void:
	if on == compact:
		return
	compact = on
	status_row.compact = on
	status_row.shown = {}
	_update_statuses()
	_update_flags()


## The personality as a flag: the trait's icon and name.
func _update_trait_flag(tag: String) -> void:
	if tag == _trait_key:
		return
	_trait_key = tag
	if _trait_flag != null and is_instance_valid(_trait_flag):
		flags_row.remove_child(_trait_flag)
		_trait_flag.queue_free()
	_trait_flag = null
	if tag.is_empty():
		return
	var trait_id := "trait_%s" % tag.to_lower()
	var icon := trait_id if UiIcons.has(trait_id) else ""
	var line := UiIcons.text(trait_id) if UiIcons.has(trait_id) else "Its personality."
	var f := Flag.make(tag.capitalize(), icon, "neutral", line, not icon.is_empty())
	f.name = "Flag_trait"
	_trait_flag = f
	flags_row.add_child(f)


## What ⋮ opens: every stat, the skills with ranks, statuses, the
## personality, and (enemies) the next move.
func detail_spec() -> Dictionary:
	return UnitDetail.spec(_unit, {
		"statuses": status_text(), "intent": intent_text,
		"change": change_label.text if change_label != null else "", "tag": tag_label.text,
		"boss": is_boss, "elite": is_elite(), "turn": turn_info, "personality": personality_ends,
		"status_flags": status_row.shown,
	})


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


## A long name is never clipped and never shrinks (ui/README.md rule 13):
## it wraps onto two lines at the body size. Its tooltip shows it too.
func _fit_name() -> void:
	var width := name_label.size.x
	if width <= 0.0 or not name_label.is_inside_tree():
		return
	var font := name_label.get_theme_font("font")
	var fits := font.get_string_size(name_label.text, HORIZONTAL_ALIGNMENT_LEFT, -1, name_label.get_theme_font_size("font_size")).x <= width
	var wrap := TextServer.AUTOWRAP_OFF if fits else TextServer.AUTOWRAP_WORD_SMART
	if name_label.autowrap_mode != wrap:
		name_label.autowrap_mode = wrap


## True when the name shows whole: no clipping, every line within the card.
func name_fits() -> bool:
	if name_label.clip_text:
		return false
	var font := name_label.get_theme_font("font")
	var size := name_label.get_theme_font_size("font_size")
	if name_label.autowrap_mode != TextServer.AUTOWRAP_OFF:
		for word in name_label.text.split(" "):
			if font.get_string_size(word, HORIZONTAL_ALIGNMENT_LEFT, -1, size).x > name_label.size.x:
				return false
		return true
	return font.get_string_size(name_label.text, HORIZONTAL_ALIGNMENT_LEFT, -1, size).x <= name_label.size.x + 0.5


static func _label(parent: Node, text: String, variation: String) -> Label:
	var label := Label.new()
	label.text = text
	if not variation.is_empty():
		label.theme_type_variation = StringName(variation)
	label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	parent.add_child(label)
	return label
