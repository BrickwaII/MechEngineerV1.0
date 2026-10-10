extends Control
## The overworld screen: grid capacity and countdown along the top, the map
## and time bar on the left, the territory panel and event log on the right.
## All rules live in Campaign; this script only shows them and forwards input.

const Palette := preload("res://ui/overworld/palette.gd")
const MapView := preload("res://ui/overworld/map_view.gd")
const MeterBar := preload("res://ui/overworld/meter_bar.gd")

const SAVE_PATH := "user://overworld.save"
const MAP_SIZE := Vector2(880, 620)
const PANEL_WIDTH := 400.0
const TOP_BAR_HEIGHT := 56.0
const RESOURCE_LABELS := {MapRegion.POWER: "Grid power", MapRegion.ENERGY: "Energy", MapRegion.MATERIAL: "Material"}

@export_file("*.json") var region_file := "res://data/regions/act1_placeholder.json"
@export_file("*.json") var tuning_file := "res://data/tuning/overworld.json"

## The two contracts the map talks to. Swap these for real implementations;
## nothing else on the map changes.
var squad_provider: SquadProvider = StubSquadProvider.new()
var fight_service: FightService = StubFightService.new()

var campaign: Campaign
var map_view: MapView

var _events: PackedStringArray = []
var _hover_wait := false

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
var _modal_eyebrow: Label
var _modal_title: Label
var _modal_body: Label
var _modal_buttons: HBoxContainer
var _status: Label


func _ready() -> void:
	set_anchors_preset(Control.PRESET_FULL_RECT)
	_build_layout()
	var error := start_new_run()
	if not error.is_empty():
		_show_message("CANNOT LOAD MAP", "The map data did not load", error)


## Starts a fresh run from the region and tuning files. Returns "" or the
## loading problems, one per line.
func start_new_run() -> String:
	var map := RegionMap.load_file(region_file)
	var tuning := MapTuning.load_file(tuning_file)
	var problems: Array[String] = map.errors + tuning.errors
	if not problems.is_empty():
		return "\n".join(problems)
	_events.clear()
	_use_campaign(Campaign.new(map, tuning, squad_provider, fight_service))
	_event("Day 1. %s is online. Hostile territory surrounds you." %
		", ".join(Array(map.starting_ids()).map(func(id: String) -> String: return map.get_region(id).name)))
	return ""


func save_run(path := SAVE_PATH) -> Error:
	var error := campaign.state.save_file(path)
	_event("Run saved." if error == OK else "Could not save the run (%s)." % error_string(error))
	return error


func load_run(path := SAVE_PATH) -> bool:
	var state := RunState.load_file(path)
	if state == null or state.region_set_id != campaign.map.id:
		_event("No saved run for this map.")
		return false
	_events.clear()
	_use_campaign(Campaign.new(campaign.map, campaign.tuning, squad_provider, fight_service, state))
	_event("Run loaded. Day %d." % campaign.day())
	_check_forced()
	return true


func _use_campaign(c: Campaign) -> void:
	campaign = c
	campaign.changed.connect(_refresh)
	campaign.event_logged.connect(_event)
	map_view.campaign = campaign
	map_view.selected_id = ""
	_hide_modal()
	_refresh()


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
	map_view = MapView.new()
	map_view.custom_minimum_size = MAP_SIZE
	map_view.region_selected.connect(func(_id: String) -> void: _refresh())
	left.add_child(map_view)
	left.add_child(_build_time_strip())

	body.add_child(_build_side_panel())
	_build_modal()


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
	header.add_child(_button("SAVE", Palette.BAR_BACKGROUND, Palette.TEXT_DIM, func() -> void: save_run()))
	header.add_child(_button("LOAD", Palette.BAR_BACKGROUND, Palette.TEXT_DIM, func() -> void: load_run()))
	header.add_child(_button("NEW RUN", Palette.BAR_BACKGROUND, Palette.TEXT_DIM, func() -> void: start_new_run()))

	_time_bar = MeterBar.new()
	_time_bar.custom_minimum_size.y = 18
	_time_bar.fill_color = Palette.TIME_FILL
	_time_bar.ghost_color = Palette.TIME_GHOST
	_time_bar.ghost_dark = Palette.TIME_GHOST_DARK
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
	_grid_bar.fill_ratio = s.grid / t.max_grid
	var ghost := minf(pending_grid, s.grid)
	_grid_bar.ghost_from = (s.grid - ghost) / t.max_grid
	_grid_bar.ghost_ratio = ghost / t.max_grid
	_grid_text.text = "%d%%" % roundi(s.grid)
	_grid_rate.text = "+%s%%/DAY" % _number(income[MapRegion.POWER] * t.points_per_day / t.grid_regen_divisor)

	_countdown.text = "PAYLOAD IN %d DAYS" % campaign.days_left()
	_day_line.text = "DAY %d / %d · %d OF %d TERRITORIES" % [
		campaign.day(), t.total_points / t.points_per_day, s.owned.size(), campaign.map.regions.size()]
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

	_wait_button.disabled = not campaign.can_act()
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
		# TODO(decision: boss-fight): the boss fight is a stub; the run stops here.
		_show_end("The payload arrives", "The countdown reached zero and the boss fight begins with whatever you have prepared. The boss fight is not built yet.")
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
	_show_modal("RUN OVER", title, body, [["NEW RUN", func() -> void: start_new_run()]])


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
	_clear(_modal_buttons)
	for entry: Array in buttons:
		var button := _big_button(entry[0], Palette.ACCENT, Palette.ACCENT_TEXT, true)
		button.custom_minimum_size.y = 44
		button.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		button.pressed.connect(entry[1])
		_modal_buttons.add_child(button)
	_modal.visible = true


func _hide_modal() -> void:
	_modal.visible = false


# --- Small builders -------------------------------------------------------------

func _text(text: String, font_size: int, color: Color) -> Label:
	var label := Label.new()
	label.text = text
	label.add_theme_font_size_override("font_size", font_size)
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
	button.add_theme_font_size_override("font_size", 13)
	_style_button(button, bg, fg, Color("#3a526a"))
	button.pressed.connect(on_press)
	return button


func _big_button(text: String, bg: Color, fg: Color, enabled: bool) -> Button:
	var button := Button.new()
	button.text = text
	button.custom_minimum_size.y = 48
	button.disabled = not enabled
	button.add_theme_font_size_override("font_size", 16)
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
	lines.add_child(_text(str(stock), 14, Palette.TEXT))
	lines.add_child(_text("%s +%d/DAY" % [RESOURCE_LABELS[key].to_upper(), per_day], 10, Palette.TEXT_DIM))
	row.add_child(lines)
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
