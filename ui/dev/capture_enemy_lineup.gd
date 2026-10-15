extends CaptureScript
## Renders the enemy lineup and one battle per faction to PNGs for pull
## requests. Needs a display:
##     xvfb-run -a godot --path . --rendering-driver opengl3 --resolution 1280x820 \
##         -s res://ui/dev/capture_enemy_lineup.gd -- <out_dir>
## Writes enemy_lineup.png and battle_<faction>.png into <out_dir>
## (default ui/dev/screenshots).

## A region each faction holds in the by-act table, the defense level and the
## seed of its sample battle. Screenshot settings, not tuning.
const BATTLES := [
	["human_resistance", "bellevue", 3, 7],
	["enhanced_humans", "illinois", 3, 7],
	["rival_ai", "california", 3, 7],
	["aliens", "china", 3, 7],
]


func _init() -> void:
	start("res://ui/dev/screenshots")


func _run() -> void:
	var lineup: EnemyLineup = load("res://ui/dev/enemy_lineup.tscn").instantiate()
	root.add_child(lineup)
	await frames(6)
	lineup.freeze_on(1)
	await frames(4)
	await save("enemy_lineup")
	lineup.queue_free()
	await frames(4)

	var factions := FactionTable.load_default()
	for spec: Array in BATTLES:
		assert(factions.faction_for_region(spec[1]) == spec[0], "%s is not held by %s" % [spec[1], spec[0]])
		var request := FightRequest.new(FightRequest.Kind.ATTACK, spec[1], spec[2], StubSquadProvider.new().get_squad())
		var screen: BattleScreen = load("res://ui/fight/battle_screen.tscn").instantiate()
		screen.setup(request, spec[3])
		root.add_child(screen)
		await frames(30)
		await save("battle_%s" % spec[0])
		screen.queue_free()
		await frames(4)
	quit()
