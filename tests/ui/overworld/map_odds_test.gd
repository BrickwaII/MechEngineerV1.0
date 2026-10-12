extends GdUnitTestSuite
## The panel's odds: simulated auto-fights ("RISKY · 42%") by default, played
## over frames, or the old stat formula under the odds-model switch.

const SCENE := "res://ui/overworld/overworld.tscn"
const PLACEHOLDER := "res://data/regions/act1_placeholder.json"
const VARIANTS := "user://map_odds_test_variants.json"

var _runner: GdUnitSceneRunner


func before_test() -> void:
	_runner = scene_runner(SCENE)
	await _runner.simulate_frames(2)
	_screen().region_file = PLACEHOLDER
	_screen().odds.variants_path = VARIANTS
	assert_str(_screen().start_new_run()).is_empty()
	await _runner.simulate_frames(1)


func after_test() -> void:
	DirAccess.remove_absolute(ProjectSettings.globalize_path(VARIANTS))


func _screen() -> Node:
	return _runner.scene()


func _odds_line(screen: Node) -> String:
	var row: Node = screen._panel.find_child("Odds", true, false)
	return row.get_child(1).text if row != null else ""


func test_the_panel_shows_the_simulated_label_and_rate() -> void:
	var screen := _screen()
	screen.map_view.select("hydro_dam")
	assert_str(_odds_line(screen)).is_equal("SIMULATING...")
	screen.odds.finish_all()
	await _runner.simulate_frames(1)
	# The panel estimates at the level the fight would use (escalation included).
	var e: OddsEstimator.Estimate = OddsEstimator.new().estimate(
		screen.campaign.squad_provider.get_squad(), "hydro_dam", screen.campaign.defense_of("hydro_dam"),
		screen.odds.run_seed)
	assert_str(_odds_line(screen)).is_equal("%s · %d%%" % [e.label.to_upper(), e.percent()])
	assert_bool(OverworldTestHelpers.panel_has_text(screen, "auto-player fights differently")).is_true()


func test_estimates_play_over_frames_without_being_asked() -> void:
	var screen := _screen()
	screen.map_view.select("hydro_dam")
	for i in 400:
		if not _odds_line(screen).begins_with("SIMULATING"):
			break
		await _runner.simulate_frames(1)
	assert_str(_odds_line(screen)).contains("%")


func test_the_formula_option_shows_the_old_label() -> void:
	var file := FileAccess.open(VARIANTS, FileAccess.WRITE)
	file.store_string(JSON.stringify({"choices": {OddsEstimator.ODDS_MODEL: OddsEstimator.MODEL_FORMULA}}))
	file.close()
	var screen := _screen()
	screen.map_view.select("hydro_dam")
	await _runner.simulate_frames(1)
	assert_str(_odds_line(screen)).is_equal(screen.campaign.odds_label("hydro_dam").to_upper())
	assert_bool(OverworldTestHelpers.panel_has_text(screen, "auto-player")).is_false()
