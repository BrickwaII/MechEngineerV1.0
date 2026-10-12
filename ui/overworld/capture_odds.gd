extends SceneTree
## Renders the territory panel's odds for the pull request: a drafted squad on
## act 1 and a region whose simulated odds sit between the extremes, then the same
## region under the odds-model "formula" option. Needs a display:
##     xvfb-run -a godot --path . --rendering-driver opengl3 --resolution 1280x820 \
##         -s res://ui/overworld/capture_odds.gd -- <out_dir>

const OVERWORLD := "res://ui/overworld/overworld.tscn"
const VARIANTS := "user://capture_odds_variants.json"

var out_dir := "res://ui/overworld/screenshots"


func _init() -> void:
	var args := OS.get_cmdline_user_args()
	if args.size() > 0:
		out_dir = args[0]
	DirAccess.make_dir_recursive_absolute(out_dir)
	_run.call_deferred()


func _run() -> void:
	DirAccess.remove_absolute(ProjectSettings.globalize_path(VARIANTS))
	# The first drafted squad with a region in range whose odds sit mid-band.
	var screen: Control
	var pick := ""
	for squad_seed in range(1, 40):
		screen = load(OVERWORLD).instantiate()
		screen.squad_provider = BotSquadProvider.new(BotFactory.new(BotTuning.load_default()).build_squad(squad_seed))
		screen.start_picker = func(options: Array) -> String: return options[0].id
		root.add_child(screen)
		screen.odds.variants_path = VARIANTS
		await _settle(2)
		for region in screen.campaign.map.regions:
			if screen.campaign.standing(region.id) != Campaign.Standing.IN_RANGE:
				continue
			var e: OddsEstimator.Estimate = screen.odds.estimator.estimate(
				screen.campaign.squad_provider.get_squad(), region.id, screen.campaign.defense_of(region.id), screen.odds.run_seed)
			if e.percent() >= 15 and e.percent() < 70:
				pick = region.id
				print("squad %d, %s defense %d: %s %d%%" % [squad_seed, region.id, region.defense, e.label, e.percent()])
				break
		if not pick.is_empty():
			break
		screen.free()
	screen.map_view.select(pick)
	screen.odds.finish_all()
	await _settle(30)
	await _save("r1d_odds_simulated")
	var file := FileAccess.open(VARIANTS, FileAccess.WRITE)
	file.store_string(JSON.stringify({"choices": {OddsEstimator.ODDS_MODEL: OddsEstimator.MODEL_FORMULA}}))
	file.close()
	screen._refresh()
	await _settle(30)
	await _save("r1d_odds_formula")
	DirAccess.remove_absolute(ProjectSettings.globalize_path(VARIANTS))
	quit()


func _settle(frames: int) -> void:
	for i in frames:
		await process_frame


func _save(name: String) -> void:
	await RenderingServer.frame_post_draw
	var image := root.get_texture().get_image()
	image.save_png(out_dir.path_join(name + ".png"))
	print("saved ", name)
