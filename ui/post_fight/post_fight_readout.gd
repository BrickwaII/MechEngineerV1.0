extends Control
## The post-fight readout: per bot, what it did (tag counters), which skills
## levelled, and how its personality shifted. Call show_report() with what
## PostFight.apply() returned.
##
## It counts up (TallySequence, data/feel/screens.json "readout"): each bot's
## panel comes in, its counters and skill uses tick up one row after another,
## then the payoffs land: a level-up pops in gold with a chime, a personality
## shift slides its dot to the new value. One bot after another. A click or
## a key skips to the end; the animation speed setting shortens it, and skip
## shows the end at once.

const ScaleBar := preload("res://ui/post_fight/scale_bar.gd")

const BACKGROUND := Color("#0b121b")
const PANEL := Color("#111b27")
const RULE := Color("#223244")
const TEXT := Color("#dbe6f0")
const TEXT_DIM := Color("#8aa0b4")
const ACCENT := Color("#35c2b0")
const LEVEL_UP := Color("#f2b84b")
const VICTORY := Color("#7be7a8")
const DEFEAT := Color("#ff6b5e")

## ActionTag label -> what the readout calls it.
const LABEL_NAMES := {
	ActionTag.HIT_ENEMY: "Hit an enemy",
	ActionTag.SELF_TARGET: "Aimed at self",
	ActionTag.ALLY_TARGET: "Aimed at an ally",
	ActionTag.WAIT: "Waited",
	ActionTag.SOLO: "Acted alone",
	ActionTag.FIRST_AFFORDABLE: "Spent energy at once",
}
const ALLY_UNIT := "ally_frame"

signal tally_finished

var report: PostFightReport
var settings: GameSettings
## The count-up in progress, or null.
var tally: TallySequence

var _title: Label
var _subtitle: Label
var _hint: Label
var _columns: HBoxContainer
var _popups: Control
## Step index -> the row it reveals and animates.
var _step_rows := {}
## Bot index -> its panel.
var _panels: Array[Control] = []
## Bot index -> rows shown with the panel (headings, locked scales).
var _panel_rows: Array[Array] = []


func _init() -> void:
	set_anchors_preset(Control.PRESET_FULL_RECT)
	theme = ScreenTheme.theme()
	mouse_filter = Control.MOUSE_FILTER_STOP
	var back := ColorRect.new()
	back.color = BACKGROUND
	back.set_anchors_preset(Control.PRESET_FULL_RECT)
	back.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(back)
	var margin := MarginContainer.new()
	margin.set_anchors_preset(Control.PRESET_FULL_RECT)
	margin.mouse_filter = Control.MOUSE_FILTER_IGNORE
	for side in ["left", "right", "top", "bottom"]:
		margin.add_theme_constant_override("margin_" + side, 24)
	add_child(margin)
	var page := VBoxContainer.new()
	page.add_theme_constant_override("separation", 16)
	page.mouse_filter = Control.MOUSE_FILTER_IGNORE
	margin.add_child(page)
	var head := HBoxContainer.new()
	head.mouse_filter = Control.MOUSE_FILTER_IGNORE
	page.add_child(head)
	_title = _label("", 30, TEXT)
	_title.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	head.add_child(_title)
	_hint = _label("CLICK OR PRESS ANY KEY TO SKIP", 10, TEXT_DIM)
	_hint.visible = false
	head.add_child(_hint)
	_subtitle = _label("", 10, TEXT_DIM)
	page.add_child(_subtitle)
	var scroll := ScrollContainer.new()
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	scroll.vertical_scroll_mode = ScrollContainer.SCROLL_MODE_AUTO
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	page.add_child(scroll)
	_columns = HBoxContainer.new()
	_columns.add_theme_constant_override("separation", 16)
	_columns.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	scroll.add_child(_columns)
	_popups = Control.new()
	_popups.set_anchors_preset(Control.PRESET_FULL_RECT)
	_popups.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_popups)


func show_report(p_report: PostFightReport) -> void:
	report = p_report
	for child in _columns.get_children():
		_columns.remove_child(child)
		child.queue_free()
	_step_rows.clear()
	_panels.clear()
	_panel_rows.clear()
	tally = null
	if report == null or not report.error.is_empty():
		_title.text = "NO REPORT"
		_title.add_theme_color_override("font_color", DEFEAT)
		_subtitle.text = report.error if report != null else "nothing to show"
		_hint.visible = false
		return
	_title.text = "VICTORY" if report.is_victory() else "DEFEAT"
	_title.add_theme_color_override("font_color", VICTORY if report.is_victory() else DEFEAT)
	_subtitle.text = "%d actions. What each bot learned from the fight." % report.action_count
	tally = TallySequence.new(report, settings)
	for i in report.bots.size():
		_panel_rows.append([])
		var panel := _bot_panel(i, report.bots[i])
		_panels.append(panel)
		_columns.add_child(panel)
	_bind_steps()
	for i in tally.steps.size():
		_apply_step(i, 0.0)
	for panel in _panels:
		panel.modulate.a = 0.0
	for row: Control in _step_rows.values():
		row.modulate.a = 0.0
	_hint.visible = true
	set_process(true)
	_reveal(tally.advance(0.0))
	if tally.is_done():
		_finish()


## True while the count-up plays.
func is_tallying() -> bool:
	return tally != null and not tally.is_done()


## Jumps to the end of the count-up.
func skip() -> void:
	if not is_tallying():
		return
	tally.skip()
	for i in tally.steps.size():
		_apply_step(i, 1.0)
	for panel in _panels:
		panel.modulate.a = 1.0
	for rows: Array in _panel_rows:
		for row: Control in rows:
			row.modulate.a = 1.0
	for row: Control in _step_rows.values():
		row.modulate.a = 1.0
		row.position.x = 0.0
	_finish()


## The panel for one bot. Public so tests can read what a bot's panel says.
func bot_panel(bot_id: String) -> Control:
	for child in _columns.get_children():
		if child.name == bot_id:
			return child
	return null


func _process(delta: float) -> void:
	if not is_tallying():
		set_process(false)
		return
	var before := tally.current
	var started := tally.advance(delta)
	for i in range(before, mini(tally.current, tally.steps.size())):
		_apply_step(i, 1.0)
	_reveal(started)
	if not tally.is_done():
		_apply_step(tally.current, tally.progress(tally.current))
	else:
		_finish()


func _gui_input(event: InputEvent) -> void:
	var click := event as InputEventMouseButton
	if click != null and click.pressed and is_tallying():
		skip()
		accept_event()


func _unhandled_key_input(event: InputEvent) -> void:
	if event.is_pressed() and not event.is_echo() and is_tallying():
		skip()
		get_viewport().set_input_as_handled()


func _finish() -> void:
	_hint.visible = false
	set_process(false)
	tally_finished.emit()


## Brings in the rows of the steps that just started, with their sounds.
func _reveal(started: Array[int]) -> void:
	var ticked := false
	for i in started:
		var step := tally.steps[i]
		match step.kind:
			"bot":
				var panel := _panels[step.bot]
				_fade_in(panel)
				for row: Control in _panel_rows[step.bot]:
					row.modulate.a = 1.0
				SoundPlayer.fire(&"card_flip")
			"count", "skill":
				_slide_in(_step_rows[i])
				ticked = true
			"level_up":
				_level_up(i)
			"shift":
				_slide_in(_step_rows[i])
				SoundPlayer.fire(&"personality_shift")
	if ticked:
		SoundPlayer.fire(&"tally_tick")


func _fade_in(node: Control) -> void:
	if FeelTween.seconds("ui", settings) <= 0.0:
		node.modulate.a = 1.0
		return
	FeelTween.to(node, "modulate:a", 1.0, "ui", settings)


func _slide_in(row: Control) -> void:
	var duration := ScreenFeel.seconds("readout.row_in_ms", settings)
	if duration <= 0.0:
		row.modulate.a = 1.0
		return
	row.position.x = -ScreenFeel.number("map.popup_rise_px")
	var tween := row.create_tween().set_parallel()
	tween.tween_property(row, "modulate:a", 1.0, duration)
	tween.tween_property(row, "position:x", 0.0, duration).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)


## The payoff for a level-up: the row turns gold and pops, a "LV n!" number
## rises from it, and the chime plays.
func _level_up(index: int) -> void:
	var row: Control = _step_rows[index]
	SoundPlayer.fire(&"level_up")
	var change := tally.steps[index].change
	var popup := NumberPopup.new()
	popup.setup(change.level_after, "crit", settings)
	popup.text = "LV %d!" % change.level_after
	popup.icon = null
	popup.position = row.global_position - _popups.global_position + Vector2(row.size.x - 40.0, 0)
	_popups.add_child(popup)
	if (settings if settings else GameSettings.shared()).reduced_motion or FeelTween.seconds("ui_pop", settings) <= 0.0:
		return
	row.pivot_offset = row.size / 2.0
	row.scale = Vector2.ONE * ScreenFeel.number("readout.level_up_pop_scale", 1.0)
	FeelTween.to(row, "scale", Vector2.ONE, "ui_pop", settings)


## Ties each step to its row in the panels.
func _bind_steps() -> void:
	for i in tally.steps.size():
		var step := tally.steps[i]
		var panel := _panels[step.bot]
		match step.kind:
			"count":
				_step_rows[i] = panel.find_child("Count_%s" % step.key, true, false)
			"skill", "level_up":
				_step_rows[i] = panel.find_child("Skill_%s" % step.change.combat_skill_id, true, false)
			"shift":
				_step_rows[i] = panel.find_child("Scale_%d" % step.key, true, false)
	# A level-up shares its skill's row.
	for i in _step_rows.keys():
		if _step_rows[i] == null:
			_step_rows.erase(i)


## Writes step `index` as it looks `p` of the way through (0 to 1).
func _apply_step(index: int, p: float) -> void:
	var step := tally.steps[index]
	var row: Control = _step_rows.get(index)
	match step.kind:
		"count":
			if row != null:
				row.get_child(1).text = str(roundi(step.to * p))
		"skill":
			if row != null:
				row.get_child(0).text = "%s ×%d" % [_skill_name(step.change), roundi(step.to * p)]
				var levels := step.change.has_bot_skill() and step.change.levels_gained() > 0
				if not levels and p >= 1.0:
					_set_skill_right(row, step.change, true)
				elif p <= 0.0 or levels:
					_set_skill_right(row, step.change, false)
		"level_up":
			if row != null and p > 0.0:
				_set_skill_right(row, step.change, true)
		"shift":
			if row != null:
				var r := report.bots[step.bot]
				var bar: Control = row.get_child(1)
				var eased := 1.0 - pow(1.0 - p, 3.0)
				bar.after = lerpf(r.personality_before[step.key], r.personality_after[step.key], eased)
				var value: Label = row.get_child(3)
				value.text = "%+.2f" % (r.shift(step.key) * eased) if p > 0.0 else "·"
				value.add_theme_color_override("font_color", ACCENT if p > 0.0 else TEXT_DIM)


func _set_skill_right(row: Control, c: SkillChange, final: bool) -> void:
	var right: Label = row.get_child(1)
	if final:
		right.text = skill_row_right(c)
		right.add_theme_color_override("font_color", skill_row_color(c))
		(row.get_child(0) as Label).add_theme_color_override("font_color", skill_row_color(c))
	else:
		right.text = "basic attack" if not c.has_bot_skill() else "Lv %d" % c.level_before
		right.add_theme_color_override("font_color", TEXT_DIM if not c.has_bot_skill() else TEXT)
		(row.get_child(0) as Label).add_theme_color_override("font_color", TEXT_DIM if not c.has_bot_skill() else TEXT)


func _bot_panel(index: int, r: BotFightReport) -> Control:
	var panel := PanelContainer.new()
	panel.name = r.bot_id
	panel.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	panel.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var style := StyleBoxFlat.new()
	style.bg_color = PANEL
	style.border_color = RULE
	style.set_border_width_all(2)
	style.set_content_margin_all(14)
	panel.add_theme_stylebox_override("panel", style)
	var box := VBoxContainer.new()
	box.add_theme_constant_override("separation", 6)
	panel.add_child(box)

	var head := HBoxContainer.new()
	head.add_theme_constant_override("separation", 10)
	box.add_child(head)
	var art := Control.new()
	art.custom_minimum_size = Vector2(56, 56)
	head.add_child(art)
	var sprite := UnitSprite.new()
	sprite.settings = settings
	sprite.setup(ALLY_UNIT, str(ScreenFeel.value("draft.sprite_tier", "beginner")),
		SpriteManifest.ally_look(ALLY_UNIT, DraftCard.look_seed(r.bot_id)))
	sprite.scale = Vector2.ONE * 2.0
	sprite.position = Vector2(28, 28)
	art.add_child(sprite)
	var names := VBoxContainer.new()
	names.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	head.add_child(names)
	names.add_child(_label(r.display_name, 20, TEXT))
	names.add_child(_label("%d decisions · generation %d" % [r.decisions, r.generation], 10, TEXT_DIM))

	box.add_child(_heading("WHAT IT DID"))
	var any_label := false
	for label: String in ActionTag.ALL_LABELS:
		var count: int = r.label_counts.get(label, 0)
		if count > 0:
			any_label = true
			var row := _row(LABEL_NAMES.get(label, label), str(count), TEXT)
			row.name = "Count_%s" % label
			box.add_child(row)
	if not any_label:
		box.add_child(_label("Nothing of note", 10, TEXT_DIM))

	box.add_child(_heading("SKILLS"))
	if r.skill_changes.is_empty():
		box.add_child(_label("No skills used", 10, TEXT_DIM))
	for change in r.skill_changes:
		var row := _skill_row(change)
		row.name = "Skill_%s" % change.combat_skill_id
		box.add_child(row)

	box.add_child(_heading("PERSONALITY"))
	for scale in Personality.SCALE_COUNT:
		var row := _scale_row(r, scale)
		row.name = "Scale_%d" % scale
		box.add_child(row)
		if not r.is_scale_active(scale) or is_zero_approx(r.shift(scale)):
			_panel_rows[index].append(row)
	return panel


func _skill_name(c: SkillChange) -> String:
	return c.skill_name if c.has_bot_skill() else c.combat_skill_id.capitalize()


func _skill_row(c: SkillChange) -> Control:
	return _row(skill_row_left(c), skill_row_right(c), skill_row_color(c))


## "Patch Up ×3", or the combat skill's name for a use with no bot skill.
static func skill_row_left(c: SkillChange) -> String:
	return "%s ×%d" % [c.skill_name if c.has_bot_skill() else c.combat_skill_id.capitalize(), c.uses]


## "Lv 1 · 3/5 to Lv 2", "LEVEL UP  1 > 2 · 1/5", "Lv 10 · max", or, for the
## basic attack a bot keeps without holding it as a skill, "basic attack".
static func skill_row_right(c: SkillChange) -> String:
	if not c.has_bot_skill():
		return "basic attack"
	var progress := "max" if c.is_max_level() else "%d/%d to Lv %d" % [c.banked_after, c.uses_per_level, c.level_after + 1]
	if c.levels_gained() > 0:
		return "LEVEL UP  %d > %d · %s" % [c.level_before, c.level_after, progress]
	return "Lv %d · %s" % [c.level_after, progress]


static func skill_row_color(c: SkillChange) -> Color:
	if not c.has_bot_skill():
		return TEXT_DIM
	return LEVEL_UP if c.levels_gained() > 0 else TEXT


func _scale_row(r: BotFightReport, scale: int) -> Control:
	var poles: Array = Personality.POLES[scale]
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 6)
	var active := r.is_scale_active(scale)
	var left := _label(poles[0], 10, TEXT_DIM)
	left.custom_minimum_size.x = 80
	left.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	row.add_child(left)
	var bar: Control = ScaleBar.new()
	bar.active = active
	bar.before = r.personality_before[scale]
	bar.after = r.personality_after[scale]
	bar.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	bar.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	row.add_child(bar)
	var right := _label(poles[1], 10, TEXT_DIM)
	right.custom_minimum_size.x = 80
	row.add_child(right)
	var shift_text := "locked"
	var color := TEXT_DIM
	if active:
		var shift := r.shift(scale)
		shift_text = "%+.2f" % shift if not is_zero_approx(shift) else "·"
		color = ACCENT if not is_zero_approx(shift) else TEXT_DIM
	var value := _label(shift_text, 10, color)
	value.custom_minimum_size.x = 50
	value.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	row.add_child(value)
	return row


func _row(left: String, right: String, color: Color) -> Control:
	var row := HBoxContainer.new()
	var l := _label(left, 10, color)
	l.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	row.add_child(l)
	row.add_child(_label(right, 10, color))
	return row


func _heading(text: String) -> Control:
	var box := VBoxContainer.new()
	box.add_theme_constant_override("separation", 2)
	var gap := Control.new()
	gap.custom_minimum_size.y = 4
	box.add_child(gap)
	box.add_child(_label(text, 10, TEXT_DIM))
	var rule := ColorRect.new()
	rule.color = RULE
	rule.custom_minimum_size.y = 2
	box.add_child(rule)
	return box


static func _label(text: String, font_size: int, color: Color) -> Label:
	var l := Label.new()
	l.text = text
	l.add_theme_font_size_override("font_size", ScreenTheme.size(font_size))
	l.add_theme_color_override("font_color", color)
	l.mouse_filter = Control.MOUSE_FILTER_IGNORE
	return l
