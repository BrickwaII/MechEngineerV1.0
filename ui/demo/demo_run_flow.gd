class_name DemoRunFlow
extends RunFlow
## A demo run: the run flow (ui/run/) opened on a DemoScenario instead of a
## draft or a save, with nothing kept on disk.
##
## Never saves: no run folder (so no Continue entry), no autosave, no journal
## (the recorder is never made), and SAVE, LOAD, NEW RUN and RUN FOLDER are
## hidden on the map. F8 still opens the feedback form; its report goes to
## user://demo_reports/<scenario id>/ and says it came from a demo. F4 opens
## the variant switchboard as in a run.
##
## A DEMO banner stays on top. Home and the Esc menu's BACK TO DEMOS leave at
## once (nothing is at stake): exit_requested, which the main menu answers
## with the demo picker. When the scenario ends (a demo fight's readout is
## done, the run is over, an act's payload arrives) the DemoEndPanel offers
## REPLAY and BACK TO DEMOS in place of the run's next step.

const DEMO_REPORTS := "user://demo_reports"
const BANNER_MARGIN := 6.0

## Set before the flow enters the tree.
var scenario: DemoScenario
## Where F8 reports go; tests point it elsewhere.
var reports_root := DEMO_REPORTS
## The end panel while it shows, or null.
var end_panel: DemoEndPanel
var banner: PanelContainer
## Problems building the scenario; the end panel says them.
var problems: Array[String] = []


func _start() -> void:
	_build_banner()
	start_scenario()


## (Re)starts the scenario from its beginning.
func start_scenario() -> void:
	transition.cover()
	close_pause_menu()
	_close_end_panel()
	_close_all()
	problems.clear()
	CampaignVariants.user_path = variants_path
	run_board = Switchboard.load_board(variants_path)
	variant_label.show_board(run_board)
	current_seed = hash(scenario.id) & 0x7fffffff
	if MusicDirector.current != null:
		MusicDirector.current.boss_battle = false
	if scenario.kind == DemoScenario.KIND_RUN_OVER:
		_show_demo_run_over()
		return
	var built := scenario.build_squad(problems)
	var state := scenario.build_state(problems)
	if state == null or not problems.is_empty():
		_show_end("CANNOT START", "\n".join(problems), "danger")
		return
	_open_map(built, SkillUseLedger.new())
	if not overworld.load_state(state):
		_show_end("CANNOT START", "The map did not take the scenario's state.", "danger")
		return
	var card := scenario.news_card(overworld.campaign.map)
	if not card.is_empty():
		overworld.escalation_hud.news.push(card)
	match scenario.kind:
		DemoScenario.KIND_FIGHT:
			_start_fight()
		DemoScenario.KIND_PRE_FIGHT:
			overworld.show_pre_fight(scenario.region)
		DemoScenario.KIND_FAST_FORWARD:
			overworld._on_fast_forward()


func _start_fight() -> void:
	var table := scenario.enemy_table(problems)
	if fight_service.inner is FightSceneService:
		(fight_service.inner as FightSceneService).enemy_table = table
	if MusicDirector.current != null:
		MusicDirector.current.boss_battle = scenario.music() == DemoScenario.MUSIC_BOSS
	fight_service.start_fight(scenario.fight_request(BotSquadProvider.new(squad).get_squad()))


# --- Nothing on disk -----------------------------------------------------------------

func new_run() -> void:
	start_scenario()


func continue_run(_dir: String) -> bool:
	return false


func save_run(_path := "", _auto := false) -> Error:
	return ERR_UNAVAILABLE


func load_run(_path := "") -> bool:
	return false


func runs_folder() -> String:
	return ""


func _autosave() -> void:
	pass


## No RUN FOLDER button, and no SAVE, LOAD or NEW RUN.
func _add_folder_button() -> void:
	overworld.show_run_buttons(false)
	overworld.save_action = func() -> void: pass
	overworld.load_action = func() -> void: pass
	overworld.payload_action = _on_payload


## The F8 report's folder, and OPEN FOLDER in the form.
func open_run_folder() -> void:
	DirAccess.make_dir_recursive_absolute(reports_root)
	folder_opener.call(ProjectSettings.globalize_path(reports_root))


# --- F8 ------------------------------------------------------------------------------

func open_feedback() -> void:
	if feedback_form != null:
		return
	var texture := get_viewport().get_texture() if DisplayServer.get_name() != "headless" else null
	_screenshot = texture.get_image() if texture != null else null
	get_tree().paused = true
	feedback_form = FeedbackForm.new()
	feedback_form.name = "FeedbackForm"
	feedback_form.settings = run_settings
	feedback_form.context_text = "DEMO · %s · %s. Saved to demo_reports, not to a run." % [scenario.scenario_name, screen_name()]
	feedback_form.submitted.connect(write_feedback)
	feedback_form.cancelled.connect(close_feedback)
	feedback_form.open_folder_requested.connect(open_run_folder)
	_variant_layer.add_child(feedback_form)


## Writes the report to demo_reports/<scenario id>/<time>/: the note and the
## screenshot, marked as a demo. Returns its folder.
func write_feedback(note: String, category: String, rating: int) -> String:
	var info := {
		"demo": true,
		"scenario": scenario.id,
		"scenario_name": scenario.scenario_name,
		"note": note,
		"category": category,
		"rating": rating,
		"stage": Stage.keys()[stage].to_lower(),
		"screen": screen_name(),
		"variants": Dictionary(Switchboard.load_board(variants_path).choices),
		"time": Time.get_datetime_string_from_system(false, true),
	}
	if overworld != null and overworld.campaign != null:
		info["act"] = overworld.campaign.state.act + 1
		info["day"] = overworld.campaign.day()
	last_report_dir = FeedbackReport.write(reports_root.path_join(scenario.id), info, _screenshot, "", "")
	close_feedback()
	if overworld != null:
		overworld.log_event("Demo feedback saved to demo_reports/%s/%s." % [scenario.id, last_report_dir.get_file()])
	return last_report_dir


# --- Leaving and the end ---------------------------------------------------------------

func _configure_pause_menu(menu: PauseMenu) -> void:
	menu.title_text = "DEMO PAUSED"
	menu.note_text = "Demo: nothing is saved."
	menu.home_text = "Back to demos"


## The run is over (run_over_action): the end panel instead of the run-over
## screen.
func show_run_over() -> void:
	var c: Campaign = overworld.campaign if overworld != null else null
	var won := c != null and c.end_reason() == Stakes.END_WON
	var reason: String = str(RunRecorder.END_TEXT.get(c.end_reason(), "")) if c != null else ""
	_show_end("RUN OVER · VICTORY" if won else "RUN OVER · DEFEAT",
		RunOverScreen.reason_text(reason, won), "accent" if won else "danger")


func _on_payload() -> void:
	var c: Campaign = overworld.campaign
	_show_end("PAYLOAD", "Act %d is over: you held %d of %d territories. A run would zoom out to %s now." % [
		c.state.act + 1, c.state.owned.size(), c.map.regions.size(), overworld.plan.act_name(c.state.act + 1)], "accent")


## A demo fight ends after its readout: the end panel, not the map.
func continue_to_map() -> void:
	if scenario.kind != DemoScenario.KIND_FIGHT:
		super.continue_to_map()
		return
	var won := fight_service.last_report != null and fight_service.last_report.is_victory()
	_show_fight_end(won)


func _on_fight_finished(result: FightResult) -> void:
	if scenario.kind != DemoScenario.KIND_FIGHT:
		super._on_fight_finished(result)
		return
	battle_screen = null
	debug_overlay = null
	# A fight with a readout ends when the readout is done (continue_to_map).
	if readout == null:
		_show_fight_end(result.is_victory())


func _show_fight_end(won: bool) -> void:
	var what := "The boss" if scenario.is_boss() else "The fight"
	_show_end("VICTORY" if won else "DEFEAT", "%s is over: %s." % [what, "the squad won" if won else "the squad lost"],
		"accent" if won else "danger")


func _show_demo_run_over() -> void:
	run_over_screen = RunOverScreen.new()
	run_over_screen.name = "RunOverScreen"
	var summary := scenario.run_over.duplicate(true)
	summary.merge({"finished": true}, false)
	run_over_screen.leave_text = "DONE"
	run_over_screen.show_run("", summary)
	run_over_screen.main_menu_requested.connect(func() -> void:
		_show_end("RUN OVER", "That is how a run ends.", "accent"))
	add_child(run_over_screen)
	run_over_screen.folder_button.visible = false


func _show_end(title: String, body: String, color: String) -> void:
	_close_end_panel()
	if pause_menu != null:
		close_pause_menu()
	end_panel = DemoEndPanel.new()
	end_panel.name = "DemoEndPanel"
	end_panel.eyebrow_text = "DEMO · %s" % scenario.scenario_name.to_upper()
	end_panel.title_text = title
	end_panel.body_text = body
	end_panel.title_color = color
	end_panel.replay_requested.connect(start_scenario)
	end_panel.back_requested.connect(leave_to_menu)
	_variant_layer.add_child(end_panel)
	_variant_layer.move_child(banner, -1)


func _close_end_panel() -> void:
	if end_panel != null:
		_free(end_panel)
		end_panel = null


## The pause menu stays shut over the end panel.
func open_pause_menu() -> PauseMenu:
	if end_panel != null:
		return null
	return super.open_pause_menu()


## Leaving a demo needs no confirm and saves nothing: straight back to the
## picker (exit_requested), or the scenario again when nothing listens.
func leave_to_menu() -> void:
	close_pause_menu()
	if exit_requested.get_connections().is_empty():
		start_scenario()
	else:
		exit_requested.emit()


# --- Banner ---------------------------------------------------------------------------

func _build_banner() -> void:
	banner = PanelContainer.new()
	banner.name = "DemoBanner"
	banner.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var style := StyleBoxFlat.new()
	style.bg_color = Color(FeelData.color("warning"), 0.92)
	style.set_content_margin_all(4)
	style.content_margin_left = 12
	style.content_margin_right = 12
	banner.add_theme_stylebox_override("panel", style)
	var label := Label.new()
	label.name = "BannerLabel"
	label.text = "DEMO · %s · NOT SAVED" % scenario.scenario_name.to_upper()
	label.add_theme_color_override("font_color", FeelData.color("text_dark"))
	label.add_theme_font_size_override("font_size", ScreenTheme.size(10))
	label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	banner.add_child(label)
	_variant_layer.add_child(banner)
	banner.set_anchors_and_offsets_preset(Control.PRESET_CENTER_BOTTOM, Control.PRESET_MODE_MINSIZE, int(BANNER_MARGIN))
	banner.grow_horizontal = Control.GROW_DIRECTION_BOTH
	banner.grow_vertical = Control.GROW_DIRECTION_BEGIN


## A demo fight's readout ends the demo: DONE, not BACK TO THE MAP.
func _label_continue() -> void:
	super._label_continue()
	if continue_button != null and scenario.kind == DemoScenario.KIND_FIGHT and not readout.is_tallying():
		continue_button.text = "DONE"


## A titled demo fight (a showcase boss) names itself in the battle header.
func _on_screen_opened(screen: BattleScreen) -> void:
	super._on_screen_opened(screen)
	var title := str(scenario.fight.get("title", ""))
	if scenario.is_fight() and not title.is_empty():
		screen.header_label.text = "%s  -  %s" % ["BOSS" if scenario.is_boss() else "FIGHT", title.to_upper()]


## Home in a demo leaves at once, from any screen: nothing is at stake.
func go_home() -> void:
	leave_to_menu()
