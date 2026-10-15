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
##
## A finished run's VIEW shows its run-over screen (RunOverScreen), read-only;
## a run that ends in play leaves its run-over screen back to this menu.
##
## DEMO opens the demo picker (ui/demo/): ready-made scenarios of each act
## that are never saved. A demo leaves back to the picker; the picker's MAIN
## MENU comes back here.

const RUN_SCENE := preload("res://ui/run/run_flow.tscn")
const MENU_WIDTH := 1040.0
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
## A finished run's run-over screen while it shows, else null.
var run_over: RunOverScreen
## The demo picker while it shows, else null.
var demo_picker: DemoPicker
## The demo run while one plays, else null.
var demo_flow: DemoRunFlow
## Set on a demo run before it starts; tests use it.
var configure_demo: Callable
## Shows the one-time What's new card when it is due (tests turn it off).
var show_whats_new := true
var _modal: DetailModal
## Where the demo picker reads scenarios; tests point it elsewhere.
var demo_dir := DemoScenario.DEFAULT_DIR

var menu: Control
var continue_button: Button
var continue_label: Label
## The run to continue as icons and numbers: day, regions held, fights won
## and lost (ui/README.md rule 1). The full line is in continue_label's tooltip.
var continue_icons: HBoxContainer
var load_button: Button
var new_run_button: Button
var demo_button: Button
## The Continue tile (continue_button is the same node).
var continue_tile: EntryTile
var how_to_play_button: Button
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
	if show_whats_new and WhatsNewCard.is_due():
		_open_modal.call_deferred(WhatsNewCard.open.bind(self))
	tree_exiting.connect(func() -> void:
		if _modal != null and is_instance_valid(_modal):
			_modal.close())


func runs_folder() -> String:
	return runs_root if not runs_root.is_empty() else settings.runs_folder


func legacy_path() -> String:
	return legacy_save if not legacy_save.is_empty() else settings.legacy_save


## Brings the buttons and the legacy offer up to date with the runs on disk.
func refresh() -> void:
	var latest := RunFolder.latest_continuable(runs_folder())
	continue_button.disabled = latest.is_empty()
	continue_label.text = "No run to continue." if latest.is_empty() else latest.get_file()
	var summary := {} if latest.is_empty() else _summary_of(latest)
	_fill_run_icons(continue_icons, summary)
	# The tile's art follows the run's act: a city map, then a globe in act 3.
	var art := continue_tile.art as TextureRect
	art.texture = UiIcons.texture("demo_globe" if int(summary.get("act", 1)) >= 3 else "demo_map")
	load_button.disabled = RunFolder.list(runs_folder(), 1).is_empty()
	legacy_panel.visible = RunFolder.legacy_pending(runs_folder(), legacy_path())


## Fills `row` with a run summary as icons: act, day, regions held, fights
## won and lost. Hovering any shows the whole summary line.
static func _fill_run_icons(row: HBoxContainer, summary: Dictionary) -> void:
	for child in row.get_children():
		row.remove_child(child)
		child.queue_free()
	if summary.is_empty():
		return
	var line := RunFolder.describe(summary)
	var items: Array = []
	if str(summary.get("stage", "")) != "draft":
		items.append(["time", "%d" % int(summary.get("day", 1))])
		items.append(["regions", "%d/%d" % [int(summary.get("regions_held", 0)), int(summary.get("regions_total", 0))]])
	items.append(["fights_won", int(summary.get("fights_won", 0))])
	items.append(["fights_lost", int(summary.get("fights_lost", 0))])
	for item: Array in items:
		var stat := IconStat.make(item[0], item[1], line)
		row.add_child(stat)


## Opens the How to play guide.
func show_how_to_play() -> DetailModal:
	_modal = DetailModal.open(self, HowToPlay.spec())
	return _modal


func _open_modal(opener: Callable) -> void:
	if is_inside_tree():
		_modal = opener.call()


## A bot from the squad, standing still, for the New Run tile.
static func _bot_art() -> Control:
	var look := {"unit_id": "ally_frame", "tier": "medium", "look": SpriteManifest.ally_look("ally_frame", 7)}
	var p := UnitPortrait.make(look, false, 96)
	p.name = "Art"
	return p


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
	flow.exit_requested.connect(close_flow)
	for child in [menu, load_list, legacy_panel]:
		child.visible = false
	add_child(flow)


## Closes the run flow and shows the menu again.
func close_flow() -> void:
	if flow != null:
		remove_child(flow)
		flow.queue_free()
		flow = null
	menu.visible = true
	load_list.visible = false
	refresh()
	if MusicDirector.current != null:
		MusicDirector.current.play_context(MusicDirector.MENU)


# --- Demos ---------------------------------------------------------------------------

## Shows the demo picker in place of the menu.
func show_demos() -> void:
	if demo_picker == null:
		demo_picker = DemoPicker.new()
		demo_picker.name = "DemoPicker"
		demo_picker.scenario_dir = demo_dir
		demo_picker.scenario_chosen.connect(open_demo)
		demo_picker.back_requested.connect(hide_demos)
		add_child(demo_picker)
	demo_picker.visible = true
	for child in [menu, load_list, legacy_panel]:
		child.visible = false


## Back from the picker to the menu.
func hide_demos() -> void:
	if demo_picker != null:
		remove_child(demo_picker)
		demo_picker.queue_free()
		demo_picker = null
	menu.visible = true
	refresh()


## Plays `scenario` as a demo run, over the picker.
func open_demo(scenario: DemoScenario) -> void:
	close_demo()
	demo_flow = DemoRunFlow.new()
	demo_flow.name = "DemoRunFlow"
	demo_flow.scenario = scenario
	if configure_demo.is_valid():
		configure_demo.call(demo_flow)
	demo_flow.exit_requested.connect(close_demo)
	if demo_picker != null:
		demo_picker.visible = false
	add_child(demo_flow)


## Ends the demo run and shows the picker again.
func close_demo() -> void:
	if demo_flow == null:
		return
	remove_child(demo_flow)
	demo_flow.queue_free()
	demo_flow = null
	get_tree().paused = false
	show_demos()
	if MusicDirector.current != null:
		MusicDirector.current.play_context(MusicDirector.MENU)


## Shows a finished run's run-over screen, read-only, over the load list.
func view_finished_run(dir: String) -> void:
	run_over = RunOverScreen.new()
	run_over.name = "RunOverScreen"
	run_over.leave_text = "BACK"
	run_over.show_run(dir, _summary_of(dir))
	run_over.main_menu_requested.connect(close_run_over)
	run_over.folder_requested.connect(func() -> void: OS.shell_open(ProjectSettings.globalize_path(dir)))
	add_child(run_over)


func close_run_over() -> void:
	if run_over != null:
		remove_child(run_over)
		run_over.queue_free()
		run_over = null


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
	menu.add_theme_constant_override("separation", UiStyle.space("m"))
	stack.add_child(menu)
	menu.add_child(_label("MECH ENGINEER", "accent", 30, true))
	menu.add_child(_label("A squad of bots against a countdown.", "text_dim", 20, true))
	menu.add_child(_spacer(UiStyle.space("s")))
	# Entry tiles with art (ui/README.md: the homepage starts you off).
	var tiles := UiStyle.row("m")
	tiles.name = "Tiles"
	tiles.alignment = BoxContainer.ALIGNMENT_CENTER
	menu.add_child(tiles)
	continue_tile = EntryTile.make("Continue", "", EntryTile.icon_art("demo_map"))
	continue_tile.pressed.connect(func() -> void: continue_latest())
	continue_button = continue_tile
	continue_button.name = "ContinueButton"
	tiles.add_child(continue_tile)
	continue_label = continue_tile.line_label
	continue_label.name = "ContinueLabel"
	continue_icons = HBoxContainer.new()
	continue_icons.name = "ContinueIcons"
	continue_icons.alignment = BoxContainer.ALIGNMENT_CENTER
	continue_icons.add_theme_constant_override("separation", UiStyle.space("s"))
	continue_tile.extra.add_child(continue_icons)
	var new_tile := EntryTile.make("New Run", "Draft a squad and take the city.", _bot_art())
	new_tile.pressed.connect(start_new_run)
	new_run_button = new_tile
	new_run_button.name = "NewRunButton"
	tiles.add_child(new_tile)
	var demo_tile := EntryTile.make("Demo", "A map, fight or boss of any act.", EntryTile.icon_art("demo_boss"))
	demo_tile.pressed.connect(show_demos)
	UiTooltip.attach(demo_tile, "Demo", "Ready-made moments of each act: maps, fights and bosses. Nothing is saved.", "", "demo_boss")
	demo_button = demo_tile
	demo_button.name = "DemoButton"
	tiles.add_child(demo_tile)
	how_to_play_button = EntryTile.make("How to play", "The run, the map and fights.", EntryTile.icon_art("guide"))
	how_to_play_button.name = "HowToPlayButton"
	how_to_play_button.pressed.connect(show_how_to_play)
	tiles.add_child(how_to_play_button)
	var below := UiStyle.row("m")
	below.alignment = BoxContainer.ALIGNMENT_CENTER
	menu.add_child(below)
	load_button = _button("Load a run", show_load_list)
	load_button.name = "LoadButton"
	below.add_child(load_button)
	var where := _label("Runs are kept in %s" % ProjectSettings.globalize_path(runs_folder()), "text_dim", 20, true)
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
	# A finished run is read-only: VIEW shows its run-over screen.
	var load := _small_button("LOAD" if not finished else "VIEW",
		load_run_folder.bind(summary.dir) if not finished else view_finished_run.bind(summary.dir))
	load.disabled = not finished and not RunFolder.can_continue(summary)
	load.tooltip_text = "This run is over (%s). See how it ended." % ("won" if summary.get("won", false) else "lost") if finished \
		else ("" if not load.disabled else "This run has no save yet.")
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
