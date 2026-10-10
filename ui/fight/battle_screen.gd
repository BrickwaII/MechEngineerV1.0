class_name BattleScreen
extends Control
## The battle screen: timeline bar on top, bots on the left, enemies on the
## right, the fight log between them, and the command bar along the bottom.
##
## Every input becomes a FightCommand for FightCommandHandler; this script only
## shows the fight and maps the mouse:
##   left-click a bot      select bot (look at it; only the ready bot acts)
##   click a skill button  select skill
##   left-click an enemy   select target (resolves the action)
##   Wait button           wait (for the selected skill, else the next one)
##   Cancel / right-click  cancel
##
## Call setup() before adding the screen to the tree.

const Palette := preload("res://ui/fight/fight_palette.gd")
const FightTheme := preload("res://ui/fight/fight_theme.gd")
const UnitPanel := preload("res://ui/fight/unit_panel.gd")
const TimelineBar := preload("res://ui/fight/timeline_bar.gd")

const LOG_LINES_SHOWN := 14

## Emitted once, when the fight is over.
signal fight_finished(result: FightResult)

var tuning: FightScreenTuning
var handler: FightCommandHandler
var fight: Fight
## Pause before each enemy action. Tests set 0 to play enemies at once.
var enemy_turn_delay := 0.0

var timeline_bar: TimelineBar
var unit_panels: Dictionary[String, UnitPanel] = {}
var skill_buttons: Dictionary[String, Button] = {}
var wait_button: Button
var cancel_button: Button
var prompt_label: Label
var message_label: Label
var log_label: Label
## Space for the choice preview. Placeholder until fight/preview/ is wired in.
## TODO(m4-telegraph): show the preview of the hovered or selected choice here.
var preview_area: PanelContainer
var header_label: Label

var _enemy_clock := 0.0
var _finished_sent := false


## Builds the fight. `p_tuning` defaults to data/ui/fight_screen.json; the
## combat tuning and enemy table default to data/combat/.
func setup(request: FightRequest, fight_seed: int, p_tuning: FightScreenTuning = null,
		combat_tuning: CombatTuning = null, enemy_table: EnemyTable = null) -> void:
	tuning = p_tuning if p_tuning != null else FightScreenTuning.load_default()
	enemy_turn_delay = tuning.enemy_turn_delay_seconds
	fight = Fight.new(request, fight_seed, combat_tuning, enemy_table)
	handler = FightCommandHandler.new(fight, null, false)
	handler.changed.connect(refresh)
	handler.action_resolved.connect(_on_action_resolved)
	handler.fight_over.connect(_on_fight_over)


func _ready() -> void:
	assert(handler != null, "BattleScreen.setup() must be called before _ready")
	set_anchors_preset(Control.PRESET_FULL_RECT)
	theme = FightTheme.make()
	_build_layout()
	refresh()
	if fight.is_over():
		_on_fight_over.call_deferred(fight.result())


func _process(delta: float) -> void:
	if not handler.is_enemy_turn():
		_enemy_clock = 0.0
		return
	_enemy_clock += delta
	if _enemy_clock >= enemy_turn_delay:
		_enemy_clock = 0.0
		handler.resolve_enemy_turn()


## Applies one command and shows why it was refused, if it was.
func send(command: FightCommand) -> String:
	var problem := handler.apply(command)
	message_label.text = problem
	return problem


func _gui_input(event: InputEvent) -> void:
	var mouse := event as InputEventMouseButton
	if mouse != null and mouse.pressed and mouse.button_index == MOUSE_BUTTON_RIGHT:
		send(FightCommand.cancel())
		accept_event()


## A click on a unit panel: bots are selected, enemies are targeted, and a
## right-click anywhere cancels.
func on_unit_clicked(unit_id: String, button_index: MouseButton) -> void:
	if button_index == MOUSE_BUTTON_RIGHT:
		send(FightCommand.cancel())
		return
	if button_index != MOUSE_BUTTON_LEFT:
		return
	var unit := fight.combatant(unit_id)
	if unit == null:
		return
	if unit.side == Combatant.Side.PLAYER:
		send(FightCommand.select_bot(unit_id))
	else:
		send(FightCommand.select_target(unit_id))


func on_skill_pressed(skill_id: String) -> void:
	send(FightCommand.select_skill(skill_id))


func on_wait_pressed() -> void:
	send(FightCommand.wait())


func on_cancel_pressed() -> void:
	send(FightCommand.cancel())


func refresh() -> void:
	if timeline_bar == null:
		return
	var actor := handler.actor()
	for c in fight.combatants:
		unit_panels[c.id].refresh(c, _highlight_for(c))
	var upcoming: Array[TimelineEntry] = []
	if not fight.is_over():
		upcoming = fight.upcoming(tuning.timeline_length)
	timeline_bar.refresh(upcoming)
	_refresh_commands()
	var lines := fight.log_lines
	log_label.text = "\n".join(lines.slice(maxi(0, lines.size() - LOG_LINES_SHOWN)))
	if fight.is_over():
		prompt_label.text = "VICTORY" if fight.outcome == FightResult.Outcome.VICTORY else "DEFEAT"
	elif handler.is_enemy_turn():
		prompt_label.text = "%s is acting..." % actor.display_name
	elif handler.selected_bot_id != actor.id:
		prompt_label.text = "%s is not ready. %s acts now." % [handler.selected_bot().display_name, actor.display_name]
	elif handler.is_choosing_target():
		prompt_label.text = "%s: %s. Click an enemy, or Cancel." % [
			actor.display_name, fight.tuning.skill(handler.selected_skill_id).display_name]
	else:
		prompt_label.text = "%s is ready. Choose a skill, or Wait." % actor.display_name


func _highlight_for(c: Combatant) -> UnitPanel.Highlight:
	if not c.is_alive() or fight.is_over():
		return UnitPanel.Highlight.NONE
	if handler.is_choosing_target() and handler.target_problem(c.id).is_empty():
		return UnitPanel.Highlight.TARGETABLE
	if c == handler.actor():
		return UnitPanel.Highlight.ACTIVE
	if c.id == handler.selected_bot_id:
		return UnitPanel.Highlight.SELECTED
	return UnitPanel.Highlight.NONE


func _refresh_commands() -> void:
	var can_act := handler.is_player_turn() and handler.selected_bot_id == handler.actor().id
	for skill_id in skill_buttons:
		var button := skill_buttons[skill_id]
		var has_it := can_act and handler.actor().has_skill(skill_id)
		button.disabled = not has_it or not handler.skill_problem(skill_id).is_empty()
		button.button_pressed = skill_id == handler.selected_skill_id
		button.tooltip_text = handler.skill_problem(skill_id) if has_it else ""
	var wait_skill := handler.default_wait_skill() if can_act else ""
	wait_button.disabled = wait_skill.is_empty()
	wait_button.text = "WAIT" if wait_skill.is_empty() else "WAIT for %s" % fight.tuning.skill(wait_skill).display_name
	cancel_button.disabled = not can_act or not handler.is_choosing_target()


func _on_action_resolved(_actor_id: String, _tag: String) -> void:
	message_label.text = ""


func _on_fight_over(result: FightResult) -> void:
	if _finished_sent:
		return
	_finished_sent = true
	refresh()
	fight_finished.emit(result)


func _build_layout() -> void:
	var back := ColorRect.new()
	back.color = Palette.BACKGROUND
	back.set_anchors_preset(Control.PRESET_FULL_RECT)
	back.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(back)

	var root := VBoxContainer.new()
	root.set_anchors_preset(Control.PRESET_FULL_RECT)
	root.offset_left = 16
	root.offset_top = 12
	root.offset_right = -16
	root.offset_bottom = -12
	root.add_theme_constant_override("separation", 10)
	root.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(root)

	var request := fight.request
	header_label = _label(root, "%s  -  %s  -  DEFENSE %d" % [
		FightRequest.Kind.keys()[request.kind], request.territory_id.capitalize().to_upper(),
		request.defense_level], 18, Palette.TEXT_BRIGHT)
	timeline_bar = TimelineBar.new()
	timeline_bar.name = "TimelineBar"
	root.add_child(timeline_bar)

	var field := HBoxContainer.new()
	field.size_flags_vertical = Control.SIZE_EXPAND_FILL
	field.add_theme_constant_override("separation", 16)
	field.mouse_filter = Control.MOUSE_FILTER_IGNORE
	root.add_child(field)
	var bots := _column(field, "SQUAD")
	var middle := VBoxContainer.new()
	middle.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	middle.mouse_filter = Control.MOUSE_FILTER_IGNORE
	field.add_child(middle)
	_label(middle, "LOG", 12, Palette.TEXT_DIM)
	log_label = _label(middle, "", 11, Palette.TEXT_DIM)
	log_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	log_label.size_flags_vertical = Control.SIZE_EXPAND_FILL
	log_label.clip_text = true
	var enemies := _column(field, "ENEMIES")
	for c in fight.combatants:
		var panel := UnitPanel.new()
		(enemies if c.side == Combatant.Side.ENEMY else bots).add_child(panel)
		panel.setup(c)
		panel.clicked.connect(on_unit_clicked)
		unit_panels[c.id] = panel

	var bar := PanelContainer.new()
	var bar_style := StyleBoxFlat.new()
	bar_style.bg_color = Palette.PANEL
	bar_style.set_content_margin_all(10)
	bar.add_theme_stylebox_override("panel", bar_style)
	root.add_child(bar)
	var bar_row := HBoxContainer.new()
	bar_row.add_theme_constant_override("separation", 16)
	bar.add_child(bar_row)
	var commands := VBoxContainer.new()
	commands.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	bar_row.add_child(commands)
	prompt_label = _label(commands, "", 15, Palette.TEXT_BRIGHT)
	var buttons := HBoxContainer.new()
	buttons.add_theme_constant_override("separation", 8)
	commands.add_child(buttons)
	for skill_id in _all_player_skills():
		var skill := fight.tuning.skill(skill_id)
		var button := _button(buttons, "%s  [%d]" % [skill.display_name.to_upper(), skill.energy_cost])
		button.name = "Skill_%s" % skill_id
		button.toggle_mode = true
		button.pressed.connect(on_skill_pressed.bind(skill_id))
		skill_buttons[skill_id] = button
	wait_button = _button(buttons, "WAIT")
	wait_button.name = "WaitButton"
	wait_button.pressed.connect(on_wait_pressed)
	cancel_button = _button(buttons, "CANCEL")
	cancel_button.name = "CancelButton"
	cancel_button.pressed.connect(on_cancel_pressed)
	message_label = _label(commands, "", 12, Palette.TARGETABLE)

	preview_area = PanelContainer.new()
	preview_area.name = "PreviewArea"
	preview_area.custom_minimum_size = Vector2(300, 0)
	var preview_style := StyleBoxFlat.new()
	preview_style.bg_color = Palette.PANEL_RAISED
	preview_style.border_color = Palette.RULE
	preview_style.set_border_width_all(1)
	preview_style.set_content_margin_all(8)
	preview_area.add_theme_stylebox_override("panel", preview_style)
	bar_row.add_child(preview_area)
	_label(preview_area, "PREVIEW\n(choice preview goes here)", 12, Palette.TEXT_DIM)


## Skill ids any bot in the fight has, in the tuning's menu order.
func _all_player_skills() -> Array[String]:
	var ids: Array[String] = []
	for id in fight.tuning.player_skills:
		ids.append(id)
	for c in fight.living(Combatant.Side.PLAYER):
		for id in c.skill_ids:
			if not id in ids:
				ids.append(id)
	return ids


func _column(parent: Node, title: String) -> VBoxContainer:
	var col := VBoxContainer.new()
	col.add_theme_constant_override("separation", 8)
	col.mouse_filter = Control.MOUSE_FILTER_IGNORE
	parent.add_child(col)
	_label(col, title, 12, Palette.TEXT_DIM)
	return col


static func _label(parent: Node, text: String, font_size: int, color: Color) -> Label:
	var label := Label.new()
	label.text = text
	label.add_theme_font_size_override("font_size", font_size)
	label.add_theme_color_override("font_color", color)
	label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	parent.add_child(label)
	return label


static func _button(parent: Node, text: String) -> Button:
	var button := Button.new()
	button.text = text
	button.focus_mode = Control.FOCUS_NONE
	button.custom_minimum_size = Vector2(0, 34)
	parent.add_child(button)
	return button
