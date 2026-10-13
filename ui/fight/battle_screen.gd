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
##   Wait ticks box        only with the d-wait-length "exact" variant: wait
##                         exactly this many ticks (0 waits until affordable)
##   Cancel / right-click  cancel
##   point at an enemy     preview the selected skill on it (changes nothing)
##   point at WAIT         preview the wait (order and intents after it)
##   point at any unit     light its slots on the NEXT bar; rest for its
##                         full stats, skills and statuses (detail card)
##
## Enemies telegraph their intent and act by it (IntentFightPolicy), so what
## each enemy's arrow says is what that enemy does next. FightTelegraph holds
## the intents, the revision marks and the choice preview; the preview is
## also drawn on the units (targets marked, the predicted hp loss blinking on
## their meters, enemies whose plan would change marked).
##
## Readability (R1-B): the numbers ride on the arrows. Each enemy arrow
## carries a badge with what it would do (damage, heal, guard) and a skull when
## it would down its target; with a skill selected and a target under the
## pointer, the bot's own arrow is drawn with its badge, and enemy arrows show
## what they would become after the choice (changed ones struck through to
## the new value). The selected skill's energy cost blinks on the bot's energy
## bar; a choice that changes the turn order previews the new order on the
## NEXT bar. Every number comes from fight/preview (BattleReadout), which
## tests/fight/preview/preview_matches_resolution_test.gd holds to what the
## fight resolves. Unit cards show ATK, DEF, SPD and BAT as icon chips.
##
## Presentation (M7): every unit is an animated sprite (BattleArt picks the
## look and tier), and BattlePresenter plays each action as it resolves. The
## fight never waits for animation; only the next enemy turn waits for the
## current one to finish playing. When the fight ends, the victory or defeat
## moment plays (OutcomeBanner) before fight_finished.
##
## A host may put a Home button at the right of the header
## (show_home_button()); RunFlow asks before leaving the battle.
##
## Call setup() before adding the screen to the tree.

const UnitPanel := preload("res://ui/fight/unit_panel.gd")
const TimelineBar := preload("res://ui/fight/timeline_bar.gd")
const IntentArrows := preload("res://ui/fight/intent_arrows.gd")
const OutcomeBanner := preload("res://ui/fight/outcome_banner.gd")

const LOG_LINES_SHOWN := 8
## Enemy cards go two to a row past this many enemies.
const ENEMIES_PER_COLUMN := 3

## Emitted once, when the fight is over.
signal fight_finished(result: FightResult)
## Every command sent, after it was applied: `problem` is "" or why it was refused.
signal command_sent(command: FightCommand, problem: String)

var tuning: FightScreenTuning
var handler: FightCommandHandler
var fight: Fight
var telegraph: FightTelegraph
## Pause before each enemy action. Tests set 0 to play enemies at once.
var enemy_turn_delay := 0.0

var timeline_bar: TimelineBar
var unit_panels: Dictionary[String, UnitPanel] = {}
var skill_buttons: Dictionary[String, SkillCard] = {}
var wait_button: ActionButton
## Exact wait length; shown only when the d-wait-length variant is "exact".
var wait_ticks_box: SpinBox
var cancel_button: ActionButton
var prompt_label: Label
var message_label: Label
var log_label: Label
## Shows and hides the log; the log starts collapsed (ui/README.md rule 5).
var log_toggle: Button
## The choice preview: what the selected skill would do to the target under
## the pointer.
var preview_area: PanelContainer
var preview_label: Label
## The unit under the pointer, or "".
var hovered_id := ""
## True while the pointer rests on the WAIT button (the wait is previewed).
var wait_hovered := false
## The preview shown now, or null. Read-only; for tests.
var shown_preview: ChoicePreview
var header_label: Label
## The fight's defense level as an icon and number in the header.
var defense_stat: IconStat
## Returns the drafted Bot for a squad member id, or null (tier rule input).
## Optional; without it tiers come from what the fight knows.
var bot_source: Callable
## The player's variant choices (the tier-rule switch is read when the fight starts).
var variants_path := FightVariants.USER_PATH
var tier_rule: BattleTierRule
var presenter: BattlePresenter
var arrows: IntentArrows
var outcome_banner: OutcomeBanner
## The Home button at the right of the header, once show_home_button() made it.
var home_button: ActionButton
var _header: HBoxContainer
var field_root: Control
var shake: ScreenShake
var settings: GameSettings

var _enemy_clock := 0.0
var _finished_sent := false
## Fight.action_count the intents were last refreshed at.
var _planned_at := 0
## The unit that took the latest action, or "".
var _last_actor_id := ""
## Events of the action resolving now, handed to the presenter when it ends.
var _pending_events: Array[FightEvent] = []
## Unit id -> its energy after its last action, for the energy gain popup.
var _energy_after_turn: Dictionary[String, int] = {}
var _announced_actor := ""
var _outcome_started := false


## Builds the fight. `p_tuning` defaults to data/ui/fight_screen.json; the
## combat tuning and enemy table default to data/combat/.
func setup(request: FightRequest, fight_seed: int, p_tuning: FightScreenTuning = null,
		combat_tuning: CombatTuning = null, enemy_table: EnemyTable = null) -> void:
	tuning = p_tuning if p_tuning != null else FightScreenTuning.load_default()
	enemy_turn_delay = tuning.enemy_turn_delay_seconds
	fight = Fight.new(request, fight_seed, combat_tuning, enemy_table)
	fight.event_raised.connect(_on_event_raised)
	var planner := IntentPlanner.new()
	handler = FightCommandHandler.new(fight, IntentFightPolicy.new(planner), false)
	# Planned once time has run to the first decision, as after every action.
	telegraph = FightTelegraph.new(fight, planner)
	telegraph.preview.order_length = tuning.timeline_length
	_planned_at = fight.action_count
	handler.changed.connect(refresh)
	handler.action_resolved.connect(_on_action_resolved)
	handler.fight_over.connect(_on_fight_over)


func _ready() -> void:
	assert(handler != null, "BattleScreen.setup() must be called before _ready")
	set_anchors_preset(Control.PRESET_FULL_RECT)
	theme = PixelTheme.theme()
	if tier_rule == null:
		tier_rule = BattleTierRule.load_active(variants_path)
	_build_layout()
	refresh()
	if fight.is_over():
		_on_fight_over.call_deferred(fight.result())


func _process(delta: float) -> void:
	# The next enemy waits for the current action to finish playing.
	if presenter != null and presenter.is_busy():
		_enemy_clock = 0.0
		return
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
	command_sent.emit(command, problem)
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
	# A bot is a target while an ally skill (Patch Up, Shield Ally) waits for one.
	if unit.side == Combatant.Side.PLAYER and not (
			handler.is_choosing_target() and handler.target_problem(unit_id).is_empty()):
		send(FightCommand.select_bot(unit_id))
	else:
		send(FightCommand.select_target(unit_id))


func on_skill_pressed(skill_id: String) -> void:
	send(FightCommand.select_skill(skill_id))


func on_wait_pressed() -> void:
	wait_hovered = false
	send(FightCommand.wait("", exact_wait_ticks()))


## Pointing at WAIT previews the wait: the order and intents after it.
func on_wait_hovered(inside: bool) -> void:
	wait_hovered = inside
	refresh()


## The exact wait the ticks box asks for, or 0 to wait until affordable.
func exact_wait_ticks() -> int:
	return int(wait_ticks_box.value) if wait_ticks_box.visible else 0


func on_cancel_pressed() -> void:
	send(FightCommand.cancel())


## Shows the selected skill's preview on `unit_id`, as pointing at it does.
## "" clears it.
func preview_target(unit_id: String) -> void:
	hovered_id = unit_id
	refresh()


func on_unit_hovered(unit_id: String, inside: bool) -> void:
	if inside:
		preview_target(unit_id)
	elif hovered_id == unit_id:
		preview_target("")


## The action being previewed: the selected skill on the unit under the
## pointer. Null when there is none or it is not allowed.
func previewed_action() -> FightAction:
	if wait_hovered and handler.is_player_turn() and handler.selected_bot_id == handler.actor().id:
		var wait_skill := handler.default_wait_skill()
		var ticks := exact_wait_ticks()
		if ticks > 0:
			return FightAction.wait_exact(wait_skill if not wait_skill.is_empty() else handler.actor().skill_ids[0], ticks)
		return FightAction.wait_for(wait_skill) if not wait_skill.is_empty() else null
	if not handler.is_player_turn() or not handler.is_choosing_target() or hovered_id.is_empty():
		return null
	if handler.selected_bot_id != handler.actor().id or not handler.target_problem(hovered_id).is_empty():
		return null
	return FightAction.use(handler.selected_skill_id, hovered_id)


func refresh() -> void:
	_sync_intents()
	if timeline_bar == null:
		return
	var actor := handler.actor()
	var action := previewed_action()
	shown_preview = telegraph.preview_choice(fight, action) if action != null else null
	for c in fight.combatants:
		var panel := unit_panels[c.id]
		panel.refresh(c, _highlight_for(c), presenter.shown_hp(c.id, c.hp), presenter.shown_energy(c.id, c.energy()))
		var intent := telegraph.intent_of(c.id) if c.is_alive() else null
		panel.show_intent(telegraph.tag_of(c.id),
			telegraph.intent_text(fight, c.id) if c.is_alive() else "", telegraph.change_text(c.id), _intent_kind(intent))
		panel.show_preview(_panel_preview(c.id))
		panel.show_meter_preview(shown_preview.effect_on(c.id) if shown_preview != null else null,
			shown_preview != null and shown_preview.change_for(c.id) != null and not _goes_down(c.id))
		panel.show_energy_preview(_energy_preview_for(c))
	var arrow_dicts := arrow_list(action)
	arrows.set_arrows(arrow_dicts, _arrow_focus())
	_refresh_intent_chips(arrow_dicts)
	_refresh_preview_box(action)
	var upcoming: Array[TimelineEntry] = []
	if not fight.is_over():
		upcoming = fight.upcoming(tuning.timeline_length)
	var order := BattleReadout.order_with_choice(upcoming, shown_preview)
	var order_changes := not order.is_empty() and not BattleReadout.same_order(order, upcoming)
	timeline_bar.refresh(order if order_changes else upcoming, order_changes)
	timeline_bar.set_highlight(hovered_id if fight.combatant(hovered_id) != null else "")
	_refresh_commands()
	var lines := fight.log_lines
	log_label.text = "\n".join(lines.slice(maxi(0, lines.size() - LOG_LINES_SHOWN)))
	log_toggle.text = "%s Log (%d)" % ["v" if log_label.visible else ">", lines.size()]
	if fight.is_over():
		prompt_label.text = "VICTORY" if fight.outcome == FightResult.Outcome.VICTORY else "DEFEAT"
	elif actor == null:
		pass
	elif handler.is_enemy_turn():
		prompt_label.text = "%s is acting..." % actor.display_name
	elif handler.selected_bot_id != actor.id:
		prompt_label.text = "%s is not ready. %s acts now." % [handler.selected_bot().display_name, actor.display_name]
	elif handler.is_choosing_target():
		var chosen := actor.skill(handler.selected_skill_id)
		prompt_label.text = "%s: %s. Click %s, or Cancel." % [
			actor.display_name, chosen.display_name, "an enemy" if chosen.targets_opponents() else "a bot"]
	else:
		prompt_label.text = "%s is ready. Choose a skill, or Wait." % actor.display_name
	_announce_turn(actor)


## Each enemy's intent as an icon and number on its card, from the arrows
## drawn now (the arrow's badge carries the number).
func _refresh_intent_chips(arrow_dicts: Array[Dictionary]) -> void:
	var badges := {}
	for a in arrow_dicts:
		if a.player or a.ghost or a.badge == null:
			continue
		badges[a.from] = a.badge
	for id: String in unit_panels:
		var panel := unit_panels[id]
		if not panel.is_enemy:
			continue
		var badge: ArrowBadge = badges.get(id)
		panel.show_intent_chip(panel.intent_kind if badge == null else badge.kind, "" if badge == null else badge.text())


## Every arrow to draw, with its badge: the enemy intents (as they would
## stand after the previewed choice, if there is one, with the ones it
## replaces as ghosts) and the pending bot's own arrows for that choice.
## TODO(decision: d-telegraph-timing): enemy arrows show each enemy's plan
## at the current decision (as the M4 telegraph always did), not the plan it
## will make at its own turn, which time and other actions may change. The
## next enemy to act is exact; while a choice is previewed, every arrow shows
## the plan at the next decision. Default kept: plan at the current decision.
func arrow_list(action: FightAction) -> Array[Dictionary]:
	var rules := telegraph.preview.rules
	var now := BattleReadout.intent_badges(fight, telegraph.tracker.current, rules)
	var out: Array[Dictionary] = []
	var p := shown_preview if shown_preview != null and shown_preview.is_allowed() else null
	if p == null or not p.intent_changes_known or p.fight_after == null:
		for b in now:
			out.append(_arrow(b, telegraph.is_marked(b.from_id)))
	else:
		var after := BattleReadout.compare(now, BattleReadout.intent_badges(p.fight_after, p.intents_after, rules))
		for b in now:
			if not after.any(func(x: ArrowBadge) -> bool: return x.same_arrow(b)):
				var ghost := _arrow(b, false)
				ghost.ghost = true
				out.append(ghost)
		for b in after:
			out.append(_arrow(b, b.changed or telegraph.is_marked(b.from_id)))
	if p != null:
		for b in BattleReadout.choice_badges(fight, action, p):
			var mine := _arrow(b, false)
			mine.player = true
			out.append(mine)
	return out


static func _arrow(badge: ArrowBadge, changed: bool) -> Dictionary:
	return {"from": badge.from_id, "to": badge.to_id, "kind": badge.kind, "changed": changed,
		"badge": badge, "player": false, "ghost": false}


## The energy `c` would have after the selected skill or the previewed choice,
## or -1 for no energy preview.
func _energy_preview_for(c: Combatant) -> int:
	if shown_preview != null and shown_preview.energy_after.has(c.id):
		return shown_preview.energy_after[c.id]
	if handler.is_player_turn() and handler.is_choosing_target() and c == handler.actor() and handler.selected_bot_id == c.id:
		var skill := c.skill(handler.selected_skill_id)
		if skill != null and skill.energy_cost > 0:
			return BattleReadout.energy_after(c, skill)
	return -1


## "attack", "heal" or "wait" for an intent (a guard skill reads "guard"), or "".
func _intent_kind(intent: UnitIntent) -> String:
	if intent == null:
		return ""
	var unit := fight.combatant(intent.unit_id)
	var skill := unit.skill(intent.skill_id()) if unit != null else null
	if skill != null and skill.is_guard():
		return "guard"
	return intent.kind_name()


## The enemy whose arrow leads the eye: the one under the pointer, else the
## next enemy to act.
func _arrow_focus() -> String:
	var hovered := fight.combatant(hovered_id)
	if hovered != null and hovered.side == Combatant.Side.ENEMY:
		return hovered_id
	if fight.is_over():
		return ""
	for entry in fight.upcoming(tuning.timeline_length):
		if entry.side == Combatant.Side.ENEMY:
			return entry.combatant_id
	return ""


func _goes_down(unit_id: String) -> bool:
	var effect := shown_preview.effect_on(unit_id) if shown_preview != null else null
	return effect != null and effect.would_go_down()


## An energy popup on the unit whose turn comes up, for what it gained since
## its last turn.
func _announce_turn(actor: Combatant) -> void:
	if actor == null or actor.id == _announced_actor or presenter.is_busy():
		return
	_announced_actor = actor.id
	if not _energy_after_turn.has(actor.id):
		return
	var gained := actor.energy() - _energy_after_turn[actor.id]
	if gained >= int(BattleArt.number("energy_popup_min_gain", 1)) and not presenter.is_instant():
		var view: Control = unit_panels[actor.id].view
		NumberPopup.spawn(presenter, presenter._local(view.center_global()) + Vector2(0, 30), gained, "energy", settings)
		SoundPlayer.fire(&"energy_tick")


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
	# Buttons show the skills of the bot in view: the one acting, else the one
	# selected. Each bot's own name and level for a skill is on its button.
	var shown := handler.actor() if can_act else handler.selected_bot()
	for skill_id in skill_buttons:
		var button := skill_buttons[skill_id]
		var own := shown.skill(skill_id) if shown != null and shown.side == Combatant.Side.PLAYER else null
		button.visible = own != null
		if own != null:
			var face := skill_card_face(own, shown.stats.attack)
			button.set_skill(face.name, own.energy_cost, face.effect, face.rank)
		var has_it := can_act and own != null
		button.disabled = not has_it or not handler.skill_problem(skill_id).is_empty()
		button.button_pressed = skill_id == handler.selected_skill_id
		button.set_problem(handler.skill_problem(skill_id) if has_it else "")
	var wait_skill := handler.default_wait_skill() if can_act else ""
	var ticks := exact_wait_ticks()
	wait_button.disabled = wait_skill.is_empty() and (ticks == 0 or not can_act)
	if ticks > 0:
		wait_button.label.text = "Wait %d ticks" % ticks
	else:
		wait_button.label.text = "Wait" if wait_skill.is_empty() else "Wait for %s" % handler.actor().skill(wait_skill).display_name
	cancel_button.disabled = not can_act or not handler.is_choosing_target()


func _on_event_raised(event: FightEvent) -> void:
	_pending_events.append(event)


func _on_action_resolved(actor_id: String, _tag: String) -> void:
	_last_actor_id = actor_id
	message_label.text = ""
	var events := _pending_events
	_pending_events = []
	var actor := fight.combatant(actor_id)
	if actor != null:
		_energy_after_turn[actor_id] = actor.energy()
	if _announced_actor == actor_id:
		_announced_actor = ""
	if presenter != null:
		presenter.present(events)


## Re-plans the enemies once per action, after time has run to the next
## decision: the state the next enemy will act from.
func _sync_intents() -> void:
	if fight.action_count == _planned_at:
		return
	_planned_at = fight.action_count
	telegraph.after_action(fight, fight.combatant(_last_actor_id))


func _panel_preview(unit_id: String) -> String:
	if shown_preview == null:
		return ""
	var lines := PackedStringArray()
	var effect := shown_preview.effect_on(unit_id)
	if effect != null:
		lines.append(FightTelegraph.effect_text(effect))
	if shown_preview.guard_changes.has(unit_id):
		lines.append(FightTelegraph.guard_text(shown_preview.guard_changes[unit_id]))
	var change := shown_preview.change_for(unit_id)
	if effect != null and effect.would_go_down():
		pass
	elif change != null:
		lines.append(telegraph.intent_change_text(fight, change))
	elif not shown_preview.intent_changes_known and telegraph.intent_of(unit_id) != null:
		lines.append("intent after: ?")
	return "\n".join(lines)


func _refresh_preview_box(action: FightAction) -> void:
	if action != null:
		preview_label.text = "PREVIEW\n" + telegraph.describe_choice(fight, action, shown_preview)
		preview_label.add_theme_color_override("font_color", FeelData.color("preview"))
	elif handler.is_player_turn() and handler.is_choosing_target():
		preview_label.text = "PREVIEW\n%s: point at a target to see what it does." % (
			handler.actor().skill(handler.selected_skill_id).display_name)
		preview_label.add_theme_color_override("font_color", FeelData.color("text_dim"))
	else:
		preview_label.text = "PREVIEW\nChoose a skill, then point at a target."
		preview_label.add_theme_color_override("font_color", FeelData.color("text_dim"))


func _on_fight_over(result: FightResult) -> void:
	if _finished_sent or _outcome_started:
		return
	_outcome_started = true
	refresh()
	if presenter != null and presenter.is_busy():
		await presenter.idle
	if not is_inside_tree() or outcome_banner == null:
		_send_finished(result)
		return
	var winners: Array = []
	var side := Combatant.Side.PLAYER if result.is_victory() else Combatant.Side.ENEMY
	for c in fight.living(side):
		winners.append(unit_panels[c.id].view)
	outcome_banner.finished.connect(_send_finished.bind(result), CONNECT_ONE_SHOT)
	outcome_banner.play(result.is_victory(), winners)


func _send_finished(result: FightResult) -> void:
	if _finished_sent:
		return
	_finished_sent = true
	refresh()
	fight_finished.emit(result)


func _build_layout() -> void:
	settings = GameSettings.shared()
	var back := ColorRect.new()
	back.color = FeelData.color("background")
	back.set_anchors_preset(Control.PRESET_FULL_RECT)
	back.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(back)

	var root := VBoxContainer.new()
	root.name = "Root"
	root.set_anchors_preset(Control.PRESET_FULL_RECT)
	root.offset_left = 16
	root.offset_top = 10
	root.offset_right = -16
	root.offset_bottom = -10
	root.add_theme_constant_override("separation", 8)
	root.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(root)
	field_root = root

	var request := fight.request
	var header := HBoxContainer.new()
	header.name = "Header"
	header.add_theme_constant_override("separation", 12)
	root.add_child(header)
	header_label = _label(header, "%s  -  %s" % [
		FightRequest.Kind.keys()[request.kind], request.territory_id.capitalize().to_upper()], "DimLabel")
	defense_stat = IconStat.make("defense_level", request.defense_level)
	defense_stat.name = "DefenseLevel"
	header.add_child(defense_stat)
	_header = header
	timeline_bar = TimelineBar.new()
	timeline_bar.name = "TimelineBar"
	timeline_bar.settings = settings
	root.add_child(timeline_bar)

	var field := HBoxContainer.new()
	field.name = "Field"
	field.size_flags_vertical = Control.SIZE_EXPAND_FILL
	field.add_theme_constant_override("separation", 12)
	field.mouse_filter = Control.MOUSE_FILTER_IGNORE
	root.add_child(field)
	var bots := _column(field, "SQUAD")
	var middle := VBoxContainer.new()
	middle.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	middle.mouse_filter = Control.MOUSE_FILTER_IGNORE
	middle.alignment = BoxContainer.ALIGNMENT_END
	field.add_child(middle)
	log_toggle = Button.new()
	log_toggle.name = "LogToggle"
	log_toggle.flat = true
	log_toggle.focus_mode = Control.FOCUS_NONE
	log_toggle.theme_type_variation = &"SmallLabel"
	log_toggle.size_flags_horizontal = Control.SIZE_SHRINK_BEGIN
	log_toggle.pressed.connect(toggle_log)
	middle.add_child(log_toggle)
	log_label = _label(middle, "", "SmallLabel")
	log_label.name = "LogLabel"
	log_label.visible = false
	log_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	log_label.clip_text = true
	log_label.custom_minimum_size = Vector2(0, 10 * LOG_LINES_SHOWN + 16)
	var enemy_col := _column(field, "ENEMIES")
	var enemy_count := fight.combatants.filter(func(c: Combatant) -> bool: return c.side == Combatant.Side.ENEMY).size()
	var enemies := GridContainer.new()
	enemies.columns = 2 if enemy_count > ENEMIES_PER_COLUMN else 1
	enemies.add_theme_constant_override("h_separation", 8)
	enemies.add_theme_constant_override("v_separation", 8)
	enemies.mouse_filter = Control.MOUSE_FILTER_IGNORE
	enemy_col.add_child(enemies)
	var used_palettes := []
	for c in fight.combatants:
		var panel := UnitPanel.new()
		(enemies if c.side == Combatant.Side.ENEMY else bots).add_child(panel)
		var bot: Bot = bot_source.call(c.id) if bot_source.is_valid() and c.side == Combatant.Side.PLAYER else null
		var look := BattleArt.look_for(c, fight.request.defense_level, tier_rule, bot)
		if c.side == Combatant.Side.PLAYER:
			look = BattleArt.with_distinct_palette(look, used_palettes)
		panel.setup(c, look)
		panel.view.settings = settings
		panel.clicked.connect(on_unit_clicked)
		panel.hovered.connect(on_unit_hovered)
		unit_panels[c.id] = panel
		_energy_after_turn[c.id] = c.energy()

	var bar := PanelContainer.new()
	bar.name = "CommandBar"
	root.add_child(bar)
	var bar_row := HBoxContainer.new()
	bar_row.add_theme_constant_override("separation", 16)
	bar.add_child(bar_row)
	var commands := VBoxContainer.new()
	commands.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	bar_row.add_child(commands)
	prompt_label = _label(commands, "", "")
	prompt_label.add_theme_color_override("font_color", FeelData.color("text_bright"))
	var buttons := HFlowContainer.new()
	buttons.add_theme_constant_override("h_separation", 8)
	buttons.add_theme_constant_override("v_separation", 6)
	commands.add_child(buttons)
	for skill_id in _all_player_skills():
		var skill := fight.tuning.skill(skill_id)
		var button := SkillCard.make(skill.display_name, skill.energy_cost, "")
		button.name = "Skill_%s" % skill_id
		buttons.add_child(button)
		button.toggle_mode = true
		button.pressed.connect(on_skill_pressed.bind(skill_id))
		skill_buttons[skill_id] = button
	# Wait and Cancel stack in a column beside the cards.
	var moves := VBoxContainer.new()
	moves.name = "Moves"
	moves.alignment = BoxContainer.ALIGNMENT_CENTER
	moves.add_theme_constant_override("separation", 6)
	buttons.add_child(moves)
	wait_button = ActionButton.make("action_wait", "Wait")
	wait_button.custom_minimum_size.y = 34
	moves.add_child(wait_button)
	wait_button.name = "WaitButton"
	wait_button.pressed.connect(on_wait_pressed)
	wait_button.mouse_entered.connect(on_wait_hovered.bind(true))
	wait_button.mouse_exited.connect(on_wait_hovered.bind(false))
	wait_ticks_box = SpinBox.new()
	wait_ticks_box.name = "WaitTicksBox"
	wait_ticks_box.min_value = 0
	wait_ticks_box.max_value = maxi(1, WaitRules.max_wait_ticks(fight.tuning))
	wait_ticks_box.rounded = true
	wait_ticks_box.prefix = "ticks"
	wait_ticks_box.tooltip_text = "Exact wait length (d-wait-length variant). 0 waits until the skill is affordable."
	wait_ticks_box.visible = WaitRules.exact_waits_allowed(fight.tuning)
	wait_ticks_box.value_changed.connect(func(_v: float) -> void: _refresh_commands())
	moves.add_child(wait_ticks_box)
	cancel_button = ActionButton.make("action_cancel", "Cancel")
	cancel_button.custom_minimum_size.y = 34
	moves.add_child(cancel_button)
	cancel_button.name = "CancelButton"
	cancel_button.pressed.connect(on_cancel_pressed)
	message_label = _label(commands, "", "SmallLabel")
	message_label.add_theme_color_override("font_color", FeelData.color("danger"))

	preview_area = PanelContainer.new()
	preview_area.name = "PreviewArea"
	preview_area.custom_minimum_size = Vector2(380, 0)
	bar_row.add_child(preview_area)
	preview_label = _label(preview_area, "", "SmallLabel")
	preview_label.name = "PreviewLabel"
	preview_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART

	# Overlays: intent arrows, then the action presenter, then the outcome.
	var views := {}
	for id: String in unit_panels:
		views[id] = unit_panels[id].view
	arrows = IntentArrows.new()
	arrows.name = "IntentArrows"
	arrows.views = views
	arrows.set_anchors_preset(Control.PRESET_FULL_RECT)
	add_child(arrows)
	presenter = BattlePresenter.new()
	presenter.name = "Presenter"
	presenter.fight = fight
	presenter.panels = unit_panels
	presenter.settings = settings
	presenter.set_anchors_preset(Control.PRESET_FULL_RECT)
	presenter.idle.connect(refresh, CONNECT_DEFERRED)
	add_child(presenter)
	shake = ScreenShake.new(root, settings)
	shake.name = "Shake"
	add_child(shake)
	presenter.shake = shake
	outcome_banner = OutcomeBanner.new()
	outcome_banner.name = "OutcomeBanner"
	outcome_banner.settings = settings
	outcome_banner.set_anchors_preset(Control.PRESET_FULL_RECT)
	add_child(outcome_banner)


## What a skill card shows for `skill` in the hands of a unit with `attack`:
## {name, rank, effect}. The rank is "+2" for a named rank ("Mega Strike +2"
## shows "Mega Strike" and "+2"), "Lv2" for a flat level above 1, else "".
## The effect is short words with numbers: "Deal 9. Pierce 20%."
static func skill_card_face(skill: CombatSkill, attack: int) -> Dictionary:
	var title := skill.display_name
	var rank := ""
	if skill.names_rank:
		var m := RegEx.create_from_string("^(.*) (\\+\\d+)$").search(title)
		if m != null:
			title = m.get_string(1)
			rank = m.get_string(2)
	elif skill.level > 1:
		rank = "Lv%d" % skill.level
	@warning_ignore("integer_division")
	var amount := attack * skill.power_percent / 100
	var parts: Array[String] = []
	if skill.is_damage():
		parts.append("Deal %d%s." % [amount, " to all" if skill.hits_all() else ""])
		if skill.pierce_percent > 0:
			parts.append("Pierce %d%%." % skill.pierce_percent)
		if skill.weakest_bonus_percent > 0:
			parts.append("+%d%% to Weakest." % skill.weakest_bonus_percent)
	elif skill.is_heal():
		parts.append("Heal %d%s." % [amount, "" if skill.target != CombatSkill.TARGET_SELF else " self"])
		if skill.heal_guard_percent > 0:
			parts.append("Guard %d%%." % skill.heal_guard_percent)
	elif skill.is_guard():
		parts.append("Guard %d%%%s." % [skill.power_percent, " self" if skill.target == CombatSkill.TARGET_SELF else ""])
		if skill.reflect_percent > 0:
			parts.append("Reflect %d%%." % skill.reflect_percent)
	return {"name": title, "rank": rank, "effect": " ".join(parts)}


## Shows or hides the battle log.
## Puts a Home button at the right end of the header; pressing it calls
## `on_press` (RunFlow asks before leaving the battle).
func show_home_button(on_press: Callable) -> ActionButton:
	if home_button == null:
		var spacer := Control.new()
		spacer.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		spacer.mouse_filter = Control.MOUSE_FILTER_IGNORE
		_header.add_child(spacer)
		home_button = ActionButton.make("action_home", "Home")
		home_button.name = "HomeButton"
		_header.add_child(home_button)
	for connection in home_button.pressed.get_connections():
		home_button.pressed.disconnect(connection.callable)
	home_button.pressed.connect(on_press)
	return home_button


func toggle_log() -> void:
	log_label.visible = not log_label.visible
	refresh()


## Skill ids any bot in the fight has, in roster then menu order. Each bot
## sees only its own on its turn.
func _all_player_skills() -> Array[String]:
	var ids: Array[String] = []
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
	_label(col, title, "SmallLabel")
	return col


static func _label(parent: Node, text: String, variation: String) -> Label:
	var label := Label.new()
	label.text = text
	if not variation.is_empty():
		label.theme_type_variation = StringName(variation)
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
