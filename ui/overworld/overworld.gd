extends Control
## The overworld screen: the top bar (payload countdown, losses, Energy,
## Material, a compact grid meter with Repair, Home), the map strip (lens:
## Defense / Pressure / Resources / Odds, and "?" for the legend), the map
## with one lens pin per region and a hover card, the time bar, and the side
## panel's Region / Squad / Log tabs (ui/README.md rules 7-16). A right-click
## on a region, or ⋮ on its card, opens its DetailModal.
## All rules live in Campaign; this script only shows them and forwards input.
##
## Presentation (M7 P3, timings in data/feel/screens.json): P1's pixel theme;
## regions react to hover and selection (MapView, MapFx); changes to the run
## (captures, energy, material, grid) are held while the map is out of sight
## or under a message, then shown at once as a capture sweep, number popups
## and bars that slide with a trailing ghost (MapChanges); the act zoom plays
## a whoosh, an act title card and a music crossfade (MusicDirector); the
## territory panel names the enemy faction holding a hostile region, with
## its icon (FactionLookup over P4's FactionTable).
##
## Odds (R1-D): the panel's odds for attacking a region come from MapOdds:
## simulated auto-fights of the squad against the region's own enemies,
## shown as "RISKY · 42%", or the old stat formula under the switchboard's
## odds-model "formula". Set odds.run_seed to seed them with the run.
##
## Stakes (R2-A, Campaign's Stakes): the top bar shows losses left this act
## ("LOSSES 1/3") and a REPAIR button that turns Material into grid; the
## Energy and Material readouts say in their tooltips what each buys. ATTACK
## opens a pre-fight step: FIGHT, BREACH (lower the defense for a cost) or
## RETREAT (time and Energy, no fight). A forced defense may be retreated
## from too, giving the region up. Once nothing is in range, FAST-FORWARD
## plays the days to the payload (Campaign.fast_forward()) and sums them up.
## When the run ends, the host's run_over_action takes over (RunFlow shows
## the run-over screen); with none, the end message offers NEW RUN.
##
## Leaving: a host may put a Home button in the top bar (show_home_button())
## and be called just before every fight (before_fight_action), which RunFlow
## uses to autosave the map a mid-battle exit comes back to.

const Palette := preload("res://ui/overworld/palette.gd")
const MapView := preload("res://ui/overworld/map_view.gd")
const GlobeView := preload("res://ui/overworld/globe_view.gd")
const MeterBar := preload("res://ui/overworld/meter_bar.gd")
const EscalationHud := preload("res://ui/overworld/escalation_hud.gd")

## A new Campaign took over the map: a new run, the next act, or a load.
signal campaign_started(campaign: Campaign)

const SAVE_PATH := "user://overworld.save"
const MAP_SIZE := Vector2(880, 580)
## The map's control strip above it (lens, legend).
const MAP_STRIP_HEIGHT := 40.0
## How far below the top bar the news toast docks: under the side tabs.
const NEWS_TOP := 56.0
const PANEL_WIDTH := 400.0
const TOP_BAR_HEIGHT := 56.0
## The top bar's compact steps (_fit_top_bar).
const TOP_BAR_LEVELS := 4
const CHOICE_CARD_WIDTH := 290.0
## The grid bar's width once the top bar also holds a Home button.
const HOME_GRID_BAR_WIDTH := 96.0
## The compact grid meter's bar.
const GRID_BAR_WIDTH := 96.0
## The icon of the campaign's Energy resource (data/ui/icons.json): the power
## cell. "energy" is the battle lightning for skill costs.
const ENERGY_ICON := "map_energy"
const GRID_TIP := "Grid capacity: how much power your network can still carry. Actions use it; it recovers each day."
const POOL_TIP := "Power pool: grid capacity and Energy are one pool. Actions and Energy costs both draw on it."
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
## Called when the player closes the end-of-run message; a host shows its
## run-over screen. When unset the message offers NEW RUN instead.
var run_over_action: Callable
## Called just before every fight starts (attack, forced defense, boss), while
## the map can still be saved: RunFlow autosaves there, so leaving mid-battle
## can come back to the map as it stood before the fight.
var before_fight_action: Callable
## When set, the payload of an act with a next act calls it instead of
## zooming out (a demo run ends there).
var payload_action: Callable
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
var music: MusicDirector
## The odds the panel shows for attacking a region.
var odds: MapOdds
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
## The alert meter and news cards over the map (R2-B).
var escalation_hud: EscalationHud

var _grid_bar: MeterBar
var _grid_text: Label
var _grid_title: IconStat
var _grid_rate: Label
var _countdown: Label
var _day_line: Label
## The countdown with its icon; its tooltip has the act, day and territories.
var _countdown_box: HBoxContainer
## The side panel's tabs: Region, Squad, Log.
var side_tabs: UiTabs
var _background: ColorRect
var _side_box: StyleBoxFlat
var _emblem: TextureRect
## The map's control strip: lens and legend.
var map_strip: ControlStrip
var _legend: Control
## The card of the region under the pointer.
var _hover_card: PanelContainer
var _hovered_region := ""
## The Squad tab's rows.
var _squad: VBoxContainer
## Log lines added since the Log tab was last open.
var _unread_log := 0
## The compact grid meter; its tooltip has the daily rate.
var _grid_meter: HBoxContainer
var _income: HBoxContainer
var _time_day: Label
var _time_bar: MeterBar
var _campaign_bar: MeterBar
var _wait_button: ActionButton
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
var _losses: IconStat
var _repair_button: ActionButton
var _ff_button: ActionButton
## The Home button in the top bar, once show_home_button() made it.
var home_button: ActionButton
## SAVE, LOAD and NEW RUN in the time strip (show_run_buttons()).
var run_buttons: Array[Button] = []
var _top_row: HBoxContainer
var _side: Control
var _toast: Control
## How far the top bar has compacted to fit (_fit_top_bar): 0 shows it all.
var top_bar_level := 0


func _ready() -> void:
	set_anchors_preset(Control.PRESET_FULL_RECT)
	theme = ScreenTheme.theme()
	music = MusicDirector.current
	if music == null:
		music = MusicDirector.new()
		music.name = "Music"
		add_child(music)
	odds = MapOdds.new()
	odds.name = "MapOdds"
	odds.estimated.connect(_on_odds_estimated)
	add_child(odds)
	_build_layout()
	new_run()


func _process(_delta: float) -> void:
	if _hover_card != null and _hover_card.visible:
		_place_hover_card()
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


## The act's identity on the map screen (ui/README.md): a faint tint of its
## color in the backdrop and side panel, and its emblem behind the panel.
func apply_act_identity(act: int) -> void:
	if _background == null:
		return
	_background.color = UiStyle.act_tinted(Palette.BACKGROUND, act, "background")
	_side_box.bg_color = UiStyle.act_tinted(Palette.PANEL, act, "panel")
	_emblem.texture = UiIcons.texture(UiStyle.act_emblem(act))


func _use_campaign(c: Campaign) -> void:
	campaign = c
	campaign_started.emit(c)
	campaign.changed.connect(_refresh)
	campaign.event_logged.connect(_event)
	campaign.fight_started.connect(_on_fight_started)
	escalation_hud.use(campaign)
	_use_view_for(campaign.map)
	map_view.campaign = campaign
	map_view.selected_id = ""
	_seen = {}
	_unshown = null
	music.play_map(campaign.state.act)
	apply_act_identity(campaign.state.act)
	_hide_modal()
	_refresh()


## True when the run plays the shared_pool energy-grid variant: grid capacity
## and Energy are one pool, kept in RunState.grid.
func is_shared_pool() -> bool:
	return campaign != null and campaign.variants != null and EnergyGridRules.is_shared(campaign.variants)


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
	for id in _unshown.captured:
		map_view.fx.hold_capture(id)


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
		popup.text = ("%+d%% POOL" if is_shared_pool() else "%+d%% GRID") % amount
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
	_background = background
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

	# On a bigger view the map grows (at its own shape, MapView.frame()) and
	# the side panel takes its share of the width (ui/README.md rule 17).
	var share := float(UiIcons.kit("map.side_panel_share", 0.25))
	var left := VBoxContainer.new()
	left.custom_minimum_size.x = MAP_SIZE.x
	left.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	left.size_flags_stretch_ratio = 1.0 - share
	left.add_theme_constant_override("separation", 0)
	body.add_child(left)
	left.add_child(_build_map_strip())
	map_view = _new_view(false)
	left.add_child(map_view)
	var time_strip := _build_time_strip()
	left.add_child(time_strip)

	var side := _build_side_panel()
	side.size_flags_stretch_ratio = share
	body.add_child(side)
	_side = side
	_hud = [column.get_child(0), map_strip, time_strip, side]
	_popups = Control.new()
	_popups.name = "Popups"
	_popups.set_anchors_preset(Control.PRESET_FULL_RECT)
	_popups.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_popups)
	escalation_hud = EscalationHud.new()
	escalation_hud.name = "EscalationHud"
	add_child(escalation_hud)
	escalation_hud.news.can_show = can_show_changes
	# News cards toast over the top of the side panel, not over the map.
	var toast := Control.new()
	toast.name = "NewsToast"
	toast.mouse_filter = Control.MOUSE_FILTER_IGNORE
	# Under the side panel's tab bar, so the tabs stay reachable.
	add_child(toast)
	_toast = toast
	escalation_hud.dock_news(toast, Vector2(12, 12), PANEL_WIDTH - 24.0)
	_hover_card = PanelContainer.new()
	_hover_card.name = "HoverCard"
	_hover_card.visible = false
	_hover_card.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_hover_card.add_theme_stylebox_override("panel", UiStyle.panel("overlay"))
	_hover_card.custom_minimum_size.x = 320
	add_child(_hover_card)
	_legend = _build_legend()
	add_child(_legend)
	_build_act_title()
	_build_modal()
	resized.connect(_fit_layout)
	body.resized.connect(_fit_layout)
	_fit_layout.call_deferred()


## Keeps what floats over the map on it as the view changes size: the
## escalation hud over the map, the news toast at the side panel's top, and
## the top bar compacted to fit (_fit_top_bar).
func _fit_layout() -> void:
	if map_view == null or _side == null:
		return
	escalation_hud.position = map_view.get_global_rect().position - get_global_rect().position
	escalation_hud.size = map_view.size
	_toast.position = Vector2(_side.get_global_rect().position.x - get_global_rect().position.x,
		_side.get_global_rect().position.y - get_global_rect().position.y + NEWS_TOP)
	_fit_top_bar()


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
	# The map's smallest view: the art's width, and a little less than its
	# height so the strips under it can take a second line; the frame keeps
	# the map's shape either way.
	view.custom_minimum_size = Vector2(MAP_SIZE.x, MAP_SIZE.y * float(UiIcons.kit("map.min_height_share", 0.9)))
	view.size_flags_vertical = Control.SIZE_EXPAND_FILL
	view.resized.connect(func() -> void: _fit_layout.call_deferred())
	view.region_selected.connect(func(_id: String) -> void: _refresh())
	view.region_hovered.connect(_on_region_hovered)
	view.region_detail_requested.connect(func(id: String) -> void: DetailModal.open(self, region_detail_spec(id)))
	view.odds_pin = _odds_pin
	view.lens = map_strip.value(&"lens") if map_strip != null else str(UiIcons.kit("map.lens", "defense"))
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


## The map's one control strip (ui/README.md rule 10): which lens the region
## pins show, and the "?" legend.
func _build_map_strip() -> Control:
	map_strip = ControlStrip.new()
	map_strip.name = "MapStrip"
	map_strip.custom_minimum_size.y = MAP_STRIP_HEIGHT
	map_strip.add_choice(&"lens", "", [
		[&"defense", "Defense", "defense_level", "Hostile regions' defense: how hard the fight is."],
		[&"pressure", "Pressure", "pressure", "Your regions' pressure: how close each is to an attack or uprising."],
		[&"resources", "Resources", "material", "What each region gives every day."],
		[&"odds", "Odds", "odds", "Your chance to win each attack in range, from simulated fights."],
	], StringName(str(UiIcons.kit("map.lens", "defense"))))
	map_strip.add_spring()
	var help := map_strip.add_toggle(&"legend", "?", false, "", "What the map's colors mean.")
	help.name = "LegendButton"
	map_strip.changed.connect(_on_map_strip)
	return map_strip


func _on_map_strip(id: StringName, value: Variant) -> void:
	match id:
		&"lens":
			map_view.lens = str(value)
		&"legend":
			_legend.visible = bool(value)
			if _legend.visible:
				var b := map_strip.button(&"legend")
				_legend.reset_size()
				_legend.position = Vector2(b.get_global_rect().end.x - _legend.size.x, b.get_global_rect().end.y + UiStyle.space("xs"))


## The map legend behind "?": what each color means.
func _build_legend() -> Control:
	var panel := PanelContainer.new()
	panel.name = "Legend"
	panel.visible = false
	panel.add_theme_stylebox_override("panel", UiStyle.panel("overlay"))
	var rows := UiStyle.column("s")
	panel.add_child(rows)
	for entry: Array in [[Palette.OWNED, "Yours"], [Palette.IN_RANGE, "Hostile, in range to attack"], [Palette.OUT_OF_REACH, "Hostile, out of reach"]]:
		var row := UiStyle.row("s")
		row.add_child(_swatch(entry[0], Vector2(16, 16)))
		row.add_child(_text(entry[1], PixelTheme.font_size("body"), Palette.TEXT))
		rows.add_child(row)
	rows.add_child(UiStyle.label("Right-click a region for everything about it.", "text_quiet"))
	return panel


## The odds lens pin of a region: ["62%", band color], or ["", ...] for none.
func _odds_pin(region_id: String) -> Array:
	if campaign == null or campaign.standing(region_id) != Campaign.Standing.IN_RANGE:
		return ["", Color.WHITE]
	if not odds.is_simulated():
		var label := campaign.odds_label(region_id)
		return [label, _odds_color(label)]
	var e := odds.estimate_for(campaign, region_id)
	if e == null:
		return ["...", Palette.TEXT_DIM]
	return ["%d%%" % e.percent(), _odds_color(e.label)]


## The full card of the region under the pointer, by the pointer.
func _on_region_hovered(region_id: String) -> void:
	_hovered_region = region_id
	_hover_card.visible = false
	if region_id.is_empty() or campaign == null or not campaign.map.has_region(region_id) or zooming:
		return
	for c in _hover_card.get_children():
		_hover_card.remove_child(c)
		c.queue_free()
	var region := campaign.map.get_region(region_id)
	var col := UiStyle.column("xs")
	col.add_child(_text(region.name, PixelTheme.font_size("body"), Palette.TEXT_BRIGHT))
	col.add_child(Flag.row(region_flags(region_id)))
	var strip := StatStrip.make(region_headlines(region_id))
	strip.set_gap(UiStyle.space("m"))
	col.add_child(strip)
	_hover_card.add_child(col)
	_hover_card.visible = true
	_hover_card.reset_size()
	_place_hover_card()


func _place_hover_card() -> void:
	if not _hover_card.visible:
		return
	var at := get_global_mouse_position() + UiIcons.kit_vector("map.hover_card_offset", Vector2(20, 20))
	var view := get_viewport_rect().size
	_hover_card.position = Vector2(clampf(at.x, 0, view.x - _hover_card.size.x), clampf(at.y, 0, view.y - _hover_card.size.y))


func _build_top_bar() -> Control:
	# One row, left to right: the payload countdown (the main element), losses,
	# Energy and Material, the compact grid meter with Repair, then Home. The
	# act, day and territory count sit in the countdown's tooltip.
	var bar := PanelContainer.new()
	bar.name = "TopBar"
	var box := UiStyle.panel("plain")
	box.bg_color = Palette.BAR_BACKGROUND
	box.content_margin_left = UiStyle.space("l")
	box.content_margin_right = UiStyle.space("l")
	box.content_margin_top = 0
	box.content_margin_bottom = 0
	bar.add_theme_stylebox_override("panel", box)
	bar.custom_minimum_size.y = TOP_BAR_HEIGHT
	var row := UiStyle.row("l")
	row.name = "Row"
	bar.add_child(row)
	_top_row = row

	var countdown := UiStyle.row("s")
	countdown.name = "Countdown"
	countdown.mouse_filter = Control.MOUSE_FILTER_PASS
	countdown.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	row.add_child(countdown)
	var clock := UiIcons.rect("time")
	clock.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	countdown.add_child(clock)
	_countdown = _text("", PixelTheme.font_size("title"), Palette.TEXT_BRIGHT)
	_countdown.name = "CountdownText"
	countdown.add_child(_countdown)
	# Kept for its words (the countdown's tooltip, tests); not shown on the bar.
	_day_line = _text("", PixelTheme.font_size("body"), Palette.TEXT_DIM)
	_day_line.visible = false
	countdown.add_child(_day_line)
	_countdown_box = countdown

	_losses = IconStat.make("losses", 0)
	_losses.name = "LossesStat"
	_losses.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	row.add_child(_losses)

	_income = UiStyle.row("m")
	_income.name = "Income"
	_income.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	row.add_child(_income)

	row.add_child(UiStyle.spring())

	# The grid as a compact meter: icon, a short bar, the percent; its rate in
	# the tooltip. Repair beside it.
	var grid := UiStyle.row("xs")
	grid.name = "GridMeter"
	grid.mouse_filter = Control.MOUSE_FILTER_PASS
	grid.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	row.add_child(grid)
	_grid_title = IconStat.make("grid_power", null, GRID_TIP)
	_grid_title.name = "GridTitle"
	grid.add_child(_grid_title)
	_grid_bar = MeterBar.new()
	_grid_bar.custom_minimum_size = Vector2(GRID_BAR_WIDTH, 12)
	_grid_bar.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	_grid_bar.segment_px = 8.0
	grid.add_child(_grid_bar)
	_grid_text = _text("", PixelTheme.font_size("body"), Palette.WARNING)
	grid.add_child(_grid_text)
	# The rate's words live in the meter's tooltip.
	_grid_rate = _text("", PixelTheme.font_size("body"), Palette.TEXT_DIM)
	_grid_rate.visible = false
	grid.add_child(_grid_rate)
	_grid_meter = grid
	_repair_button = ActionButton.make("action_repair", "Repair")
	_repair_button.name = "RepairButton"
	_repair_button.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	_repair_button.pressed.connect(_on_repair)
	row.add_child(_repair_button)
	return bar


## The top bar on one row whatever the view and the numbers: while it is too
## wide it drops, in order, the day's gains (still in each stat's tooltip),
## the grid's bar (the percent stays), the countdown's title size, and the
## words of Repair and Home (icons, names on hover). top_bar_level says how
## far it went.
func _fit_top_bar() -> void:
	if _top_row == null or size.x <= 0.0:
		return
	var bar := _top_row.get_parent() as PanelContainer
	var box := bar.get_theme_stylebox("panel")
	var room := size.x - box.content_margin_left - box.content_margin_right
	top_bar_level = 0
	_compact_top_bar()
	while _top_row.get_combined_minimum_size().x > room + 0.5 and top_bar_level < TOP_BAR_LEVELS:
		top_bar_level += 1
		_compact_top_bar()


func _compact_top_bar() -> void:
	for row in _income.get_children():
		var rate := row.get_node_or_null("Rate") as Control
		if rate != null:
			rate.visible = top_bar_level < 1
	_grid_bar.visible = top_bar_level < 2
	_countdown.add_theme_font_size_override("font_size", PixelTheme.font_size("title" if top_bar_level < 3 else "body"))
	for b: ActionButton in [_repair_button, home_button]:
		if b != null:
			b.set_icon_only(top_bar_level >= 4)


func _build_time_strip() -> Control:
	var strip := _box(Palette.BAR_BACKGROUND, Vector4(28, 10, 28, 10))
	var rows := VBoxContainer.new()
	rows.add_theme_constant_override("separation", 10)
	strip.add_child(rows)

	# Wraps onto a second line when a run shows every button (Fast-forward,
	# SAVE, LOAD, NEW RUN) on a narrow view.
	var header := HFlowContainer.new()
	header.name = "TimeHeader"
	header.add_theme_constant_override("h_separation", 12)
	header.add_theme_constant_override("v_separation", UiStyle.space("xs"))
	rows.add_child(header)
	header.add_child(UiStyle.caption(_text("TIME", 10, Palette.TEXT_DIM)))
	_time_day = _text("", PixelTheme.font_size("body"), Palette.TEXT)
	header.add_child(_time_day)
	_status = _text("", PixelTheme.font_size("body"), Palette.DEFENSE_TEXT)
	_status.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	header.add_child(_status)
	_wait_button = _action("action_wait", "Wait", "", null, _on_wait, true, "Let time pass. Regions you hold pay out; pressure rises.")
	_wait_button.name = "WaitButton"
	_wait_button.custom_minimum_size.y = 26
	_wait_button.mouse_entered.connect(_set_hover_wait.bind(true))
	_wait_button.mouse_exited.connect(_set_hover_wait.bind(false))
	header.add_child(_wait_button)
	_ff_button = ActionButton.make("action_fast_forward", "Fast-forward")
	_ff_button.name = "FastForwardButton"
	_ff_button.pressed.connect(_on_fast_forward)
	_ff_button.visible = false
	header.add_child(_ff_button)
	run_buttons = [_button("SAVE", Palette.BAR_BACKGROUND, Palette.TEXT_DIM, _on_save),
		_button("LOAD", Palette.BAR_BACKGROUND, Palette.TEXT_DIM, _on_load),
		_button("NEW RUN", Palette.BAR_BACKGROUND, Palette.TEXT_DIM, _on_new_run)]
	for b in run_buttons:
		b.name = b.text.capitalize().replace(" ", "") + "Button"
		header.add_child(b)

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
	camp.add_child(UiStyle.caption(_text("CAMPAIGN", 10, Palette.TEXT_DIM)))
	_campaign_bar = MeterBar.new()
	_campaign_bar.custom_minimum_size.y = 6
	_campaign_bar.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_campaign_bar.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	_campaign_bar.fill_color = Palette.TIME_FILL
	_campaign_bar.border = Color(0, 0, 0, 0)
	camp.add_child(_campaign_bar)
	camp.add_child(UiStyle.caption(_text("PAYLOAD", 10, Palette.TEXT_DIM)))
	return strip


func _build_side_panel() -> Control:
	# Tabs (ui/README.md rule 16): the selected region, the squad, the log.
	var side := PanelContainer.new()
	side.name = "SidePanel"
	side.custom_minimum_size.x = PANEL_WIDTH
	side.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	var box := UiStyle.panel("plain")
	box.bg_color = Palette.PANEL
	box.set_content_margin_all(UiStyle.space("m"))
	side.add_theme_stylebox_override("panel", box)
	_side_box = box
	# The act's emblem, large and faint, behind the panel's content.
	_emblem = EntryTile.icon_art("demo_map", 20)
	_emblem.name = "ActEmblem"
	_emblem.size_flags_horizontal = Control.SIZE_SHRINK_END
	_emblem.size_flags_vertical = Control.SIZE_SHRINK_END
	_emblem.modulate.a = float(UiIcons.kit("acts.emblem_alpha", 0.06))
	side.add_child(_emblem)
	side_tabs = UiTabs.new()
	side_tabs.name = "SideTabs"
	side.add_child(side_tabs)

	_panel = UiStyle.column("m")
	_panel.name = "Region"
	_panel.size_flags_vertical = Control.SIZE_EXPAND_FILL
	side_tabs.add_tab(&"region", "Region", _panel, "defense_level")

	_squad = UiStyle.column("s")
	_squad.name = "Squad"
	side_tabs.add_tab(&"squad", "Squad", _squad, "hp")

	var log_scroll := ScrollContainer.new()
	log_scroll.name = "LogScroll"
	log_scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	_log = UiStyle.column("s")
	_log.name = "Log"
	_log.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	log_scroll.add_child(_log)
	side_tabs.add_tab(&"log", "Log", log_scroll, "status_waiting")
	side_tabs.changed.connect(_on_side_tab)
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
	# With the shared pool (energy-grid variant) the bar is the one pool of
	# grid and Energy, and there is no separate Energy count.
	var shared := is_shared_pool()
	_grid_title.set_tip_text(POOL_TIP if shared else GRID_TIP)
	_grid_bar.fill_color = Palette.ENERGY if shared else Color("#f2b84b")
	if shared:
		var divisor := campaign.variants.param_float(CampaignVariants.ENERGY_GRID, "pool_regen_divisor", 1.0)
		_grid_rate.text = "+%s%%/DAY" % _number((income[MapRegion.POWER] + income[MapRegion.ENERGY]) * t.points_per_day / maxf(divisor, 0.001))
	else:
		_grid_rate.text = "+%s%%/DAY" % _number(income[MapRegion.POWER] * t.points_per_day / t.grid_regen_divisor)
	UiTooltip.attach(_grid_meter, "Power pool" if shared else "Grid capacity", POOL_TIP if shared else GRID_TIP,
		"%s now, %s a day" % [_grid_text.text, _grid_rate.text.to_lower().replace("/day", "")], "grid_power")

	_countdown.text = "Payload in %d days" % campaign.days_left()
	_day_line.text = "ACT %d · %s · DAY %d / %d · %d OF %d TERRITORIES" % [
		s.act + 1, campaign.map.name.to_upper(), campaign.day(), t.total_points / t.points_per_day,
		s.owned.size(), campaign.map.regions.size()]
	UiTooltip.attach(_countdown_box, "Payload countdown",
		"When it reaches 0 the act's payload lands: the boss fight. Act %d, %s." % [s.act + 1, campaign.map.name],
		"Day %d of %d\nTerritories %d of %d" % [campaign.day(), t.total_points / t.points_per_day,
			s.owned.size(), campaign.map.regions.size()], "time",
		[UiFormula.new().term("Days", t.total_points / t.points_per_day).op("−").term("Day", campaign.day()).equals(campaign.days_left(), "left")])
	_clear(_income)
	for key in ([MapRegion.MATERIAL] if shared else [MapRegion.ENERGY, MapRegion.MATERIAL]):
		var stock: float = s.energy if key == MapRegion.ENERGY else s.material
		_income.add_child(_resource_stat(key, floori(stock), income[key]))
	_fit_top_bar()

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
	if _wait_button.cost != _days_number(t.wait_time):
		_wait_button.set_cost("time", _days_number(t.wait_time))
	_ff_button.visible = campaign.can_fast_forward() and not zooming
	_refresh_stakes()
	_status.text = "FIGHT IN PROGRESS" if campaign.fighting else ""
	map_view.queue_redraw()
	odds.update(campaign, map_view.selected_id)
	_refresh_panel()
	_refresh_squad()
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
	var owned := standing == Campaign.Standing.OWNED

	# The region card (ui/README.md rule 8): name and ⋮, flags, three headlines.
	var head := UiStyle.row("s")
	head.name = "TitleRow"
	var names := UiStyle.column("xs")
	names.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	names.add_child(UiStyle.label(region.kind.capitalize(), "text_quiet"))
	var name_label := _text(region.name, PixelTheme.font_size("title"), Palette.TEXT_BRIGHT)
	name_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	names.add_child(name_label)
	head.add_child(names)
	var more := DetailModal.more_button(region_detail_spec.bind(id))
	more.size_flags_vertical = Control.SIZE_SHRINK_BEGIN
	head.add_child(more)
	_panel.add_child(head)
	_panel.add_child(Flag.row(region_flags(id)))

	var strip := StatStrip.make(region_headlines(id))
	strip.name = "Headlines"
	strip.set_gap(UiStyle.space("l"))
	_panel.add_child(strip)
	# The headlines keep the names the panel's parts always had.
	if owned:
		strip.headline(0).name = "Pressure"
	else:
		strip.headline(0).name = "Odds"
		strip.headline(1).name = "Defense"
		if odds.is_simulated():
			UiTooltip.attach(strip.headline(0), "Your odds%s" % _odds_band_suffix(id),
				"Auto-fights against this territory's enemies, %d of them. The auto-player fights differently from you." % odds.estimator.tuning.runs,
				"", "odds", odds_math(id))
	strip.headline(2).name = "Provides"

	if owned:
		var attacker := campaign.attacker_of(id)
		_panel.add_child(_text("Attack building from %s" % attacker.name if attacker != null
			else "Uprising building from within", PixelTheme.font_size("body"), Palette.TEXT))
	else:
		_panel_faction(region)
		if campaign.escalation.fortify_of(id) > 0:
			_panel.add_child(IconStat.make("fortify", "+%d" % campaign.escalation.fortify_of(id),
				"Dug in while left alone on Alert. Attack it to stop the digging."))

	var spacer := Control.new()
	spacer.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_panel.add_child(spacer)

	var actions := _rows(UiStyle.space("s"))
	if owned:
		var stakes := campaign.stakes
		var note := "Lowers pressure here. Takes %s and a little grid power" % _points_text(campaign.tuning.reinforce_time)
		if stakes.is_offered(Stakes.USE_REINFORCE):
			note += ", and %s" % stakes.cost_text(Stakes.USE_REINFORCE)
		note += "."
		if campaign.can_act() and not stakes.can_pay(Stakes.USE_REINFORCE, campaign.state):
			note += " Not enough to pay for it."
		var c := _use_cost(Stakes.USE_REINFORCE) if stakes.is_offered(Stakes.USE_REINFORCE) else ["time", _days_number(campaign.tuning.reinforce_time)]
		var reinforce := _action("action_reinforce", "Reinforce", c[0], c[1], _on_reinforce.bind(id),
			campaign.can_reinforce(id), note)
		reinforce.name = "ReinforceButton"
		actions.add_child(reinforce)
	else:
		var why := "Not next to your network. Take a neighbor first." if standing == Campaign.Standing.OUT_OF_REACH \
			else "Opens the fight. Takes %s and grid power, more if the assault fails." % _points_text(campaign.tuning.attack_time)
		var attack := _action("action_attack", "Attack", "time", _days_number(campaign.tuning.attack_time),
			show_pre_fight.bind(id), campaign.can_attack(id), why)
		attack.name = "AttackButton"
		attack.custom_minimum_size.y = 48
		if not attack.disabled:
			_style_button(attack, Palette.ATTACK_BUTTON, Palette.ATTACK_TEXT, Color(0, 0, 0, 0))
			attack.label.add_theme_color_override("font_color", Palette.ATTACK_TEXT)
		actions.add_child(attack)
	_panel.add_child(actions)


## The flags on a region's card: its standing, Fortified, Under attack or
## Uprising (once pressure reaches the warning level).
func region_flags(region_id: String) -> Array:
	var out: Array = []
	match campaign.standing(region_id):
		Campaign.Standing.OWNED:
			out.append(Flag.of("yours"))
		Campaign.Standing.IN_RANGE:
			out.append(Flag.of("in_range"))
		_:
			out.append(Flag.of("out_of_reach"))
	if campaign.is_owned(region_id):
		if campaign.pressure_of(region_id) >= campaign.tuning.ring_warning_at:
			out.append(Flag.of("under_attack" if campaign.attacker_of(region_id) != null else "uprising"))
	elif campaign.escalation.fortify_of(region_id) > 0:
		out.append(Flag.of("fortified"))
	return out


## A region's three headlines. Hostile: odds (ring), defense (pips), what it
## gives (chip). Held: pressure (ring), what it gives, border or interior.
func region_headlines(region_id: String) -> Array:
	var t := campaign.tuning
	var region := campaign.map.get_region(region_id)
	var gives := _gives_spec(region)
	if campaign.is_owned(region_id):
		var pressure := campaign.pressure_of(region_id)
		var role := "bad" if pressure >= t.imminent_at else ("caution" if pressure >= t.ring_warning_at else "interactive")
		var where := "Border territory, exposed to its neighbors. " if campaign.is_border(region_id) \
			else "Interior territory, shielded by your other holdings. "
		var ring := StatStrip.ring("pressure", pressure / t.forces_defense_at,
			where + "Pressure is rising %s." % t.rate_word(campaign.pressure_rate(region_id)),
			[UiFormula.new().term("Pressure", "%d%%" % roundi(pressure)).op("/").term("Defense fight at", "%d%%" % roundi(t.forces_defense_at))
				.equals("%d%%" % roundi(100.0 * pressure / t.forces_defense_at))], role)
		ring["text"] = "%d%%" % roundi(pressure)
		ring["title"] = "Pressure"
		return [ring, gives, StatStrip.chip("defense_level", "Border" if campaign.is_border(region_id) else "Interior",
			where.strip_edges(), [], "caution" if campaign.is_border(region_id) else "text_quiet")]
	var e := odds.estimate_for(campaign, region_id) if odds.is_simulated() else null
	var share := e.win_rate() if e != null else 0.0
	var odds_spec := StatStrip.ring("odds", share, "Chance to win, from simulated fights.", odds_math(region_id), "hint")
	odds_spec["text"] = ("%d%%" % e.percent()) if e != null else ("..." if odds.is_simulated() else campaign.odds_label(region_id))
	odds_spec["title"] = "Your odds%s" % _odds_band_suffix(region_id)
	var level := campaign.defense_of(region_id)
	var defense := StatStrip.pips("defense_level", level, MapRegion.MAX_DEFENSE,
		campaign.tuning.opposition(level), [], "info")
	defense["numbers"] = "Defense %d of %d: %s" % [level, MapRegion.MAX_DEFENSE, campaign.tuning.defense_label(level)]
	return [odds_spec, defense, gives]


## What a region gives each day, as a chip: "+3" with its main resource's icon
## (every resource in the tooltip).
func _gives_spec(region: MapRegion) -> Dictionary:
	var best := ""
	var total := 0
	var lines := PackedStringArray()
	for key in MapRegion.RESOURCE_KEYS:
		var n: int = region.provides[key]
		if n > 0:
			total += n
			lines.append("%s +%d a day" % [RESOURCE_LABELS[key], n])
			if best.is_empty() or n > region.provides[best]:
				best = key
	if best.is_empty():
		return StatStrip.chip("material", "None", "Gives nothing.", [], "text_quiet")
	# The main resource on the card; every resource in the tooltip, the
	# detail card and the Resources lens.
	var more := " and more" if lines.size() > 1 else ""
	var spec := StatStrip.chip(_resource_icon(best), "+%d" % region.provides[best],
		"What it adds every day while you hold it%s." % more, [], "good")
	spec["numbers"] = "\n".join(lines)
	spec["title"] = "Gives"
	return spec


func _odds_band_suffix(region_id: String) -> String:
	if not odds.is_simulated():
		return ": " + campaign.odds_label(region_id)
	var e := odds.estimate_for(campaign, region_id)
	return (": " + e.label) if e != null else ""


## Everything about a region (⋮ on its card, or a right-click on the map).
func region_detail_spec(region_id: String) -> Dictionary:
	var region := campaign.map.get_region(region_id)
	var rows: Array = []
	if campaign.is_owned(region_id):
		var pressure := campaign.pressure_of(region_id)
		rows.append(["pressure", "Pressure", "%d%%" % roundi(pressure)])
		rows.append(["defense_level", "Exposure", "Border" if campaign.is_border(region_id) else "Interior"])
		var attacker := campaign.attacker_of(region_id)
		rows.append(["alert", "Cause", attacker.name if attacker != null else "Uprising"])
	else:
		var e := odds.estimate_for(campaign, region_id) if odds.is_simulated() else null
		rows.append(["odds", "Odds", ("%d%%" % e.percent()) if e != null else odds_text(region_id), odds_math(region_id)])
		rows.append(["defense_level", "Defense", "%d · %s" % [campaign.defense_of(region_id), campaign.tuning.defense_label(campaign.defense_of(region_id))]])
		if campaign.escalation.fortify_of(region_id) > 0:
			rows.append(["fortify", "Fortified", "+%d" % campaign.escalation.fortify_of(region_id)])
		var faction := factions.faction_for(region_id)
		if not faction.is_empty():
			rows.append(["alert", "Held by", faction["name"]])
	for key in MapRegion.RESOURCE_KEYS:
		if region.provides[key] > 0:
			rows.append([_resource_icon(key), RESOURCE_LABELS[key], "+%d a day" % region.provides[key]])
	var neighbors := PackedStringArray()
	for n in region.adjacent:
		if campaign.map.has_region(n):
			neighbors.append(campaign.map.get_region(n).name)
	var sections: Array = [{"id": "region", "title": "Region", "content": DetailModal.rows(rows)}]
	if not neighbors.is_empty():
		sections.append({"id": "neighbors", "title": "Neighbors", "content": DetailModal.prose(", ".join(neighbors) + ".")})
	return {"title": region.name, "icon": "defense_level", "subtitle": region.kind.capitalize(),
		"flags": region_flags(region_id), "sections": sections}


func _panel_intro() -> void:
	var rows := _rows(UiStyle.space("s"))
	rows.name = "Intro"
	# The first-turn hint shows only early in a run; the color legend lives
	# behind the map strip's "?" (ui/README.md rule 5).
	if campaign.day() <= int(UiIcons.kit("map.hint_days", 2)):
		var title := _text("Pick a territory on the map.", PixelTheme.font_size("title"), Palette.TEXT)
		title.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		UiTooltip.attach(title, "Territories", "You can only attack territories next to ones you already hold. Rings on your territories show how close each is to an uprising or an attack.")
		rows.add_child(title)
	else:
		rows.add_child(UiStyle.label("Select a territory to see it here.", "text_quiet"))
	_panel.add_child(rows)


## The enemy faction holding a hostile region, with its icon or a diamond in
## its color; nothing when the data names none.
func _panel_faction(region: MapRegion) -> void:
	var faction := factions.faction_for(region.id)
	if faction.is_empty():
		return
	var rows := _rows(6)
	rows.name = "Faction"
	rows.add_child(UiStyle.label("Held by", "text_quiet"))
	var line := HBoxContainer.new()
	line.add_theme_constant_override("separation", 10)
	var color: Color = faction["color"]
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
	line.add_child(_text(faction["name"], PixelTheme.font_size("body"), color))
	rows.add_child(line)
	_panel.add_child(rows)


## How the odds came about: "Won 20 of 32 simulated fights = 62%", or
## nothing while the estimate is still running (ui/README.md rule 15).
func odds_math(region_id: String) -> Array:
	var e := odds.estimate_for(campaign, region_id) if odds.is_simulated() else null
	if e == null or e.runs <= 0:
		return []
	return [UiFormula.new().term("Won", e.wins).op("/").term("Fights", e.runs).equals("%d%%" % e.percent()),
		"Won %d of %d simulated fights." % [e.wins, e.runs]]


## The odds as the panel shows them: "RISKY · 42%" from simulated
## auto-fights, "SIMULATING..." while they play, or the formula's "RISKY".
func odds_text(region_id: String) -> String:
	if not odds.is_simulated():
		return campaign.odds_label(region_id).to_upper()
	var e := odds.estimate_for(campaign, region_id)
	if e == null:
		return "SIMULATING..."
	return "%s · %d%%" % [e.label.to_upper(), e.percent()]


## The boss fight plays the boss variant of the battle music.
func _on_fight_started(request: FightRequest) -> void:
	music.boss_battle = request.territory_id == Campaign.BOSS_ID


func _on_odds_estimated(region_id: String) -> void:
	if campaign != null and region_id == map_view.selected_id:
		_refresh_panel()


func _refresh_log() -> void:
	_clear(_log)
	for text in _events:
		var line := _text(text, PixelTheme.font_size("body"), Palette.TEXT_BODY)
		line.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		_log.add_child(line)
	if side_tabs != null:
		side_tabs.button(&"log").text = "Log" if _unread_log == 0 else "Log %d" % _unread_log


## The Squad tab: each bot's name, HP, ATK and trait (the SquadProvider's
## summaries; the fight screen and readout have the rest).
func _refresh_squad() -> void:
	if _squad == null or campaign == null or campaign.squad_provider == null:
		return
	_clear(_squad)
	for m in campaign.squad_provider.get_squad():
		var card := PanelContainer.new()
		card.name = "Bot_%s" % m.id.validate_node_name()
		var cbox := UiStyle.panel("plain")
		cbox.bg_color = Palette.BAR_BACKGROUND
		card.add_theme_stylebox_override("panel", cbox)
		var col := UiStyle.column("xs")
		card.add_child(col)
		var head := UiStyle.row("s")
		col.add_child(head)
		var n := _text(m.display_name, PixelTheme.font_size("body"), Palette.TEXT_BRIGHT)
		n.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		head.add_child(n)
		if not m.personality_tag.is_empty():
			var trait_id := "trait_%s" % m.personality_tag.to_lower()
			head.add_child(Flag.make(m.personality_tag.capitalize(), trait_id if UiIcons.has(trait_id) else "",
				"neutral", UiIcons.text(trait_id) if UiIcons.has(trait_id) else "Its personality.", UiIcons.has(trait_id)))
		var hp_max := maxi(1, m.max_hp)
		var specs := [StatStrip.bar("hp", m.hp, hp_max)]
		if m.stats != null:
			specs.append(StatStrip.number("atk", m.stats.attack))
			specs.append(StatStrip.chip("spd", str(m.stats.speed), "Speed: how often it acts."))
		var strip := StatStrip.make(specs)
		strip.set_gap(UiStyle.space("m"))
		col.add_child(strip)
		_squad.add_child(card)
	if _squad.get_child_count() == 0:
		_squad.add_child(UiStyle.label("No bots yet.", "text_quiet"))


func _on_side_tab(id: StringName) -> void:
	if id == &"log":
		_unread_log = 0
		_refresh_log()


func _event(text: String) -> void:
	if side_tabs != null and side_tabs.current != &"log":
		_unread_log += 1
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


func _on_attack(region_id: String, breach := false) -> void:
	var region := campaign.map.get_region(region_id)
	var result_holder := []
	var on_finish := func(_request: FightRequest, result: FightResult) -> void: result_holder.append(result)
	campaign.fight_finished.connect(on_finish, CONNECT_ONE_SHOT)
	if campaign.can_attack(region_id):
		_before_fight()
	if not await campaign.attack(region_id, breach):
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
			"The defenders held. Grid drained by %s%%. %s" % [_number(charge), _loss_text()], _check_forced)


func _before_fight() -> void:
	if before_fight_action.is_valid() and not campaign.fighting:
		before_fight_action.call()


## Puts a Home button at the right end of the top bar; pressing it calls
## `on_press` (RunFlow leaves for the main menu).
func show_home_button(on_press: Callable) -> ActionButton:
	if home_button == null:
		home_button = ActionButton.make("action_home", "Home")
		home_button.name = "HomeButton"
		home_button.size_flags_vertical = Control.SIZE_SHRINK_CENTER
		_top_row.add_child(home_button)
		_fit_top_bar()
		# Room for it at the end of the bar, even with large income numbers.
		_grid_bar.custom_minimum_size.x = HOME_GRID_BAR_WIDTH
	for connection in home_button.pressed.get_connections():
		home_button.pressed.disconnect(connection.callable)
	home_button.pressed.connect(on_press)
	return home_button


## Shows or hides SAVE, LOAD and NEW RUN (a demo run hides them).
func show_run_buttons(on: bool) -> void:
	for b in run_buttons:
		b.visible = on


## Shows whatever the run now demands: the end, or a forced defense.
func _check_forced() -> void:
	match campaign.end_reason():
		Stakes.END_ALL_LOST:
			_show_end("Your network is gone", "Every territory has fallen. The run ends here.", false)
			return
		Stakes.END_LOSS_LIMIT:
			_show_end("Too many defeats", "That was loss %d of %d in %s. The squad cannot go on; the run ends here." % [
				campaign.state.losses, campaign.stakes.loss_limit, plan.act_name(campaign.state.act)], false)
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
	var buttons := [_action("action_defend", "Defend", "", 0.0, _on_defend, true, "")]
	# TODO(decision: retreat-defense): pulling out gives the region up.
	buttons.append(_use_action(Stakes.USE_RETREAT, "action_retreat", "Retreat", _on_retreat.bind(region_id),
		campaign.can_retreat(region_id), "Give %s up without a fight. Takes %s. Not counted as a loss." % [
			region.name, _points_text(campaign.stakes.retreat_defense_time)]))
	_show_modal("DEFENSIVE BATTLE · FORCED", title, body, buttons)
	_show_stat_row([_losses_stat()])


func _on_defend() -> void:
	_hide_modal()
	var region_id := campaign.pending_defense()
	var region := campaign.map.get_region(region_id)
	var result_holder := []
	var on_finish := func(_request: FightRequest, result: FightResult) -> void: result_holder.append(result)
	campaign.fight_finished.connect(on_finish, CONNECT_ONE_SHOT)
	_before_fight()
	if not await campaign.defend():
		if campaign.fight_finished.is_connected(on_finish):
			campaign.fight_finished.disconnect(on_finish)
		return
	var result: FightResult = result_holder[0]
	if result.is_victory():
		_show_message("DEFENSE · VICTORY", "Held %s" % region.name,
			"The attack was beaten back and pressure eased.%s" % _rewards_text(result), _check_forced)
	else:
		_show_message("DEFENSE · DEFEAT", "Lost %s" % region.name, "It is hostile again. %s" % _loss_text(), _check_forced)


## What the loss just cost, for a defeat message.
func _loss_text() -> String:
	var stakes := campaign.stakes
	var text := "The defeat cost up to %s energy and %s material." % [
		Stakes._n(stakes.loss_cost[Stakes.ENERGY]), Stakes._n(stakes.loss_cost[Stakes.MATERIAL])]
	if stakes.loss_limit > 0:
		text += " Losses this act: %d of %d." % [campaign.state.losses, stakes.loss_limit]
	return text


func _show_end(title: String, body: String, won: bool) -> void:
	music.play_context(MusicDirector.VICTORY if won else MusicDirector.DEFEAT)
	if run_over_action.is_valid():
		_show_modal("RUN OVER", title, body, [["CONTINUE", _close_modal_then.bind(run_over_action)]])
	else:
		_show_modal("RUN OVER", title, body, [["NEW RUN", _on_new_run]])


## The last act's payload: the stub boss fight, then the end of the run.
func _show_boss() -> void:
	var body := "The countdown is over and the boss is here. Everything you hold across %s stands behind the squad. " % plan.act_name(campaign.state.act)
	body += "The boss fight is a stand-in for now: a fight at defense level %d." % campaign.tuning.boss_defense_level
	_show_modal("ACT %d · FINAL PAYLOAD" % (campaign.state.act + 1), "The boss arrives", body, [["FIGHT THE BOSS", _on_boss]])


func _on_boss() -> void:
	_hide_modal()
	_before_fight()
	var result: FightResult = await campaign.boss_fight()
	if result == null:
		return
	if result.is_victory():
		_show_end("The boss falls", "The squad beat the boss. The run is won.", true)
	else:
		_show_end("The boss holds", "The squad could not break the boss. The run ends here.", false)


func _show_payload_zoom() -> void:
	var act := campaign.state.act
	var held := campaign.state.owned.size()
	var bonus := plan.bonus_region_count(held)
	var body := "The boss fight is not built yet, so the payload passes. You held %d of %d territories in %s. " % [
		held, campaign.map.regions.size(), plan.act_name(act)]
	body += "The network zooms out to %s: you carry %d energy and %d material (up to the storage cap), the grid recovers %s%%, and you hold %s%s." % [
		plan.act_name(act + 1), floori(campaign.state.energy * plan.energy_kept),
		floori(campaign.state.material * plan.material_kept), _number(plan.grid_restore), plan.act_name(act),
		"" if bonus == 0 else " plus %d neighboring territor%s" % [bonus, "y" if bonus == 1 else "ies"]]
	if payload_action.is_valid():
		_show_modal("ACT %d · PAYLOAD" % (act + 1), "The payload arrives", body, [["CONTINUE", _close_modal_then.bind(payload_action)]])
		return
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


## buttons: [[label, Callable], ...] or ready-made buttons (ActionButton).
func _show_modal(eyebrow: String, title: String, body: String, buttons: Array) -> void:
	_modal_eyebrow.text = eyebrow
	_modal_title.text = title
	_modal_body.text = body
	_modal_body.visible = not body.is_empty()
	_clear(_modal_options)
	_modal_options.visible = false
	_modal_card.custom_minimum_size.x = 480
	_clear(_modal_buttons)
	for entry: Variant in buttons:
		if entry is Button:
			(entry as Button).size_flags_horizontal = Control.SIZE_EXPAND_FILL
			_modal_buttons.add_child(entry)
			continue
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


# --- Stakes and economy (R2-A) ---------------------------------------------------

## The losses stat and the REPAIR button.
func _refresh_stakes() -> void:
	var stakes := campaign.stakes
	_losses.set_value(_losses_value())
	_losses.set_tip_text(_losses_tip())
	_repair_button.visible = stakes.is_offered(Stakes.USE_REPAIR) and stakes.repair_grid > 0.0
	_repair_button.label.text = "Repair +%s%%" % _number(stakes.repair_grid)
	var c := _use_cost(Stakes.USE_REPAIR)
	_repair_button.set_cost(c[0], c[1])
	_repair_button.disabled = not campaign.can_repair() or zooming


func _losses_tip() -> String:
	var stakes := campaign.stakes
	var text := "Battles lost this act. Each loss takes %s Energy and %s Material." % [
		Stakes._n(stakes.loss_cost[Stakes.ENERGY]), Stakes._n(stakes.loss_cost[Stakes.MATERIAL])]
	if stakes.loss_limit <= 0:
		return text + " No limit this run."
	return text + " Loss %d ends the run; the next act starts again at 0. Losing the boss ends the run." % stakes.loss_limit


## "1/3": battles lost this act over the limit; "1" with no limit.
func _losses_value() -> String:
	var limit := campaign.stakes.loss_limit
	return "%d/%d" % [campaign.state.losses, limit] if limit > 0 else str(campaign.state.losses)


func _losses_stat() -> IconStat:
	var stat := IconStat.make("losses", _losses_value(), _losses_tip())
	stat.name = "LossesLeft"
	return stat


## [cost icon id, amount] for a use: its Energy cost, else its Material cost,
## else ["", null].
func _use_cost(use: String) -> Array:
	var c := campaign.stakes.cost(use)
	if c[Stakes.ENERGY] > 0.0:
		return [ENERGY_ICON, roundi(c[Stakes.ENERGY])]
	if c[Stakes.MATERIAL] > 0.0:
		return ["material", roundi(c[Stakes.MATERIAL])]
	return ["", null]


## An ActionButton for a map action: icon, label, cost, tooltip lines.
func _action(icon_id: String, label: String, cost_icon: String, cost: Variant, on_press: Callable,
		enabled: bool, lines: String) -> ActionButton:
	var b := ActionButton.make(icon_id, label, cost_icon, cost if not cost_icon.is_empty() else null)
	b.disabled = not enabled
	b.custom_minimum_size.y = maxf(b.custom_minimum_size.y, 44)
	b.pressed.connect(on_press)
	if not lines.is_empty():
		var numbers := "" if cost_icon.is_empty() else "Cost: %s %s" % [IconStat.format_value(cost), UiIcons.display_name(cost_icon)]
		UiTooltip.attach(b, label, lines, numbers, icon_id)
	return b


## An ActionButton for a Stakes use, with its cost.
func _use_action(use: String, icon_id: String, label: String, on_press: Callable, enabled: bool, lines: String) -> ActionButton:
	var c := _use_cost(use)
	return _action(icon_id, label, c[0], c[1], on_press, enabled, lines)


## A resource readout: its icon and stock (tooltip: what it buys), and the
## income per day beside it.
func _resource_stat(key: String, stock: int, per_day: int) -> Control:
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 6)
	# The day's gain is in the stat's tooltip too, for when the top bar is too
	# crowded to show it (_fit_top_bar).
	var stat := IconStat.make(ENERGY_ICON if key == Stakes.ENERGY else key, stock,
		"%s Gains %+d a day." % [resource_tooltip(key), per_day])
	row.add_child(stat)
	var rate := _text("+%d" % per_day, PixelTheme.font_size("body"), Palette.TEXT_DIM)
	rate.name = "Rate"
	row.add_child(rate)
	UiTooltip.attach(row.get_child(1), UiIcons.display_name(ENERGY_ICON if key == Stakes.ENERGY else key),
		"Gained each day from the territories you hold.", "+%d a day" % per_day, ENERGY_ICON if key == Stakes.ENERGY else key)
	row.set_meta("resource", key)
	return row


## The icon id of a map resource key.
func _resource_icon(key: String) -> String:
	return {MapRegion.POWER: "grid_power", MapRegion.ENERGY: ENERGY_ICON, MapRegion.MATERIAL: "material"}.get(key, key)


## What a resource buys, for its tooltip.
## TODO(decision: resource-uses): the uses follow the switchboard option.
func resource_tooltip(key: String) -> String:
	var stakes := campaign.stakes
	var names := {Stakes.USE_REINFORCE: "Reinforce", Stakes.USE_RETREAT: "Retreat",
		Stakes.USE_BREACH: "Breach", Stakes.USE_REPAIR: "Repair"}
	var uses := PackedStringArray()
	for use in Stakes.USES:
		var amount: float = stakes.cost(use)[key]
		if amount > 0.0:
			uses.append("%s %s" % [names[use], _number(amount)])
	var text := "From held regions and won fights. "
	text += ("Pays for %s." % ", ".join(uses)) if not uses.is_empty() else "Nothing spends it this run."
	text += " A lost battle takes %s." % _number(stakes.loss_cost[key])
	var cap := campaign.resource_cap(key)
	if cap < INF:
		var stock := campaign.state.energy if key == Stakes.ENERGY else campaign.state.material
		text += " Stored %d / %d: more is lost. The cap grows with regions held." % [floori(stock), floori(cap)]
	return text


## A number of time points as days: "1 day", "0.75 day".
func _points_text(points: int) -> String:
	var per_day := campaign.tuning.points_per_day
	if points % per_day == 0:
		return "%d day%s" % [points / per_day, "" if points / per_day == 1 else "s"]
	return "%s day" % str(snappedf(float(points) / per_day, 0.01))


## A number of time points as a bare number of days for a time icon: "1", "0.75".
func _days_number(points: int) -> String:
	return str(snappedf(float(points) / campaign.tuning.points_per_day, 0.01)).trim_suffix(".0")


## A row of icon stats in the message, above its buttons.
func _show_stat_row(stats: Array) -> void:
	_show_stat_rows([stats])


## Rows of icon stats in the message, above its buttons. A row may start
## with a String, shown as its small label.
func _show_stat_rows(rows: Array) -> void:
	_clear(_modal_options)
	_modal_options.visible = true
	var column := _rows(10)
	_modal_options.add_child(column)
	for stats: Array in rows:
		var row := HBoxContainer.new()
		row.add_theme_constant_override("separation", 18)
		column.add_child(row)
		for stat: Variant in stats:
			row.add_child(_text(stat, 11, Palette.TEXT_DIM) if stat is String else stat)


## The step between ATTACK and the fight: what the squad faces as icons, and
## the choice to fight, breach first, or call it off.
func show_pre_fight(region_id: String) -> void:
	if not campaign.can_attack(region_id):
		return
	var region := campaign.map.get_region(region_id)
	var stakes := campaign.stakes
	var buttons := [_action("action_attack", "Fight", "grid_power", roundi(campaign.attack_grid_cost(region_id)),
		_close_modal_then.bind(_on_attack.bind(region_id)), true,
		"Start the fight. Takes %s; a defeat costs more grid." % _points_text(campaign.tuning.attack_time))]
	if stakes.is_offered(Stakes.USE_BREACH) and stakes.breach_levels > 0:
		buttons.append(_use_action(Stakes.USE_BREACH, "action_breach", "Breach",
			_close_modal_then.bind(_on_attack.bind(region_id, true)), campaign.can_breach(region_id),
			"Fight at Defense %d instead of %d." % [campaign.attack_level(region_id, true), campaign.defense_of(region_id)]))
	buttons.append(_use_action(Stakes.USE_RETREAT, "action_retreat", "Retreat", _on_retreat.bind(region_id),
		campaign.can_retreat(region_id), "Call it off. Takes %s. No fight, no loss." % _points_text(stakes.retreat_attack_time)))
	_show_modal("ASSAULT", region.name, "", buttons)
	var level := campaign.defense_of(region_id)
	var defense := IconStat.make("defense_level", level, "%s. %s" % [
		campaign.tuning.defense_label(level), campaign.tuning.opposition(level)])
	var odds_label := _text(odds_text(region_id), 13, _odds_color(odds.label_for(campaign, region_id)))
	UiTooltip.attach(odds_label, "Your odds", "From auto-fights against this region's enemies." if odds.is_simulated()
		else "Squad strength against the Defense level.")
	var loss := stakes.loss_cost
	_show_stat_rows([
		[odds_label, defense, IconStat.make("time", _points_text(campaign.tuning.attack_time), "Time the attack takes."),
			IconStat.make("grid_power", "-%s%%" % _number(campaign.attack_grid_cost(region_id)),
				"Grid the attack takes if it wins; a defeat takes %s times that." % _number(campaign.tuning.defeat_grid_multiplier)),
			_losses_stat()],
		["DEFEAT COSTS", IconStat.make(ENERGY_ICON, "-%s" % _number(loss[Stakes.ENERGY]), "Energy a lost battle takes."),
			IconStat.make("material", "-%s" % _number(loss[Stakes.MATERIAL]), "Material a lost battle takes.")],
	])


func _on_retreat(region_id: String) -> void:
	_hide_modal()
	campaign.retreat(region_id)
	_check_forced()


func _on_repair() -> void:
	campaign.repair()


func _on_fast_forward() -> void:
	var summary := campaign.fast_forward()
	if summary.is_empty():
		return
	var body := ""
	match str(summary.stopped):
		"defense":
			body = "Stopped: a region is under attack."
		"attackable":
			body = "Stopped: a region is in range again."
	_show_message("FAST-FORWARD", "Day %d" % campaign.day(), body, _check_forced)
	_show_stat_row([
		IconStat.make("time", "+%s" % _number(summary.days), "Days that passed."),
		IconStat.make(ENERGY_ICON, "%+d" % roundi(summary.energy), "Energy gained, after auto-reinforcing."),
		IconStat.make("material", "%+d" % roundi(summary.material), "Material gained."),
		IconStat.make("grid_power", "%+d%%" % roundi(summary.grid), "Grid capacity change."),
		IconStat.make("action_reinforce", int(summary.reinforced), "Regions auto-reinforced at %s Pressure or more." % _number(campaign.stakes.ff_reinforce_at)),
	])


# --- Small builders -------------------------------------------------------------

func _text(text: String, font_size: int, color: Color) -> Label:
	var label := Label.new()
	label.text = text
	label.add_theme_font_size_override("font_size", _size(font_size))
	label.add_theme_color_override("font_color", color)
	label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	return label


## A description line; its keywords are links to their glossary boxes.
## The type scale step for a font size: 10 stays small (captions only, which
## UiStyle.caption marks), anything up to 24 is body size, larger is title
## (ui/README.md rule 13: nothing the player reads is smaller than body).
static func _size(font_size: int) -> int:
	if font_size <= 10:
		return PixelTheme.font_size("small")
	return PixelTheme.font_size("body") if font_size <= 24 else PixelTheme.font_size("title")


func _note(text: String, font_size := 13) -> RichTextLabel:
	var label := UiGlossary.rich(text, _size(font_size), Palette.TEXT_BODY, 100)
	label.name = "Note"
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


func _button(text: String, bg: Color, fg: Color, on_press: Callable) -> Button:
	var button := Button.new()
	button.text = text
	button.custom_minimum_size.y = 26
	button.add_theme_font_size_override("font_size", _size(13))
	_style_button(button, bg, fg, Color("#3a526a"))
	button.pressed.connect(on_press)
	return button


func _big_button(text: String, bg: Color, fg: Color, enabled: bool) -> Button:
	var button := Button.new()
	button.text = text
	button.custom_minimum_size.y = 48
	button.disabled = not enabled
	button.add_theme_font_size_override("font_size", _size(16))
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


func _odds_color(label: String) -> Color:
	if odds.is_simulated():
		var index := odds.estimator.tuning.band_index(label)
		return Palette.ODDS[mini(index, Palette.ODDS.size() - 1)] if index >= 0 else Palette.TEXT_DIM
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
