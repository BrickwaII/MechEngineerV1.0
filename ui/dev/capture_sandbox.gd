extends CaptureScript
## Renders the S9 sandbox on the battle screen (ScenarioBattle) with the
## action-use panel, mid-fight and after the fight, to PNGs for pull requests.
## Needs a display:
##     xvfb-run -a -s "-screen 0 1600x1000x24" godot --path . --rendering-driver opengl3 \
##         --resolution 1280x820 -s res://ui/dev/capture_sandbox.gd -- <out_dir>
## Writes sandbox_battle.png, sandbox_battle_overlay.png and sandbox_end.png
## into <out_dir> (default ui/dev/screenshots).

## Seed of the sample fight and player turns before the first shot.
## Screenshot settings, not tuning.
const SEED := 1
const TURNS := 4


func _init() -> void:
	start("res://ui/dev/screenshots")


func _run() -> void:
	var battle: ScenarioBattle = load(ScenarioBattle.SCENE_PATH).instantiate()
	battle.fight_seed = SEED
	root.add_child(battle)
	current_scene = battle
	await frames(10)
	var screen := battle.service.screen
	for i in TURNS:
		await until_player_turn(screen)
		take_turn(screen)
	await until_player_turn(screen)
	await frames(20)
	await save("sandbox_battle")
	battle.overlay.visible = true
	battle.overlay.refresh()
	await frames(4)
	await save("sandbox_battle_overlay")
	battle.overlay.visible = false
	while not screen.fight.is_over():
		await until_player_turn(screen)
		if not screen.fight.is_over():
			take_turn(screen)
	await wait_until(func() -> bool: return battle.last_result != null)
	await frames(10)
	await save("sandbox_end")
	quit()
