extends Control
## The overworld screen: grid capacity and countdown along the top, the map
## and time bar on the left, the territory panel and event log on the right.
## All rules live in Campaign; this script only shows them and forwards input.
##
## Presentation (M7 P3, timings in data/feel/screens.json): P1's pixel theme;
## regions react to hover and selection (MapView, MapFx); changes to the run
## (captures, energy, material, grid) are held while the map is out of sight
## or under a message, then shown at once as a capture sweep, number popups
## and bars that slide with a trailing ghost (MapChanges); the act zoom plays
## a whoosh, an act title card and a music crossfade (ActMusic); the
## territory panel names the enemy faction when the data has one
## (FactionLookup).

const Palette := preload("res://ui/overworld/palette.gd")
const MapView := preload("res://ui/overworld/map_view.gd")
const GlobeView := preload("res://ui/overworld/globe_view.gd")
const MeterBar := preload("res://ui/overworld/meter_bar.gd")

const SAVE_PATH := "user://overworld.save"
const MAP_SIZE := Vector2(880, 620)
const PANEL_WIDTH := 400.0
const TOP_BAR_HEIGHT := 56.0
const CHOICE_CARD_WIDTH := 290.0
const RESOURCE_LABELS := {MapRegion.POWER: "Grid power", MapRegion.ENERGY: "Energy", MapRegion.MATERIAL: "Material"}

## The acts of a run: each act's region and tuning file, and the zoom between.
@export_file("*.json") var acts_file := "res://data/tuning/acts.json"
## When set, act 1 is played on this region file instead of the acts file's.
@export_file("*.json") var region_file := ""
## When set, act 1 uses this tuning file instead of the acts file's.
@export_file("*.json") var tuning_file := ""
## Dev option: the map variant to play in each act, by act index; "" or a
## missing entry plays the act's default_variant from the acts file.
@export var act_variants: PackedStringArray = []

## The two contracts the map talks to. Swap these for real implementations;
## nothing else on the map changes.
var squad_provider: SquadProvider = StubSquadProvider.new()
var fight_service: FightService = StubFightService.new()

## A host that keeps more of the run than the map (ui/run/ keeps the bots) sets
## these; the SAVE, LOAD and NEW RUN buttons then call them instead of
## save_run(), load_run() and new_run().
var save_action: Callable
var load_action: Callable
var new_run_action: Callable
## Callable(options: Array[StartOption]) -> String. When set, new_run() starts
## on the start it names and offers no choice; when unset the player chooses.
var start_picker: Callable

var campaign: Campaign
var plan: ActPlan
## The map: a MapView, or a GlobeView on a globe act. Replaced when the act's
## projection changes.
var map_view: MapView
## True while the act zoom plays.
var zooming := false
## Where the act zoom starts: [zoom_center, zoom].
var _zoom_from := [Vector2(0.5, 0.5), 1.0]

var _events: PackedStringArray = []
var _hover_wait := false
## The map's music, one loop per act.
var music: ActMusic
## Which enemy faction holds each region, from data/combat/.
var factions := FactionLookup.load_default()
## The run as it looked at the last refresh, and the changes not yet shown.
var _seen := {}
var _unshown: MapChanges
## The act title card the zoom shows.
var _act_title: Control
## The panels dimmed while the act zoom plays.
var _hud: Array[Control] = []
var _popups: Control

var _grid_bar: MeterBar
var _grid_text: Label
var _grid_rate: Label
var _countdown: Label
var _day_line: Label
var _income: HBoxContainer
var _time_day: Label
var _time_bar: MeterBar
var _campaign_bar: MeterBar
var _wait_button: Button
var _panel: VBoxContainer
var _log: VBoxContainer
var _modal: Control
var _modal_card: Control
var _modal_eyebrow: Label
var _modal_title: Label
var _modal_body: Label
var _modal_options: HBoxContainer
var _modal_buttons: HBoxContainer
var _status: Label


func _ready() -> void:
	set_anchors_preset(Control.PRESET_FULL_RECT)
	theme = ScreenTheme.theme()
	music = ActMusic.new()
	music.name = "ActMusic"
	add_child(music)
	_build_layout()
	new_run()


func _process(_delta: float) -> void:
	if _unshown != null and can_show_changes():
		_show_changes(_unshown)
		_unshown = null


## Starts a fresh run on the default start and offers the choice of start.
func new_run() -> void:
	var error := start_new_run()
	if not error.is_empty():
		_show_message("CANNOT LOAD MAP", "The map data did not load", error)
		return
	if start_picker.is_valid():
		var options := campaign.map.start_options()
		if options.size() > 1:
			choose_start(start_picker.call(options))
		return
	show_start_choice()


## Starts a fresh run in act 1 from the start with this id ("" for the first).
## Returns "" or the loading problems, one per line.
func start_new_run(start_id := "") -> String:
	plan = ActPlan.load_file(acts_file)
	if not plan.is_valid():
		return "\n".join(plan.errors)
	for act in mini(act_variants.size(), plan.act_count()):
		if not plan.choose_variant(act, act_variants[act]):
			return "act %d has no map variant '%s'" % [act + 1, act_variants[act]]
	var map := _load_map(0)
	var tuning := _load_tuning(0)
	var problems: Array[String] = map.errors + tuning.errors
	if not problems.is_empty():
		return "\n".join(problems)
	var start := map.get_start(start_id)
	if start == null:
		return "no start '%s' on map '%s'" % [start_id, map.id]
	_events.clear()
	_use_campaign(Campaign.new(map, tuning, squad_provider, fight_service,
		Campaign.new_run_state(map, tuning, start)))
	_event("Day 1. %s is online. Hostile territory surrounds you." % _region_names(campaign.state.owned))
	return ""


## Shows the starting locations of act 1's map to choose from. A map with
## only one start has nothing to choose.
func show_start_choice() -> void:
	var options := campaign.map.start_options()
	if options.size() < 2:
		return
	var cards := []
	for start in options:
		cards.append([start.name, start.description, _start_traits(start), "START HERE", choose_start.bind(start.id)])
	_show_choice("NEW RUN · ACT 1 · %s" % plan.act_name(0).to_upper(), "Choose a starting location",
		"Each start holds different ground and brings its own edge.", cards)


func choose_start(start_id: String) -> void:
	var error := start_new_run(start_id)
	if not error.is_empty():
		_show_message("CANNOT START", "The run did not start", error)


## Moves the run to the next act's map, carrying over what the act plan says.
## Returns "" or the loading problems. The zoom animation is separate.
func advance_act() -> String:
	var next := campaign.state.act + 1
	if not plan.has_next(campaign.state.act):
		return "there is no act %d" % (next + 1)
	var map := _load_map(next)
	var tuning := _load_tuning(next)
	var problems: Array[String] = map.errors + tuning.errors
	if not problems.is_empty():
		return "\n".join(problems)
	var state := plan.zoom_state(campaign.state, map, tuning)
	_events.clear()
	_use_campaign(Campaign.new(map, tuning, squad_provider, fight_service, state))
	_event("Act %d: %s. %s is online. The countdown starts again." % [
		next + 1, plan.act_name(next), _region_names(state.owned)])
	return ""


func save_run(path := SAVE_PATH) -> Error:
	var error := campaign.state.save_file(path)
	_event("Run saved." if error == OK else "Could not save the run (%s)." % error_string(error))
	return error


func load_run(path := SAVE_PATH) -> bool:
	return load_state(RunState.load_file(path))


## Continues the run `state` describes on its act's map. False, with the
## current run kept, if it does not fit the acts file.
func load_state(state: RunState) -> bool:
	if state == null or state.act < 0 or state.act >= plan.act_count():
		_event("No saved run for this map.")
		return false
	# Play on the variant the save was made on. Act 1 on a region_file
	# override has no variant to pick.
	var on_override := state.act == 0 and not region_file.is_empty()
	if not on_override and not plan.choose_variant(state.act, state.region_set_id):
		_event("No saved run for this map.")
		return false
	var map := _load_map(state.act)
	var tuning := _load_tuning(state.act)
	if not map.is_valid() or not tuning.is_valid() or state.region_set_id != map.id:
		_event("No saved run for this map.")
		return false
	_events.clear()
	_use_campaign(Campaign.new(map, tuning, squad_provider, fight_service, state))
	_event("Run loaded. Act %d, day %d." % [state.act + 1, campaign.day()])
	_check_forced()
	return true


## Adds a line to the event log, for a host's own messages.
func log_event(text: String) -> void:
	_event(text)


func _load_map(act: int) -> RegionMap:
	return RegionMap.load_file(region_file) if act == 0 and not region_file.is_empty() else plan.load_map(act)


func _load_tuning(act: int) -> MapTuning:
	return MapTuning.load_file(tuning_file) if act == 0 and not tuning_file.is_empty() else plan.load_tuning(act)


func _region_names(region_ids: PackedStringArray) -> String:
	return ", ".join(Array(region_ids).map(func(id: String) -> String: return campaign.map.get_region(id).name))


func _use_campaign(c: Campaign) -> void:
	campaign = c
	campaign.changed.connect(_refresh)
	campaign.event_logged.connect(_event)
	_use_view_for(campaign.map)
	map_view.campaign = campaign
	map_view.selected_id = ""
	_seen = {}
	_unshown = null
	music.play_act(campaign.state.act)
	_hide_modal()
	_refresh()


## True when the map is on screen with nothing over it, so changes to the run
## can be shown: not hidden behind a fight or readout, a message or the zoom.
func can_show_changes() -> bool:
	return is_visible_in_tree() and not _modal.visible and not zooming


## Changes to the run not shown yet, or null.
func unshown_changes() -> MapChanges:
	return _unshown


## Notes what changed since the last refresh, to show when the map is in view.
func _note_changes() -> void:
	var now := MapChanges.snapshot(campaign.state)
	if _seen.is_empty():
		_seen = now
		_grid_bar.animate_to(campaign.state.grid / campaign.tuning.max_grid, true)
		return
	var changes := MapChanges.between(_seen, now)
	_seen = now
	if changes.is_empty():
		return
	if _unshown == null:
		_unshown = changes
	else:
		_unshown.merge(changes)


## Plays the held changes: captured regions sweep to the owned color, the grid
## bar slides with a trailing ghost, and gains and losses pop as numbers by
## their readouts.
func _show_changes(changes: MapChanges) -> void:
	for id in changes.captured:
		if campaign.map.has_region(id):
			map_view.play_capture(id)
	if not changes.captured.is_empty():
		SoundPlayer.fire(&"map_capture")
	_grid_bar.animate_to(campaign.state.grid / campaign.tuning.max_grid)
	var gained := false
	var spent := false
	for key: String in changes.deltas:
		var delta: float = changes.deltas[key]
		_pop_number(key, roundi(delta))
		gained = gained or delta > 0.0
		spent = spent or delta < 0.0
	if gained and changes.captured.is_empty():
		SoundPlayer.fire(&"resource_gain")
	elif spent and changes.captured.is_empty():
		SoundPlayer.fire(&"resource_loss")


## A popup by a readout: "+3 EN" with the energy bolt, "+2 MAT", "-10% GRID".
## Sign, word and color together, never color alone.
func _pop_number(key: String, amount: int) -> void:
	if amount == 0:
		return
	var anchor: Control = _grid_text if key == "grid" else _income_label(key)
	if anchor == null or not anchor.is_inside_tree():
		return
	var popup := NumberPopup.new()
	popup.setup(amount, "energy" if key == "energy" else "heal")
	if key == "material":
		popup.text = "%+d MAT" % amount
		popup.color = Palette.MATERIAL
		popup.icon = null
	elif key == "grid":
		popup.text = "%+d%% GRID" % amount
		popup.color = Palette.WARNING if amount > 0 else Palette.DANGER
		popup.icon = null
	var offset: Array = ScreenFeel.value("map.popup_offset_px", [0, 0])
	var at := anchor.global_position - _popups.global_position + Vector2(anchor.size.x / 2.0, 0)
	popup.position = at + Vector2(offset[0], offset[1])
	_popups.add_child(popup)


func _income_label(key: String) -> Control:
	for row in _income.get_children():
		if row.has_meta("resource") and row.get_meta("resource") == key:
			return row
	return null


# --- Layout ---------------------------------------------------------------------

func _build_layout() -> void:
	var background := ColorRect.new()
	background.color = Palette.BACKGROUND
	background.set_anchors_preset(Control.PRESET_FULL_RECT)
	background.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(background)

	var column := VBoxContainer.new()
	column.set_anchors_preset(Control.PRESET_FULL_RECT)
	column.add_theme_constant_override("separation", 0)
	add_child(column)
	column.add_child(_build_top_bar())

	var body := HBoxContainer.new()
	body.size_flags_vertical = Control.SIZE_EXPAND_FILL
	body.add_theme_constant_override("separation", 0)
	column.add_child(body)

	var left := VBoxContainer.new()
	left.custom_minimum_size.x = MAP_SIZE.x
	left.add_theme_constant_override("separation", 0)
	body.add_child(left)
	map_view = _new_view(false)
	left.add_child(map_view)
	left.add_child(_build_time_strip())

	body.add_child(_build_side_panel())
	_hud = [column.get_child(0), left.get_child(1), body.get_child(1)]
	_popups = Control.new()
	_popups.name = "Popups"
	_popups.set_anchors_preset(Control.PRESET_FULL_RECT)
	_popups.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_popups)
	_build_act_title()
	_build_modal()


## The act title card the zoom shows over the map: "ACT 2" over the act name.
func _build_act_title() -> void:
	_act_title = _box(Color(Palette.BAR_BACKGROUND, 0.92), Vector4(28, 14, 28, 14), Palette.RULE)
	_act_title.name = "ActTitle"
	_act_title.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_act_title.visible = false
	var rows := _rows(4)
	rows.add_child(_text("", 11, Palette.ACCENT))
	rows.add_child(_text("", 30, Palette.TEXT_BRIGHT))
	for label: Label in rows.get_children():
		label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_act_title.add_child(rows)
	add_child(_act_title)


func _new_view(globe: bool) -> MapView:
	var view: MapView = GlobeView.new() if globe else MapView.new()
	view.name = "GlobeView" if globe else "MapView"
	view.custom_minimum_size = MAP_SIZE
	view.region_selected.connect(func(_id: String) -> void: _refresh())
	if _time_bar != null:
		_time_bar.fx = view.fx
		_grid_bar.fx = view.fx
	return view


## Swaps the map view for a globe or a flat one to suit `map`.
func _use_view_for(map: RegionMap) -> void:
	if (map_view is GlobeView) == map.is_globe():
		return
	var view := _new_view(map.is_globe())
	var parent := map_view.get_parent()
	var index := map_view.get_index()
	parent.remove_child(map_view)
	map_view.queue_free()
	parent.add_child(view)
	parent.move_child(view, index)
	map_view = view


func _build_top_bar() -> Control:
	var bar := _box(Palette.BAR_BACKGROUND, Vector4(24, 0, 24, 0))
	bar.custom_minimum_size.y = TOP_BAR_HEIGHT
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 12)
	bar.add_child(row)

	var grid := HBoxContainer.new()
	grid.add_theme_constant_override("separation", 12)
	grid.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	grid.alignment = BoxContainer.ALIGNMENT_BEGIN
	row.add_child(grid)
	grid.add_child(_text("GRID CAPACITY", 11, Palette.TEXT_DIM))
	_grid_bar = MeterBar.new()
	_grid_bar.custom_minimum_size = Vector2(260, 16)
	_grid_bar.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	_grid_bar.segment_px = 13.0
	grid.add_child(_grid_bar)
	_grid_text = _text("", 14, Palette.WARNING)
	grid.add_child(_grid_text)
	_grid_rate = _text("", 11, Palette.TEXT_DIM)
	grid.add_child(_grid_rate)

	var middle := VBoxContainer.new()
	middle.add_theme_constant_override("separation", 0)
	middle.alignment = BoxContainer.ALIGNMENT_CENTER
	row.add_child(middle)
	_countdown = _text("", 20, Palette.TEXT)
	_countdown.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	middle.add_child(_countdown)
	_day_line = _text("", 11, Palette.TEXT_DIM)
	_day_line.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	middle.add_child(_day_line)

	_income = HBoxContainer.new()
	_income.add_theme_constant_override("separation", 22)
	_income.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_income.alignment = BoxContainer.ALIGNMENT_END
	row.add_child(_income)
	return bar


func _build_time_strip() -> Control:
	var strip := _box(Palette.BAR_BACKGROUND, Vector4(28, 10, 28, 10))
	strip.size_flags_vertical = Control.SIZE_EXPAND_FILL
	var rows := VBoxContainer.new()
	rows.add_theme_constant_override("separation", 10)
	strip.add_child(rows)

	var header := HBoxContainer.new()
	header.add_theme_constant_override("separation", 12)
	rows.add_child(header)
	header.add_child(_text("TIME", 11, Palette.TEXT_DIM))
	_time_day = _text("", 18, Palette.TEXT)
	header.add_child(_time_day)
	_status = _text("", 11, Palette.DEFENSE_TEXT)
	_status.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	header.add_child(_status)
	_wait_button = _button("WAIT", Color("#16283a"), Palette.TEXT, _on_wait)
	_wait_button.mouse_entered.connect(_set_hover_wait.bind(true))
	_wait_button.mouse_exited.connect(_set_hover_wait.bind(false))
	header.add_child(_wait_button)
	header.add_child(_button("SAVE", Palette.BAR_BACKGROUND, Palette.TEXT_DIM, _on_save))
	header.add_child(_button("LOAD", Palette.BAR_BACKGROUND, Palette.TEXT_DIM, _on_load))
	header.add_child(_button("NEW RUN", Palette.BAR_BACKGROUND, Palette.TEXT_DIM, _on_new_run))

	_time_bar = MeterBar.new()
	_time_bar.custom_minimum_size.y = 18
	_time_bar.fill_color = Palette.TIME_FILL
	_time_bar.ghost_color = Palette.TIME_GHOST
	_time_bar.ghost_dark = Palette.TIME_GHOST_DARK
	_time_bar.fx = map_view.fx
	_grid_bar.fx = map_view.fx
	rows.add_child(_time_bar)

	var camp := HBoxContainer.new()
	camp.add_theme_constant_override("separation", 10)
	rows.add_child(camp)
	camp.add_child(_text("CAMPAIGN", 10, Palette.TEXT_DIM))
	_campaign_bar = MeterBar.new()
	_campaign_bar.custom_minimum_size.y = 6
	_campaign_bar.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_campaign_bar.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	_campaign_bar.fill_color = Palette.TIME_FILL
	_campaign_bar.border = Color(0, 0, 0, 0)
	camp.add_child(_campaign_bar)
	camp.add_child(_text("PAYLOAD", 10, Palette.TEXT_DIM))
	return strip


func _build_side_panel() -> Control:
	var side := VBoxContainer.new()
	side.custom_minimum_size.x = PANEL_WIDTH
	side.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	side.add_theme_constant_override("separation", 0)

	var top := _box(Palette.PANEL, Vector4(24, 20, 24, 20))
	top.size_flags_vertical = Control.SIZE_EXPAND_FILL
	side.add_child(top)
	_panel = VBoxContainer.new()
	_panel.add_theme_constant_override("separation", 14)
	top.add_child(_panel)

	var log_box := _box(Palette.BAR_BACKGROUND, Vector4(24, 12, 24, 12))
	log_box.custom_minimum_size.y = 150
	log_box.clip_contents = true
	side.add_child(log_box)
	_log = VBoxContainer.new()
	_log.add_theme_constant_override("separation", 6)
	log_box.add_child(_log)
	return side


func _build_modal() -> void:
	_modal = ColorRect.new()
	_modal.name = "Modal"
	(_modal as ColorRect).color = Color(5 / 255.0, 9 / 255.0, 14 / 255.0, 0.78)
	_modal.set_anchors_preset(Control.PRESET_FULL_RECT)
	_modal.visible = false
	add_child(_modal)
	var center := CenterContainer.new()
	center.set_anchors_preset(Control.PRESET_FULL_RECT)
	_modal.add_child(center)
	var card := _box(Color("#14212f"), Vector4(28, 28, 28, 28), Color("#3a526a"))
	card.custom_minimum_size.x = 480
	center.add_child(card)
	_modal_card = card
	var rows := VBoxContainer.new()
	rows.add_theme_constant_override("separation", 14)
	card.add_child(rows)
	_modal_eyebrow = _text("", 11, Palette.DEFENSE_TEXT)
	rows.add_child(_modal_eyebrow)
	_modal_title = _text("", 28, Palette.TEXT)
	_modal_title.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	rows.add_child(_modal_title)
	_modal_body = _text("", 15, Palette.TEXT_BODY)
	_modal_body.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	rows.add_child(_modal_body)
	_modal_options = HBoxContainer.new()
	_modal_options.add_theme_constant_override("separation", 14)
	rows.add_child(_modal_options)
	_modal_buttons = HBoxContainer.new()
	_modal_buttons.add_theme_constant_override("separation", 10)
	rows.add_child(_modal_buttons)


# --- Refresh ----------------------------------------------------------------------

func _refresh() -> void:
	if campaign == null:
		return
	var t := campaign.tuning
	var s := campaign.state
	var pending := _pending_action()
	var pending_grid := campaign.grid_cost(pending, map_view.selected_id) if pending != Campaign.Action.NONE else 0.0

	var income := campaign.income_per_day()
	_note_changes()
	if _unshown == null or not _unshown.deltas.has("grid"):
		_grid_bar.animate_to(s.grid / t.max_grid)
	var ghost := minf(pending_grid, s.grid)
	_grid_bar.ghost_from = (s.grid - ghost) / t.max_grid
	_grid_bar.ghost_ratio = ghost / t.max_grid
	_grid_text.text = "%d%%" % roundi(s.grid)
	_grid_rate.text = "+%s%%/DAY" % _number(income[MapRegion.POWER] * t.points_per_day / t.grid_regen_divisor)

	_countdown.text = "PAYLOAD IN %d DAYS" % campaign.days_left()
	_day_line.text = "ACT %d · %s · DAY %d / %d · %d OF %d TERRITORIES" % [
		s.act + 1, campaign.map.name.to_upper(), campaign.day(), t.total_points / t.points_per_day,
		s.owned.size(), campaign.map.regions.size()]
	_clear(_income)
	for key in [MapRegion.ENERGY, MapRegion.MATERIAL]:
		var stock: float = s.energy if key == MapRegion.ENERGY else s.material
		_income.add_child(_resource_readout(key, floori(stock), income[key]))

	_time_day.text = "DAY %d" % campaign.day()
	var window := float(t.bar_window_points)
	var now := float(t.bar_history_points) / window
	_time_bar.fill_ratio = now
	_time_bar.ghost_from = now
	_time_bar.ghost_ratio = campaign.time_cost(pending) / window
	var markers := {now: Palette.TEXT_BRIGHT}
	var to_payload := float(t.total_points - s.time_points) / window + now
	if to_payload <= 1.0:
		markers[to_payload] = Palette.DANGER
	_time_bar.markers = markers
	_campaign_bar.fill_ratio = float(s.time_points) / t.total_points

	_wait_button.disabled = not campaign.can_act() or zooming
	_status.text = "FIGHT IN PROGRESS" if campaign.fighting else ""
	map_view.queue_redraw()
	_refresh_panel()
	_refresh_log()


## The action whose cost the bars preview: wait while hovering its button,
## otherwise what the panel offers for the selected region.
func _pending_action() -> Campaign.Action:
	if not campaign.can_act():
		return Campaign.Action.NONE
	if _hover_wait:
		return Campaign.Action.WAIT
	if map_view.selected_id.is_empty():
		return Campaign.Action.NONE
	return campaign.action_for(map_view.selected_id)


func _refresh_panel() -> void:
	_clear(_panel)
	var id := map_view.selected_id
	if id.is_empty() or not campaign.map.has_region(id):
		_panel_intro()
		return
	var region := campaign.map.get_region(id)
	var standing := campaign.standing(id)

	var head := _rows(6)
	head.add_child(_text(region.kind.to_upper(), 11, Palette.TEXT_DIM))
	var name_label := _text(region.name, 30, Palette.TEXT)
	name_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	head.add_child(name_label)
	head.add_child(_pill(standing))
	_panel.add_child(head)

	var provides := _rows(6)
	provides.add_child(_text("PROVIDES", 11, Palette.TEXT_DIM))
	var any := false
	for key in MapRegion.RESOURCE_KEYS:
		if region.provides[key] > 0:
			any = true
			var row := HBoxContainer.new()
			row.add_theme_constant_override("separation", 10)
			row.add_child(_swatch(Palette.resource_color(key), Vector2(10, 10)))
			var label := _text(RESOURCE_LABELS[key], 16, Palette.TEXT)
			label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
			row.add_child(label)
			row.add_child(_text("+%d / day" % region.provides[key], 14, Palette.TEXT))
			provides.add_child(row)
	if not any:
		provides.add_child(_text("Nothing", 16, Palette.TEXT_DIM))
	_panel.add_child(provides)

	if standing == Campaign.Standing.OWNED:
		_panel_pressure(id)
	else:
		_panel_faction(region)
		_panel_defense(region)

	var spacer := Control.new()
	spacer.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_panel.add_child(spacer)

	var actions := _rows(8)
	if standing == Campaign.Standing.OWNED:
		var reinforce := _big_button("REINFORCE", Palette.ACCENT, Palette.ACCENT_TEXT, campaign.can_reinforce(id))
		reinforce.pressed.connect(_on_reinforce.bind(id))
		actions.add_child(reinforce)
		actions.add_child(_note("Lowers pressure here. Costs a little time and grid power."))
	else:
		var attack := _big_button("ATTACK", Palette.ATTACK_BUTTON, Palette.ATTACK_TEXT, campaign.can_attack(id))
		attack.pressed.connect(_on_attack.bind(id))
		actions.add_child(attack)
		if standing == Campaign.Standing.OUT_OF_REACH:
			actions.add_child(_note("Not next to your network. Take a neighbor first."))
		else:
			actions.add_child(_note("Opens the fight. Costs time and grid power, more if the assault fails."))
	_panel.add_child(actions)


func _panel_intro() -> void:
	var rows := _rows(12)
	rows.add_child(_text("NO TERRITORY SELECTED", 11, Palette.TEXT_DIM))
	var title := _text("Pick a territory on the map.", 26, Palette.TEXT)
	title.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	rows.add_child(title)
	rows.add_child(_note("You can only attack territories next to ones you already hold. Rings on your territories show how close each is to an uprising or an attack.", 15))
	for entry: Array in [[Palette.OWNED, "Yours"], [Palette.IN_RANGE, "Hostile, in range to attack"], [Palette.OUT_OF_REACH, "Hostile, out of reach"]]:
		var row := HBoxContainer.new()
		row.add_theme_constant_override("separation", 10)
		row.add_child(_swatch(entry[0], Vector2(16, 12)))
		row.add_child(_text(entry[1], 14, Palette.TEXT))
		rows.add_child(row)
	_panel.add_child(rows)


## The enemy faction holding a hostile region, with its icon or a diamond in
## its color; nothing when the data names none.
func _panel_faction(region: MapRegion) -> void:
	var faction := factions.faction_for(campaign.map.id, campaign.state.act, region.id)
	if faction.is_empty():
		return
	var rows := _rows(6)
	rows.name = "Faction"
	rows.add_child(_text("HELD BY", 11, Palette.TEXT_DIM))
	var line := HBoxContainer.new()
	line.add_theme_constant_override("separation", 10)
	var color: Color = faction["color"] if faction["color"] != null else Palette.DEFENSE
	if faction["icon"] != null:
		var icon := TextureRect.new()
		icon.texture = faction["icon"]
		icon.custom_minimum_size = Vector2(20, 20)
		icon.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
		icon.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
		icon.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
		icon.size_flags_vertical = Control.SIZE_SHRINK_CENTER
		line.add_child(icon)
	else:
		var diamond := _swatch(color, Vector2(10, 10))
		diamond.pivot_offset = Vector2(5, 5)
		diamond.rotation = PI / 4.0
		line.add_child(diamond)
	line.add_child(_text(faction["name"], 16, color))
	rows.add_child(line)
	_panel.add_child(rows)


func _panel_defense(region: MapRegion) -> void:
	var rows := _rows(8)
	rows.add_child(_text("DEFENSE", 11, Palette.TEXT_DIM))
	var line := HBoxContainer.new()
	line.add_theme_constant_override("separation", 12)
	var pips := HBoxContainer.new()
	pips.add_theme_constant_override("separation", 4)
	for i in MapRegion.MAX_DEFENSE:
		pips.add_child(_pip(i < region.defense))
	line.add_child(pips)
	line.add_child(_text(campaign.tuning.defense_label(region.defense).to_upper(), 16, Palette.TEXT))
	rows.add_child(line)
	rows.add_child(_note(campaign.tuning.opposition(region.defense), 14))
	var odds := HBoxContainer.new()
	odds.add_theme_constant_override("separation", 10)
	odds.add_child(_text("YOUR ODDS", 11, Palette.TEXT_DIM))
	var label := campaign.odds_label(region.id)
	odds.add_child(_text(label.to_upper(), 16, _odds_color(label)))
	rows.add_child(odds)
	_panel.add_child(rows)


func _panel_pressure(region_id: String) -> void:
	var t := campaign.tuning
	var pressure := campaign.pressure_of(region_id)
	var rows := _rows(8)
	rows.add_child(_text("PRESSURE", 11, Palette.TEXT_DIM))
	var line := HBoxContainer.new()
	line.add_theme_constant_override("separation", 12)
	var bar := MeterBar.new()
	bar.custom_minimum_size.y = 14
	bar.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	bar.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	bar.fill_ratio = pressure / t.forces_defense_at
	bar.fill_color = Palette.DANGER if pressure >= t.imminent_at else (Palette.WARNING if pressure >= t.ring_warning_at else Palette.ACCENT)
	if _pending_action() == Campaign.Action.REINFORCE:
		var relief := minf(t.reinforce_relief, pressure)
		bar.ghost_from = (pressure - relief) / t.forces_defense_at
		bar.ghost_ratio = relief / t.forces_defense_at
		bar.ghost_color = Palette.ACCENT
		bar.ghost_dark = Palette.OWNED
	line.add_child(bar)
	line.add_child(_text("%d%%" % roundi(pressure), 15, Palette.TEXT))
	rows.add_child(line)
	var attacker := campaign.attacker_of(region_id)
	rows.add_child(_text("Attack building from %s" % attacker.name if attacker != null
		else "Uprising building from within", 16, Palette.TEXT))
	var where := "Border territory, exposed to its neighbors. " if campaign.is_border(region_id) \
		else "Interior territory, shielded by your other holdings. "
	rows.add_child(_note(where + "Pressure is rising %s." % t.rate_word(campaign.pressure_rate(region_id)), 14))
	_panel.add_child(rows)


func _refresh_log() -> void:
	_clear(_log)
	_log.add_child(_text("EVENT LOG", 11, Palette.TEXT_DIM))
	for text in _events:
		var line := _text(text, 13, Color("#c7d6e3"))
		line.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		_log.add_child(line)


func _event(text: String) -> void:
	_events.insert(0, text)
	var keep := campaign.tuning.event_log_length if campaign != null else 5
	if _events.size() > keep:
		_events.resize(keep)
	_refresh_log()


# --- Actions and fights ---------------------------------------------------------

func _on_save() -> void:
	if save_action.is_valid():
		save_action.call()
	else:
		save_run()


func _on_load() -> void:
	if load_action.is_valid():
		load_action.call()
	else:
		load_run()


func _on_new_run() -> void:
	if new_run_action.is_valid():
		new_run_action.call()
	else:
		new_run()


func _on_wait() -> void:
	campaign.wait()
	_check_forced()


func _on_reinforce(region_id: String) -> void:
	campaign.reinforce(region_id)
	_check_forced()


func _on_attack(region_id: String) -> void:
	var region := campaign.map.get_region(region_id)
	var result_holder := []
	var on_finish := func(_request: FightRequest, result: FightResult) -> void: result_holder.append(result)
	campaign.fight_finished.connect(on_finish, CONNECT_ONE_SHOT)
	if not await campaign.attack(region_id):
		if campaign.fight_finished.is_connected(on_finish):
			campaign.fight_finished.disconnect(on_finish)
		return
	var result: FightResult = result_holder[0]
	var charge := campaign.fight_grid_charge(FightRequest.Kind.ATTACK, result)
	if result.is_victory():
		_show_message("ASSAULT · VICTORY", "Captured %s" % region.name,
			"Grid drained by %s%%.%s" % [_number(charge), _rewards_text(result)], _check_forced)
	else:
		_show_message("ASSAULT · DEFEAT", "The assault on %s failed" % region.name,
			"The defenders held. Grid drained by %s%%." % _number(charge), _check_forced)


## Shows whatever the run now demands: the end, or a forced defense.
func _check_forced() -> void:
	if campaign.is_lost():
		_show_end("Your network is gone", "Every territory has fallen. The run ends here.")
		return
	if campaign.is_payload_due():
		# TODO(decision: boss-fight): the boss fight is a stub. The last act's
		# payload brings it and the run ends after it; an earlier payload
		# zooms out to the next act.
		if plan.has_next(campaign.state.act):
			_show_payload_zoom()
		else:
			_show_boss()
		return
	var region_id := campaign.pending_defense()
	if region_id.is_empty():
		return
	var region := campaign.map.get_region(region_id)
	var attacker := campaign.attacker_of(region_id)
	var title := "%s is under attack" % region.name if attacker != null else "%s is in revolt" % region.name
	var body := ("Forces from %s are assaulting it." % attacker.name if attacker != null else "Unrest boiled over.") \
		+ " You must fight to hold it."
	_show_modal("DEFENSIVE BATTLE · FORCED", title, body, [["DEFEND", _on_defend]])


func _on_defend() -> void:
	_hide_modal()
	var region_id := campaign.pending_defense()
	var region := campaign.map.get_region(region_id)
	var result_holder := []
	var on_finish := func(_request: FightRequest, result: FightResult) -> void: result_holder.append(result)
	campaign.fight_finished.connect(on_finish, CONNECT_ONE_SHOT)
	if not await campaign.defend():
		if campaign.fight_finished.is_connected(on_finish):
			campaign.fight_finished.disconnect(on_finish)
		return
	var result: FightResult = result_holder[0]
	if result.is_victory():
		_show_message("DEFENSE · VICTORY", "Held %s" % region.name,
			"The attack was beaten back and pressure eased.%s" % _rewards_text(result), _check_forced)
	else:
		_show_message("DEFENSE · DEFEAT", "Lost %s" % region.name, "It is hostile again.", _check_forced)


func _show_end(title: String, body: String) -> void:
	_show_modal("RUN OVER", title, body, [["NEW RUN", _on_new_run]])


## The last act's payload: the stub boss fight, then the end of the run.
func _show_boss() -> void:
	var body := "The countdown is over and the boss is here. Everything you hold across %s stands behind the squad. " % plan.act_name(campaign.state.act)
	body += "The boss fight is a stand-in for now: a fight at defense level %d." % campaign.tuning.boss_defense_level
	_show_modal("ACT %d · FINAL PAYLOAD" % (campaign.state.act + 1), "The boss arrives", body, [["FIGHT THE BOSS", _on_boss]])


func _on_boss() -> void:
	_hide_modal()
	var result: FightResult = await campaign.boss_fight()
	if result == null:
		return
	if result.is_victory():
		_show_end("The boss falls", "The squad beat the boss. The run is won.")
	else:
		_show_end("The boss holds", "The squad could not break the boss. The run ends here.")


func _show_payload_zoom() -> void:
	var act := campaign.state.act
	var held := campaign.state.owned.size()
	var bonus := plan.bonus_region_count(held)
	var body := "The boss fight is not built yet, so the payload passes. You held %d of %d territories in %s. " % [
		held, campaign.map.regions.size(), plan.act_name(act)]
	body += "The network zooms out to %s: you carry %d energy and %d material, the grid recovers %s%%, and you hold %s%s." % [
		plan.act_name(act + 1), floori(campaign.state.energy * plan.energy_kept),
		floori(campaign.state.material * plan.material_kept), _number(plan.grid_restore), plan.act_name(act),
		"" if bonus == 0 else " plus %d neighboring territor%s" % [bonus, "y" if bonus == 1 else "ies"]]
	_show_modal("ACT %d · PAYLOAD" % (act + 1), "The payload arrives", body, [["ZOOM OUT", zoom_out]])


## Moves to the next act and plays the zoom: the old map shrinks into the
## region it sits in on the new one.
func zoom_out() -> void:
	_hide_modal()
	var old_map := campaign.map
	var old_owned := campaign.state.owned
	var error := advance_act()
	if not error.is_empty():
		_show_message("CANNOT LOAD MAP", "The next act did not load", error)
		return
	# The old map sits where the region file's zoom_inset says, or over the
	# whole focus region when it says nothing.
	var inset := campaign.map.zoom_inset
	if inset.is_empty():
		var focus := campaign.map.get_region(plan.acts[campaign.state.act]["zoom_focus"])
		if focus == null:
			return
		inset = focus.polygon
	if map_view is GlobeView:
		var middle := Vector2.ZERO
		for p in inset:
			middle += p
		map_view.look_at_lonlat(middle / inset.size())
	var rect := map_view.zoom_space_rect(inset)
	if rect.size.x <= 0.0 or rect.size.y <= 0.0:
		return
	map_view.inset_map = old_map
	map_view.inset_owned = old_owned
	map_view.inset_rect = rect
	map_view.inset_alpha = 1.0
	_zoom_from = [rect.get_center(), minf(1.0 / rect.size.x, 1.0 / rect.size.y)]
	_set_zoom_progress(0.0)
	var settings := GameSettings.shared()
	var zoom_s := settings.scale_seconds(plan.zoom_seconds)
	if zoom_s <= 0.0:
		_end_zoom()
		return
	map_view.modulate.a = 0.0
	zooming = true
	_refresh()
	SoundPlayer.fire(&"zoom_whoosh")
	_play_act_title(campaign.state.act, zoom_s)
	var tween := create_tween()
	tween.tween_property(map_view, "modulate:a", 1.0, settings.scale_seconds(plan.fade_seconds))
	tween.tween_method(_set_zoom_progress, 0.0, 1.0, zoom_s).set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_IN_OUT)
	tween.finished.connect(_end_zoom)
	var dim := create_tween().set_parallel()
	for panel in _hud:
		dim.tween_property(panel, "modulate:a", ScreenFeel.number("act_zoom.hud_dim_alpha", 1.0), FeelTween.seconds("ui", settings))


## Shows "ACT n" and the act's name over the map while the camera pulls back:
## it slides in, holds and fades, inside `zoom_s` seconds.
func _play_act_title(act: int, zoom_s: float) -> void:
	var labels := _act_title.get_child(0).get_children()
	labels[0].text = "ACT %d" % (act + 1)
	labels[1].text = plan.act_name(act).to_upper()
	_act_title.visible = true
	_act_title.reset_size()
	var map_rect := map_view.get_global_rect()
	var rest := map_rect.position - global_position + Vector2((map_rect.size.x - _act_title.size.x) / 2.0, map_rect.size.y * 0.12)
	_act_title.position = rest + Vector2(0, -ScreenFeel.number("map.popup_rise_px"))
	_act_title.modulate.a = 0.0
	var title_in := ScreenFeel.seconds("act_zoom.title_in_ms")
	var title_out := ScreenFeel.seconds("act_zoom.title_out_ms")
	var hold := clampf(ScreenFeel.seconds("act_zoom.title_hold_ms"), 0.0, maxf(zoom_s - title_in - title_out, 0.0))
	var tween := create_tween()
	tween.tween_property(_act_title, "modulate:a", 1.0, title_in)
	tween.parallel().tween_property(_act_title, "position", rest, title_in).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
	tween.tween_interval(hold)
	tween.tween_property(_act_title, "modulate:a", 0.0, title_out)
	tween.tween_callback(_act_title.hide)


## Places the act zoom camera `t` of the way from the old map filling the view
## (0) to the whole new map (1). The view's width shrinks at an even rate on a
## log scale, and its middle moves in step with the width, so the zoom is about
## one fixed point and the old map stays put on screen as it shrinks.
func _set_zoom_progress(t: float) -> void:
	var start_center: Vector2 = _zoom_from[0]
	var start_zoom: float = _zoom_from[1]
	var width := exp(lerpf(log(1.0 / start_zoom), 0.0, t))
	var moved := (width - 1.0 / start_zoom) / (1.0 - 1.0 / start_zoom) if start_zoom != 1.0 else 1.0
	map_view.zoom = 1.0 / width
	map_view.zoom_center = start_center.lerp(Vector2(0.5, 0.5), moved)
	map_view.inset_alpha = 1.0 - t * t


func _end_zoom() -> void:
	zooming = false
	map_view.zoom = 1.0
	map_view.zoom_center = Vector2(0.5, 0.5)
	map_view.inset_map = null
	map_view.modulate.a = 1.0
	var undim := create_tween().set_parallel()
	for panel in _hud:
		undim.tween_property(panel, "modulate:a", 1.0, FeelTween.seconds("ui"))
	if FeelTween.seconds("ui") <= 0.0:
		for panel in _hud:
			panel.modulate.a = 1.0
	_refresh()


func _show_message(eyebrow: String, title: String, body: String, then := Callable()) -> void:
	_show_modal(eyebrow, title, body, [["CONTINUE", _close_modal_then.bind(then)]])


func _close_modal_then(then: Callable) -> void:
	_hide_modal()
	if then.is_valid():
		then.call()


func _set_hover_wait(hovering: bool) -> void:
	_hover_wait = hovering
	_refresh()


## buttons: [[label, Callable], ...]
func _show_modal(eyebrow: String, title: String, body: String, buttons: Array) -> void:
	_modal_eyebrow.text = eyebrow
	_modal_title.text = title
	_modal_body.text = body
	_clear(_modal_options)
	_modal_options.visible = false
	_modal_card.custom_minimum_size.x = 480
	_clear(_modal_buttons)
	for entry: Array in buttons:
		var button := _big_button(entry[0], Palette.ACCENT, Palette.ACCENT_TEXT, true)
		button.custom_minimum_size.y = 44
		button.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		button.pressed.connect(entry[1])
		_modal_buttons.add_child(button)
	_modal.visible = true


## cards: [[name, description, [trait lines], button label, Callable], ...],
## shown side by side.
func _show_choice(eyebrow: String, title: String, body: String, cards: Array) -> void:
	_show_modal(eyebrow, title, body, [])
	_modal_options.visible = true
	_modal_card.custom_minimum_size.x = CHOICE_CARD_WIDTH * cards.size() + 14 * (cards.size() - 1) + 56
	for entry: Array in cards:
		var card := _box(Palette.PANEL, Vector4(18, 18, 18, 18), Palette.RULE)
		card.custom_minimum_size.x = CHOICE_CARD_WIDTH
		var rows := _rows(10)
		card.add_child(rows)
		var name_label := _text(entry[0], 20, Palette.TEXT)
		name_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		rows.add_child(name_label)
		rows.add_child(_note(entry[1], 14))
		for line: String in entry[2]:
			var trait_line := _text(line, 13, Palette.ACCENT)
			trait_line.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
			rows.add_child(trait_line)
		var spacer := Control.new()
		spacer.size_flags_vertical = Control.SIZE_EXPAND_FILL
		rows.add_child(spacer)
		var button := _big_button(entry[3], Palette.ACCENT, Palette.ACCENT_TEXT, true)
		button.pressed.connect(entry[4])
		rows.add_child(button)
		_modal_options.add_child(card)


## What a start brings, one line per trait.
func _start_traits(start: StartOption) -> PackedStringArray:
	var lines := PackedStringArray()
	var names := ", ".join(Array(start.regions).map(func(id: String) -> String: return campaign.map.get_region(id).name))
	lines.append(("Holds %d territories: " % start.regions.size() if start.regions.size() > 1 else "Holds ") + names)
	for key in MapRegion.RESOURCE_KEYS:
		if start.income_bonus.get(key, 0) > 0:
			lines.append("+%d %s / day for the whole run" % [start.income_bonus[key], RESOURCE_LABELS[key].to_lower()])
	if start.pressure_rate_factor < 1.0:
		lines.append("Pressure builds %d%% slower on its territories" % roundi((1.0 - start.pressure_rate_factor) * 100.0))
	elif start.pressure_rate_factor > 1.0:
		lines.append("Pressure builds %d%% faster on its territories" % roundi((start.pressure_rate_factor - 1.0) * 100.0))
	if start.energy > 0.0:
		lines.append("+%s energy at the start" % _number(start.energy))
	if start.material > 0.0:
		lines.append("+%s material at the start" % _number(start.material))
	return lines


func _hide_modal() -> void:
	_modal.visible = false


# --- Small builders -------------------------------------------------------------

func _text(text: String, font_size: int, color: Color) -> Label:
	var label := Label.new()
	label.text = text
	label.add_theme_font_size_override("font_size", ScreenTheme.size(font_size))
	label.add_theme_color_override("font_color", color)
	label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	return label


func _note(text: String, font_size := 13) -> Label:
	var label := _text(text, font_size, Palette.TEXT_BODY)
	label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	label.custom_minimum_size.x = 100
	return label


func _rows(separation: int) -> VBoxContainer:
	var rows := VBoxContainer.new()
	rows.add_theme_constant_override("separation", separation)
	return rows


func _box(color: Color, padding: Vector4, border := Color(0, 0, 0, 0)) -> PanelContainer:
	var panel := PanelContainer.new()
	var style := StyleBoxFlat.new()
	style.bg_color = color
	style.content_margin_left = padding.x
	style.content_margin_top = padding.y
	style.content_margin_right = padding.z
	style.content_margin_bottom = padding.w
	if border.a > 0.0:
		style.set_border_width_all(1)
		style.border_color = border
	panel.add_theme_stylebox_override("panel", style)
	return panel


func _swatch(color: Color, swatch_size: Vector2) -> Control:
	var rect := ColorRect.new()
	rect.color = color
	rect.custom_minimum_size = swatch_size
	rect.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	return rect


func _pip(filled: bool) -> Control:
	var pip := Panel.new()
	var style := StyleBoxFlat.new()
	style.bg_color = Palette.DEFENSE if filled else Color(0, 0, 0, 0)
	style.set_border_width_all(2)
	style.border_color = Palette.DEFENSE
	pip.add_theme_stylebox_override("panel", style)
	pip.custom_minimum_size = Vector2(18, 18)
	return pip


func _pill(standing: Campaign.Standing) -> Control:
	var text := "YOURS"
	var fg := Palette.ACCENT_TEXT
	var bg := Palette.ACCENT
	var edge := Palette.ACCENT
	if standing == Campaign.Standing.IN_RANGE:
		text = "HOSTILE · IN RANGE"
		fg = Palette.DEFENSE_TEXT
		bg = Color(0, 0, 0, 0)
		edge = Palette.DEFENSE
	elif standing == Campaign.Standing.OUT_OF_REACH:
		text = "HOSTILE · OUT OF REACH"
		fg = Color("#aab4c2")
		bg = Color(0, 0, 0, 0)
		edge = Color("#5b6678")
	var box := _box(bg, Vector4(10, 4, 10, 4), edge)
	box.size_flags_horizontal = Control.SIZE_SHRINK_BEGIN
	box.add_child(_text(text, 11, fg))
	return box


func _button(text: String, bg: Color, fg: Color, on_press: Callable) -> Button:
	var button := Button.new()
	button.text = text
	button.custom_minimum_size.y = 26
	button.add_theme_font_size_override("font_size", ScreenTheme.size(13))
	_style_button(button, bg, fg, Color("#3a526a"))
	button.pressed.connect(on_press)
	return button


func _big_button(text: String, bg: Color, fg: Color, enabled: bool) -> Button:
	var button := Button.new()
	button.text = text
	button.custom_minimum_size.y = 48
	button.disabled = not enabled
	button.add_theme_font_size_override("font_size", ScreenTheme.size(16))
	_style_button(button, bg if enabled else Palette.DISABLED, fg if enabled else Palette.TEXT_DIM, Color(0, 0, 0, 0))
	return button


func _style_button(button: Button, bg: Color, fg: Color, edge: Color) -> void:
	for state in ["normal", "hover", "pressed", "disabled", "focus"]:
		var style := StyleBoxFlat.new()
		style.bg_color = bg.lightened(0.12) if state == "hover" else bg
		style.content_margin_left = 14
		style.content_margin_right = 14
		if edge.a > 0.0:
			style.set_border_width_all(1)
			style.border_color = edge
		if state == "focus":
			style.bg_color = Color(0, 0, 0, 0)
			style.set_border_width_all(2)
			style.border_color = Palette.TEXT_BRIGHT
		button.add_theme_stylebox_override(state, style)
	for color_name in ["font_color", "font_hover_color", "font_pressed_color", "font_focus_color"]:
		button.add_theme_color_override(color_name, fg)
	button.add_theme_color_override("font_disabled_color", Palette.TEXT_DIM if bg == Palette.DISABLED else fg.darkened(0.4))


func _resource_readout(key: String, stock: int, per_day: int) -> Control:
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 8)
	row.add_child(_swatch(Palette.resource_color(key), Vector2(10, 10)))
	var lines := VBoxContainer.new()
	lines.add_theme_constant_override("separation", 0)
	lines.add_child(_text(str(stock), 20, Palette.TEXT))
	lines.add_child(_text("%s +%d/DAY" % [RESOURCE_LABELS[key].to_upper(), per_day], 10, Palette.TEXT_DIM))
	row.add_child(lines)
	row.set_meta("resource", key)
	return row


func _odds_color(label: String) -> Color:
	var bands := campaign.tuning.odds_bands
	for i in bands.size():
		if bands[i]["label"] == label:
			return Palette.ODDS[mini(i, Palette.ODDS.size() - 1)]
	return Palette.TEXT


func _rewards_text(result: FightResult) -> String:
	if result.rewards.is_empty():
		return ""
	var parts := PackedStringArray()
	for key: String in result.rewards:
		parts.append("%d %s" % [result.rewards[key], key])
	return " Recovered %s." % ", ".join(parts)


static func _number(value: float) -> String:
	return str(roundi(value)) if is_equal_approx(value, roundf(value)) else "%.1f" % value


static func _clear(node: Node) -> void:
	for child in node.get_children():
		node.remove_child(child)
		child.queue_free()
