class_name BattleDebugger
extends PanelContainer
## The battle debug simulator's panel (combat rework S9b): a dev-only drawer
## on a live battle screen for tuning by experimentation. Every change goes
## through a BattleDebugSession (tools/battle_debug/), and the screen redraws
## at once: preview, timeline, intents.
##
##   var dbg := BattleDebugger.attach(screen)   # null in release builds
##
## F7 (data/dev/battle_debugger.json; F6 is the S9 action-share panel) shows
## and hides it. While shown the
## fight is paused: enemy turns wait for Step or Resume. Alt-click a unit
## card or an action tile to inspect it.
##
## Tabs: Unit (stats, energy, statuses, plating, personality, timeline,
## forced next action, add/copy/remove), Action (the definition), AI (intent
## weights), Simulate (the S8 harness on the edited set-up), Changes (the
## log, Save to data with its diff, Export tuning diff).

const Ui := preload("res://ui/dev/dev_ui.gd")
const Palette := preload("res://ui/dev/dev_palette.gd")

const TAB_UNIT := 0
const TAB_ACTION := 1
const TAB_AI := 2
const TAB_SIMULATE := 3
const TAB_CHANGES := 4

## Spin box limits for every integer field.
const INT_MIN := -100000
const INT_MAX := 100000

var screen: BattleScreen
var session: BattleDebugSession
var settings: BattleDebugSettings
var paused := true
## The unit and action the inspector shows.
var unit_id := ""
var action_id := ""
## The latest Simulate result, or null.
var comparison: PolicyComparison
## The latest message (an edit refused, a file written).
var status_text := ""

var tabs: TabContainer
var status_label: Label
var pause_button: Button
var rewind_list: OptionButton
var unit_list: OptionButton
var action_list: OptionButton
## Field name -> its editor (SpinBox, CheckBox, LineEdit or OptionButton).
var unit_editors: Dictionary = {}
var personality_editors: Dictionary = {}
var action_editors: Dictionary = {}
## "<weight>/<key>" -> SpinBox.
var ai_editors: Dictionary = {}
var status_box: VBoxContainer
var status_pick: OptionButton
var force_skill: OptionButton
var force_target: OptionButton
var forced_label: Label
var enemy_pick: OptionButton
var sim_runs: SpinBox
var sim_label: Label
## S9's live action-use share of the squad in this fight (ActionSharePanel).
var share_panel: ActionSharePanel
var changes_label: Label
var save_box: VBoxContainer
## Change seq -> its "save" CheckBox.
var save_checks: Dictionary = {}
var diff_label: Label
var save_dialog: ConfirmationDialog

var _toggle_key := KEY_F7
## True while the panel writes values into its editors (no edits sent).
var _filling := false
## The screen's right offset before the panel took room; INF until read.
var _screen_right := INF


## Builds a session on `p_screen`'s fight and adds the panel to the screen,
## hidden. Null when the debugger is off (release builds), unless `force`.
static func attach(p_screen: BattleScreen, force := false, p_settings: BattleDebugSettings = null) -> BattleDebugger:
	if not force and not BattleDebugSession.is_enabled():
		return null
	var d := BattleDebugger.new()
	d.settings = p_settings if p_settings != null else BattleDebugSettings.load_default()
	d.screen = p_screen
	var planner := p_screen.telegraph.planner
	d.session = BattleDebugSession.new(p_screen.fight, null, p_screen.handler.enemy_policy, planner, d.settings)
	p_screen.handler.enemy_policy = d.session.enemy_policy
	p_screen.add_child(d)
	d.visible = false
	return d


## Waits on a battle screen for the toggle key, then attaches the debugger
## and shows it: so a run's battles carry nothing extra until it is asked for.
class Hook:
	extends Node
	var screen: BattleScreen
	var key := KEY_F7

	func _unhandled_key_input(event: InputEvent) -> void:
		var k := event as InputEventKey
		if k == null or not k.pressed or k.echo or k.keycode != key:
			return
		var d := BattleDebugger.attach(screen)
		if d != null:
			d.visible = true
		get_viewport().set_input_as_handled()
		queue_free()


## Puts a Hook on `p_screen` (dev builds only): F7 then attaches the
## debugger. Returns the hook, or null when the debugger is off.
static func install(p_screen: BattleScreen) -> Node:
	if not BattleDebugSession.is_enabled():
		return null
	var hook := Hook.new()
	hook.screen = p_screen
	hook.key = OS.find_keycode_from_string(BattleDebugSettings.load_default().toggle_key)
	hook.name = "BattleDebuggerHook"
	p_screen.add_child(hook)
	return hook


func _ready() -> void:
	name = "BattleDebugger"
	theme = Ui.theme()
	_toggle_key = OS.find_keycode_from_string(settings.toggle_key)
	var style := StyleBoxFlat.new()
	style.bg_color = Palette.PANEL
	style.border_color = Palette.RULE
	style.set_border_width_all(1)
	style.set_content_margin_all(8)
	add_theme_stylebox_override("panel", style)
	# Laid out against the window, not the screen it sits in, which shrinks
	# beside it.
	top_level = true
	set_anchors_and_offsets_preset(Control.PRESET_RIGHT_WIDE)
	offset_left = -settings.panel_width
	custom_minimum_size.x = settings.panel_width
	get_viewport().size_changed.connect(_make_room)
	_build()
	session.changed.connect(_on_session_changed)
	screen.handler.changed.connect(_on_screen_moved)
	screen.unit_inspect_requested.connect(inspect_unit)
	screen.action_inspect_requested.connect(inspect_action)
	visibility_changed.connect(_on_visibility_changed)
	unit_id = session.fight.combatants[0].id if not session.fight.combatants.is_empty() else ""
	action_id = "heavy_strike" if session.action("heavy_strike") != null else session.action_ids()[0]
	refresh()


func _unhandled_key_input(event: InputEvent) -> void:
	var key := event as InputEventKey
	if key != null and key.pressed and not key.echo and key.keycode == _toggle_key:
		toggle()
		get_viewport().set_input_as_handled()


func toggle() -> void:
	visible = not visible


func _on_visibility_changed() -> void:
	screen.inspect_enabled = visible
	screen.hold_enemy_turns = visible and paused
	_make_room()


## While shown, the battle screen itself is made narrower (its right edge
## moves in by the panel's width), so it runs its own fit pass and lays out
## as it would in a window that wide: every unit, the dock and the strip
## stay whole and clickable. The panel is top-level, on the window's right
## edge. The screen never goes below settings.min_screen_width (the
## narrowest window the fit tests cover): in a smaller window the panel
## narrows, down to min_panel_width, and past that covers the screen's edge.
func _make_room() -> void:
	if _screen_right == INF:
		_screen_right = screen.offset_right
	var width := panel_width()
	offset_left = -width
	custom_minimum_size.x = width
	screen.offset_right = _screen_right - (mini(width, maxi(0, _window_width() - settings.min_screen_width))
		if visible else 0)


## The panel's width in the current window (see _make_room()).
func panel_width() -> int:
	var room := _window_width() - settings.min_screen_width
	return clampi(room, settings.min_panel_width, settings.panel_width)


func _window_width() -> int:
	return int(get_viewport_rect().size.x) if is_inside_tree() else settings.panel_width + settings.min_screen_width


# --- Actions the buttons call (tests call them too) --------------------------

func set_paused(on: bool) -> void:
	paused = on
	screen.hold_enemy_turns = visible and paused
	pause_button.text = "Resume" if paused else "Pause"


## One decision: an enemy's turn as the screen plays it, or the bot's turn
## played by the session's squad policy.
func step() -> void:
	if screen.handler.is_enemy_turn():
		screen.handler.resolve_enemy_turn()
	else:
		session.step()


func rewind_to(action_count: int) -> void:
	_report(session.rewind_to(action_count))


func rewind_one() -> void:
	_report(session.rewind_one())


func restart() -> void:
	_report(session.restart())


func inspect_unit(id: String) -> void:
	unit_id = id
	visible = true
	tabs.current_tab = TAB_UNIT
	refresh()


func inspect_action(id: String) -> void:
	action_id = id
	visible = true
	tabs.current_tab = TAB_ACTION
	refresh()


func edit_unit(field: String, value: Variant) -> void:
	if not _filling:
		_report(session.set_unit_field(unit_id, field, value))


func edit_personality(field: String, value: float) -> void:
	if not _filling:
		_report(session.set_personality(unit_id, field, value))


func edit_action(field: String, value: Variant) -> void:
	if not _filling:
		_report(session.set_action_field(action_id, field, value))


func edit_ai(weight: String, key: String, value: float) -> void:
	if not _filling:
		_report(session.set_ai_weight(weight, key, value))


func simulate() -> PolicyComparison:
	comparison = session.simulate(int(sim_runs.value))
	sim_label.text = _simulation_text(comparison)
	return comparison


## Shows what Save to data would write for the checked changes.
func show_save_diff() -> TuningPatch:
	var patch := session.preview_save(_checked_seqs())
	var text := patch.diff_text() if not patch.is_empty() else "Nothing to write: the files already hold these values."
	if not patch.problems.is_empty():
		text = "Problems:\n" + "\n".join(patch.problems) + "\n\n" + text
	diff_label.text = text
	save_dialog.dialog_text = text
	if is_inside_tree() and not patch.is_empty():
		save_dialog.popup_centered()
	return patch


func save_checked() -> Array[String]:
	var problems := session.save_to_data(_checked_seqs())
	_report("\n".join(problems) if not problems.is_empty() else "Saved to data.")
	return problems


func export_diff() -> String:
	var path := session.export_tuning_diff()
	_report("Exported %s" % ProjectSettings.globalize_path(path) if not path.is_empty() else "Export failed")
	return path


# --- Refresh -----------------------------------------------------------------

func _on_session_changed() -> void:
	screen.debug_resync()
	refresh()


## The screen played a decision (a player's choice, an enemy's turn).
func _on_screen_moved() -> void:
	session.sync()
	if is_inside_tree():
		refresh()


func refresh() -> void:
	if tabs == null:
		return
	_filling = true
	_fill_time()
	_fill_unit()
	_fill_action()
	_fill_ai()
	_fill_changes()
	if share_panel != null:
		share_panel.refresh()
	status_label.text = status_text
	_filling = false


func _report(problem: String) -> void:
	status_text = problem
	if status_label != null:
		status_label.text = problem


func _fill_time() -> void:
	var points := session.snapshot_points()
	rewind_list.clear()
	for p in points:
		var snap := session.snapshot(p)
		rewind_list.add_item("decision %d (t%d) %s" % [p, snap.tick, snap.pending_id], p)
	if not points.is_empty():
		rewind_list.select(points.size() - 1)


func _fill_unit() -> void:
	_fill_list(unit_list, session.fight.combatants.map(func(c: Combatant) -> Array:
		return [c.id, "%s %s%s" % ["ally" if c.side == Combatant.Side.PLAYER else "enemy", c.display_name,
			"" if c.is_alive() else " (down)"]]), unit_id)
	var c := session.fight.combatant(unit_id)
	for field: String in unit_editors:
		_set_editor(unit_editors[field], session.unit_field(unit_id, field) if c != null else 0)
	var p: Personality = session.personality(unit_id) if c != null else null
	for field: String in personality_editors:
		_set_editor(personality_editors[field], p.get(field) if p != null else 0.0)
	for child in status_box.get_children():
		child.queue_free()
	if c != null:
		for st in c.statuses:
			var sid := st.status_id
			status_box.add_child(Ui.row([Ui.label("%s x%d" % [sid, st.stacks]),
				Ui.button("Remove", func() -> void: _report(session.remove_status(unit_id, sid)))]))
	force_skill.clear()
	if c != null:
		for s in c.skills():
			force_skill.add_item(s.display_name)
			force_skill.set_item_metadata(force_skill.item_count - 1, s.id)
	force_target.clear()
	for t in session.fight.combatants:
		force_target.add_item(t.display_name)
		force_target.set_item_metadata(force_target.item_count - 1, t.id)
	var forced := session.forced_action(unit_id)
	forced_label.text = "Next: %s" % forced if forced != null else "Next: its own choice"


func _fill_action() -> void:
	_fill_list(action_list, session.action_ids().map(func(id: String) -> Array:
		return [id, session.action(id).display_name]), action_id)
	var a := session.action(action_id)
	if a == null:
		return
	for field: String in action_editors:
		_set_editor(action_editors[field], a.get(field))


func _fill_ai() -> void:
	for key: String in ai_editors:
		var parts := key.split("/")
		_set_editor(ai_editors[key], session.ai_weight(parts[0], parts[1]))


func _fill_changes() -> void:
	var lines := PackedStringArray()
	var shown := session.changes.slice(maxi(0, session.changes.size() - settings.log_lines_shown))
	for ch: DebugChange in shown:
		lines.append(ch.text())
	changes_label.text = "\n".join(lines) if not lines.is_empty() else "No changes yet."
	var data := session.data_changes()
	var wanted := {}
	for ch in data:
		wanted[ch.seq] = true
	for seq: int in save_checks.keys():
		if not wanted.has(seq):
			(save_checks[seq] as CheckBox).queue_free()
			save_checks.erase(seq)
	for ch in data:
		if not save_checks.has(ch.seq):
			var box := CheckBox.new()
			box.button_pressed = true
			# A long change line is cut at the panel's edge; its tooltip has it whole.
			box.clip_text = true
			box.custom_minimum_size.x = 1
			save_box.add_child(box)
			save_checks[ch.seq] = box
		(save_checks[ch.seq] as CheckBox).text = ch.text()
		(save_checks[ch.seq] as CheckBox).tooltip_text = ch.text()


func _checked_seqs() -> Array[int]:
	var out: Array[int] = []
	for seq: int in save_checks:
		if (save_checks[seq] as CheckBox).button_pressed:
			out.append(seq)
	# None checked writes nothing (an empty list would mean "all").
	if out.is_empty():
		out.append(-1)
	return out


## Fills `list` with [id, text] pairs and selects `selected`.
static func _fill_list(list: OptionButton, items: Array, selected: String) -> void:
	list.clear()
	for i in items.size():
		list.add_item(String(items[i][1]))
		list.set_item_metadata(i, items[i][0])
		if items[i][0] == selected:
			list.select(i)


## Writes `value` into an editor, unless the user is typing in it.
static func _set_editor(editor: Control, value: Variant) -> void:
	if editor is SpinBox:
		var spin := editor as SpinBox
		if not spin.get_line_edit().has_focus():
			spin.set_value_no_signal(float(value))
	elif editor is CheckBox:
		(editor as CheckBox).set_pressed_no_signal(bool(value))
	elif editor is LineEdit:
		if not (editor as LineEdit).has_focus():
			(editor as LineEdit).text = str(value)
	elif editor is OptionButton:
		var list := editor as OptionButton
		for i in list.item_count:
			if list.get_item_text(i) == str(value):
				list.select(i)


static func _simulation_text(cmp: PolicyComparison) -> String:
	if not cmp.problems.is_empty():
		return "Cannot simulate:\n" + "\n".join(cmp.problems)
	var lines := PackedStringArray()
	lines.append(cmp.format_text())
	lines.append("")
	lines.append("Action use (share of squad decisions):")
	for r in cmp.rows:
		var parts := PackedStringArray()
		for id in cmp.action_ids():
			parts.append("%s %.0f%%" % [id, r.share_percent(id)])
		lines.append("  %s: %s" % [r.policy, ", ".join(parts)])
	return "\n".join(lines)


# --- Layout ------------------------------------------------------------------

func _build() -> void:
	var outer := VBoxContainer.new()
	outer.add_theme_constant_override("separation", 6)
	add_child(outer)
	outer.add_child(Ui.heading("Battle debugger (%s)" % settings.toggle_key))
	pause_button = Ui.button("Resume", func() -> void: set_paused(not paused))
	outer.add_child(Ui.row([pause_button, Ui.button("Step", step), Ui.button("Back 1", rewind_one),
		Ui.button("Restart", restart)]))
	rewind_list = OptionButton.new()
	rewind_list.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	outer.add_child(Ui.row([rewind_list, Ui.button("Rewind", func() -> void:
		if rewind_list.selected >= 0:
			rewind_to(rewind_list.get_item_id(rewind_list.selected)))]))
	status_label = Ui.label("", Palette.WARNING)
	status_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	outer.add_child(status_label)
	tabs = TabContainer.new()
	tabs.size_flags_vertical = Control.SIZE_EXPAND_FILL
	outer.add_child(tabs)
	tabs.add_child(_scroll("Unit", _build_unit_tab()))
	tabs.add_child(_scroll("Action", _build_action_tab()))
	tabs.add_child(_scroll("AI", _build_ai_tab()))
	tabs.add_child(_scroll("Simulate", _build_simulate_tab()))
	tabs.add_child(_scroll("Changes", _build_changes_tab()))
	save_dialog = ConfirmationDialog.new()
	save_dialog.title = "Save to data"
	save_dialog.ok_button_text = "Write files"
	save_dialog.confirmed.connect(save_checked)
	add_child(save_dialog)


func _scroll(title: String, body: Control) -> ScrollContainer:
	var s := ScrollContainer.new()
	s.name = title
	s.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	body.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	s.add_child(body)
	return s


## `child` in a box that scrolls sideways when it is wider than the panel.
## `label` unwrapped in a monospace font (tables and diffs line up).
static func _mono(label: Label) -> Label:
	label.autowrap_mode = TextServer.AUTOWRAP_OFF
	var font := SystemFont.new()
	font.font_names = PackedStringArray(["DejaVu Sans Mono", "Menlo", "Consolas", "monospace"])
	label.add_theme_font_override("font", font)
	return label


## `label` wrapped to the panel's width.
static func _wrapped(label: Label) -> Label:
	label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	label.custom_minimum_size.x = 1
	return label


static func _hscroll(child: Control) -> ScrollContainer:
	var s := ScrollContainer.new()
	s.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_AUTO
	s.vertical_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	s.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	s.add_child(child)
	return s


func _build_unit_tab() -> VBoxContainer:
	var box := VBoxContainer.new()
	unit_list = OptionButton.new()
	unit_list.item_selected.connect(func(i: int) -> void:
		unit_id = String(unit_list.get_item_metadata(i))
		refresh())
	box.add_child(unit_list)
	var grid := GridContainer.new()
	grid.columns = 4
	box.add_child(grid)
	for field in BattleDebugSession.UNIT_FIELDS:
		var editor: Control
		if field == "staggered":
			var check := CheckBox.new()
			check.toggled.connect(func(on: bool) -> void: edit_unit(field, on))
			editor = check
		else:
			var spin := Ui.spin(INT_MIN, INT_MAX)
			spin.value_changed.connect(func(v: float) -> void: edit_unit(field, int(v)))
			editor = spin
		grid.add_child(Ui.label(field, Palette.TEXT_DIM))
		grid.add_child(editor)
		unit_editors[field] = editor
	box.add_child(Ui.label("Personality", Palette.ACCENT))
	var pgrid := GridContainer.new()
	pgrid.columns = 4
	box.add_child(pgrid)
	for field in BattleDebugSession.PERSONALITY_FIELDS:
		var spin := SpinBox.new()
		spin.min_value = 0
		spin.max_value = 100
		spin.step = 1.0 if field == "generation" else 0.05
		spin.custom_minimum_size.x = 96
		spin.value_changed.connect(func(v: float) -> void: edit_personality(field, v))
		pgrid.add_child(Ui.label(field, Palette.TEXT_DIM))
		pgrid.add_child(spin)
		personality_editors[field] = spin
	box.add_child(Ui.label("Statuses", Palette.ACCENT))
	status_box = VBoxContainer.new()
	box.add_child(status_box)
	status_pick = OptionButton.new()
	for sid in session.tuning.statuses.ids():
		status_pick.add_item(sid)
	box.add_child(Ui.row([status_pick, Ui.button("Apply", func() -> void:
		if status_pick.selected >= 0:
			_report(session.apply_status(unit_id, status_pick.get_item_text(status_pick.selected))))]))
	box.add_child(Ui.label("Timeline and intent", Palette.ACCENT))
	box.add_child(Ui.row([Ui.button("Act now", func() -> void: _report(session.give_turn(unit_id)))]))
	force_skill = OptionButton.new()
	force_target = OptionButton.new()
	box.add_child(Ui.row([force_skill, force_target]))
	forced_label = Ui.label("", Palette.TEXT_DIM)
	box.add_child(Ui.row([Ui.button("Force next", _force_next),
		Ui.button("Clear", func() -> void: session.clear_forced(unit_id)), forced_label]))
	box.add_child(Ui.label("Roster", Palette.ACCENT))
	enemy_pick = OptionButton.new()
	var enemy_ids: Array = session.fight.enemy_table.enemies.keys()
	enemy_ids.sort()
	for id: String in enemy_ids:
		enemy_pick.add_item(id)
	box.add_child(Ui.row([enemy_pick, Ui.button("Add", func() -> void:
		if enemy_pick.selected >= 0:
			_report(session.add_enemy(enemy_pick.get_item_text(enemy_pick.selected))))]))
	box.add_child(Ui.row([Ui.button("Copy unit", func() -> void: _report(session.copy_unit(unit_id))),
		Ui.button("Remove unit", func() -> void: _report(session.remove_unit(unit_id)))]))
	return box


func _force_next() -> void:
	if force_skill.selected < 0 or force_target.selected < 0:
		return
	var skill_id := String(force_skill.get_item_metadata(force_skill.selected))
	var target_id := String(force_target.get_item_metadata(force_target.selected))
	_report(session.force_action(unit_id, FightAction.use(skill_id, target_id)))


func _build_action_tab() -> VBoxContainer:
	var box := VBoxContainer.new()
	action_list = OptionButton.new()
	action_list.item_selected.connect(func(i: int) -> void:
		action_id = String(action_list.get_item_metadata(i))
		refresh())
	box.add_child(action_list)
	var grid := GridContainer.new()
	grid.columns = 2
	box.add_child(grid)
	var sample := CombatSkill.new()
	for field: String in BattleDebugSession.ACTION_FIELDS:
		var editor: Control
		if field == "effect" or field == "target":
			var list := OptionButton.new()
			for option in (CombatSkill.EFFECTS if field == "effect" else CombatSkill.TARGETS):
				list.add_item(option)
			list.item_selected.connect(func(i: int) -> void: edit_action(field, list.get_item_text(i)))
			editor = list
		elif typeof(sample.get(field)) == TYPE_STRING:
			var line := LineEdit.new()
			line.custom_minimum_size.x = 160
			line.text_submitted.connect(func(text: String) -> void: edit_action(field, text))
			line.focus_exited.connect(func() -> void: edit_action(field, line.text))
			editor = line
		else:
			var spin := Ui.spin(0, INT_MAX)
			spin.value_changed.connect(func(v: float) -> void: edit_action(field, int(v)))
			editor = spin
		grid.add_child(Ui.label(field, Palette.TEXT_DIM))
		grid.add_child(editor)
		action_editors[field] = editor
	box.add_child(_wrapped(Ui.label("Applies to every unit holding it, at once. Alt-click a tile to pick it.", Palette.TEXT_DIM)))
	return box


func _build_ai_tab() -> VBoxContainer:
	var box := VBoxContainer.new()
	box.add_child(_wrapped(Ui.label("Intent weights (base, and lean per spectrum)", Palette.TEXT_DIM)))
	var keys := IntentWeights.value_keys()
	var grid := GridContainer.new()
	grid.columns = keys.size() + 1
	box.add_child(grid)
	grid.add_child(Ui.label(""))
	for key in keys:
		grid.add_child(Ui.label(key.get_slice("_", 0), Palette.TEXT_DIM))
	for weight in IntentWeights.NAMES:
		grid.add_child(Ui.label(weight, Palette.TEXT_DIM))
		for key in keys:
			var spin := SpinBox.new()
			spin.min_value = -100
			spin.max_value = 100
			spin.step = 0.05
			spin.custom_minimum_size.x = 64
			spin.value_changed.connect(func(v: float) -> void: edit_ai(weight, key, v))
			grid.add_child(spin)
			ai_editors["%s/%s" % [weight, key]] = spin
	return box


func _build_simulate_tab() -> VBoxContainer:
	var box := VBoxContainer.new()
	sim_runs = Ui.spin(1, 10000, settings.simulate_runs)
	box.add_child(Ui.row([Ui.label("Fights per policy"), sim_runs,
		Ui.button("Simulate %d" % settings.simulate_runs, func() -> void: simulate())]))
	box.add_child(_wrapped(Ui.label("Policies: %s. Fresh fights on the set-up as edited." % ", ".join(
		settings.simulate_policies), Palette.TEXT_DIM)))
	sim_label = _mono(Ui.label("", Palette.TEXT))
	# The harness table is wider than the panel: it scrolls sideways.
	box.add_child(_hscroll(sim_label))
	box.add_child(Ui.label("This fight, live", Palette.ACCENT))
	share_panel = ActionSharePanel.new()
	# Shown in this tab, not toggled by its own key.
	share_panel.toggle_key = KEY_NONE
	box.add_child(_hscroll(share_panel))
	share_panel.fight = session.fight
	return box


func _build_changes_tab() -> VBoxContainer:
	var box := VBoxContainer.new()
	changes_label = Ui.label("", Palette.TEXT)
	changes_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	box.add_child(changes_label)
	box.add_child(Ui.label("Data changes to save", Palette.ACCENT))
	save_box = VBoxContainer.new()
	box.add_child(save_box)
	box.add_child(Ui.row([Ui.button("Save to data...", func() -> void: show_save_diff()),
		Ui.button("Export tuning diff", func() -> void: export_diff())]))
	# Diff lines are whole data-file lines: they scroll sideways, unwrapped.
	diff_label = _mono(Ui.label("", Palette.TEXT_DIM))
	box.add_child(_hscroll(diff_label))
	return box
