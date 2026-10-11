class_name MainMenu
extends Control
## The main menu, the project's first screen: CONTINUE (the latest run that
## is not over), LOAD (every run with a one-line summary) and NEW RUN. Each
## opens the run flow (ui/run/run_flow.tscn) in place of the menu.
##
## Runs live in their own folders (RunFolder). Finished runs, won or lost,
## stay in the load list with their summary but cannot be loaded. The
## single-slot save of earlier versions (user://run.res) is offered once as
## an imported run.

const RUN_SCENE := preload("res://ui/run/run_flow.tscn")
const MENU_WIDTH := 520.0
const BUTTON_SIZE := Vector2(320, 52)
const LIST_SIZE := Vector2(860, 520)
const ROW_BUTTON_SIZE := Vector2(110, 36)

## Where run folders are; "" means data/run/run_data.json's runs_folder.
var runs_root := ""
## The old single-slot save; "" means data/run/run_data.json's legacy_save.
var legacy_save := ""
## Set on the flow before it starts; tests use it to pick seeds and services.
var configure_flow: Callable
var settings := RunDataSettings.load_default()
## The run flow once a run is open, else null.
var flow: RunFlow

var menu: Control
var continue_button: Button
var continue_label: Label
var load_button: Button
var new_run_button: Button
var load_list: Control
## Folder path -> that run's LOAD button in the list.
var load_buttons: Dictionary[String, Button] = {}
var legacy_panel: Control


func _ready() -> void:
	set_anchors_preset(Control.PRESET_FULL_RECT)
	theme = ScreenTheme.theme()
	_build()
	refresh()
	if MusicDirector.current != null:
		MusicDirector.current.play_context(MusicDirector.MENU)


func runs_folder() -> String:
	return runs_root if not runs_root.is_empty() else settings.runs_folder


func legacy_path() -> String:
	return legacy_save if not legacy_save.is_empty() else settings.legacy_save


## Brings the buttons and the legacy offer up to date with the runs on disk.
func refresh() -> void:
	var latest := RunFolder.latest_continuable(runs_folder())
	continue_button.disabled = latest.is_empty()
	continue_label.text = "No run to continue." if latest.is_empty() else (
		"%s\n%s" % [latest.get_file(), RunFolder.describe(_summary_of(latest))])
	load_button.disabled = RunFolder.list(runs_folder(), 1).is_empty()
	legacy_panel.visible = RunFolder.legacy_pending(runs_folder(), legacy_path())


## Starts a new run on the draft.
func start_new_run() -> void:
	_open_flow("")


## Continues the latest run that is not over. False when there is none.
func continue_latest() -> bool:
	var latest := RunFolder.latest_continuable(runs_folder())
	if latest.is_empty():
		return false
	_open_flow(latest)
	return true


## Opens the run in `dir`. False when it cannot be continued.
func load_run_folder(dir: String) -> bool:
	var summary := _summary_of(dir)
	if not RunFolder.can_continue(summary):
		return false
	_open_flow(dir)
	return true


## Copies the old save into a run folder of its own. Returns the folder.
func import_legacy() -> String:
	var dir := RunFolder.import_legacy(runs_folder(), legacy_path())
	if dir.is_empty():
		RunFolder.mark_legacy_offered(runs_folder(), "")
	refresh()
	return dir


func decline_legacy() -> void:
	RunFolder.mark_legacy_offered(runs_folder(), "")
	refresh()


## Shows the list of runs, newest first.
func show_load_list() -> void:
	_fill_load_list()
	menu.visible = false
	load_list.visible = true


func hide_load_list() -> void:
	load_list.visible = false
	menu.visible = true
	refresh()


func _summary_of(dir: String) -> Dictionary:
	var summary := RunFolder.read_summary(dir)
	summary["dir"] = dir
	summary["has_save"] = FileAccess.file_exists(RunFolder.save_path(dir))
	return summary


func _open_flow(dir: String) -> void:
	flow = RUN_SCENE.instantiate()
	flow.name = "RunFlow"
	flow.runs_root = runs_folder()
	flow.start_dir = dir
	if configure_flow.is_valid():
		configure_flow.call(flow)
	for child in [menu, load_list, legacy_panel]:
		child.visible = false
	add_child(flow)


# --- Layout ----------------------------------------------------------------------

func _build() -> void:
	var back := ColorRect.new()
	back.color = FeelData.color("background")
	back.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	add_child(back)
	var center := CenterContainer.new()
	center.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	add_child(center)
	var stack := VBoxContainer.new()
	stack.add_theme_constant_override("separation", 16)
	center.add_child(stack)

	menu = VBoxContainer.new()
	menu.name = "Menu"
	menu.custom_minimum_size = Vector2(MENU_WIDTH, 0)
	menu.add_theme_constant_override("separation", 14)
	stack.add_child(menu)
	menu.add_child(_label("MECH ENGINEER", "accent", 30, true))
	menu.add_child(_label("A squad of bots against a countdown.", "text_dim", 10, true))
	menu.add_child(_spacer(12))
	continue_button = _button("CONTINUE", func() -> void: continue_latest())
	menu.add_child(_centered(continue_button))
	continue_label = _label("", "text_dim", 10, true)
	continue_label.name = "ContinueLabel"
	menu.add_child(continue_label)
	load_button = _button("LOAD", show_load_list)
	menu.add_child(_centered(load_button))
	new_run_button = _button("NEW RUN", start_new_run)
	menu.add_child(_centered(new_run_button))
	menu.add_child(_spacer(12))
	var where := _label("Runs are kept in %s" % ProjectSettings.globalize_path(runs_folder()), "text_dim", 10, true)
	where.name = "RunsFolderLabel"
	menu.add_child(where)

	legacy_panel = _panel()
	legacy_panel.name = "LegacyOffer"
	var legacy_box := VBoxContainer.new()
	legacy_box.add_theme_constant_override("separation", 10)
	legacy_panel.add_child(legacy_box)
	legacy_box.add_child(_label("A save from an earlier version was found. Import it as a run of its own?", "warning", 10, true))
	var legacy_row := HBoxContainer.new()
	legacy_row.alignment = BoxContainer.ALIGNMENT_CENTER
	legacy_row.add_theme_constant_override("separation", 10)
	legacy_box.add_child(legacy_row)
	var import_button := _small_button("IMPORT", func() -> void: import_legacy())
	import_button.name = "ImportButton"
	legacy_row.add_child(import_button)
	var skip_button := _small_button("NO", decline_legacy)
	skip_button.name = "SkipImportButton"
	legacy_row.add_child(skip_button)
	stack.add_child(legacy_panel)

	load_list = _panel()
	load_list.name = "LoadList"
	load_list.custom_minimum_size = LIST_SIZE
	load_list.visible = false
	stack.add_child(load_list)


func _fill_load_list() -> void:
	for child in load_list.get_children():
		child.queue_free()
	load_buttons.clear()
	var box := VBoxContainer.new()
	box.add_theme_constant_override("separation", 10)
	load_list.add_child(box)
	var head := HBoxContainer.new()
	box.add_child(head)
	var title := _label("LOAD A RUN", "accent", 20, false)
	title.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	head.add_child(title)
	var back := _small_button("BACK", hide_load_list)
	back.name = "BackButton"
	head.add_child(back)
	var scroll := ScrollContainer.new()
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	box.add_child(scroll)
	var rows := VBoxContainer.new()
	rows.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	rows.add_theme_constant_override("separation", 8)
	scroll.add_child(rows)
	var runs := RunFolder.list(runs_folder(), settings.load_list_max)
	if runs.is_empty():
		rows.add_child(_label("No runs yet.", "text_dim", 10, false))
	for summary in runs:
		rows.add_child(_run_row(summary))


func _run_row(summary: Dictionary) -> Control:
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 10)
	var text := VBoxContainer.new()
	text.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	row.add_child(text)
	var finished := bool(summary.get("finished", false))
	var name_text := str(summary.get("folder", str(summary.dir).get_file()))
	if not str(summary.get("act_name", "")).is_empty():
		name_text += "  ·  %s" % summary.act_name
	text.add_child(_label(name_text, "text_bright" if not finished else "text_dim", 10, false))
	text.add_child(_label(RunFolder.describe(summary), "text_dim", 10, false))
	var load := _small_button("LOAD" if not finished else ("WON" if summary.get("won", false) else "LOST"),
		load_run_folder.bind(summary.dir))
	load.disabled = not RunFolder.can_continue(summary)
	load.tooltip_text = "" if not load.disabled else ("This run is over." if finished else "This run has no save yet.")
	row.add_child(load)
	load_buttons[summary.dir] = load
	var dir: String = summary.dir
	row.add_child(_small_button("FOLDER", func() -> void: OS.shell_open(ProjectSettings.globalize_path(dir))))
	return row


func _label(text: String, color: String, font_size: int, centered: bool) -> Label:
	var l := Label.new()
	l.text = text
	l.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	if centered:
		l.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	l.add_theme_color_override("font_color", FeelData.color(color))
	l.add_theme_font_size_override("font_size", ScreenTheme.size(font_size))
	return l


func _button(text: String, on_press: Callable) -> Button:
	var b := Button.new()
	b.text = text
	b.name = text.capitalize().replace(" ", "") + "Button"
	b.custom_minimum_size = BUTTON_SIZE
	b.pressed.connect(on_press)
	return b


func _small_button(text: String, on_press: Callable) -> Button:
	var b := Button.new()
	b.text = text
	b.custom_minimum_size = ROW_BUTTON_SIZE
	b.pressed.connect(on_press)
	return b


func _centered(c: Control) -> Control:
	var box := CenterContainer.new()
	box.add_child(c)
	return box


func _spacer(height: float) -> Control:
	var c := Control.new()
	c.custom_minimum_size = Vector2(0, height)
	return c


func _panel() -> PanelContainer:
	var panel := PanelContainer.new()
	var style := StyleBoxFlat.new()
	style.bg_color = FeelData.color("panel")
	style.border_color = FeelData.color("panel_border")
	style.set_border_width_all(2)
	style.set_content_margin_all(16)
	panel.add_theme_stylebox_override("panel", style)
	return panel
