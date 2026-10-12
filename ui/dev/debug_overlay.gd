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
## Intents: each enemy's current plan from IntentPlanner (fight/intent/). A
## scene that already tracks intents can set `intent_source` to a
## Callable(fight: Fight, unit: Combatant) -> String to show its own instead.
##
## Personality: each enemy's leans as the intent planner weighs them (the
## larger end of each spectrum and its lean, -1..1 scaled to 0..1, for
## example "agg .60 sol .40 rea .60"; a spectrum its generation does not weigh
## is in brackets), and each squad bot's tag.

const Palette := preload("res://ui/dev/dev_palette.gd")
const COLUMNS: Array[String] = ["Unit", "HP", "ATK", "DEF", "SPD", "ELA", "BAT", "Energy", "Gauge", "State", "Personality", "Intent"]
const NO_INTENT := "—"

var fight: Fight:
	set(value):
		fight = value
		_built_for = []
		refresh()
## Callable(fight, unit) -> String. Defaults to planned_intent() with an IntentPlanner.
var intent_source: Callable
## Callable(fight, unit) -> String. Defaults to the planner's personality for
## enemies (personality_text()) and the squad member's tag for bots.
var personality_source: Callable
var toggle_key := KEY_F3
var timeline_count: int
var refresh_seconds: float

var _header: Label
var _grid: GridContainer
var _timeline: Label
var _planner: IntentPlanner
## Combatant ids the grid rows were built for.
var _built_for: Array = []
var _cells: Dictionary = {}
var _since_refresh := 0.0


func _init() -> void:
	var settings := DevToolSettings.load_default()
	timeline_count = settings.overlay_timeline_count
	refresh_seconds = settings.overlay_refresh_seconds
	name = "DebugOverlay"
	_planner = IntentPlanner.new()
	intent_source = func(f: Fight, unit: Combatant) -> String: return planned_intent(_planner, f, unit)
	personality_source = func(f: Fight, unit: Combatant) -> String: return unit_personality(_planner, f, unit)
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
	var snap := snapshot(fight, timeline_count, intent_source, personality_source)
	_header.text = snap.header
	var ids: Array = snap.units.map(func(u: Dictionary) -> String: return u.id)
	if ids != _built_for:
		_rebuild_rows(snap.units)
		_built_for = ids
	for u: Dictionary in snap.units:
		var row: Array = _cells[u.id]
		var values: Array = [u.name, u.hp_text, u.attack, u.defense, u.speed, u.elasticity, u.battery,
			u.energy_text, u.gauge_text, u.state, u.personality, u.intent]
		var color: Color = Palette.DOWN if not u.alive else (Palette.PLAYER if u.side == "player" else Palette.ENEMY)
		for i in values.size():
			var cell: Label = row[i]
			cell.text = str(values[i])
			cell.add_theme_color_override("font_color", color if i == 0 or not u.alive else Palette.TEXT)
	_timeline.text = "Next: " + ("  →  ".join(snap.timeline) if not snap.timeline.is_empty() else "nothing")


## Everything the overlay shows, as plain data. Pure: reads the fight only.
static func snapshot(p_fight: Fight, count: int, p_intent_source: Callable = Callable(),
		p_personality_source: Callable = Callable()) -> Dictionary:
	if p_fight == null:
		return {"header": "Debug · no fight", "units": [], "timeline": []}
	var threshold := p_fight.tuning.turn_threshold()
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
			"personality": str(p_personality_source.call(p_fight, c)) if p_personality_source.is_valid() else "",
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


## `unit`'s planned action as text, such as "attack Heavy Strike → Torque (7)".
static func planned_intent(planner: IntentPlanner, p_fight: Fight, unit: Combatant) -> String:
	var intent := planner.plan(p_fight, unit)
	if intent == null:
		return NO_INTENT
	var skill := p_fight.tuning.skill(intent.skill_id())
	var target := p_fight.combatant(intent.target_id())
	return "%s %s → %s (%d)" % [intent.kind_name(), skill.display_name if skill != null else intent.skill_id(),
		target.display_name if target != null else intent.target_id(), intent.amount]


## `unit`'s personality as the overlay shows it: the planner's leans for an
## enemy, the squad summary's tag for a bot.
static func unit_personality(planner: IntentPlanner, p_fight: Fight, unit: Combatant) -> String:
	if unit.side == Combatant.Side.ENEMY:
		return personality_text(planner.personality_of(unit), planner.weights.lean_floor)
	for m in p_fight.request.squad:
		if m.id == unit.id:
			return m.personality_tag
	return ""


## "agg .60 sol .40 [rea .60]": per spectrum, the larger end's first three
## letters and its lean (Personality.get_lean, as a size); brackets mark a
## spectrum the planner does not weigh for this generation; "bal" a tie.
static func personality_text(p: Personality, lean_floor: float) -> String:
	if p == null:
		return ""
	var parts := PackedStringArray()
	for scale in Personality.SCALE_COUNT:
		var lean := p.get_lean(scale, lean_floor)
		var end: String = "bal" if is_zero_approx(lean) else Personality.POLES[scale][0 if lean < 0.0 else 1].substr(0, 3)
		var text := "%s %s" % [end, ("%.2f" % absf(lean)).trim_prefix("0")]
		parts.append(text if p.is_active(scale) else "[%s]" % text)
	return " ".join(parts)


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
