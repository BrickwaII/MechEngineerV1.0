extends CaptureScript
## Renders the battle debugger (S9b) on the sandbox fight to PNGs for pull
## requests. Needs a display:
##     xvfb-run -a -s "-screen 0 1920x1080x24" godot --path . --rendering-driver opengl3 \
##         --resolution 1920x1080 -s res://ui/dev/battle_debugger/capture_debugger.gd -- <out_dir>
## Writes into <out_dir> (default ui/dev/battle_debugger/screenshots):
##   debug_unit.png      the Unit tab on the second enemy (stats, Exposed, plating, personality)
##   debug_action.png    Heavy Strike's recovery set to 60 in the Action tab, Heavy Strike aimed
##   debug_rewind.png    one decision stepped, then rewound: the time controls and the log
##   debug_simulate.png  Simulate 100 (greedy vs smart, the checks) and the live share panel
##   debug_changes.png   the Changes tab with Save to data's diff

const DEMO := "res://ui/dev/battle_debugger/battle_debugger_demo.tscn"


func _init() -> void:
	start("res://ui/dev/battle_debugger/screenshots")


func _run() -> void:
	var demo = load(DEMO).instantiate()
	root.add_child(demo)
	await frames(30)
	var dbg: BattleDebugger = demo.debugger
	var screen: BattleScreen = demo.screen
	var enemies := screen.fight.living(Combatant.Side.ENEMY)
	var foe: Combatant = enemies[mini(1, enemies.size() - 1)]
	dbg.session.apply_status(foe.id, "exposed")
	dbg.inspect_unit(foe.id)
	await frames(10)
	await save("debug_unit")
	dbg.inspect_action("heavy_strike")
	await frames(5)
	dbg.edit_action("recovery", 60)
	var actor := screen.handler.actor()
	if actor != null and actor.side == Combatant.Side.PLAYER and actor.has_skill("heavy_strike"):
		dbg.session.set_unit_field(actor.id, "energy", actor.stats.battery_capacity)
		screen.on_skill_pressed("heavy_strike")
		screen.on_unit_hovered(enemies[0].id, true)
	await frames(10)
	await save("debug_action")
	var at := screen.fight.action_count
	dbg.step()
	await frames(10)
	dbg.rewind_to(at)
	dbg.tabs.current_tab = BattleDebugger.TAB_CHANGES
	await frames(10)
	await save("debug_rewind")
	dbg.tabs.current_tab = BattleDebugger.TAB_SIMULATE
	dbg.sim_runs.value = 100
	dbg.simulate()
	await frames(10)
	await save("debug_simulate")
	dbg.tabs.current_tab = BattleDebugger.TAB_CHANGES
	dbg.show_save_diff()
	dbg.save_dialog.hide()
	await frames(10)
	await save("debug_changes")
	quit()
