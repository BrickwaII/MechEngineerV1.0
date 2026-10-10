extends Control
## Robot and enemy builder: create or edit a bot's stats and skills and save it
## through BotSquadStorage (one bot per file, see BotLibrary). Bots and enemies
## are the same kind of data and go to separate folders.

const Ui := preload("res://ui/dev/dev_ui.gd")
const Palette := preload("res://ui/dev/dev_palette.gd")

enum Role { BOT, ENEMY }

## Save folders. Empty means: take them from data/scenarios/_dev_tools.json.
var bot_dir := ""
var enemy_dir := ""
var role := Role.BOT

var tuning: BotTuning
var settings: DevToolSettings

var _role_picker: OptionButton
var _library: ItemList
var _id_edit: LineEdit
var _name_edit: LineEdit
var _hp_spin: SpinBox
var _stat_spins: Dictionary = {}
## Catalog skill name -> [CheckBox, SpinBox level].
var _skill_rows: Dictionary = {}
var _problems: Label
var _status: Label
## The bot being edited; fields not on the form (personality, augment slots)
## are kept from it when saving.
var _editing: Bot


func _ready() -> void:
	settings = DevToolSettings.load_default()
	tuning = BotTuning.load_default()
	bot_dir = bot_dir if not bot_dir.is_empty() else settings.bot_dir
	enemy_dir = enemy_dir if not enemy_dir.is_empty() else settings.enemy_dir
	theme = Ui.theme()
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	Ui.background(self)
	_build()
	new_bot()
	refresh_library()


func current_dir() -> String:
	return enemy_dir if role == Role.ENEMY else bot_dir


func set_role(p_role: Role) -> void:
	role = p_role
	_role_picker.select(role)
	refresh_library()


## A blank bot to start from, with an id not yet used in the current folder.
func new_bot() -> void:
	var prefix := "enemy" if role == Role.ENEMY else "bot"
	var n := BotLibrary.list(current_dir()).size() + 1
	while FileAccess.file_exists(BotLibrary.path_for(current_dir(), "%s_%d" % [prefix, n])):
		n += 1
	show_bot(BotLibrary.new_bot(tuning, "%s_%d" % [prefix, n], "New %s %d" % [prefix, n]))
	_set_status("New bot. Edit it and press Save.")


## Fills the form from `bot`.
func show_bot(bot: Bot) -> void:
	_editing = bot
	_id_edit.text = bot.id
	_name_edit.text = bot.display_name
	for stat in Bot.STAT_NAMES:
		(_stat_spins[stat] as SpinBox).set_value_no_signal(int(bot.stats.get(stat)))
	_hp_spin.max_value = maxi(1, bot.stats.hp)
	_hp_spin.set_value_no_signal(bot.hp)
	for skill_name: String in _skill_rows:
		var held: Skill = null
		for s in bot.skills:
			if s.display_name == skill_name:
				held = s
		var row: Array = _skill_rows[skill_name]
		(row[0] as CheckBox).set_pressed_no_signal(held != null)
		(row[1] as SpinBox).set_value_no_signal(held.level if held != null else tuning.starting_skill_level)
	_update_problems()


## The bot the form describes. Personality and augment slots come from the bot
## that was loaded or created.
func bot_from_form() -> Bot:
	var stats := UnitStats.new()
	for stat in Bot.STAT_NAMES:
		stats.set(stat, int((_stat_spins[stat] as SpinBox).value))
	var skills: Array[Skill] = []
	for skill_name: String in _skill_rows:
		var row: Array = _skill_rows[skill_name]
		if (row[0] as CheckBox).button_pressed:
			var skill: Skill = BotJson.catalog_skill(tuning, skill_name).duplicate()
			skill.level = int((row[1] as SpinBox).value)
			skills.append(skill)
	var personality: Personality = _editing.personality.duplicate() if _editing != null else Personality.new(tuning.starting_generation)
	var slots: Array[AugmentSlot] = []
	if _editing != null:
		for slot in _editing.augment_slots:
			slots.append(slot.duplicate())
	var bot := Bot.new(_id_edit.text.strip_edges(), _name_edit.text.strip_edges(), stats, personality, skills, slots)
	bot.hp = mini(int(_hp_spin.value), stats.hp)
	return bot


## Saves the form's bot into the current folder. Returns OK or the error.
func save() -> Error:
	var bot := bot_from_form()
	var err := BotLibrary.save_bot(bot, current_dir(), tuning)
	if err == OK:
		_editing = bot
		_set_status("Saved %s" % BotLibrary.path_for(current_dir(), bot.id))
		refresh_library()
	else:
		_set_status("Not saved: %s" % ("; ".join(bot.validation_errors()) if not bot.is_valid() else error_string(err)), true)
	return err


## Loads a saved bot into the form. Returns false when the file holds no bot.
func load_file(path: String) -> bool:
	var bot := BotLibrary.load_bot(path)
	if bot == null:
		_set_status("Cannot load %s" % path, true)
		return false
	show_bot(bot)
	_set_status("Loaded %s" % path)
	return true


func refresh_library() -> void:
	_library.clear()
	for path in BotLibrary.list(current_dir()):
		var bot := BotLibrary.load_bot(path)
		var i := _library.add_item("%s  (%s)" % [bot.display_name, bot.id] if bot != null else path.get_file())
		_library.set_item_metadata(i, path)


func _build() -> void:
	var margin := MarginContainer.new()
	margin.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	for side in ["left", "right", "top", "bottom"]:
		margin.add_theme_constant_override("margin_" + side, 20)
	add_child(margin)
	var root := VBoxContainer.new()
	root.add_theme_constant_override("separation", 12)
	margin.add_child(root)
	root.add_child(Ui.heading("Robot and enemy builder"))
	var cols := HBoxContainer.new()
	cols.add_theme_constant_override("separation", 16)
	cols.size_flags_vertical = Control.SIZE_EXPAND_FILL
	root.add_child(cols)

	# Library column.
	var lib_panel := Ui.panel()
	lib_panel.custom_minimum_size.x = 300
	cols.add_child(lib_panel)
	var lib := VBoxContainer.new()
	lib.add_theme_constant_override("separation", 8)
	lib_panel.add_child(lib)
	_role_picker = OptionButton.new()
	_role_picker.add_item("Squad bots", Role.BOT)
	_role_picker.add_item("Enemies", Role.ENEMY)
	_role_picker.item_selected.connect(func(i: int) -> void:
		set_role(i as Role)
		new_bot())
	lib.add_child(Ui.row([Ui.label("Library"), _role_picker]))
	_library = ItemList.new()
	_library.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_library.item_activated.connect(func(i: int) -> void: load_file(_library.get_item_metadata(i)))
	_library.item_selected.connect(func(i: int) -> void: load_file(_library.get_item_metadata(i)))
	lib.add_child(_library)
	lib.add_child(Ui.button("New bot", new_bot))

	# Form column.
	var form_panel := Ui.panel()
	form_panel.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	cols.add_child(form_panel)
	var form := VBoxContainer.new()
	form.add_theme_constant_override("separation", 10)
	form_panel.add_child(form)
	var ident := GridContainer.new()
	ident.columns = 2
	ident.add_theme_constant_override("h_separation", 12)
	_id_edit = LineEdit.new()
	_id_edit.custom_minimum_size.x = 260
	_name_edit = LineEdit.new()
	_id_edit.text_changed.connect(func(_t: String) -> void: _update_problems())
	_name_edit.text_changed.connect(func(_t: String) -> void: _update_problems())
	ident.add_child(Ui.label("Id"))
	ident.add_child(_id_edit)
	ident.add_child(Ui.label("Name"))
	ident.add_child(_name_edit)
	form.add_child(ident)

	form.add_child(Ui.label("Stats", Palette.TEXT_DIM))
	var stats := GridContainer.new()
	stats.columns = 4
	stats.add_theme_constant_override("h_separation", 12)
	for stat in Bot.STAT_NAMES:
		var range_text := "%d–%d" % [tuning.stat_ranges[stat].x, tuning.stat_ranges[stat].y]
		stats.add_child(Ui.label("%s  (%s)" % [stat.capitalize(), range_text]))
		var s := Ui.spin(0, settings.builder_max_stat)
		s.value_changed.connect(func(_v: float) -> void: _on_stat_changed())
		_stat_spins[stat] = s
		stats.add_child(s)
	stats.add_child(Ui.label("Current HP"))
	_hp_spin = Ui.spin(0, settings.builder_max_stat)
	_hp_spin.value_changed.connect(func(_v: float) -> void: _update_problems())
	stats.add_child(_hp_spin)
	form.add_child(stats)

	form.add_child(Ui.label("Skills (level)", Palette.TEXT_DIM))
	var skills := GridContainer.new()
	skills.columns = 4
	skills.add_theme_constant_override("h_separation", 12)
	for template in tuning.skills:
		var check := CheckBox.new()
		check.text = "%s  (%s, %d energy)" % [template.display_name, template.effect_id, template.energy_cost]
		check.toggled.connect(func(_on: bool) -> void: _update_problems())
		var level := Ui.spin(Skill.MIN_LEVEL, settings.builder_max_skill_level, tuning.starting_skill_level)
		_skill_rows[template.display_name] = [check, level]
		skills.add_child(check)
		skills.add_child(level)
	form.add_child(skills)

	_problems = Ui.label("", Palette.WARNING, 13)
	_problems.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	form.add_child(_problems)
	form.add_child(Ui.row([Ui.button("Save", func() -> void: save())]))
	_status = Ui.label("", Palette.TEXT_DIM, 13)
	root.add_child(_status)


func _on_stat_changed() -> void:
	var max_hp := int((_stat_spins["hp"] as SpinBox).value)
	var follow := int(_hp_spin.value) == int(_hp_spin.max_value)
	_hp_spin.max_value = maxi(1, max_hp)
	if follow:
		_hp_spin.set_value_no_signal(max_hp)
	_update_problems()


## Errors block saving; range warnings only say the bot is outside the tuning.
func _update_problems() -> void:
	var bot := bot_from_form()
	var errors := bot.validation_errors()
	var warnings := PackedStringArray()
	for problem in tuning.validation_errors_for(bot):
		if not problem in errors:
			warnings.append(problem)
	var lines := PackedStringArray()
	for e in errors:
		lines.append("Cannot save: " + e)
	for w in warnings:
		lines.append("Outside the draft tuning (saves anyway): " + w)
	_problems.text = "\n".join(lines) if not lines.is_empty() else "Valid, within the draft tuning."
	_problems.add_theme_color_override("font_color", Palette.WARNING if not lines.is_empty() else Palette.ACCENT)


func _set_status(text: String, is_error := false) -> void:
	_status.text = text
	_status.add_theme_color_override("font_color", Palette.ENEMY if is_error else Palette.TEXT_DIM)
