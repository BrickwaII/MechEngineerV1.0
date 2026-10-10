class_name DebugOverlay
extends PanelContainer
## Developer overlay for a Fight: every unit's stats, hp, energy and gauge, the
## upcoming timeline, and each unit's current intent. Read-only: it never
## changes the fight. Standalone, so any scene holding a Fight can add one:
##
##   var overlay := DebugOverlay.new()
##   add_child(overlay)
##   overlay.fight = my_fight        # refreshes itself while visible
##
## Toggle it with F3 (the "toggle_key" property).
##
## Intents: fight/intent/ is not on main yet. Set `intent_source` to a
## Callable(fight: Fight, unit: Combatant) -> String to fill the Intent column;
## until then it shows a dash.

const Palette := preload("res://ui/dev/dev_palette.gd")
const COLUMNS: Array[String] = ["Unit", "HP", "ATK", "DEF", "SPD", "ELA", "BAT", "Energy", "Gauge", "State", "Intent"]
const NO_INTENT := "—"

var fight: Fight:
	set(value):
		fight = value
		_built_for = []
		refresh()
## Callable(fight, unit) -> String. Empty until an intent module exists.
var intent_source: Callable
var toggle_key := KEY_F3
var timeline_count: int
var refresh_seconds: float

var _header: Label
var _grid: GridContainer
var _timeline: Label
var _intent_note: Label
## Combatant ids the grid rows were built for.
var _built_for: Array = []
var _cells: Dictionary = {}
var _since_refresh := 0.0


func _init() -> void:
	var settings := DevToolSettings.load_default()
	timeline_count = settings.overlay_timeline_count
	refresh_seconds = settings.overlay_refresh_seconds
	name = "DebugOverlay"
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	var style := StyleBoxFlat.new()
	style.bg_color = Palette.OVERLAY
	style.border_color = Palette.RULE
	style.set_border_width_all(1)
	style.set_content_margin_all(10)
	add_theme_stylebox_override("panel", style)
	var box := VBoxContainer.new()
	box.add_theme_constant_override("separation", 6)
	add_child(box)
	_header = _label("", Palette.ACCENT)
	box.add_child(_header)
	_grid = GridContainer.new()
	_grid.columns = COLUMNS.size()
	_grid.add_theme_constant_override("h_separation", 14)
	_grid.add_theme_constant_override("v_separation", 2)
	box.add_child(_grid)
	_timeline = _label("", Palette.TEXT)
	_timeline.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_timeline.custom_minimum_size.x = 560
	box.add_child(_timeline)
	_intent_note = _label("Intent: no intent module on main yet (set intent_source to fill this column)", Palette.TEXT_DIM)
	box.add_child(_intent_note)


func _process(delta: float) -> void:
	if not visible:
		return
	_since_refresh += delta
	if _since_refresh >= refresh_seconds:
		_since_refresh = 0.0
		refresh()


func _unhandled_key_input(event: InputEvent) -> void:
	var key := event as InputEventKey
	if key != null and key.pressed and not key.echo and key.keycode == toggle_key:
		visible = not visible
		refresh()
		get_viewport().set_input_as_handled()


## Redraws from the fight now. Called on its own every refresh_seconds.
func refresh() -> void:
	if _header == null:
		return
	var snap := snapshot(fight, timeline_count, intent_source)
	_header.text = snap.header
	var ids: Array = snap.units.map(func(u: Dictionary) -> String: return u.id)
	if ids != _built_for:
		_rebuild_rows(snap.units)
		_built_for = ids
	for u: Dictionary in snap.units:
		var row: Array = _cells[u.id]
		var values: Array = [u.name, u.hp_text, u.attack, u.defense, u.speed, u.elasticity, u.battery,
			u.energy_text, u.gauge_text, u.state, u.intent]
		var color: Color = Palette.DOWN if not u.alive else (Palette.PLAYER if u.side == "player" else Palette.ENEMY)
		for i in values.size():
			var cell: Label = row[i]
			cell.text = str(values[i])
			cell.add_theme_color_override("font_color", color if i == 0 or not u.alive else Palette.TEXT)
	_timeline.text = "Next: " + ("  →  ".join(snap.timeline) if not snap.timeline.is_empty() else "nothing")
	_intent_note.visible = not intent_source.is_valid()


## Everything the overlay shows, as plain data. Pure: reads the fight only.
static func snapshot(p_fight: Fight, count: int, p_intent_source: Callable = Callable()) -> Dictionary:
	if p_fight == null:
		return {"header": "Debug · no fight", "units": [], "timeline": []}
	var threshold := p_fight.tuning.action_threshold
	var pending := p_fight.pending_actor
	var state_text := "over: %s" % ("victory" if p_fight.outcome == FightResult.Outcome.VICTORY else "defeat") \
		if p_fight.is_over() else ("waiting on %s" % pending.display_name if pending != null else "running")
	var units := []
	for c in p_fight.combatants:
		var state := "charging"
		if not c.is_alive():
			state = "down"
		elif c == pending:
			state = "acting"
		elif c.is_waiting():
			state = "waiting for %.0f" % (float(c.wait_target_milli) / Combatant.MILLI)
		var intent := NO_INTENT
		if p_intent_source.is_valid() and c.is_alive() and c.side == Combatant.Side.ENEMY:
			intent = str(p_intent_source.call(p_fight, c))
		units.append({
			"id": c.id,
			"name": c.display_name,
			"side": "player" if c.side == Combatant.Side.PLAYER else "enemy",
			"alive": c.is_alive(),
			"hp_text": "%d/%d" % [c.hp, c.max_hp],
			"attack": c.stats.attack,
			"defense": c.stats.defense,
			"speed": c.stats.speed,
			"elasticity": c.stats.elasticity,
			"battery": c.stats.battery_capacity,
			"energy_text": "%.1f/%d" % [float(c.energy_milli) / Combatant.MILLI, c.stats.battery_capacity],
			"gauge_text": "%d/%d" % [c.gauge, threshold],
			"state": state,
			"intent": intent,
		})
	var timeline := []
	if not p_fight.is_over():
		for entry in p_fight.upcoming(count):
			timeline.append("%s @%d%s" % [entry.display_name, entry.tick, " (wait)" if entry.ends_wait else ""])
	return {
		"header": "Debug · tick %d · action %d · %s" % [p_fight.timeline.current_tick, p_fight.action_count, state_text],
		"units": units,
		"timeline": timeline,
	}


func _rebuild_rows(units: Array) -> void:
	for child in _grid.get_children():
		_grid.remove_child(child)
		child.queue_free()
	_cells.clear()
	for title in COLUMNS:
		_grid.add_child(_label(title, Palette.TEXT_DIM))
	for u: Dictionary in units:
		var row := []
		for i in COLUMNS.size():
			var cell := _label("", Palette.TEXT)
			_grid.add_child(cell)
			row.append(cell)
		_cells[u.id] = row


static func _label(text: String, color: Color) -> Label:
	var l := Label.new()
	l.text = text
	l.mouse_filter = Control.MOUSE_FILTER_IGNORE
	l.add_theme_color_override("font_color", color)
	l.add_theme_font_size_override("font_size", 13)
	return l
