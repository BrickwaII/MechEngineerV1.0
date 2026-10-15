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
## Boss fights (show_boss()): the boss unit is drawn larger in its own row
## above its escorts, a wide boss HP bar with its name runs under the header,
## and the header reads "BOSS - <name>".
##
## Call setup() before adding the screen to the tree.

const UnitPanel := preload("res://ui/fight/unit_panel.gd")
const PreviewBar := preload("res://ui/fight/preview_bar.gd")
const TimelineBar := preload("res://ui/fight/timeline_bar.gd")
const IntentArrows := preload("res://ui/fight/intent_arrows.gd")
const OutcomeBanner := preload("res://ui/fight/outcome_banner.gd")

const LOG_LINES_SHOWN := 8
## The action dock's portrait and the room for the acting bot's name.
const DOCK_PORTRAIT := 72.0
const DOCK_NAME_WIDTH := 112.0
## The drawer for the log and the preview, on the right edge.
const DRAWER_WIDTH := 400.0
## The narrowest middle the drawer opens in rather than on the right edge.
const DRAWER_MIN_WIDTH := 320.0
## Animation speeds the control strip offers, as GameSettings names them.
const SPEEDS: Array[String] = ["1x", "1.5x", "2x", "skip"]
## A boss is drawn this many times the standard size, on a card this many
## times as wide, with an HP bar this tall under the header.
const BOSS_SIZE := 1.6
const BOSS_CARD_WIDTH := 1.25
const BOSS_BAR_HEIGHT := 18.0
## Enemy cards go two to a row past this many enemies.
const ENEMIES_PER_COLUMN := 3
## How much more of the header's free width the boss bar takes than the gap
## before Home.
const BOSS_BAR_STRETCH := 6.0

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
## The screen's one control strip: speed, log, preview, compact or detailed.
var control_strip: ControlStrip
## The chosen skill lifted into the middle of the screen.
var focus_card: FocusCard
## The log and preview drawer on the right edge.
var drawer: PanelContainer
## The acting bot's name and Energy in the action dock.
var dock_name: Label
var dock_energy: IconStat
## Compact cards: icon-only flags.
var compact := false
## The player's view choice; the cards are compact anyway while detailed ones
## do not fit (_fit_view).
var _view_choice := &"detailed"
var _view_forced := false
var _fit_pending := false
## The skill Wait would wait for ("" for a plain wait), as its name.
var wait_for_skill := ""
var _dock_portrait: Control
var _dock_portrait_id := ""
var _middle: VBoxContainer
var _log_box: VBoxContainer
var _drawer_scroll: ScrollContainer
## The boss unit's id, or "" in a fight with no boss (show_boss()).
var boss_id := ""
## The wide boss HP bar under the header, or null.
var boss_bar: PreviewBar
var _enemy_column: VBoxContainer
var _enemy_grid: GridContainer
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
	resized.connect(func() -> void: _fit_view(true))
	_fit_view.call_deferred(true)
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
	message_label.visible = not problem.is_empty()
	command_sent.emit(command, problem)
	return problem


func _gui_input(event: InputEvent) -> void:
	var mouse := event as InputEventMouseButton
	if mouse != null and mouse.pressed and mouse.button_index == MOUSE_BUTTON_RIGHT:
		send(FightCommand.cancel())
		accept_event()


## A click on a unit panel: bots are selected, enemies are targeted. A
## right-click cancels a skill being aimed; with nothing to cancel it opens
## the unit's detail card (as its ⋮ does).
func on_unit_clicked(unit_id: String, button_index: MouseButton) -> void:
	if button_index == MOUSE_BUTTON_RIGHT:
		if not _has_choice_to_cancel() and unit_panels.has(unit_id):
			open_unit_detail(unit_id)
		else:
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


## An arrow badge's tooltip: who does what to whom, and the math behind the
## number with the real values (BattleMath).
func describe_badge(badge: ArrowBadge) -> Dictionary:
	var actor := fight.combatant(badge.from_id)
	var target := fight.combatant(badge.to_id)
	var skill := actor.skill(badge.skill_id) if actor != null else null
	var what: String = {ArrowBadge.HEAL: "Repair", ArrowBadge.GUARD: "Guard"}.get(badge.kind, "Damage")
	var icon: String = {ArrowBadge.HEAL: "intent_heal", ArrowBadge.GUARD: "intent_guard", ArrowBadge.WAIT: "intent_charge"}.get(badge.kind, "intent_attack")
	var body := "%s: %s on %s." % [
		actor.display_name if actor != null else "?", skill.display_name if skill != null else "?",
		target.display_name if target != null else "?"]
	if badge.knocks_out:
		body += " It goes Down."
	return {"title": "%s %s" % [what, badge.text()], "body": body, "icon": icon,
		"math": BattleMath.badge_lines(fight, badge)}


## True while a right-click has something to undo: a skill being aimed, or
## another bot than the one acting selected.
func _has_choice_to_cancel() -> bool:
	var actor := handler.actor()
	return not handler.selected_skill_id.is_empty() or (actor != null and handler.selected_bot_id != actor.id)


## Opens the DetailModal of `unit_id`'s card.
func open_unit_detail(unit_id: String) -> DetailModal:
	return DetailModal.open(self, unit_panels[unit_id].detail_spec())


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
	var upcoming: Array[TimelineEntry] = []
	if not fight.is_over():
		upcoming = fight.upcoming(tuning.timeline_length)
	for c in fight.combatants:
		var panel := unit_panels[c.id]
		panel.set_turn(BattleMath.turn(fight, c.id, upcoming))
		panel.refresh(c, _highlight_for(c), presenter.shown_hp(c.id, c.hp), presenter.shown_energy(c.id, c.energy()))
		var intent := telegraph.intent_of(c.id) if c.is_alive() else null
		panel.show_intent(telegraph.tag_of(c.id),
			telegraph.intent_text(fight, c.id) if c.is_alive() else "", telegraph.change_text(c.id), _intent_kind(intent))
		panel.show_preview(_panel_preview(c.id))
		panel.show_meter_preview(shown_preview.effect_on(c.id) if shown_preview != null else null,
			shown_preview != null and shown_preview.change_for(c.id) != null and not _goes_down(c.id))
		panel.show_energy_preview(_energy_preview_for(c))
	var arrow_dicts := arrow_list(action)
	arrows.hover_id = hovered_id
	arrows.set_arrows(arrow_dicts, _arrow_focus())
	_refresh_intent_chips(arrow_dicts)
	_refresh_preview_box(action)
	var order := BattleReadout.order_with_choice(upcoming, shown_preview)
	var order_changes := not order.is_empty() and not BattleReadout.same_order(order, upcoming)
	timeline_bar.refresh(order if order_changes else upcoming, order_changes)
	timeline_bar.set_highlight(hovered_id if fight.combatant(hovered_id) != null else "")
	_refresh_commands()
	_refresh_boss_bar()
	var lines := fight.log_lines
	log_label.text = "\n".join(lines.slice(maxi(0, lines.size() - LOG_LINES_SHOWN)))
	log_toggle.text = "Log %d" % lines.size()
	if drawer != null and drawer.visible:
		_place_drawer()
		_drawer_scroll.scroll_vertical = int(_drawer_scroll.get_v_scroll_bar().max_value)
	_refresh_dock()
	_refresh_focus()
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
	_fit_view()


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
	# The button stays short ("Wait"); what it waits for is in its tooltip.
	if ticks > 0:
		wait_button.label.text = "Wait %d ticks" % ticks
		UiTooltip.attach(wait_button, wait_button.label.text, "Hold this many ticks, filling Energy.", "", "action_wait")
	else:
		wait_button.label.text = "Wait"
		var why := "End the turn and let time pass, filling Energy." if wait_skill.is_empty() \
			else "Wait for %s: hold until it is affordable, filling Energy." % handler.actor().skill(wait_skill).display_name
		UiTooltip.attach(wait_button, "Wait", why, "", "action_wait")
	wait_for_skill = "" if wait_skill.is_empty() else handler.actor().skill(wait_skill).display_name
	cancel_button.disabled = not can_act or not handler.is_choosing_target()


func _on_event_raised(event: FightEvent) -> void:
	_pending_events.append(event)


func _on_action_resolved(actor_id: String, _tag: String) -> void:
	_last_actor_id = actor_id
	message_label.text = ""
	message_label.visible = false
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
		preview_label.text = telegraph.describe_choice(fight, action, shown_preview)
		preview_label.add_theme_color_override("font_color", FeelData.color("preview"))
	elif handler.is_player_turn() and handler.is_choosing_target():
		preview_label.text = "%s: point at a target to see what it does." % (
			handler.actor().skill(handler.selected_skill_id).display_name)
		preview_label.add_theme_color_override("font_color", FeelData.color("text_dim"))
	else:
		preview_label.text = "Choose a skill, then point at a target."
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
	root.offset_top = 8
	root.offset_right = -16
	root.offset_bottom = -8
	root.add_theme_constant_override("separation", 8)
	root.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(root)
	field_root = root
	_build_header(root)
	_build_field(root)
	_build_command_bar(root)
	_build_overlays(root)


## The header (fight kind, territory, defense) and the turn order row with
## the control strip.
func _build_header(root: VBoxContainer) -> void:
	var request := fight.request
	var header := HBoxContainer.new()
	header.name = "Header"
	header.add_theme_constant_override("separation", 12)
	root.add_child(header)
	header_label = UiStyle.add_label(header, "%s  -  %s" % [
		FightRequest.Kind.keys()[request.kind], request.territory_id.capitalize().to_upper()], "DimLabel")
	defense_stat = IconStat.make("defense_level", request.defense_level)
	defense_stat.name = "DefenseLevel"
	header.add_child(defense_stat)
	_header = header
	timeline_bar = TimelineBar.new()
	timeline_bar.turn_info = func(id: String) -> Dictionary:
		return unit_panels[id].turn_info if unit_panels.has(id) else {}
	timeline_bar.look_for = func(id: String) -> Dictionary:
		return unit_panels[id].view.look if unit_panels.has(id) else {}
	timeline_bar.name = "TimelineBar"
	timeline_bar.settings = settings
	# The turn order and, on the same row's right end, the screen's one
	# control strip.
	var turn_row := UiStyle.row("m")
	turn_row.name = "TurnRow"
	root.add_child(turn_row)
	timeline_bar.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	turn_row.add_child(timeline_bar)
	turn_row.add_child(_build_control_strip())


## The squad and enemy columns with a unit panel per combatant.
func _build_field(root: VBoxContainer) -> void:
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
	_middle = middle
	var enemy_col := _column(field, "ENEMIES")
	_enemy_column = enemy_col
	var enemy_count := fight.combatants.filter(func(c: Combatant) -> bool: return c.side == Combatant.Side.ENEMY).size()
	# A crowded field (two columns of enemies) starts with compact cards so
	# everything fits; the strip switches to detailed.
	if enemy_count > ENEMIES_PER_COLUMN:
		compact = true
		_view_choice = &"compact"
		control_strip.set_value(&"view", &"compact")
	var enemies := GridContainer.new()
	enemies.columns = 2 if enemy_count > ENEMIES_PER_COLUMN else 1
	enemies.add_theme_constant_override("h_separation", 8)
	enemies.add_theme_constant_override("v_separation", 8)
	enemies.mouse_filter = Control.MOUSE_FILTER_IGNORE
	enemy_col.add_child(enemies)
	_enemy_grid = enemies
	var used_palettes := []
	for c in fight.combatants:
		var panel := UnitPanel.new()
		(enemies if c.side == Combatant.Side.ENEMY else bots).add_child(panel)
		var bot: Bot = bot_source.call(c.id) if bot_source.is_valid() and c.side == Combatant.Side.PLAYER else null
		var look := BattleArt.look_for(c, fight.request.defense_level, tier_rule, bot)
		if c.side == Combatant.Side.PLAYER:
			look = BattleArt.with_distinct_palette(look, used_palettes)
		panel.setup(c, look)
		panel.set_compact(compact)
		if bot != null and bot.personality != null:
			panel.personality_ends = bot.personality.get_ends()
		panel.view.settings = settings
		panel.clicked.connect(on_unit_clicked)
		panel.hovered.connect(on_unit_hovered)
		unit_panels[c.id] = panel
		_energy_after_turn[c.id] = c.energy()


## The action dock (bottom left): the bot whose turn it is, its portrait and
## name, and its skills as compact action tiles; the step header in the
## middle; Wait (end the turn) and Cancel on the right.
func _build_command_bar(root: VBoxContainer) -> void:
	var bar := PanelContainer.new()
	bar.name = "CommandBar"
	bar.add_theme_stylebox_override("panel", UiStyle.panel("plain"))
	root.add_child(bar)
	var bar_row := UiStyle.row("m")
	bar.add_child(bar_row)
	var dock := UiStyle.row("s")
	dock.name = "ActionDock"
	bar_row.add_child(dock)
	_dock_portrait = Control.new()
	_dock_portrait.name = "ActivePortrait"
	_dock_portrait.custom_minimum_size = Vector2(DOCK_PORTRAIT, DOCK_PORTRAIT)
	_dock_portrait.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	dock.add_child(_dock_portrait)
	var who := UiStyle.column("xs")
	who.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	who.custom_minimum_size.x = DOCK_NAME_WIDTH
	dock.add_child(who)
	dock_name = Label.new()
	dock_name.name = "ActiveName"
	dock_name.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	UiTooltip._bold(dock_name, UiStyle.role("title"))
	who.add_child(dock_name)
	dock_energy = IconStat.make("energy", 0)
	dock_energy.name = "ActiveEnergy"
	who.add_child(dock_energy)
	var buttons := UiStyle.row("s")
	buttons.name = "Tiles"
	dock.add_child(buttons)
	for skill_id in _all_player_skills():
		var skill := fight.tuning.skill(skill_id)
		var button := ActionTile.make_tile(skill.display_name, skill.energy_cost, "", "", _skill_icon(skill))
		button.name = "Skill_%s" % skill_id
		buttons.add_child(button)
		button.toggle_mode = true
		button.pressed.connect(on_skill_pressed.bind(skill_id))
		skill_buttons[skill_id] = button
	var commands := UiStyle.column("xs")
	commands.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	commands.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	bar_row.add_child(commands)
	prompt_label = UiStyle.add_label(commands, "", "")
	prompt_label.name = "StepHeader"
	prompt_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	prompt_label.add_theme_color_override("font_color", FeelData.color("text_bright"))
	message_label = UiStyle.add_label(commands, "", "")
	message_label.name = "Message"
	message_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	message_label.add_theme_color_override("font_color", UiStyle.role("bad"))
	# Takes no line while there is nothing to say.
	message_label.visible = false
	# The chosen skill lifts into the dock's middle, where the step header is,
	# so it never covers a target on the board.
	focus_card = FocusCard.new()
	commands.add_child(focus_card)
	var moves := UiStyle.column("xs")
	moves.name = "Moves"
	moves.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	bar_row.add_child(moves)
	wait_button = ActionButton.make("action_wait", "Wait")
	wait_button.custom_minimum_size.y = 40
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
	cancel_button.custom_minimum_size.y = 40
	moves.add_child(cancel_button)
	cancel_button.name = "CancelButton"
	cancel_button.pressed.connect(on_cancel_pressed)


## Overlays: intent arrows, then the action presenter, then the outcome.
func _build_overlays(root: VBoxContainer) -> void:
	var views := {}
	for id: String in unit_panels:
		views[id] = unit_panels[id].view
	arrows = IntentArrows.new()
	arrows.name = "IntentArrows"
	arrows.views = views
	arrows.describe = describe_badge
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
	_build_drawer()
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
## Shows enemy `unit_id` as this fight's boss named `title`: drawn
## BOSS_SIZE times larger in a row of its own above the escorts, a wide HP bar
## with its name under the header, and "BOSS - <title>" as the header.
func show_boss(unit_id: String, title: String) -> void:
	var unit := fight.combatant(unit_id)
	if unit == null or not unit_panels.has(unit_id):
		push_error("BattleScreen: no unit '%s' to show as the boss" % unit_id)
		return
	boss_id = unit_id
	unit_panels[unit_id].set_boss(true)
	header_label.text = "BOSS  -  %s" % title.to_upper()
	var panel := unit_panels[unit_id]
	panel.get_parent().remove_child(panel)
	var row := CenterContainer.new()
	row.name = "BossRow"
	row.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_enemy_column.add_child(row)
	_enemy_column.move_child(row, _enemy_grid.get_index())
	row.add_child(panel)
	panel.view.set_size_factor(BOSS_SIZE)
	panel.custom_minimum_size.x = UnitPanel.CARD_WIDTH * BOSS_CARD_WIDTH
	if boss_bar == null:
		var box := HBoxContainer.new()
		box.name = "BossBarRow"
		box.add_theme_constant_override("separation", 10)
		box.mouse_filter = Control.MOUSE_FILTER_IGNORE
		# In the header's free middle, not a row of its own, so a boss fight
		# keeps the room its bigger card needs (ui/README.md rule 17).
		box.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		box.size_flags_stretch_ratio = BOSS_BAR_STRETCH
		box.size_flags_vertical = Control.SIZE_SHRINK_CENTER
		_header.add_child(box)
		_header.move_child(box, defense_stat.get_index() + 1)
		# The header beside it already names the boss.
		boss_bar = PreviewBar.new()
		boss_bar.name = "BossBar"
		boss_bar.kind = "hp"
		boss_bar.custom_minimum_size = Vector2(0, BOSS_BAR_HEIGHT)
		boss_bar.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		boss_bar.size_flags_vertical = Control.SIZE_SHRINK_CENTER
		box.add_child(boss_bar)
		boss_bar.reset(unit.hp, unit.max_hp)
	_refresh_boss_bar()


func _refresh_boss_bar() -> void:
	if boss_bar == null:
		return
	var unit := fight.combatant(boss_id)
	var hp: int = presenter.shown_hp(boss_id, unit.hp) if presenter != null else unit.hp
	boss_bar.caption = "HP %d/%d" % [maxi(0, hp), unit.max_hp]
	boss_bar.max_value = unit.max_hp
	boss_bar.set_value(maxi(0, hp))
	boss_bar.queue_redraw()


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
	control_strip.press(&"log")


## The screen's one control strip (ui/README.md rule 10), on the header's
## top edge: animation speed, the log and preview drawer, compact or
## detailed cards.
func _build_control_strip() -> ControlStrip:
	control_strip = ControlStrip.new()
	control_strip.name = "BattleStrip"
	var speeds: Array = []
	for sp in SPEEDS:
		speeds.append([StringName(sp), "Skip" if sp == "skip" else sp, "", "Animation speed. Skip plays every action at once."])
	control_strip.add_choice(&"speed", "", speeds, StringName(settings.animation_speed if settings.animation_speed in SPEEDS else "1x"))
	log_toggle = control_strip.add_toggle(&"log", "Log", false, "status_waiting", "The fight's log, in the drawer.")
	control_strip.add_toggle(&"preview", "Preview", false, "status_intent_changed", "What the chosen action would do, in words, in the drawer.")
	control_strip.add_choice(&"view", "", [
		[&"detailed", "Detailed", "", "Cards show every flag with its name."],
		[&"compact", "Compact", "", "Cards show flags as icons; names on hover."],
	], &"compact" if compact else &"detailed")
	control_strip.changed.connect(_on_strip_changed)
	return control_strip


func _on_strip_changed(id: StringName, value: Variant) -> void:
	match id:
		&"speed":
			settings.animation_speed = str(value)
			settings.save()
		&"log", &"preview":
			_refresh_drawer()
			refresh()
		&"view":
			_view_choice = StringName(value)
			_fit_view(true)


## Detailed cards when they fit the window's height; else compact cards, with
## Detailed greyed out and saying why until the window has room again (then
## the player's choice comes back). `remeasure` tries detailed cards again,
## for a resize or a new choice. The cards' flags wrap a frame after they
## change, so the height is read then.
func _fit_view(remeasure := false) -> void:
	if field_root == null or control_strip == null or unit_panels.is_empty() or size.y <= 0.0:
		return
	if _view_choice == &"compact":
		_view_forced = false
		_set_cards_compact(true)
		_show_view_state()
		return
	if _view_forced and not remeasure:
		return
	_set_cards_compact(false)
	if _fit_pending:
		return
	_fit_pending = true
	await get_tree().process_frame
	_fit_pending = false
	if not is_inside_tree() or _view_choice == &"compact":
		return
	var room := size.y - field_root.offset_top + field_root.offset_bottom
	_view_forced = field_root.get_combined_minimum_size().y > room + 0.5
	if _view_forced:
		_set_cards_compact(true)
	_show_view_state()


func _show_view_state() -> void:
	control_strip.set_value(&"view", &"compact" if compact else &"detailed")
	var detailed := control_strip.button(&"view", &"detailed")
	if detailed.disabled != _view_forced:
		detailed.disabled = _view_forced
		UiTooltip.attach(detailed, "Detailed", "Cards show every flag with its name." if not _view_forced
			else "Needs a taller window: the cards are compact until there is room.")


func _set_cards_compact(on: bool) -> void:
	compact = on
	for pid: String in unit_panels:
		unit_panels[pid].set_compact(on)


## The drawer on the right edge for the log and the preview: closed unless the
## strip opens one; it slides over the field's empty middle, never the cards.
func _build_drawer() -> void:
	drawer = PanelContainer.new()
	drawer.name = "Drawer"
	drawer.visible = false
	drawer.mouse_filter = Control.MOUSE_FILTER_STOP
	drawer.add_theme_stylebox_override("panel", UiStyle.panel("overlay"))
	drawer.custom_minimum_size.x = DRAWER_WIDTH
	add_child(drawer)
	# The drawer keeps its height; a long log scrolls inside it, newest last.
	var scroll := ScrollContainer.new()
	scroll.name = "Scroll"
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	scroll.follow_focus = false
	drawer.add_child(scroll)
	_drawer_scroll = scroll
	var col := UiStyle.column("m")
	col.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	scroll.add_child(col)
	preview_area = PanelContainer.new()
	preview_area.name = "PreviewArea"
	preview_area.add_theme_stylebox_override("panel", StyleBoxEmpty.new())
	col.add_child(preview_area)
	var pcol := UiStyle.column("xs")
	preview_area.add_child(pcol)
	var pcap := UiStyle.caption(Label.new())
	pcap.text = "PREVIEW"
	pcol.add_child(pcap)
	preview_label = UiStyle.add_label(pcol, "", "")
	preview_label.name = "PreviewLabel"
	preview_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_log_box = UiStyle.column("xs")
	_log_box.name = "LogBox"
	col.add_child(_log_box)
	var lcap := UiStyle.caption(Label.new())
	lcap.text = "LOG"
	_log_box.add_child(lcap)
	log_label = UiStyle.add_label(_log_box, "", "")
	log_label.name = "LogLabel"
	log_label.visible = false
	log_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_refresh_drawer()


func _refresh_drawer() -> void:
	if drawer == null:
		return
	var show_log: bool = control_strip.value(&"log")
	var show_preview: bool = control_strip.value(&"preview")
	log_label.visible = show_log
	_log_box.visible = show_log
	preview_area.visible = show_preview
	drawer.visible = show_log or show_preview
	if drawer.visible:
		_place_drawer()


## The drawer opens in the field's empty middle when there is room, so no
## card is covered; on a crowded field it opens on the right edge.
func _place_drawer() -> void:
	var top := _header.get_global_rect().end.y + UiStyle.space("s")
	var bottom := (field_root.get_node("CommandBar") as Control).get_global_rect().position.y - UiStyle.space("s")
	var mid := _middle.get_global_rect()
	var w := DRAWER_WIDTH
	var x := size.x - DRAWER_WIDTH - UiStyle.space("m")
	if mid.size.x >= DRAWER_MIN_WIDTH:
		w = minf(DRAWER_WIDTH, mid.size.x)
		x = mid.get_center().x - w / 2.0
		top = maxf(top, mid.position.y)
	drawer.custom_minimum_size.x = w
	drawer.position = Vector2(x, top)
	drawer.size = Vector2(w, maxf(120.0, bottom - top))


## The icon a skill's tile shows, by what it does.
static func _skill_icon(skill: CombatSkill) -> String:
	if skill.is_heal():
		return "intent_heal"
	if skill.is_guard():
		return "intent_guard"
	return "intent_attack"


## The dock shows the bot whose turn it is (or the one selected): portrait,
## name and Energy.
func _refresh_dock() -> void:
	var can_act := handler.is_player_turn() and handler.selected_bot_id == handler.actor().id
	var shown := handler.actor() if can_act else handler.selected_bot()
	if shown == null or shown.side != Combatant.Side.PLAYER:
		shown = handler.selected_bot()
	if shown == null:
		dock_name.text = ""
		return
	dock_name.text = shown.display_name
	@warning_ignore("integer_division")
	dock_energy.set_value("%d/%d" % [shown.energy(), shown.max_energy_milli / Combatant.MILLI])
	if _dock_portrait_id != shown.id and unit_panels.has(shown.id):
		_dock_portrait_id = shown.id
		for c in _dock_portrait.get_children():
			c.queue_free()
		var p := UnitPortrait.make(unit_panels[shown.id].view.look, false, DOCK_PORTRAIT)
		_dock_portrait.add_child(p)
		UiTooltip.attach(p, shown.display_name, "Its turn: pick a skill below, or Wait.", "", "hp")
	for c in _dock_portrait.get_children():
		if c is UnitPortrait:
			(c as UnitPortrait).now = can_act
	var i := 0
	for skill_id in skill_buttons:
		var tile: ActionTile = skill_buttons[skill_id]
		if tile.visible:
			i += 1
			tile.hotkey = i
			tile.hotkey_label.text = str(i) if i <= 9 else ""


## While a skill is aimed: the focused card with its math for the target under
## the pointer, and on every valid target what the skill would do to it.
func _refresh_focus() -> void:
	var aiming := handler.is_player_turn() and handler.is_choosing_target() and not fight.is_over()
	var targets := {}
	if aiming:
		var actor := handler.actor()
		var skill := actor.skill(handler.selected_skill_id)
		for c in fight.combatants:
			if c.is_alive() and handler.target_problem(c.id).is_empty():
				targets[c.id] = _outcome_on(FightAction.use(skill.id, c.id), c.id)
		var face := skill_card_face(skill, actor.stats.attack)
		var math: Array = []
		if targets.has(hovered_id):
			math = _focus_math(actor, skill, hovered_id, targets[hovered_id])
		elif skill.is_damage():
			math = [UiFormula.new().term("ATK", actor.stats.attack).op("×").term("Power", "%d%%" % skill.power_percent)
				.equals(actor.stats.attack * skill.power_percent / 100, "before Defense"),
				"Point at a target for its exact damage."]
		var hint := "Click %s. Esc cancels." % ("an enemy" if skill.targets_opponents() else "a bot")
		focus_card.show_skill(skill.id, face, skill.energy_cost, math, hint)
	else:
		focus_card.hide_card()
	prompt_label.visible = not focus_card.visible
	for id: String in unit_panels:
		var o: Variant = targets.get(id)
		unit_panels[id].show_target_outcome(o if o != null else {})


## What `action` would do to `unit_id`: {"text": "-13" | "+8" | "Guard 40%",
## "ko": bool, "amount": int}.
func _outcome_on(action: FightAction, unit_id: String) -> Dictionary:
	var preview := telegraph.preview_choice(fight, action)
	var u := fight.combatant(unit_id)
	var effect: UnitEffect = preview.effect_on(unit_id) if preview != null else null
	if effect == null or not effect.hp_after.known:
		var skill := handler.actor().skill(action.skill_id)
		if skill != null and skill.is_guard():
			return {"text": "Guard %d%%" % skill.power_percent, "ko": false, "amount": 0}
		return {"text": "?", "ko": false, "amount": 0}
	var after := int(effect.hp_after.value)
	var change := after - u.hp
	return {"text": ("+%d" % change) if change > 0 else str(change), "ko": after <= 0, "amount": absi(change)}


func _focus_math(actor: Combatant, skill: CombatSkill, target_id: String, outcome: Dictionary) -> Array:
	if skill.is_heal():
		return BattleMath.heal_lines(fight, actor.id, target_id, skill.id, int(outcome.get("amount", 0)))
	if skill.is_guard():
		return BattleMath.guard_lines(fight, actor.id, skill.id, skill.power_percent)
	var lines := BattleMath.damage_lines(fight, actor.id, target_id, skill.id, int(outcome.get("amount", 0)))
	if outcome.get("ko", false):
		lines.append("%s goes Down." % fight.combatant(target_id).display_name)
	return lines


## Esc or a right-click puts an aimed skill back; 1-9 pick the dock's tiles.
func _unhandled_input(event: InputEvent) -> void:
	if event.is_action_pressed("ui_cancel") and not event.is_echo() and _has_choice_to_cancel():
		send(FightCommand.cancel())
		get_viewport().set_input_as_handled()
		return
	var key := event as InputEventKey
	if key != null and key.pressed and not key.echo and key.keycode >= KEY_1 and key.keycode <= KEY_9:
		if press_hotkey(key.keycode - KEY_0):
			get_viewport().set_input_as_handled()


## Presses the dock tile with hotkey `n` (1-9). True when one was pressed.
func press_hotkey(n: int) -> bool:
	for skill_id in skill_buttons:
		var tile: ActionTile = skill_buttons[skill_id]
		if tile.visible and tile.hotkey == n and not tile.disabled:
			on_skill_pressed(skill_id)
			return true
	return false


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
	UiStyle.add_label(col, title, "SmallLabel")
	return col


static func _button(parent: Node, text: String) -> Button:
	var button := Button.new()
	button.text = text
	button.focus_mode = Control.FOCUS_NONE
	button.custom_minimum_size = Vector2(0, 34)
	parent.add_child(button)
	return button
