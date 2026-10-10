extends Control
## Scenario builder: pick saved bots and enemies, set the defense level and
## policies, save the scenario as JSON, and run it headless with the batch
## simulator from this screen.

const Ui := preload("res://ui/dev/dev_ui.gd")
const Palette := preload("res://ui/dev/dev_palette.gd")

## Folders. Empty means: take them from data/scenarios/_dev_tools.json.
var bot_dir := ""
var enemy_dir := ""
var scenario_dir := ""
## Stats log for runs started here; "" with log_runs off writes nothing.
var log_path := ""

var settings: DevToolSettings
var enemy_table: EnemyTable

var _scenario_picker: OptionButton
var _name_edit: LineEdit
var _kind_picker: OptionButton
var _level_spin: SpinBox
var _player_policy: OptionButton
var _enemy_policy: OptionButton
var _squad_source: OptionButton
var _squad_list: ItemList
var _draft_seed: SpinBox
var _enemy_source: OptionButton
var _enemy_list: ItemList
var _runs_spin: SpinBox
var _seed_spin: SpinBox
var _log_check: CheckBox
var _output: TextEdit
var _status: Label
## Entries in the squad and enemy lists, as scenario-file dictionaries.
var _squad_entries: Array = []
var _enemy_entries: Array = []


func _ready() -> void:
	settings = DevToolSettings.load_default()
	enemy_table = EnemyTable.load_default()
	bot_dir = bot_dir if not bot_dir.is_empty() else settings.bot_dir
	enemy_dir = enemy_dir if not enemy_dir.is_empty() else settings.enemy_dir
	scenario_dir = scenario_dir if not scenario_dir.is_empty() else settings.scenario_dir
	log_path = log_path if not log_path.is_empty() else settings.stats_log_path
	theme = Ui.theme()
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	Ui.background(self)
	_build()
	refresh_sources()
	_show_entries()


## Re-reads the saved bots, enemies and scenarios into the pickers.
func refresh_sources() -> void:
	_fill_sources(_squad_source, [bot_dir, enemy_dir], false)
	_fill_sources(_enemy_source, [enemy_dir, bot_dir], true)
	_scenario_picker.clear()
	_scenario_picker.add_item("Load a scenario…")
	_scenario_picker.set_item_metadata(0, "")
	for path in ScenarioFiles.list(["res://data/scenarios", scenario_dir]):
		_scenario_picker.add_item(path.trim_prefix("res://data/").trim_prefix("user://"))
		_scenario_picker.set_item_metadata(_scenario_picker.item_count - 1, path)


func add_squad_entry(entry: Dictionary) -> void:
	_squad_entries.append(entry)
	_show_entries()


func add_enemy_entry(entry: Variant) -> void:
	_enemy_entries.append(entry)
	_show_entries()


func clear_entries() -> void:
	_squad_entries.clear()
	_enemy_entries.clear()
	_show_entries()


## The scenario the form describes.
func scenario_from_form() -> FightScenario:
	var s := FightScenario.new()
	s.scenario_name = _name_edit.text.strip_edges()
	s.kind = _kind_picker.selected as FightRequest.Kind
	s.defense_level = int(_level_spin.value)
	s.squad_entries = _squad_entries.duplicate(true)
	s.enemy_entries = _enemy_entries.duplicate(true)
	s.player_policy = FightScenario.POLICIES[_player_policy.selected]
	s.enemy_policy = FightScenario.POLICIES[_enemy_policy.selected]
	return s


func show_scenario(s: FightScenario) -> void:
	_name_edit.text = s.scenario_name
	_kind_picker.select(s.kind)
	_level_spin.set_value_no_signal(s.defense_level)
	_player_policy.select(maxi(0, FightScenario.POLICIES.find(s.player_policy)))
	_enemy_policy.select(maxi(0, FightScenario.POLICIES.find(s.enemy_policy)))
	_squad_entries = s.squad_entries.duplicate(true)
	_enemy_entries = s.enemy_entries.duplicate(true)
	_show_entries()


## Saves to scenario_dir/<name>.json. Returns the path, or "" when not saved.
func save() -> String:
	var s := scenario_from_form()
	var problems := s.resolve().problems
	if not problems.is_empty():
		_set_status("Not saved: " + "; ".join(problems), true)
		return ""
	var path := ScenarioFiles.path_for(scenario_dir, s.scenario_name)
	var err := ScenarioFiles.save_scenario(s, path)
	if err != OK:
		_set_status("Not saved: %s" % error_string(err), true)
		return ""
	_set_status("Saved %s" % path)
	refresh_sources()
	return path


func load_file(path: String) -> bool:
	var s := ScenarioFiles.load_scenario(path)
	if s == null:
		_set_status("Cannot read %s" % path, true)
		return false
	show_scenario(s)
	_set_status("Loaded %s" % path)
	return true


## Runs the form's scenario with the batch simulator and shows the report.
func run_batch() -> BatchReport:
	var report := BatchSimulator.run(
		scenario_from_form(), int(_runs_spin.value), int(_seed_spin.value), log_path if _log_check.button_pressed else "")
	_output.text = report.format_text()
	if report.problems.is_empty():
		_set_status("Ran %d fights%s" % [report.runs, (", logged to " + log_path) if _log_check.button_pressed else ""])
	else:
		_set_status("Cannot run, see the report", true)
	return report


func set_run_options(runs: int, base_seed: int, write_log: bool) -> void:
	_runs_spin.set_value_no_signal(runs)
	_seed_spin.set_value_no_signal(base_seed)
	_log_check.set_pressed_no_signal(write_log)


func report_text() -> String:
	return _output.text


func _build() -> void:
	var margin := MarginContainer.new()
	margin.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	for side in ["left", "right", "top", "bottom"]:
		margin.add_theme_constant_override("margin_" + side, 20)
	add_child(margin)
	var root := VBoxContainer.new()
	root.add_theme_constant_override("separation", 12)
	margin.add_child(root)
	_scenario_picker = OptionButton.new()
	_scenario_picker.item_selected.connect(func(i: int) -> void:
		var path: String = _scenario_picker.get_item_metadata(i)
		if not path.is_empty():
			load_file(path))
	root.add_child(Ui.row([Ui.heading("Scenario builder"), Control.new(), _scenario_picker,
		Ui.button("Refresh lists", refresh_sources)]))

	var cols := HBoxContainer.new()
	cols.add_theme_constant_override("separation", 16)
	cols.size_flags_vertical = Control.SIZE_EXPAND_FILL
	root.add_child(cols)

	# Setup column.
	var setup_panel := Ui.panel()
	setup_panel.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	cols.add_child(setup_panel)
	var setup := VBoxContainer.new()
	setup.add_theme_constant_override("separation", 8)
	setup_panel.add_child(setup)
	var grid := GridContainer.new()
	grid.columns = 4
	grid.add_theme_constant_override("h_separation", 12)
	_name_edit = LineEdit.new()
	_name_edit.text = "New scenario"
	_name_edit.custom_minimum_size.x = 220
	_kind_picker = OptionButton.new()
	for k in FightScenario.KINDS:
		_kind_picker.add_item(k.capitalize())
	_level_spin = Ui.spin(FightRequest.MIN_DEFENSE_LEVEL, FightRequest.MAX_DEFENSE_LEVEL, 1)
	_player_policy = _policy_picker()
	_enemy_policy = _policy_picker()
	for pair in [["Name", _name_edit], ["Kind", _kind_picker], ["Defense level", _level_spin],
			["Squad policy", _player_policy], ["Enemy policy", _enemy_policy]]:
		grid.add_child(Ui.label(pair[0]))
		grid.add_child(pair[1])
	setup.add_child(grid)

	setup.add_child(Ui.label("Squad", Palette.TEXT_DIM))
	_squad_source = OptionButton.new()
	_squad_source.custom_minimum_size.x = 260
	_draft_seed = Ui.spin(0, 999999, 2024)
	setup.add_child(Ui.row([_squad_source, Ui.button("Add bot", _add_picked_squad_bot),
		Ui.label("or draft seed"), _draft_seed, Ui.button("Add draft", func() -> void:
			add_squad_entry({"draft_seed": int(_draft_seed.value)}))]))
	_squad_list = ItemList.new()
	_squad_list.custom_minimum_size.y = 110
	setup.add_child(_squad_list)
	setup.add_child(Ui.button("Remove selected squad entry", func() -> void: _remove_selected(_squad_list, _squad_entries)))

	setup.add_child(Ui.label("Enemies (empty list: drawn from the enemy table for the defense level, per seed)", Palette.TEXT_DIM))
	_enemy_source = OptionButton.new()
	_enemy_source.custom_minimum_size.x = 260
	setup.add_child(Ui.row([_enemy_source, Ui.button("Add enemy", _add_picked_enemy)]))
	_enemy_list = ItemList.new()
	_enemy_list.custom_minimum_size.y = 110
	setup.add_child(_enemy_list)
	setup.add_child(Ui.row([Ui.button("Remove selected enemy", func() -> void: _remove_selected(_enemy_list, _enemy_entries)),
		Ui.button("Save scenario", func() -> void: save())]))

	# Run column.
	var run_panel := Ui.panel()
	run_panel.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	cols.add_child(run_panel)
	var run := VBoxContainer.new()
	run.add_theme_constant_override("separation", 8)
	run_panel.add_child(run)
	_runs_spin = Ui.spin(1, 100000, settings.default_runs)
	_seed_spin = Ui.spin(0, 2147483647, settings.default_base_seed)
	_log_check = CheckBox.new()
	_log_check.text = "Append to stats log"
	_log_check.button_pressed = true
	run.add_child(Ui.row([Ui.label("Runs"), _runs_spin, Ui.label("First seed"), _seed_spin]))
	run.add_child(Ui.row([_log_check, Ui.button("Run batch", func() -> void: run_batch())]))
	_output = TextEdit.new()
	_output.editable = false
	_output.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_output.custom_minimum_size = Vector2(520, 300)
	_output.add_theme_font_size_override("font_size", 12)
	var mono := SystemFont.new()
	mono.font_names = PackedStringArray(["DejaVu Sans Mono", "Menlo", "Consolas", "monospace"])
	_output.add_theme_font_override("font", mono)
	run.add_child(_output)

	_status = Ui.label("", Palette.TEXT_DIM, 13)
	root.add_child(_status)


func _policy_picker() -> OptionButton:
	var o := OptionButton.new()
	for p in FightScenario.POLICIES:
		o.add_item(p.capitalize())
	return o


## Fills `picker` with saved bot files (as squad_file entries) and, for enemies,
## the enemy table's ids first.
func _fill_sources(picker: OptionButton, dirs: Array, with_table: bool) -> void:
	picker.clear()
	if with_table:
		var ids := enemy_table.enemies.keys()
		ids.sort()
		for id: String in ids:
			picker.add_item("Enemy table: %s" % enemy_table.name_of(id))
			picker.set_item_metadata(picker.item_count - 1, id)
	for dir: String in dirs:
		var kind := "enemy" if dir == enemy_dir else "bot"
		for path in BotLibrary.list(dir):
			var bot := BotLibrary.load_bot(path)
			if bot == null:
				continue
			picker.add_item("Saved %s: %s (%s)" % [kind, bot.display_name, bot.id])
			picker.set_item_metadata(picker.item_count - 1, {"squad_file": path})


func _add_picked_squad_bot() -> void:
	if _squad_source.selected >= 0:
		add_squad_entry((_squad_source.get_item_metadata(_squad_source.selected) as Dictionary).duplicate())


func _add_picked_enemy() -> void:
	if _enemy_source.selected < 0:
		return
	var meta: Variant = _enemy_source.get_item_metadata(_enemy_source.selected)
	add_enemy_entry(meta.duplicate() if meta is Dictionary else meta)


func _remove_selected(list: ItemList, entries: Array) -> void:
	for i in list.get_selected_items():
		entries.remove_at(i)
	_show_entries()


func _show_entries() -> void:
	_squad_list.clear()
	for e: Variant in _squad_entries:
		_squad_list.add_item(_describe(e))
	_enemy_list.clear()
	for e: Variant in _enemy_entries:
		_enemy_list.add_item(_describe(e))
	if _enemy_entries.is_empty():
		_enemy_list.add_item("(drawn from the enemy table)")
		_enemy_list.set_item_selectable(0, false)
		_enemy_list.set_item_custom_fg_color(0, Palette.TEXT_DIM)


func _describe(e: Variant) -> String:
	if e is String:
		return "%s  (enemy table)" % (enemy_table.name_of(e) if enemy_table.enemies.has(e) else e)
	if e is Dictionary:
		if e.has("enemy"):
			return "%s × %d  (enemy table)" % [enemy_table.name_of(e.enemy) if enemy_table.enemies.has(e.enemy) else e.enemy, int(e.get("count", 1))]
		if e.has("draft_seed"):
			return "Fielded bots of draft seed %d" % int(e.draft_seed)
		if e.has("bot"):
			return "%s (%s)  (inline bot)" % [e.bot.get("name", "?"), e.bot.get("id", "?")]
		if e.has("squad_file"):
			var bot := BotLibrary.load_bot(e.squad_file)
			var who := "%s (%s)" % [bot.display_name, bot.id] if bot != null else "missing file"
			return "%s  %s" % [who, e.squad_file]
	return str(e)


func _set_status(text: String, is_error := false) -> void:
	_status.text = text
	_status.add_theme_color_override("font_color", Palette.ENEMY if is_error else Palette.TEXT_DIM)
