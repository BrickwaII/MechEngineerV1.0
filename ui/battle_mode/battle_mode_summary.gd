class_name BattleModeSummary
extends Control
## The end of a Battle Mode run: how it ended, the run's totals as icons
## (fights won, turns, HP lost, energy spent and wasted, combos, Staggers),
## each action's share of the squad's turns as a bar with the dominant-share
## line (the plan's "no action above about 50%"), and one row per fight. The
## same numbers go to the CSV (BattleModeRun.write_csv); where is said below.

signal again_requested
signal home_requested

const SHARE_BAR_SIZE := Vector2(192, 24)
const NAME_WIDTH := 168.0

var summary: BattleRunSummary
var names: Callable
## Where the CSV went, or "" when it was not written.
var csv_path := ""
var again_button: ActionButton
var home_button: ActionButton
## Action id -> its share bar row.
var share_rows: Dictionary[String, Control] = {}


func show_summary(p_summary: BattleRunSummary, p_names: Callable, p_csv_path := "") -> void:
	summary = p_summary
	names = p_names
	csv_path = p_csv_path
	if is_inside_tree():
		_build()


func _ready() -> void:
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	theme = ScreenTheme.theme()
	if summary != null:
		_build()


func _name(id: String) -> String:
	return str(names.call(id)) if names.is_valid() else id


func _build() -> void:
	for child in get_children():
		child.queue_free()
	var back := ColorRect.new()
	back.color = FeelData.color("background")
	back.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	add_child(back)
	var margin := MarginContainer.new()
	margin.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	for side in ["left", "right", "top", "bottom"]:
		margin.add_theme_constant_override("margin_" + side, UiStyle.space("l"))
	add_child(margin)
	var page := UiStyle.column("m")
	page.name = "Page"
	margin.add_child(page)

	var head := UiStyle.row("m")
	page.add_child(head)
	var cleared := summary.cleared
	var title := UiStyle.label(summary.outcome_text().to_upper(), "good" if cleared else "title", "title")
	title.name = "Outcome"
	head.add_child(title)
	head.add_child(UiStyle.spring())
	var length := UiStyle.label("Battle Mode · %s · squad %s" % [summary.length_id.capitalize(), summary.squad_label.capitalize()], "text_quiet")
	head.add_child(length)

	var totals := UiStyle.row("l")
	totals.name = "Totals"
	page.add_child(totals)
	totals.add_child(IconStat.make("fights_won", summary.won(), "Fights won."))
	totals.add_child(IconStat.make("fights_lost", summary.fights() - summary.won(), "Fights lost."))
	totals.add_child(IconStat.make("time", TextFormat.short_number(snappedf(summary.avg_turns(), 0.1)),
		"Turns per fight: the squad's decisions. %d in all." % summary.total("turns")))
	var hp := IconStat.make("hp", "-%s%%" % TextFormat.short_number(snappedf(summary.avg_hp_lost_percent(), 0.1)),
		"HP lost per fight, as a share of the squad's full HP. %d HP in all." % summary.total("hp_lost"))
	totals.add_child(hp)
	totals.add_child(IconStat.make("energy", TextFormat.short_number(summary.energy_spent()), "Energy the squad spent."))
	totals.add_child(IconStat.make("battery", "%s (%d%%)" % [TextFormat.short_number(summary.energy_wasted()), summary.wasted_percent()],
		"Energy wasted: recharge lost to full batteries, and its share of all the energy the squad had."))
	totals.add_child(IconStat.make("multiplier", summary.total("combos"), "Combos: hits that cashed in a setup."))
	totals.add_child(IconStat.make("status_intent_changed", summary.total("staggers"), "Staggers: enemy plating broken."))
	totals.add_child(IconStat.make("intent_buff", summary.total("rank_ups"), "Skill rank-ups the squad earned."))

	var columns := UiStyle.row("l")
	columns.size_flags_vertical = Control.SIZE_EXPAND_FILL
	page.add_child(columns)
	var shares := UiStyle.column("s")
	shares.name = "Shares"
	columns.add_child(shares)
	shares.add_child(UiStyle.caption(UiStyle.label("ACTION SHARE")))
	for s: Array in summary.action_shares():
		var row := _share_row(s[0], s[1], s[2])
		shares.add_child(row)
		share_rows[s[0]] = row
	var flagged := summary.dominated_fights()
	var verdict := UiStyle.label("%d of %d fights had one action above %d%%." % [
		flagged, summary.fights(), summary.dominant_share_percent], "caution" if flagged > 0 else "good")
	verdict.name = "Verdict"
	verdict.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	verdict.custom_minimum_size.x = NAME_WIDTH + SHARE_BAR_SIZE.x
	shares.add_child(verdict)

	var fights := UiStyle.column("s")
	fights.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	columns.add_child(fights)
	fights.add_child(UiStyle.caption(UiStyle.label("FIGHTS")))
	var scroll := ScrollContainer.new()
	scroll.name = "FightsScroll"
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	scroll.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	fights.add_child(scroll)
	var rows := UiStyle.column("s")
	rows.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	scroll.add_child(rows)
	for r in summary.records:
		var row := UiStyle.row("m")
		var kind := UiStyle.label("%d" % r.fight_number, "title")
		kind.custom_minimum_size.x = 32
		row.add_child(kind)
		# Every row keeps the flag's room, so the numbers line up.
		var flag_slot := CenterContainer.new()
		flag_slot.custom_minimum_size.x = 40
		row.add_child(flag_slot)
		if r.kind != "normal":
			flag_slot.add_child(Flag.of(r.kind, true))
		row.add_child(BattleFightLine.make(r, names, summary.dominant_share_percent, true))
		rows.add_child(row)

	if not csv_path.is_empty():
		var where := UiStyle.label("Numbers saved to %s" % csv_path, "text_quiet")
		where.name = "CsvPath"
		where.autowrap_mode = TextServer.AUTOWRAP_ARBITRARY
		page.add_child(where)
	var actions := UiStyle.row("m")
	page.add_child(actions)
	home_button = ActionButton.make("action_home", "Main menu")
	home_button.name = "HomeButton"
	home_button.pressed.connect(func() -> void: home_requested.emit())
	actions.add_child(home_button)
	actions.add_child(UiStyle.spring())
	again_button = ActionButton.make("action_replay", "Play again")
	again_button.name = "AgainButton"
	again_button.pressed.connect(func() -> void: again_requested.emit())
	actions.add_child(again_button)


func _share_row(id: String, uses: int, percent: int) -> Control:
	var row := UiStyle.row("s")
	row.name = "Share_%s" % id
	var label := UiStyle.label(_name(id))
	label.custom_minimum_size.x = NAME_WIDTH
	label.clip_text = false
	row.add_child(label)
	var bar := Control.new()
	bar.name = "Bar"
	bar.custom_minimum_size = SHARE_BAR_SIZE
	bar.mouse_filter = Control.MOUSE_FILTER_PASS
	row.add_child(bar)
	var track := ColorRect.new()
	track.color = UiStyle.role("neutral").darkened(0.5)
	track.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	track.mouse_filter = Control.MOUSE_FILTER_IGNORE
	bar.add_child(track)
	var over := percent > summary.dominant_share_percent
	var fill := ColorRect.new()
	fill.name = "Fill"
	fill.color = UiStyle.role("caution" if over else "info")
	fill.position = Vector2.ZERO
	fill.size = Vector2(SHARE_BAR_SIZE.x * percent / 100.0, SHARE_BAR_SIZE.y)
	fill.mouse_filter = Control.MOUSE_FILTER_IGNORE
	bar.add_child(fill)
	var line := ColorRect.new()
	line.name = "Limit"
	line.color = UiStyle.role("bad")
	line.position = Vector2(SHARE_BAR_SIZE.x * summary.dominant_share_percent / 100.0 - 1, 0)
	line.size = Vector2(2, SHARE_BAR_SIZE.y)
	line.mouse_filter = Control.MOUSE_FILTER_IGNORE
	bar.add_child(line)
	var value := UiStyle.label("%d%%" % percent, "caution" if over else "text")
	row.add_child(value)
	UiTooltip.attach(row, _name(id), "%d of the squad's %d turns this run." % [uses, summary.total("turns")],
		"Share %d%%. The line marks %d%%." % [percent, summary.dominant_share_percent])
	return row
