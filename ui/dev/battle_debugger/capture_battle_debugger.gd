extends CaptureScript
## Renders the battle debugger (S9b) on the S9 sandbox fight to PNGs for pull
## requests. Needs a display:
##     xvfb-run -a -s "-screen 0 1600x1000x24" godot --path . --rendering-driver opengl3 \
##         --resolution 1600x900 -s res://ui/dev/battle_debugger/capture_battle_debugger.gd -- <out_dir>
## Writes into <out_dir> (default ui/dev/battle_debugger/screenshots):
##   debugger_unit.png      the Unit tab on an enemy (stats, statuses, plating, personality)
##   debugger_action_30.png Heavy Strike aimed, recovery 30: the AFTER bar's landing slot
##   debugger_action_90.png the same choice after recovery is set to 90 in the Action tab
##   debugger_rewind.png    after a step and a rewind back to the same decision
##   debugger_simulate.png  the Simulate tab after Simulate (greedy vs smart) and the live share panel
##   debugger_changes.png   the Changes tab with Save to data's diff shown

const BATTLE_SCENE := preload("res://ui/fight/battle_screen.tscn")
const SANDBOX := "res://data/scenarios/sandbox_3v3.json"
const SIM_RUNS := 20


func _init() -> void:
	start("res://ui/dev/battle_debugger/screenshots")


func _run() -> void:
	var r := ScenarioFiles.load_scenario(SANDBOX).resolve()
	var screen: BattleScreen = BATTLE_SCENE.instantiate()
	screen.setup(r.request, 5, FightScreenTuning.load_default(), r.tuning, r.enemy_table)
	root.add_child(screen)
	await frames(10)
	await until_player_turn(screen)
	var dbg := BattleDebugger.attach(screen, true)
	dbg.visible = true
	await frames(10)
	var foe := screen.fight.living(Combatant.Side.ENEMY)[0]
	dbg.session.apply_status(foe.id, "exposed")
	dbg.inspect_unit(foe.id)
	await frames(10)
	save("debugger_unit.png")
	# Heavy Strike aimed at the first enemy, recovery 30 then 90.
	var actor := screen.handler.actor()
	dbg.session.set_unit_field(actor.id, "energy", actor.stats.battery_capacity)
	await frames(5)
	dbg.inspect_action("heavy_strike")
	screen.on_skill_pressed("heavy_strike")
	screen.on_unit_hovered(foe.id, true)
	await frames(10)
	save("debugger_action_30.png")
	(dbg.action_editors["recovery"] as SpinBox).value = 90
	screen.on_skill_pressed("heavy_strike")
	screen.on_unit_hovered(foe.id, true)
	await frames(10)
	save("debugger_action_90.png")
	var at := screen.fight.action_count
	dbg.step()
	await frames(10)
	dbg.rewind_to(at)
	await frames(10)
	save("debugger_rewind.png")
	dbg.sim_runs.value = SIM_RUNS
	dbg.simulate()
	dbg.tabs.current_tab = BattleDebugger.TAB_SIMULATE
	await frames(10)
	save("debugger_simulate.png")
	dbg.tabs.current_tab = BattleDebugger.TAB_CHANGES
	dbg.refresh()
	var patch := dbg.session.preview_save()
	dbg.diff_label.text = patch.diff_text()
	await frames(10)
	save("debugger_changes.png")
	quit()
