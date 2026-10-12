extends Control
## The post-fight readout: per bot, what it did (tag counters), which skills
## ranked up, and how its personality grew. Call show_report() with what
## PostFight.apply() returned.
##
## It counts up (TallySequence, data/feel/screens.json "readout"): each bot's
## panel comes in, its counters and skill uses tick up one row after another,
## then the payoffs land: a rank-up takes the screen with the level-up callout
## (LevelUpCallout: before and after numbers, a sound, a pop and a hit pause;
## a Mega or Ultra tier shift is a bigger moment with its own sound), and the
## personality hexagon (PersonalityHexagon) traces its new outline, then fills
## from the old shape to the new one with a rising sound. One bot after
## another. A click or a key skips to the end; the animation speed setting
## shortens it, and skip shows the end at once.
## Only one-shot sounds play here; the readout's music is R1-D's.

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
## The level-up callout on screen, or null.
var _callout: LevelUpCallout
## Step index of the callout on screen, or -1.
var _callout_step := -1
## Grow steps whose rising sound already played.
var _grow_sounded := {}
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
	_grow_sounded.clear()
	_clear_callout()
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
	_clear_callout()
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
		if i == _callout_step:
			_dismiss_callout()
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


## The level-up callout on screen, or null. Public so tests can read it.
func callout() -> LevelUpCallout:
	return _callout if is_instance_valid(_callout) else null


func _finish() -> void:
	_dismiss_callout()
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
			"grow":
				pass
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


## The payoff for a level-up: the skill's row turns gold and pops, and the
## level-up callout takes the screen until the step ends.
func _level_up(index: int) -> void:
	var row: Control = _step_rows.get(index)
	var change := tally.steps[index].change
	_dismiss_callout()
	_callout = LevelUpCallout.new()
	_callout.setup(change, settings)
	_callout_step = index
	_popups.add_child(_callout)
	_callout.play(_popups.size, _popups)
	if row == null or (settings if settings else GameSettings.shared()).reduced_motion \
			or FeelTween.seconds("ui_pop", settings) <= 0.0:
		return
	row.pivot_offset = row.size / 2.0
	row.scale = Vector2.ONE * ScreenFeel.number("readout.level_up_pop_scale", 1.0)
	FeelTween.to(row, "scale", Vector2.ONE, "ui_pop", settings)


func _dismiss_callout() -> void:
	if is_instance_valid(_callout):
		_callout.dismiss()
	_callout = null
	_callout_step = -1


func _clear_callout() -> void:
	if is_instance_valid(_callout):
		_callout.queue_free()
	_callout = null
	_callout_step = -1


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
			"grow":
				_step_rows[i] = panel.find_child("Hexagon", true, false)
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
		"grow":
			if row != null:
				var hex: PersonalityHexagon = row.find_child("Chart", true, false)
				var was_filling := hex.fill_progress() > 0.0
				hex.progress = p
				# The rising sound starts with the fill, once.
				if hex.fill_progress() > 0.0 and not was_filling and p < 1.0 and not _grow_sounded.has(index):
					_grow_sounded[index] = true
					SoundPlayer.fire(&"personality_grow")
				var growth: Control = row.find_child("Growth", true, false)
				growth.modulate.a = 1.0 if hex.fill_progress() > 0.0 else 0.0


func _set_skill_right(row: Control, c: SkillChange, final: bool) -> void:
	var right: Label = row.get_child(1)
	if final:
		right.text = skill_row_right(c)
		right.add_theme_color_override("font_color", skill_row_color(c))
		(row.get_child(0) as Label).add_theme_color_override("font_color", skill_row_color(c))
	else:
		var before := _rank_or_base(c.rank_before) if c.ranked else "Lv %d" % c.level_before
		right.text = "basic attack" if not c.has_bot_skill() else before
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
	# The old shape shows with the panel; the grow step then draws the new one.
	var hex_box := _hexagon_box(r)
	box.add_child(hex_box)
	_panel_rows[index].append(hex_box)
	return panel


func _skill_name(c: SkillChange) -> String:
	return _skill_name_of(c)


func _skill_row(c: SkillChange) -> Control:
	var row := _row(skill_row_left(c), skill_row_right(c), skill_row_color(c))
	UiTooltip.attach(row, _skill_name_of(c), skill_row_tip(c))
	return row


## The skill row's tooltip, keywords and numbers: "Rank up to +2. Mega: Pierce 50%."
static func skill_row_tip(c: SkillChange) -> String:
	if not c.has_bot_skill():
		return "The basic attack. It does not Rank up."
	var parts: Array[String] = ["Used %d times." % c.uses]
	if c.levels_gained() > 0:
		parts.append("Rank up to %s." % _rank_or_base(c.rank_after) if c.ranked else "Level %d." % c.level_after)
	if not c.new_bonuses.is_empty():
		parts.append("%s: %s." % [c.name_after.split(" ")[0] if c.is_tier_shift() else "Now", ", ".join(c.new_bonuses)])
	return " ".join(parts)


## "Patch Up ×3", or the combat skill's name for a use with no bot skill.
static func skill_row_left(c: SkillChange) -> String:
	return "%s ×%d" % [_skill_name_of(c), c.uses]


static func _skill_name_of(c: SkillChange) -> String:
	if not c.has_bot_skill():
		return c.combat_skill_id.capitalize()
	return c.name_after if not c.name_after.is_empty() else c.skill_name


## "Lv 1 · 3/5 to Lv 2", "LEVEL UP  1 > 2 · 1/5", "Lv 10 · max", or, for the
## basic attack a bot keeps without holding it as a skill, "basic attack".
static func skill_row_right(c: SkillChange) -> String:
	if not c.has_bot_skill():
		return "basic attack"
	if c.ranked:
		var progress_r := "max" if c.is_max_level() else "%d/%d" % [c.banked_after, c.uses_per_level]
		if c.levels_gained() > 0:
			return "%s %s > %s · %s" % ["TIER UP" if c.is_tier_shift() else "RANK UP",
				_rank_or_base(c.rank_before), _rank_or_base(c.rank_after), progress_r]
		return "%s · %s" % [_rank_or_base(c.rank_after), progress_r]
	var progress := "max" if c.is_max_level() else "%d/%d to Lv %d" % [c.banked_after, c.uses_per_level, c.level_after + 1]
	if c.levels_gained() > 0:
		return "LEVEL UP  %d > %d · %s" % [c.level_before, c.level_after, progress]
	return "Lv %d · %s" % [c.level_after, progress]


static func _rank_or_base(label: String) -> String:
	return "base" if label.is_empty() else label


static func skill_row_color(c: SkillChange) -> Color:
	if not c.has_bot_skill():
		return TEXT_DIM
	return LEVEL_UP if c.levels_gained() > 0 else TEXT


## The personality hexagon and, under it, what grew ("+0.06 aggressive").
func _hexagon_box(r: BotFightReport) -> Control:
	var box := VBoxContainer.new()
	box.name = "Hexagon"
	box.add_theme_constant_override("separation", 2)
	box.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var hex := PersonalityHexagon.new()
	hex.name = "Chart"
	var hex_size: Array = ScreenFeel.value("readout.hex_size", [260, 200])
	hex.custom_minimum_size = Vector2(hex_size[0], hex_size[1])
	hex.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	hex.min_extent = ScreenFeel.number("readout.hex_min_extent", 0.5)
	hex.outline_share = ScreenFeel.number("readout.outline_share", 0.35)
	hex.before = r.personality_before.duplicate()
	hex.after = r.personality_after.duplicate()
	box.add_child(hex)
	# What grew as trait icons with their gain (ui/README.md rule 1); the
	# words stay in each icon's tooltip. No growth keeps the dim words.
	var grown := growth_items(r)
	if grown.is_empty():
		var growth := _label(growth_text(r), 10, TEXT_DIM)
		growth.name = "Growth"
		growth.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		box.add_child(growth)
		return box
	var row := HBoxContainer.new()
	row.name = "Growth"
	row.alignment = BoxContainer.ALIGNMENT_CENTER
	row.add_theme_constant_override("separation", 12)
	box.add_child(row)
	for g: Array in grown:
		var stat := IconStat.make("trait_%s" % g[1], "+%.2f" % g[0], "Grew this fight.")
		stat.value_label.add_theme_color_override("font_color", ACCENT)
		row.add_child(stat)
	return box


## What grew, biggest first: [[gain, end], ...].
static func growth_items(r: BotFightReport) -> Array:
	var grown: Array = []
	for i in Personality.ENDS.size():
		if i < r.personality_after.size() and r.growth(i) > 0.0001:
			grown.append([r.growth(i), Personality.ENDS[i]])
	grown.sort_custom(func(a: Array, b: Array) -> bool: return a[0] > b[0])
	return grown


## What grew, biggest first: "+0.06 aggressive  +0.02 solitary", or "No change".
static func growth_text(r: BotFightReport) -> String:
	var grown := growth_items(r)
	if grown.is_empty():
		return "No change"
	return "  ".join(grown.map(func(g: Array) -> String: return "+%.2f %s" % [g[0], g[1]]))


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
