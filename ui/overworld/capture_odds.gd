extends CaptureScript
## Renders the territory panel's odds for the pull request: a drafted squad on
## act 1 and a region whose simulated odds sit between the extremes, then the same
## region under the odds-model "formula" option. Needs a display:
##     xvfb-run -a godot --path . --rendering-driver opengl3 --resolution 1280x820 \
##         -s res://ui/overworld/capture_odds.gd -- <out_dir>

const OVERWORLD := "res://ui/overworld/overworld.tscn"
const VARIANTS := "user://capture_odds_variants.json"


func _init() -> void:
	start("res://ui/overworld/screenshots")


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
		await frames(2)
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
	await frames(30)
	await save("r1d_odds_simulated")
	JsonFile.write(VARIANTS, {"choices": {OddsEstimator.ODDS_MODEL: OddsEstimator.MODEL_FORMULA}})
	screen._refresh()
	await frames(30)
	await save("r1d_odds_formula")
	DirAccess.remove_absolute(ProjectSettings.globalize_path(VARIANTS))
	quit()
