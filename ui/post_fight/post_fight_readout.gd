extends Control
## The basic post-fight readout: per bot, what it did (tag counters), which
## skills levelled, and how its personality shifted. Plain text and shapes.
## Call show_report() with what PostFight.apply() returned.

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

var report: PostFightReport

var _title: Label
var _subtitle: Label
var _columns: HBoxContainer


func _init() -> void:
	set_anchors_preset(Control.PRESET_FULL_RECT)
	var back := ColorRect.new()
	back.color = BACKGROUND
	back.set_anchors_preset(Control.PRESET_FULL_RECT)
	add_child(back)
	var margin := MarginContainer.new()
	margin.set_anchors_preset(Control.PRESET_FULL_RECT)
	for side in ["left", "right", "top", "bottom"]:
		margin.add_theme_constant_override("margin_" + side, 24)
	add_child(margin)
	var page := VBoxContainer.new()
	page.add_theme_constant_override("separation", 16)
	margin.add_child(page)
	_title = _label("", 28, TEXT)
	page.add_child(_title)
	_subtitle = _label("", 14, TEXT_DIM)
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


func show_report(p_report: PostFightReport) -> void:
	report = p_report
	for child in _columns.get_children():
		_columns.remove_child(child)
		child.queue_free()
	if report == null or not report.error.is_empty():
		_title.text = "NO REPORT"
		_title.add_theme_color_override("font_color", DEFEAT)
		_subtitle.text = report.error if report != null else "nothing to show"
		return
	_title.text = "VICTORY" if report.is_victory() else "DEFEAT"
	_title.add_theme_color_override("font_color", VICTORY if report.is_victory() else DEFEAT)
	_subtitle.text = "%d actions. What each bot learned from the fight." % report.action_count
	for bot_report in report.bots:
		_columns.add_child(_bot_panel(bot_report))


## The panel for one bot. Public so tests can read what a bot's panel says.
func bot_panel(bot_id: String) -> Control:
	for child in _columns.get_children():
		if child.name == bot_id:
			return child
	return null


func _bot_panel(r: BotFightReport) -> Control:
	var panel := PanelContainer.new()
	panel.name = r.bot_id
	panel.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	var style := StyleBoxFlat.new()
	style.bg_color = PANEL
	style.border_color = RULE
	style.set_border_width_all(1)
	style.set_corner_radius_all(6)
	style.set_content_margin_all(14)
	panel.add_theme_stylebox_override("panel", style)
	var box := VBoxContainer.new()
	box.add_theme_constant_override("separation", 6)
	panel.add_child(box)

	box.add_child(_label(r.display_name, 20, TEXT))
	box.add_child(_label("%d decisions · generation %d" % [r.decisions, r.generation], 13, TEXT_DIM))

	box.add_child(_heading("WHAT IT DID"))
	var any_label := false
	for label: String in ActionTag.ALL_LABELS:
		var count: int = r.label_counts.get(label, 0)
		if count > 0:
			any_label = true
			box.add_child(_row(LABEL_NAMES.get(label, label), str(count), TEXT))
	if not any_label:
		box.add_child(_label("Nothing of note", 14, TEXT_DIM))

	box.add_child(_heading("SKILLS"))
	if r.skill_changes.is_empty():
		box.add_child(_label("No skills used", 14, TEXT_DIM))
	for change in r.skill_changes:
		box.add_child(_skill_row(change))

	box.add_child(_heading("PERSONALITY"))
	for scale in Personality.SCALE_COUNT:
		box.add_child(_scale_row(r, scale))
	return panel


func _skill_row(c: SkillChange) -> Control:
	var name := c.skill_name if c.has_bot_skill() else c.combat_skill_id.capitalize()
	if not c.has_bot_skill():
		return _row("%s ×%d" % [name, c.uses], "no skill to train", TEXT_DIM)
	if c.levels_gained() > 0:
		return _row("%s ×%d" % [name, c.uses], "LEVEL UP  %d → %d" % [c.level_before, c.level_after], LEVEL_UP)
	return _row("%s ×%d" % [name, c.uses], "Lv %d · %d banked" % [c.level_after, c.banked_after], TEXT)


func _scale_row(r: BotFightReport, scale: int) -> Control:
	var poles: Array = Personality.POLES[scale]
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 6)
	var active := r.is_scale_active(scale)
	var left := _label(poles[0], 13, TEXT_DIM)
	left.custom_minimum_size.x = 70
	left.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	row.add_child(left)
	var bar: Control = ScaleBar.new()
	bar.active = active
	bar.before = r.personality_before[scale]
	bar.after = r.personality_after[scale]
	bar.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	bar.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	row.add_child(bar)
	var right := _label(poles[1], 13, TEXT_DIM)
	right.custom_minimum_size.x = 70
	row.add_child(right)
	var shift_text := "locked"
	var color := TEXT_DIM
	if active:
		var shift := r.shift(scale)
		shift_text = "%+.2f" % shift if not is_zero_approx(shift) else "·"
		color = ACCENT if not is_zero_approx(shift) else TEXT_DIM
	var value := _label(shift_text, 13, color)
	value.custom_minimum_size.x = 40
	value.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	row.add_child(value)
	return row


func _row(left: String, right: String, color: Color) -> Control:
	var row := HBoxContainer.new()
	var l := _label(left, 14, color)
	l.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	row.add_child(l)
	row.add_child(_label(right, 14, color))
	return row


func _heading(text: String) -> Control:
	var box := VBoxContainer.new()
	box.add_theme_constant_override("separation", 2)
	var gap := Control.new()
	gap.custom_minimum_size.y = 4
	box.add_child(gap)
	box.add_child(_label(text, 11, TEXT_DIM))
	var rule := ColorRect.new()
	rule.color = RULE
	rule.custom_minimum_size.y = 1
	box.add_child(rule)
	return box


static func _label(text: String, font_size: int, color: Color) -> Label:
	var l := Label.new()
	l.text = text
	l.add_theme_font_size_override("font_size", font_size)
	l.add_theme_color_override("font_color", color)
	return l
